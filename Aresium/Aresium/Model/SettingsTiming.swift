#if DEBUG
import Foundation
import Darwin
import os

/// Opt-in simulator experiment. Record complete main run-loop turns, including SwiftUI/UIKit work.
/// Timestamps align with the UI driver's steps; file writes run on a private queue, outside measured turns.
@MainActor
final class SettingsTiming {
    private static var recorder: SettingsTiming?
    private var observer: CFRunLoopObserver?
    nonisolated private static let output = DispatchQueue(label: "de.ares-empire.aresium.settings-timing")
    nonisolated private static let spans = OSAllocatedUnfairLock<URL?>(initialState: nil)
    private let log = OSLog(subsystem: "de.ares-empire.aresium", category: "settings")
    private var began: Double?
    private var cpu: UInt64 = 0
    private let url = FileManager.default.temporaryDirectory.appending(path: "57-settings-turns.jsonl")

    static func startIfRequested() {
        guard LaunchArguments.current.contains("-settingsTimings"), recorder == nil else { return }
        let value = SettingsTiming()
        recorder = value
        value.start()
    }

    private func start() {
        try? Data().write(to: url)
        let spanURL = url.deletingLastPathComponent().appending(path: "57-settings-spans.jsonl")
        try? Data().write(to: spanURL)
        Self.spans.withLock { $0 = spanURL }
        let url = url
        observer = CFRunLoopObserverCreateWithHandler(nil,
            CFRunLoopActivity.afterWaiting.rawValue | CFRunLoopActivity.beforeWaiting.rawValue,
            true, CFIndex.max) { [weak self] _, activity in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    let now = Date().timeIntervalSince1970
                    let cpu = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
                    if activity == .afterWaiting {
                        self.began = now; self.cpu = cpu
                        os_signpost(.begin, log: self.log, name: "settings.mainTurn")
                    }
                    else if let began = self.began {
                        os_signpost(.end, log: self.log, name: "settings.mainTurn")
                        let ms = (now - began) * 1000
                        if ms >= 0.5 {
                            let line = "{\"start\":\(began),\"ms\":\(ms),\"cpu\":\(Double(cpu - self.cpu) / 1_000_000)}\n"
                            Self.write(line, to: url)
                        }
                        self.began = nil
                    }
                }
            }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
    }

    nonisolated static func record(_ sample: PickerTiming.Sample) {
        guard let url = spans.withLock({ $0 }) else { return }
        let line = "{\"name\":\"\(sample.name)\",\"kind\":\"\(sample.kind)\",\"ms\":\(sample.ms)}\n"
        write(line, to: url)
    }

    nonisolated private static func write(_ line: String, to url: URL) {
        output.async {
            guard let file = try? FileHandle(forWritingTo: url) else { return }
            defer { try? file.close() }
            _ = try? file.seekToEnd()
            try? file.write(contentsOf: Data(line.utf8))
        }
    }
}
#endif
