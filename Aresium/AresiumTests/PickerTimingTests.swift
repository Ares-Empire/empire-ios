import Foundation
import Darwin
import SwiftUI
import UIKit
import Testing
@testable import Aresium

/// Opt-in timing experiment: run this suite alone with TEST_RUNNER_PICKER_TIMINGS=1.
/// Real picker and dashboard views stay mounted. Main-run-loop turns include SwiftUI updates/layout;
/// async signposts report wall time separately. No time limit is asserted on a shared development Mac.
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["PICKER_TIMINGS"] == "1"))
@MainActor
struct PickerTimingTests {
    @Test func shopIdentityWork() async throws {
        let phone = try await PhoneCountingTests.backend()
        let file = try PhoneTest.fixture("timing-vr-5000.csv")
        let header = String(decoding: file.data, as: UTF8.self).components(separatedBy: "\n")[0]
        try await phone.saveLayout(CsvLayout(separator: ";", header: header.components(separatedBy: ";"),
            dateFormat: "YYYY-MM-DD", numberFormat: "de",
            columns: .init(date: 0, valueDate: 1, amount: 4, counterparty: [2], text: [3], currency: 5)))
        _ = try await phone.importFiles([file], auth: BackendAuth(token: nil))
        #expect(phone.summary.payments == 5000)
        let id = try #require(try await phone.ledger.payments().first?.id)
        var dashboards: [Double] = [], infos: [Double] = []
        for round in 0..<6 {
            let recording = PickerTiming.Recording()
            try await PickerTiming.$recording.withValue(recording) {
                var start = ProcessInfo.processInfo.systemUptime
                _ = try await phone.dashboard(auth: BackendAuth(token: nil))
                let dashboard = (ProcessInfo.processInfo.systemUptime - start) * 1000
                start = ProcessInfo.processInfo.systemUptime
                _ = try await phone.renameInfo(id: id)
                let info = (ProcessInfo.processInfo.systemUptime - start) * 1000
                if round > 0 { dashboards.append(dashboard); infos.append(info) }
            }
            if round > 0 {
                print("SHOP TIMING round=\(round) dashboard-ms=\(dashboards.last!) renameInfo-ms=\(infos.last!)")
                for sample in recording.values where sample.name == "names.identities" {
                    print("SHOP SPAN \(sample.name) kind=\(sample.kind) ms=\(sample.ms)")
                }
            }
        }
        print("SHOP TIMING size=5000 median-dashboard-ms=\(dashboards.sorted()[2]) median-renameInfo-ms=\(infos.sorted()[2])")
    }

    @Test func pickerSteps() async throws {
        let sizes = ProcessInfo.processInfo.environment["PICKER_SIZE"].flatMap(Int.init).map { [$0] } ?? [0, 1000, 5000]
        for size in sizes {
            let phone: PhoneBackend
            if size == 0 {
                phone = try await PhoneSample.backend(empty: false, storage: PhoneTest.storage()).backend
            } else {
                phone = try await PhoneCountingTests.backend()
                let file = try PhoneTest.fixture("timing-vr-5000.csv")
                let lines = String(decoding: file.data, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: false)
                let subset = ImportFile(name: file.name, data: Data(lines.prefix(size + 1).joined(separator: "\n").utf8))
                let layout = CsvLayout(separator: ";", header: String(lines[0]).components(separatedBy: ";"),
                    dateFormat: "YYYY-MM-DD", numberFormat: "de",
                    columns: .init(date: 0, valueDate: 1, amount: 4, counterparty: [2], text: [3], currency: 5))
                try await phone.saveLayout(layout)
                _ = try await phone.importFiles([subset], auth: BackendAuth(token: nil))
                #expect(phone.summary.payments == size)
            }
            let session = await PhoneTest.session(nil, transport: RoutedTransport())
            let dashboard = DashboardStore(session: session, backend: phone)
            await dashboard.reload()
            let imports = ImportStore(dashboard: dashboard, background: PhoneActivity())
            let importedIDs = try await phone.ledger.payments().map(\.id)
            let importResult = PhoneImportResult(name: "fictional-timing.csv", added: importedIDs.count, newIDs: importedIDs)
            let picker = CategoryPickerModel(phone: phone) { await dashboard.reloadAfterTransactionChange() }
            await picker.load()
            let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
            let window = UIWindow(windowScene: scene)
            let host = UIHostingController(rootView: TimingViews(picker: picker, dashboard: dashboard, imports: imports))
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer { window.isHidden = true; window.rootViewController = nil }
            try await Task.sleep(for: .milliseconds(600)) // Initial layout and fonts are outside measured steps.
            print("PICKER DATA size=\(size == 0 ? "sample" : String(size)) payments=\(phone.summary.payments)")
            for round in 0..<6 { // One warm-up, median of five observations per step afterwards.
                for (step, action) in [
                    ("tick", { await picker.toggle("hobbies") }),
                    ("settle", {
                        try? await Task.sleep(for: .milliseconds(550))
                        while picker.isWorking { try? await Task.sleep(for: .milliseconds(10)) }
                    }),
                    ("untick", {
                        await picker.toggle("hobbies")
                        if picker.untick != nil { await picker.resolveUntick(moveTo: nil) }
                    }),
                    ("close", {
                        _ = await picker.flush()
                        _ = try? await phone.recount([.phone(importResult)])
                    })
                ] as [(String, () async -> Void)] {
                    let turns = MainTurns()
                    turns.start()
                    PickerTiming.startRecording()
                    let start = ProcessInfo.processInfo.systemUptime
                    await action()
                    // Let the actual observation-driven render finish, including the views under the picker.
                    try await Task.sleep(for: .milliseconds(100))
                    host.view.setNeedsLayout()
                    PickerTiming.measure("views.layout") { host.view.layoutIfNeeded(); CATransaction.flush() }
                    let elapsed = (ProcessInfo.processInfo.systemUptime - start) * 1000
                    let samples = PickerTiming.finishRecording()
                    turns.stop()
                    if round > 0 {
                        let label = "size=\(size) round=\(round) step=\(step)"
                        print("PICKER \(label) main-turn-max=\(turns.maximum) main-cpu-max=\(turns.maximumCPU) elapsed=\(elapsed)")
                        for key in Set(samples.map { $0.name + "/" + $0.kind }).sorted() {
                            let values = samples.filter { $0.name + "/" + $0.kind == key }.map(\.ms)
                            print("PICKER \(label) \(key) max=\(values.max() ?? 0) sum=\(values.reduce(0,+)) n=\(values.count)")
                        }
                    }
                }
            }
        }
    }
}

@MainActor
private final class MainTurns {
    private var observer: CFRunLoopObserver?
    private var began: Double?
    private var beganCPU: UInt64?
    private(set) var maximum = 0.0
    private(set) var maximumCPU = 0.0

    func start() {
        began = ProcessInfo.processInfo.systemUptime
        beganCPU = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
        observer = CFRunLoopObserverCreateWithHandler(nil,
            CFRunLoopActivity.afterWaiting.rawValue | CFRunLoopActivity.beforeWaiting.rawValue,
            true, CFIndex.max) { [weak self] _, activity in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    let now = ProcessInfo.processInfo.systemUptime
                    let cpu = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
                    if activity == .afterWaiting { self.began = now; self.beganCPU = cpu }
                    else if let began = self.began, let beganCPU = self.beganCPU {
                        self.maximum = max(self.maximum, (now - began) * 1000)
                        self.maximumCPU = max(self.maximumCPU, Double(cpu - beganCPU) / 1_000_000)
                        self.began = nil
                        self.beganCPU = nil
                    }
                }
            }
        CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
    }
    func stop() { if let observer { CFRunLoopRemoveObserver(CFRunLoopGetMain(), observer, .commonModes) } }
}

private struct TimingViews: View {
    let picker: CategoryPickerModel
    let dashboard: DashboardStore
    let imports: ImportStore
    private let palette = Palette(theme: .light)

    var body: some View {
        ZStack {
            StartScreen(store: dashboard, palette: palette,
                        current: .constant(true), side: .constant(.expenses), graph: false, graphMoves: false,
                        band: AresiumBand(palette: palette, width: 402, hidden: false) { _ in }) { _ in }
            NavigationStack { CategoryPickerScreen(model: picker) }
        }
    }
}
