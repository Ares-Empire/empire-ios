import Foundation
import Observation
import UIKit

struct ImportBanner: Identifiable {
    let id = UUID()
    var message: String
    let success: Bool
    var files: [String] = []
    /// Phone mode, after a file of an unknown bank was read with the layout the person confirmed: the quiet card that
    /// offers to send its format to us (`BankFormatCard`). While it shows, the result stays until it is answered.
    var share: BankFormatCard?
    /// The import results `message` sums up (empty for other lines), so it can be counted again after the category
    /// picker sorted the payments (`ImportStore.categoriesClosed`).
    var results: [ImportFileResult] = []
}

/// Phone mode: a CSV whose layout the engine does not know. The person sees its first payments read the engine's ways
/// ("Does this look right?", `FileCheckModel`) and, if none fits, picks the columns; the layout is saved and the file
/// read again.
struct LayoutRequest: Identifiable {
    let id = UUID()
    let file: ImportFile
    let guess: LayoutGuess
    /// The engine's readings, best first; empty: the column check at once.
    var readings: [FileReading] = []
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
    /// Files whose layout the person confirms first, one sheet at a time (phone mode).
    private(set) var layoutQueue: [LayoutRequest] = []
    /// Phone mode: an import that added payments ended while no category is chosen, so the category picker shows over
    /// the app (ContentView), saying they are in; ticking sorts them at once. Decided here, at the import's end, for
    /// every way files come in (`finishIfDone`).
    private(set) var asksForCategories = false
    /// Payments the import under way has added so far: all its files, those confirmed in the file check window too.
    @ObservationIgnored private var addedSoFar = 0
    private var generation = 0
    private var uploadID: UUID?
    private let dashboard: DashboardStore
    /// Tests give imports a server of their own; otherwise they go where the dashboard's data comes from.
    private let fixedBackend: (any AresiumBackend)?
    private let background: any ImportBackgroundActivity
    private let maximumRequestBytes: Int
    /// Where a confirmed unknown bank's format goes when the person sends it (phone mode); nil: never offered.
    private let outbox: BankOutbox?

    var isBusy: Bool { readingCount > 0 || isImporting || batchScheduled }
    var waitingCount: Int { pending.count + attempted.count }
    var canRetry: Bool { !attempted.isEmpty && !isImporting && (isReady || dashboard.isSample) }
    /// A swipe down on the result does what its Dismiss does, or the send card's Not now (both `close()`), brief 41.
    /// Not while Retry and Discard are offered: a swipe would put the files aside without a choice. Not while the
    /// format is being sent, when Not now waits too.
    var closesBySwipe: Bool {
        guard let banner, !canRetry else { return false }
        return banner.share?.shown != .sending
    }
    var layoutRequest: LayoutRequest? { layoutQueue.first }

    /// Imports go where the dashboard's data comes from (`DashboardStore.backend`).
    init(dashboard: DashboardStore, background: any ImportBackgroundActivity = ApplicationImportActivity(),
         maximumRequestBytes: Int = ImportRequestPlan.maximumBytes, outbox: BankOutbox? = nil) {
        self.dashboard = dashboard
        fixedBackend = nil
        self.background = background
        self.maximumRequestBytes = maximumRequestBytes
        self.outbox = outbox
        // Files on their way to the server go with its login; the phone's imports do not depend on one.
        dashboard.session.onAppDataReset { [weak self] in
            if self?.backend?.mode == .server { self?.discard() }
        }
    }

    /// Imports to this server (tests).
    init(dashboard: DashboardStore, client: APIClient,
         background: any ImportBackgroundActivity = ApplicationImportActivity(),
         maximumRequestBytes: Int = ImportRequestPlan.maximumBytes) {
        self.dashboard = dashboard
        fixedBackend = ServerBackend(client: client)
        self.background = background
        self.maximumRequestBytes = maximumRequestBytes
        outbox = nil
        // Files on their way to the server go with its login; the phone's imports do not depend on one.
        dashboard.session.onAppDataReset { [weak self] in
            if self?.backend?.mode == .server { self?.discard() }
        }
    }

    private var backend: (any AresiumBackend)? { fixedBackend ?? dashboard.backend }
    /// The mode is known and its backend can take files (the server needs the login).
    private var isReady: Bool { backend?.isReady(dashboard.session) ?? false }

    func showSampleUnavailable() { show("Not available with sample data", success: false) }

    func show(_ message: String, success: Bool, files: [String] = [], share: BankFormatCard? = nil,
              results: [ImportFileResult] = []) {
        bannerTask?.cancel()
        let banner = ImportBanner(message: message, success: success, files: files, share: share, results: results)
        self.banner = banner
        // With the send card the result waits for an answer; once answered it goes after the same pause. (Only the id
        // is captured: the banner holds the card, so capturing it would keep both alive.)
        let id = banner.id
        share?.onAnswered = { [weak self] in self?.dismissLater(id) }
        guard success, share == nil else { return }
        dismissLater(id)
    }

    private func dismissLater(_ id: UUID) {
        bannerTask?.cancel()
        bannerTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(4500)) } catch { return }
            if self?.banner?.id == id { self?.banner = nil }
        }
    }

    func dismiss() { bannerTask?.cancel(); banner = nil }

    /// The person closes the result: a send card not answered yet counts as "Not now" (never asked again for that
    /// layout).
    func close() {
        banner?.share?.notNow()
        dismiss()
    }

    func discard() {
        generation += 1
        addedSoFar = 0
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
        layoutQueue.removeAll()
        dismiss()
    }

    func receive(_ urls: [URL], source: ImportFileSource = .picker) async {
        guard !dashboard.isSample else { showSampleUnavailable(); return }
        let generation = generation
        // Before the mode is known (files shared before login), only what both modes read.
        let extensions = backend?.importExtensions ?? ImportFileReader.serverExtensions
        readingCount += 1
        defer { readingCount -= 1; schedulePendingImport(); finishIfDone() }
        do {
            // Capture the bytes while access is available; shared Inbox copies are removed after reading.
            let files = try await Task.detached {
                try ImportFileReader.read(urls, source: source, extensions: extensions)
            }.value
            guard generation == self.generation else { return }
            pending.append(contentsOf: files)
        } catch {
            guard generation == self.generation else { return }
            show(error.localizedDescription, success: false)
        }
    }

    /// The login or the mode changed: files waiting for either are imported now. The category picker an import of the
    /// phone's store asked for is not asked any more once the app left phone mode.
    func sessionChanged() async {
        if asksForCategories, backend?.waitsForCategories != true { asksForCategories = false }
        if isReady { await importPendingFiles() }
    }

    func importPendingFiles() async {
        batchTask?.cancel()
        batchTask = nil
        batchScheduled = false
        guard !isImporting, readingCount == 0, let backend, backend.isReady(dashboard.session) else { return }
        let token = dashboard.session.token
        if attempted.isEmpty { attempted = pending; pending.removeAll() }
        guard !attempted.isEmpty else { return }
        isImporting = true
        let id = UUID()
        uploadID = id
        let generation = generation
        let sessionGeneration = dashboard.session.generation
        let task = Task {
            await self.upload(backend: backend, token: token, generation: generation, sessionGeneration: sessionGeneration)
            guard self.uploadID == id else { return }
            self.background.end()
            self.uploadTask = nil
            self.uploadID = nil
            self.isImporting = false
            self.schedulePendingImport()
            self.finishIfDone()
        }
        uploadTask = task
        background.begin { [weak self] in self?.uploadTask?.cancel() }
        await task.value
    }

    private func upload(backend: any AresiumBackend, token: String?, generation: Int, sessionGeneration: Int) async {
        var results: [ImportFileResult] = []
        var changed = false
        // The server's answer belongs to the login it was sent with; the phone's store does not depend on the login.
        let current = { generation == self.generation
            && (backend.mode == .phone || sessionGeneration == self.dashboard.session.generation) }
        do {
            let plan = try backend.importPlan(attempted, maximumBytes: maximumRequestBytes)
            for file in plan.refused {
                results.append(.server(.init(name: file.name, added: 0, total: 0, account: nil, skipped: false,
                                             error: String(localized: "Too large for a 25 MB import request"))))
            }
            let auth = BackendAuth(token: token) {
                if generation == self.generation {
                    self.dashboard.session.handleAuthFailure(HTTPError.unauthorized, generation: sessionGeneration,
                                                             token: token)
                }
            }
            for files in plan.batches {
                try Task.checkCancellation()
                let batch = try await backend.importFiles(files, auth: auth)
                guard current() else { return }
                try Task.checkCancellation()
                results.append(contentsOf: batch)
                addedSoFar += batch.reduce(0) { $0 + $1.added }
                changed = true
                // Keep failed files and any files the server did not report; completed requests need no retry. A file
                // whose layout the person confirms first waits in `layoutQueue`.
                for result in batch where !result.failed {
                    if let index = attempted.firstIndex(where: { $0.name == result.name }) {
                        let file = attempted.remove(at: index)
                        if let guess = result.layoutGuess {
                            layoutQueue.append(LayoutRequest(file: file, guess: guess, readings: result.readings))
                        }
                    }
                }
            }
            guard generation == self.generation else { return }
            show(backend.importSummary(results), success: attempted.isEmpty && !results.contains { $0.failed },
                 files: results.map(\.displayMessage), share: outbox?.card(for: results.compactMap(\.bankFormat)),
                 results: results)
        } catch {
            guard current() else { return }
            dashboard.session.handleAuthFailure(error, generation: sessionGeneration, token: token)
            guard generation == self.generation else { return }
            let message = error is CancellationError || (error as? URLError)?.code == .cancelled
                ? String(localized: "Import interrupted. Retry when you return to Aresium.") : error.localizedDescription
            show(message, success: false, files: results.map(\.displayMessage) + attempted.map { "\($0.name): \(message)" })
        }
        if changed, current() {
            await dashboard.reloadAfterImport()
        }
    }

    /// The person confirmed a file's layout (it is saved): the file is read again with it.
    func layoutConfirmed(_ request: LayoutRequest) {
        guard let index = layoutQueue.firstIndex(where: { $0.id == request.id }) else { return }
        layoutQueue.remove(at: index)
        pending.append(request.file)
        schedulePendingImport()
    }

    /// The person did not confirm a layout: the file is not imported.
    func layoutSkipped(_ request: LayoutRequest) {
        layoutQueue.removeAll { $0.id == request.id }
        finishIfDone()
    }

    // MARK: the category picker after an import

    /// An import is done when nothing is read, waiting, imported or checked in the file check window any more (files
    /// that failed and wait for Retry do not hold it: Retry is an import of its own). When it added payments while no
    /// category is chosen (phone mode), the category picker opens: once per import, whether the files came from the
    /// picker, the share sheet or the file check window. Not after a cancelled picker, a failed file, a file whose
    /// payments were all there already, or with categories chosen; a restore from an export and the tour do not import
    /// through here.
    private func finishIfDone() {
        guard !isBusy, pending.isEmpty, layoutQueue.isEmpty else { return }
        let added = addedSoFar
        addedSoFar = 0
        guard added > 0, backend?.waitsForCategories == true else { return }
        bannerTask?.cancel()            // the result waits under the picker; it is counted again when the picker closes
        asksForCategories = true
    }

    /// The category picker after an import closed (Done, or swiped away; closing with nothing ticked is allowed: the
    /// payments stay Not sorted and the next import asks again). The result line is counted again as the store holds
    /// it now, so it never claims numbers the picker changed, then goes after the usual pause.
    @discardableResult
    func categoriesClosed() -> Task<Void, Never>? {
        guard asksForCategories else { return nil }
        asksForCategories = false
        return Task { await recountBanner() }
    }

    private func recountBanner() async {
        guard let shown = banner, !shown.results.isEmpty, let backend else { return }
        do {
            let results = try await backend.recount(shown.results)
            guard banner?.id == shown.id else { return }        // a newer result is showing
            banner?.message = backend.importSummary(results)
            banner?.results = results
        } catch {
            // The numbers could not be read again: the line goes rather than claim old ones.
            if banner?.id == shown.id { dismiss() }
            return
        }
        if shown.success, shown.share == nil { dismissLater(shown.id) }
    }

    private func schedulePendingImport() {
        guard attempted.isEmpty, !pending.isEmpty, readingCount == 0, !isImporting, isReady else { return }
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
    /// `-sampleLayout`: imports made-up files as if they were picked.
    func debugImport(_ files: [ImportFile]) {
        pending.append(contentsOf: files)
        schedulePendingImport()
    }
    /// `-sampleImportResult` in the phone sample: an import's result that stays (no timer), for screenshots.
    func debugShowResult(_ message: String, files: [String]) {
        bannerTask?.cancel()
        banner = ImportBanner(message: message, success: true, files: files)
    }
    func seedDebugImportFailure() {
        attempted = [ImportFile(name: "bank.csv", content: "fictional")]
        show("Import failed", success: false, files: ["bank.csv: Unknown format"])
    }
    #endif

}
