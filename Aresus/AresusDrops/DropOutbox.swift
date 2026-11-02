import CryptoKit
import Foundation
import Network
import Observation

nonisolated struct DropFile: Sendable {
    enum Content: Sendable { case file(URL), data(Data) }
    var content: Content
    var suggestedName: String
    /// An optional name edited by the user; keeps the original source kind for recent folders.
    var name: String?
    var source: DropSource = .file
    var date: Date = .now
    var identity: String?
}

nonisolated struct DropOutboxItem: Codable, Equatable, Identifiable, Sendable {
    enum State: String, Codable, Sendable { case onPhone, uploading, failed }
    var id: UUID
    var drop: NewDrop
    /// A relative, generated name, never the source URL (which may only be readable during import).
    var localFile: String
    var serverID: Int?
    var created: Date
    var attempts = 0
    var lastError: String?
    var state: State = .onPhone
    var retryAt: Date?
    var checksumRetries = 0
    var cancellationRequested = false
    var uploadSession: String?
    var uploadAttempt: UUID?
}

nonisolated enum DropLocalError: LocalizedError {
    case unreadableFile, invalidName, invalidFolder
    var errorDescription: String? {
        switch self {
        case .unreadableFile: String(localized: LocalizedStringResource("The file could not be read.", table: "AresusDrops", locale: .appLanguage))
        case .invalidName: String(localized: LocalizedStringResource("The file name is not allowed.", table: "AresusDrops", locale: .appLanguage))
        case .invalidFolder: String(localized: LocalizedStringResource("The folder name is not allowed.", table: "AresusDrops", locale: .appLanguage))
        }
    }
}

/// Small durable records are changed on the main actor. File copying and streaming SHA-256 run off it.
/// A record is saved before any request; a returned server id is saved before uploading bytes.
@MainActor @Observable
final class DropOutbox {
    private(set) var items: [DropOutboxItem] = []
    private(set) var storageError: String?
    var onUploaded: ((Drop) -> Void)?
    let directory: URL
    private let session: EmpireSession
    private let client: AresusAPI
    private let automatic: Bool
    private var generation = 0
    private var worker: Task<Void, Never>?
    private var wakeup: Task<Void, Never>?
    private var removing = false
    private var recovered: [String: DropOutbox] = [:]
    private let activity: (any DropActivity)?
    private let uploads: any DropUploading
    private var journal: DropJournal { DropJournal(directory: directory) }
    private let hasContainer: Bool
    @ObservationIgnored private var monitor: NWPathMonitor?

    init(session: EmpireSession, client: AresusAPI = AresusAPI(), directory: URL? = nil, automatic: Bool = true,
         activity: (any DropActivity)? = nil, legacyDirectory: URL? = nil, uploads: (any DropUploading)? = nil) {
        self.session = session
        self.client = client
        hasContainer = directory != nil || DropContainer.url != nil
        self.directory = directory ?? DropContainer.url?.appending(path: "Drops", directoryHint: .isDirectory)
            ?? URL.applicationSupportDirectory.appendingPathComponent("UnavailableDropGroup")
        self.automatic = automatic
        self.activity = activity
        self.uploads = uploads ?? DropBackgroundUploads.live()
        do {
            try prepareDirectory()
            if let legacyDirectory { try journal.migrate(from: legacyDirectory) }
        } catch { storageError = error.localizedDescription }
        reload()
        (self.uploads as? DropBackgroundUploads)?.outbox = self
        self.uploads.completed = { [weak self] id, result, token in
            await self?.finished(id, result: result, token: token)
        }
        session.onAppDataReset { [weak self] in self?.clear() }
        session.onSignIn { [weak self] in self?.start() }
        if automatic {
            observeNetwork()
            activity?.observe(active: { [weak self] in self?.reload(); self?.start() },
                              expiring: { [weak self] in self?.worker?.cancel() })
            start()
        }
    }

    /// Another process may have queued, cancelled or finished a drop. Always replace the in-memory snapshot; never
    /// write that snapshot back over a record the other process has advanced.
    func reload() {
        guard hasContainer else { storageError = DropLocalError.unreadableFile.localizedDescription; return }
        do {
            items = try journal.locked {
                guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
                var loaded: [DropOutboxItem] = []
                for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                    where url.pathExtension == "json" {
                    do {
                        guard let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent),
                              var item = try journal.read(id) else { throw DropLocalError.unreadableFile }
                        // Old foreground uploads have no background task to reconnect.
                        if item.state == .uploading && item.uploadSession == nil, let idle = journal.claim(id) {
                            item.state = .onPhone
                            withExtendedLifetime(idle) {}
                        }
                        loaded.append(item)
                    } catch { storageError = error.localizedDescription }
                }
                return loaded.sorted { $0.created < $1.created }
            }
        } catch { storageError = error.localizedDescription }
    }

    /// Reconcile only this driver's tasks. An upload owned by the other process stays uploading until that process
    /// (or the app woken for its session) handles it. A crash between saving the intent and task creation is retried.
    func restoreForEvents() async {
        while session.isBusy { try? await Task.sleep(for: .milliseconds(50)) }
        if !session.isSignedIn { await session.restore() }
    }

    func reconnect() async {
        reload()
        let active = await uploads.activeIDs()
        for item in items where item.uploadSession == uploads.identifier && !active.contains(item.id) {
            guard let lease = journal.claim(item.id) else { continue }
            defer { withExtendedLifetime(lease) {} }
            let epoch = generation
            let login = session.generation
            let token = session.token
            if let token, let serverID = item.serverID, !item.cancellationRequested {
                do {
                    // The server may have accepted the bytes just before a force quit. Do not turn that into a
                    // second PUT (409); the existing list tells us whether the upload already reached the server.
                    let server = try await client.drops(token: token)
                    guard epoch == generation else { continue }
                    if let accepted = server.first(where: { $0.id == serverID && $0.state != .uploading }) {
                        try discard(item.id)
                        onUploaded?(accepted)
                        continue
                    }
                } catch {
                    session.handleAuthFailure(error, generation: login, token: token)
                }
            }
            guard epoch == generation else { continue }
            withExtendedLifetime(lease) {
                try? update(item.id) { $0.uploadSession = nil; $0.state = .onPhone }
            }
        }
    }

    /// Called by the foreground app, when the share host has closed. This also repairs uploads iOS cancelled after
    /// a force quit: each saved session is reattached and its actual tasks reconciled before any retry is made.
    func recoverSharedUploads() async {
        reload()
        let identifiers = Set(items.compactMap(\.uploadSession)).filter {
            $0 != uploads.identifier && DropContainer.ownsSession($0)
        }
        for identifier in identifiers {
            let driver = DropBackgroundUploads.driver(identifier: identifier)
            let recovery = driver.outbox ?? DropOutbox(session: session, client: client, directory: directory,
                                                       automatic: false, uploads: driver)
            recovered[identifier] = recovery
            recovery.onUploaded = { [weak self] drop in self?.onUploaded?(drop) }
            driver.completed = { [weak self, recovery] id, result, token in
                await recovery.finished(id, result: result, token: token)
                self?.reload()
                self?.start()
            }
            await recovery.reconnect()
            // An absent task is returned to the main app's queue, which uses its own session for the retry.
            if await driver.activeIDs().isEmpty {
                driver.invalidate()
                recovered[identifier] = nil
            }
        }
        reload()
    }

    /// Import while the picker still grants access. The queued copy is independent of the source afterwards.
    @discardableResult
    func enqueue(_ file: DropFile, name: String, target: Target?) async throws -> UUID {
        session.followMarker()
        guard session.isSignedIn else { throw HTTPError.unauthorized }
        guard DropNames.newName(name) == nil else { throw DropLocalError.invalidName }
        if let target {
            guard DropNames.folderPath(target.folder) == nil,
                  target.newFolder.map({ DropNames.newName($0) == nil }) ?? true else { throw DropLocalError.invalidFolder }
        }
        let epoch = generation
        try prepareDirectory()
        let id = UUID()
        let destination = directory.appendingPathComponent(id.uuidString + ".file")
        do { try await DropFileIO.copy(file.content, to: destination) }
        catch {
            try? FileManager.default.removeItem(at: destination)
            throw DropLocalError.unreadableFile
        }
        session.followMarker()
        guard generation == epoch else {
            try? FileManager.default.removeItem(at: destination)
            throw CancellationError()
        }
        let normalizedTarget = target.map {
            Target(root: $0.root, folder: DropNames.normalized($0.folder), newFolder: $0.newFolder.map(DropNames.normalized))
        }
        let item = DropOutboxItem(id: id, drop: NewDrop(kind: .file, name: DropNames.normalized(name), size: 0,
                                                       sha256: "", target: normalizedTarget, receipt: nil),
                                 localFile: destination.lastPathComponent, created: .now)
        do { try save(item) }
        catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
        reload()
        start()
        return id
    }

    func retry(_ id: UUID) async {
        reload()
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        guard items[index].uploadSession == nil else { return }
        do {
            try update(id) {
                $0.state = .onPhone; $0.retryAt = nil; $0.lastError = nil; $0.checksumRetries = 0
            }
        } catch { storageError = error.localizedDescription; return }
        await process()
    }

    /// Cancel the current request before DELETE. A failed DELETE stays durable and can be retried offline.
    /// While it waits the item is out of the list (`DropsStore.merge`): the upload has stopped, so the Mac never gets it.
    func remove(_ id: UUID) async {
        reload()
        guard item(id) != nil else { return }
        do {
            try update(id) { $0.cancellationRequested = true; $0.retryAt = nil }
        } catch { storageError = error.localizedDescription; return }
        if let owner = item(id)?.uploadSession, owner != uploads.identifier, DropContainer.ownsSession(owner) {
            let foreign = DropBackgroundUploads.driver(identifier: owner)
            await foreign.cancel(id)
            if foreign.outbox == nil { foreign.invalidate() }
        } else { await uploads.cancel(id) }
        removing = true
        worker?.cancel()
        await worker?.value
        removing = false
        // A task owned by another process is cancelled by its owner on reload; DELETE also prevents its acceptance.
        try? update(id) { $0.state = .onPhone; $0.uploadSession = nil }
        await process()
    }

    func start() {
        guard automatic, !removing, worker == nil, session.isSignedIn else { return }
        worker = Task { [weak self] in
            guard let self else { return }
            await self.drain()
        }
    }

    /// Also used by tests: one serial pass through all eligible items, without waiting for a retry deadline.
    func process() async {
        guard !removing, session.isSignedIn else { return }
        if let worker { await worker.value; return }
        let task = Task { [weak self] in
            guard let self else { return }
            await self.drain()
        }
        worker = task
        await task.value
    }

    func clear() {
        guard hasContainer else { return }
        generation += 1
        worker?.cancel()
        wakeup?.cancel()
        wakeup = nil
        reload()
        let cancelling = items.map { ($0.id, $0.uploadSession) }
        Task { [uploads] in
            for (id, owner) in cancelling {
                if let owner, owner != uploads.identifier, DropContainer.ownsSession(owner) {
                    let driver = DropBackgroundUploads.driver(identifier: owner)
                    await driver.cancel(id)
                    if driver.outbox == nil { driver.invalidate() }
                } else { await uploads.cancel(id) }
            }
        }
        items = []
        storageError = nil
        do {
            if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
        } catch { storageError = error.localizedDescription }
        activity?.end()
    }

    private func drain() async {
        let epoch = generation
        defer {
            worker = nil
            activity?.end()
            if automatic { scheduleWakeup() }
        }
        activity?.begin()
        reload()
        var visited = Set<UUID>()
        while !Task.isCancelled, epoch == generation, session.isSignedIn,
              let item = items.first(where: { !visited.contains($0.id) && $0.state != .failed && $0.uploadSession == nil
                  && ($0.retryAt.map { $0 <= .now } ?? true) }) {
            visited.insert(item.id)
            guard let lease = journal.claim(item.id) else { continue }
            reload()
            if let current = self.item(item.id), current.uploadSession == nil {
                await attempt(item.id, epoch: epoch)
            }
            withExtendedLifetime(lease) {}
            reload()
            if let after = self.item(item.id), after.state == .onPhone && after.retryAt == nil && after.uploadSession == nil {
                visited.remove(item.id)
            }
        }
    }

    private func attempt(_ id: UUID, epoch: Int) async {
        session.followMarker()
        guard let token = session.token, let initial = item(id) else { return }
        let login = session.generation
        do {
            try update(id) { $0.attempts += 1; $0.state = .uploading; $0.lastError = nil; $0.retryAt = nil }
            if initial.cancellationRequested {
                if let serverID = initial.serverID { try await client.delete(serverID, token: token) }
                guard epoch == generation else { return }
                try discard(id)
                return
            }
            let url = directory.appendingPathComponent(initial.localFile)
            let fingerprint = try await DropFileIO.fingerprint(url)
            guard epoch == generation else { return }
            try Task.checkCancellation()
            try update(id) { $0.drop.size = fingerprint.size; $0.drop.sha256 = fingerprint.sha256 }
            guard let current = item(id) else { return }
            if current.serverID == nil {
                // TODO(api): version 1 has no idempotency key or lookup for a lost POST response.
                // A saved id prevents repeat creates; an interrupted POST without an id cannot be reconciled.
                let created = try await client.create(current.drop, token: token)
                guard epoch == generation else { return }
                // Save even when removal cancelled this task while POST was returning; DELETE needs this id.
                try update(id) { $0.serverID = created.id }
            }
            try Task.checkCancellation()
            guard let pending = item(id), let serverID = pending.serverID, !pending.cancellationRequested else {
                throw CancellationError()
            }
            let request = try client.uploadRequest(serverID, token: token)
            // Save the background session's ownership before handing over the file. Reconnect repairs an interrupted
            // hand-over. No bytes go until the durable server id is present.
            let upload = DropUploadID(record: id)
            try update(id) { $0.uploadSession = uploads.identifier; $0.uploadAttempt = upload.attempt }
            try await uploads.submit(upload, request: request, file: url, earliestBeginDate: nil)
        } catch {
            guard epoch == generation, item(id) != nil else { return }
            if Task.isCancelled || error is CancellationError {
                try? update(id) { $0.state = .onPhone }
                return
            }
            fail(id, error: error, login: login, token: token)
        }
    }

    /// Called by whichever process receives iOS's completion, after reading the current record under the journal
    /// lock. The other process sees it disappear (or its retry state) on its next reload.
    func finished(_ upload: DropUploadID, result: Result<Drop, Error>, token: String?) async {
        session.followMarker()
        let id = upload.record
        reload()
        guard let pending = item(id), pending.uploadAttempt == upload.attempt else { return } // deleted, logged out or retried meanwhile
        if pending.cancellationRequested {
            try? update(id) { $0.uploadSession = nil; $0.state = .onPhone }
            start()
            return
        }
        switch result {
        case .success(let drop):
            do { try discard(id); onUploaded?(drop) }
            catch { storageError = error.localizedDescription }
        case .failure(let error):
            if case HTTPError.server(400, _) = error, pending.checksumRetries == 0 {
                do {
                    let checked = try await DropFileIO.fingerprint(directory.appendingPathComponent(pending.localFile))
                    try update(id) {
                        $0.checksumRetries += 1; $0.drop.size = checked.size; $0.drop.sha256 = checked.sha256
                        $0.state = .onPhone; $0.uploadSession = nil
                    }
                    // A single checksum retry, including during a background event delivery.
                    if uploads.supportsDeferredRetry {
                        await worker?.value
                        await process()
                    } else if worker == nil { await process() }
                } catch { fail(id, error: error, login: session.generation, token: token) }
            } else { fail(id, error: error, login: session.generation, token: token) }
        }
        if uploads.supportsDeferredRetry {
            await worker?.value
            await scheduleDeferredRetry(id)
        }
        if automatic { scheduleWakeup() }
    }

    /// Give a timed retry to the daemon before the extension/event delivery closes. A Task.sleep in this process
    /// alone would stop working as soon as iOS suspended it. The file and server id are already durable.
    private func scheduleDeferredRetry(_ id: UUID) async {
        reload()
        guard let pending = item(id), pending.state == .onPhone, !pending.cancellationRequested,
              pending.uploadSession == nil, let deadline = pending.retryAt, let serverID = pending.serverID,
              let token = session.token, session.isSignedIn, let lease = journal.claim(id) else { return }
        defer { withExtendedLifetime(lease) {} }
        do {
            let ticket = DropUploadID(record: id)
            let request = try client.uploadRequest(serverID, token: token)
            try update(id) {
                $0.uploadSession = uploads.identifier; $0.uploadAttempt = ticket.attempt; $0.attempts += 1
            }
            try await uploads.submit(ticket, request: request, file: directory.appendingPathComponent(pending.localFile),
                                     earliestBeginDate: deadline)
        } catch {
            try? update(id) { $0.uploadSession = nil }
            storageError = error.localizedDescription
        }
    }

    private func fail(_ id: UUID, error: Error, login: Int, token: String?) {
        session.handleAuthFailure(error, generation: login, token: token)
        guard item(id) != nil else { return }
        do {
            try update(id) {
                $0.uploadSession = nil
                $0.lastError = Self.message(error)
                if Self.canRetry(error) || (error as? URLError)?.code == .cancelled
                    || (session.isSignedIn && session.token != token && Self.isUnauthorized(error)) {
                    $0.state = .onPhone
                    $0.retryAt = Date.now.addingTimeInterval(Self.retryDelay(attempts: $0.attempts))
                } else {
                    $0.state = .failed; $0.retryAt = nil
                    if $0.cancellationRequested { $0.cancellationRequested = false }
                }
            }
        } catch { storageError = error.localizedDescription }
    }

    static func retryDelay(attempts: Int) -> TimeInterval { min(600, 5 * pow(2, Double(min(10, max(0, attempts - 1))))) }

    private static func isUnauthorized(_ error: Error) -> Bool {
        if case HTTPError.unauthorized = error { return true }
        return false
    }

    private static func canRetry(_ error: Error) -> Bool {
        if case HTTPError.server(let status, _) = error { return status >= 500 && status <= 599 && status != 507 }
        if let error = error as? URLError {
            return [.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotConnectToHost,
                    .cannotFindHost, .dnsLookupFailed, .internationalRoamingOff, .dataNotAllowed].contains(error.code)
        }
        return false
    }

    static func message(_ error: Error) -> String {
        if error is DecodingError { return String(localized: LocalizedStringResource("The server's answer could not be read.", table: "AresusDrops", locale: .appLanguage)) }
        if let error = error as? URLError, error.code == .notConnectedToInternet { return String(localized: LocalizedStringResource("No connection.", table: "AresusDrops", locale: .appLanguage)) }
        if error is CocoaError { return String(localized: LocalizedStringResource("The file could not be read.", table: "AresusDrops", locale: .appLanguage)) }
        return error.localizedDescription
    }

    private func item(_ id: UUID) -> DropOutboxItem? { items.first { $0.id == id } }

    private func update(_ id: UUID, _ change: (inout DropOutboxItem) -> Void) throws {
        try journal.locked {
            guard var current = try journal.read(id) else { return }
            change(&current)
            try journal.save(current)
        }
        reload()
    }

    private func prepareDirectory() throws {
        guard hasContainer else { throw DropLocalError.unreadableFile }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var url = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }

    private func save(_ item: DropOutboxItem) throws {
        try journal.locked { try journal.save(item) }
    }

    private func discard(_ id: UUID) throws {
        try journal.locked {
            guard let current = try journal.read(id) else { return }
            let file = directory.appendingPathComponent(current.localFile)
            if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
            try FileManager.default.removeItem(at: journal.record(id))
        }
        reload()
    }

    private func scheduleWakeup() {
        wakeup?.cancel()
        guard !removing, session.isSignedIn,
              let next = items.filter({ $0.state != .failed && $0.uploadSession == nil }).map({ $0.retryAt ?? .now }).min() else { return }
        wakeup = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(max(0.1, next.timeIntervalSinceNow))) } catch { return }
            self?.start()
        }
    }

    private func observeNetwork() {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            if path.status == .satisfied { Task { @MainActor [weak self] in self?.start() } }
        }
        monitor.start(queue: DispatchQueue(label: "de.ares-empire.aresus.drops-network"))
        self.monitor = monitor
    }

    isolated deinit {
        monitor?.cancel()
        wakeup?.cancel()
        worker?.cancel()
        activity?.end()
    }
}

nonisolated enum DropFileIO {
    struct Fingerprint: Sendable { var size: Int64; var sha256: String }

    @concurrent static func copy(_ content: DropFile.Content, to destination: URL) async throws {
        switch content {
        case .file(let source):
            let scoped = source.startAccessingSecurityScopedResource()
            defer { if scoped { source.stopAccessingSecurityScopedResource() } }
            try FileManager.default.copyItem(at: source, to: destination)
        case .data(let data): try data.write(to: destination, options: .atomic)
        }
    }

    @concurrent static func fingerprint(_ url: URL) async throws -> Fingerprint {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        var size: Int64 = 0
        while let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty {
            try Task.checkCancellation()
            size += Int64(data.count)
            hash.update(data: data)
        }
        return Fingerprint(size: size, sha256: hash.finalize().map { String(format: "%02x", $0) }.joined())
    }
}
