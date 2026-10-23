import Foundation
import Observation
import UIKit

struct ImportBanner: Identifiable {
    let id = UUID()
    let message: String
    let success: Bool
    var files: [String] = []
}

@MainActor
protocol ImportBackgroundActivity {
    func begin(expiration: @escaping @MainActor () -> Void)
    func end()
}

@MainActor
final class ApplicationImportActivity: ImportBackgroundActivity {
    private var identifier: UIBackgroundTaskIdentifier = .invalid
    func begin(expiration: @escaping @MainActor () -> Void) {
        identifier = UIApplication.shared.beginBackgroundTask(withName: "Import statements") { [weak self] in
            MainActor.assumeIsolated { expiration(); self?.end() }
        }
    }
    func end() {
        guard identifier != .invalid else { return }
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
    }
}

@MainActor @Observable
final class ImportStore {
    private(set) var banner: ImportBanner?
    private(set) var isImporting = false
    private var readingCount = 0
    private var pending: [ImportFile] = []
    private var attempted: [ImportFile] = []
    private var batchScheduled = false
    @ObservationIgnored private var batchTask: Task<Void, Never>?
    @ObservationIgnored private var bannerTask: Task<Void, Never>?
    @ObservationIgnored private var uploadTask: Task<Void, Never>?
    private var generation = 0
    private var uploadID: UUID?
    private let dashboard: DashboardStore
    private let client: APIClient
    private let background: any ImportBackgroundActivity
    private let maximumRequestBytes: Int

    var isBusy: Bool { readingCount > 0 || isImporting || batchScheduled }
    var waitingCount: Int { pending.count + attempted.count }
    var canRetry: Bool { !attempted.isEmpty && !isImporting && (dashboard.session.token != nil || dashboard.isSample) }

    init(dashboard: DashboardStore, client: APIClient = APIClient(),
         background: any ImportBackgroundActivity = ApplicationImportActivity(),
         maximumRequestBytes: Int = ImportRequestPlan.maximumBytes) {
        self.dashboard = dashboard
        self.client = client
        self.background = background
        self.maximumRequestBytes = maximumRequestBytes
        dashboard.session.onLogout { [weak self] in self?.discard() }
    }

    func showSampleUnavailable() { show("Not available with sample data", success: false) }

    func show(_ message: String, success: Bool, files: [String] = []) {
        bannerTask?.cancel()
        let banner = ImportBanner(message: message, success: success, files: files)
        self.banner = banner
        guard success else { return }
        bannerTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(4500)) } catch { return }
            if self?.banner?.id == banner.id { self?.banner = nil }
        }
    }

    func dismiss() { bannerTask?.cancel(); banner = nil }

    func discard() {
        generation += 1
        uploadTask?.cancel()
        uploadTask = nil
        uploadID = nil
        background.end()
        isImporting = false
        batchTask?.cancel()
        batchTask = nil
        batchScheduled = false
        pending.removeAll()
        attempted.removeAll()
        dismiss()
    }

    func receive(_ urls: [URL], source: ImportFileSource = .picker) async {
        guard !dashboard.isSample else { showSampleUnavailable(); return }
        let generation = generation
        readingCount += 1
        defer { readingCount -= 1; schedulePendingImport() }
        do {
            // Capture text while access is available; shared Inbox copies are removed after reading.
            let files = try await Task.detached { try ImportFileReader.read(urls, source: source) }.value
            guard generation == self.generation else { return }
            pending.append(contentsOf: files)
        } catch {
            guard generation == self.generation else { return }
            show(error.localizedDescription, success: false)
        }
    }

    func sessionChanged() async {
        if dashboard.session.token != nil { await importPendingFiles() }
    }

    func importPendingFiles() async {
        batchTask?.cancel()
        batchTask = nil
        batchScheduled = false
        guard !isImporting, readingCount == 0, let token = dashboard.session.token else { return }
        if attempted.isEmpty { attempted = pending; pending.removeAll() }
        guard !attempted.isEmpty else { return }
        isImporting = true
        let id = UUID()
        uploadID = id
        let generation = generation
        let sessionGeneration = dashboard.session.generation
        let task = Task {
            await self.upload(token: token, generation: generation, sessionGeneration: sessionGeneration)
            guard self.uploadID == id else { return }
            self.background.end()
            self.uploadTask = nil
            self.uploadID = nil
            self.isImporting = false
            self.schedulePendingImport()
        }
        uploadTask = task
        background.begin { [weak self] in self?.uploadTask?.cancel() }
        await task.value
    }

    private func upload(token: String, generation: Int, sessionGeneration: Int) async {
        var results: [ImportResponse.Result] = []
        var changed = false
        do {
            let plan = try ImportRequestPlan(files: attempted, maximumBytes: maximumRequestBytes)
            for file in plan.refused {
                results.append(.init(name: file.name, added: 0, total: 0, account: nil, skipped: false,
                                     error: "Too large for a 25 MB import request"))
            }
            for files in plan.batches {
                try Task.checkCancellation()
                let result = try await client.importFiles(files, token: token) {
                    if generation == self.generation, sessionGeneration == self.dashboard.session.generation {
                        self.dashboard.session.logOut()
                    }
                }
                guard generation == self.generation, sessionGeneration == dashboard.session.generation else { return }
                try Task.checkCancellation()
                results.append(contentsOf: result.results)
                changed = true
                // Keep failed files and any files the server did not report; completed requests need no retry.
                for result in result.results where result.error?.isEmpty != false {
                    if let index = attempted.firstIndex(where: { $0.name == result.name }) { attempted.remove(at: index) }
                }
            }
            guard generation == self.generation else { return }
            let response = ImportResponse(results: results)
            show(response.summary, success: attempted.isEmpty && !results.contains { $0.error?.isEmpty == false },
                 files: results.map(\.displayMessage))
        } catch {
            guard generation == self.generation, sessionGeneration == dashboard.session.generation else { return }
            dashboard.session.handleAuthFailure(error, generation: sessionGeneration)
            guard generation == self.generation else { return }
            let message = error is CancellationError || (error as? URLError)?.code == .cancelled
                ? "Import interrupted. Retry when you return to Aresium." : error.localizedDescription
            show(message, success: false, files: results.map(\.displayMessage) + attempted.map { "\($0.name): \(message)" })
        }
        if changed, generation == self.generation, sessionGeneration == dashboard.session.generation {
            await dashboard.reloadAfterImport()
        }
    }

    private func schedulePendingImport() {
        guard attempted.isEmpty, !pending.isEmpty, readingCount == 0, !isImporting,
              dashboard.session.token != nil else { return }
        batchTask?.cancel()
        batchScheduled = true
        batchTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            guard let self else { return }
            self.batchTask = nil
            await self.importPendingFiles()
        }
    }
    #if DEBUG
    func seedDebugWaitingFiles() {
        pending = [ImportFile(name: "bank.csv", content: "fictional"), ImportFile(name: "paypal.xml", content: "<fictional/>")]
    }
    func seedDebugImportFailure() {
        attempted = [ImportFile(name: "bank.csv", content: "fictional")]
        show("Import failed", success: false, files: ["bank.csv: Unknown format"])
    }
    #endif

}
