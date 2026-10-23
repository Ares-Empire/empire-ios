import Foundation
import Observation

struct ImportBanner: Identifiable {
    let id = UUID()
    let message: String
    let success: Bool
}

@MainActor @Observable
final class ImportStore {
    private(set) var banner: ImportBanner?
    private(set) var isImporting = false
    private var readingCount = 0
    private var pending: [ImportFile] = []
    private var batchScheduled = false
    @ObservationIgnored private var batchTask: Task<Void, Never>?
    @ObservationIgnored private var bannerTask: Task<Void, Never>?
    private var generation = 0
    private let dashboard: DashboardStore
    private let client: APIClient

    var isBusy: Bool { readingCount > 0 || isImporting || batchScheduled }

    init(dashboard: DashboardStore, client: APIClient = APIClient()) {
        self.dashboard = dashboard
        self.client = client
    }

    func showSampleUnavailable() {
        show("Not available with sample data", success: false)
    }

    func show(_ message: String, success: Bool) {
        bannerTask?.cancel()
        let banner = ImportBanner(message: message, success: success)
        self.banner = banner
        bannerTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(4500)) } catch { return }
            if self?.banner?.id == banner.id { self?.banner = nil }
        }
    }

    func receive(_ urls: [URL]) async {
        guard !dashboard.isSample else { showSampleUnavailable(); return }
        readingCount += 1
        defer { readingCount -= 1; schedulePendingImport() }
        do {
            // Capture text while access is available. Pending login never relies on a temporary URL.
            let files = try await Task.detached { try ImportFileReader.read(urls) }.value
            pending.append(contentsOf: files)
        } catch { show(error.localizedDescription, success: false) }
    }

    func sessionChanged() async {
        generation += 1
        await importPendingFiles()
    }

    // Also used on login, so all files received while logged out go in one request.
    func importPendingFiles() async {
        batchTask?.cancel()
        batchTask = nil
        batchScheduled = false
        guard !isImporting, readingCount == 0, !pending.isEmpty,
              let token = dashboard.session.token else { return }
        isImporting = true
        let generation = generation
        let files = pending
        pending.removeAll()
        defer { isImporting = false; schedulePendingImport() }
        do {
            let result = try await client.importFiles(files, token: token) {
                if generation == self.generation, self.dashboard.session.token == token {
                    self.dashboard.session.logOut()
                }
            }
            guard generation == self.generation, dashboard.session.token == token else { return }
            await dashboard.reloadAfterImport()
            guard generation == self.generation, dashboard.session.token == token else { return }
            show(result.summary, success: !result.results.contains { !($0.error ?? "").isEmpty })
        } catch {
            guard generation == self.generation else { return }
            show(error.localizedDescription, success: false)
        }
    }

    private func schedulePendingImport() {
        guard !pending.isEmpty, readingCount == 0, !isImporting, dashboard.session.token != nil else { return }
        batchTask?.cancel()
        batchScheduled = true
        // Document-open callbacks arrive one URL at a time. Collect a burst into one upload.
        batchTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(250)) } catch { return }
            guard let self else { return }
            self.batchTask = nil
            await self.importPendingFiles()
        }
    }
}
