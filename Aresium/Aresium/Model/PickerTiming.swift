import Foundation
import os

/// Picker intervals are visible in Instruments under de.ares-empire.aresium / picker.
/// Synchronous spans distinguish main-thread work from actor work; async spans measure elapsed time only.
nonisolated enum PickerTiming {
    private static let log = OSLog(subsystem: "de.ares-empire.aresium", category: "picker")

    struct Interval {
        let name: StaticString
        let id: OSSignpostID
        let start = ProcessInfo.processInfo.systemUptime

        func end() {
            os_signpost(.end, log: PickerTiming.log, name: name, signpostID: id)
            PickerTiming.record(name, start: start, kind: "elapsed")
        }
    }

    static func begin(_ name: StaticString) -> Interval {
        let id = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: name, signpostID: id)
        return Interval(name: name, id: id)
    }

    static func measure<T>(_ name: StaticString, _ action: () throws -> T) rethrows -> T {
        let interval = begin(name)
        defer {
            os_signpost(.end, log: log, name: name, signpostID: interval.id)
            record(name, start: interval.start, kind: Thread.isMainThread ? "main" : "worker")
        }
        return try action()
    }

    private static func record(_ name: StaticString, start: Double, kind: String) {
        #if DEBUG
        let sample = Sample(name: String(describing: name), kind: kind,
                            ms: (ProcessInfo.processInfo.systemUptime - start) * 1000)
        recording?.append(sample)
        samples.withLock { values in
            if values != nil { values?.append(sample) }
        }
        #endif
    }

    #if DEBUG
    struct Sample: Sendable {
        let name: String
        let kind: String
        let ms: Double
    }
    /// Unit tests capture only their task and its actor calls; the UI timing experiment records globally as well,
    /// since SwiftUI render callbacks run outside the initiating task.
    final class Recording: Sendable {
        private let storage = OSAllocatedUnfairLock<[Sample]>(initialState: [])
        fileprivate func append(_ sample: Sample) { storage.withLock { $0.append(sample) } }
        var values: [Sample] { storage.withLock { $0 } }
    }
    @TaskLocal static var recording: Recording?
    private static let samples = OSAllocatedUnfairLock<[Sample]?>(initialState: nil)
    static func startRecording() { samples.withLock { $0 = [] } }
    static func finishRecording() -> [Sample] { samples.withLock { let result = $0 ?? []; $0 = nil; return result } }
    #endif
}
