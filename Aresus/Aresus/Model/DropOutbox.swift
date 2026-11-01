import CryptoKit
import Foundation
import Network
import Observation
import UIKit

nonisolated struct DropFile: Sendable {
    enum Content: Sendable { case file(URL), data(Data) }
    var content: Content
    var suggestedName: String
    /// An optional name edited by the user; keeps the original source kind for recent folders.
    var name: String?
    var source: DropSource = .file
    var date: Date = .now
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
}

nonisolated enum DropLocalError: LocalizedError {
    case unreadableFile, invalidName, invalidFolder
    var errorDescription: String? {
        switch self {
        case .unreadableFile: String(localized: "The file could not be read.")
        case .invalidName: String(localized: "The file name is not allowed.")
        case .invalidFolder: String(localized: "The folder name is not allowed.")
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
    private var backgroundTask = UIBackgroundTaskIdentifier.invalid
    @ObservationIgnored private var monitor: NWPathMonitor?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init(session: EmpireSession, client: AresusAPI = AresusAPI(), directory: URL? = nil, automatic: Bool = true) {
        self.session = session
        self.client = client
        self.directory = directory ?? URL.applicationSupportDirectory.appending(path: "Drops", directoryHint: .isDirectory)
        self.automatic = automatic
        do {
            try prepareDirectory()
            let urls = try FileManager.default.contentsOfDirectory(at: self.directory, includingPropertiesForKeys: nil)
            for url in urls where url.pathExtension == "json" {
                do {
                    var item = try JSONDecoder().decode(DropOutboxItem.self, from: Data(contentsOf: url))
                    // Records never supply an arbitrary filesystem path, even if damaged.
                    guard item.localFile == item.id.uuidString + ".file", url.lastPathComponent == item.id.uuidString + ".json" else {
                        throw DropLocalError.unreadableFile
                    }
                    if item.state == .uploading { item.state = .onPhone }
                    items.append(item)
                } catch { storageError = error.localizedDescription }
            }
            items.sort { $0.created < $1.created }
            let retained = Set(items.map(\.localFile))
            for url in urls where storageError == nil && url.pathExtension == "file" && !retained.contains(url.lastPathComponent) {
                // A crash during import may leave a copied file whose record was never committed.
                if UUID(uuidString: url.deletingPathExtension().lastPathComponent) != nil {
                    try FileManager.default.removeItem(at: url)
                }
            }
        } catch { storageError = error.localizedDescription }
        session.onAppDataReset { [weak self] in self?.clear() }
        session.onSignIn { [weak self] in self?.start() }
        if automatic { observeLifecycle(); start() }
    }

    /// Import while the picker still grants access. The queued copy is independent of the source afterwards.
    @discardableResult
    func enqueue(_ file: DropFile, name: String, target: Target?) async throws -> UUID {
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
        items.append(item)
        start()
        return id
    }

    func retry(_ id: UUID) async {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].state = .onPhone
        items[index].retryAt = nil
        items[index].lastError = nil
        // A manual retry is a new chance to check the file; automatic checksum retries remain limited to one.
        items[index].checksumRetries = 0
        do { try save(items[index]) } catch { storageError = error.localizedDescription; return }
        await process()
    }

    /// Cancel the current request before DELETE. A failed DELETE stays durable and can be retried offline.
    func remove(_ id: UUID) async {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].cancellationRequested = true
        items[index].state = .onPhone
        items[index].retryAt = nil
        do { try save(items[index]) } catch { storageError = error.localizedDescription; return }
        removing = true
        worker?.cancel()
        await worker?.value
        removing = false
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
        generation += 1
        worker?.cancel()
        wakeup?.cancel()
        wakeup = nil
        items = []
        storageError = nil
        do {
            if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
        } catch { storageError = error.localizedDescription }
        endBackgroundTime()
    }

    private func drain() async {
        let epoch = generation
        defer {
            worker = nil
            endBackgroundTime()
            if automatic { scheduleWakeup() }
        }
        while !Task.isCancelled, epoch == generation, session.isSignedIn,
              let item = items.first(where: { $0.state != .failed && ($0.retryAt.map { $0 <= .now } ?? true) }) {
            await attempt(item.id, epoch: epoch)
        }
    }

    private func attempt(_ id: UUID, epoch: Int) async {
        guard let token = session.token, let initial = item(id) else { return }
        let login = session.generation
        do {
            try update(id) { $0.attempts += 1; $0.state = .uploading; $0.lastError = nil; $0.retryAt = nil }
            if UIApplication.shared.applicationState == .background { beginBackgroundTime() }
            if initial.cancellationRequested {
                if let serverID = initial.serverID { try await client.cancel(serverID, token: token) }
                guard epoch == generation else { return }
                try discard(id)
                return
            }
            let url = directory.appendingPathComponent(initial.localFile)
            let fingerprint = try await DropFileIO.fingerprint(url)
            guard epoch == generation else { return }
            try Task.checkCancellation()
            try update(id) { $0.drop.size = fingerprint.size; $0.drop.sha256 = fingerprint.sha256 }
            guard var current = item(id) else { return }
            if current.serverID == nil {
                // TODO(api): version 1 has no idempotency key or lookup for a lost POST response.
                // A saved id prevents repeat creates; an interrupted POST without an id cannot be reconciled.
                let created = try await client.create(current.drop, token: token)
                guard epoch == generation else { return }
                // Save even when removal cancelled this task while POST was returning; DELETE needs this id.
                try update(id) { $0.serverID = created.id }
            }
            try Task.checkCancellation()
            while let pending = item(id), let serverID = pending.serverID {
                guard !pending.cancellationRequested else { throw CancellationError() }
                do {
                    let uploaded = try await client.upload(serverID, fileURL: url, token: token)
                    guard epoch == generation else { return }
                    try Task.checkCancellation()
                    onUploaded?(uploaded)
                    try discard(id)
                    return
                } catch HTTPError.server(400, let sentence) {
                    guard epoch == generation else { return }
                    try Task.checkCancellation()
                    current = item(id) ?? current
                    guard current.checksumRetries == 0 else { throw HTTPError.server(400, sentence) }
                    try update(id) { $0.checksumRetries += 1 }
                    let checked = try await DropFileIO.fingerprint(url)
                    guard epoch == generation else { return }
                    try Task.checkCancellation()
                    try update(id) { $0.drop.size = checked.size; $0.drop.sha256 = checked.sha256 }
                }
            }
        } catch {
            guard epoch == generation, item(id) != nil else { return }
            if Task.isCancelled || error is CancellationError {
                try? update(id) { $0.state = .onPhone }
                return
            }
            session.handleAuthFailure(error, generation: login, token: token)
            guard epoch == generation else { return }
            do {
                try update(id) {
                    $0.lastError = Self.message(error)
                    if Self.canRetry(error) {
                        $0.state = .onPhone
                        $0.retryAt = Date.now.addingTimeInterval(Self.retryDelay(attempts: $0.attempts))
                    } else {
                        $0.state = .failed
                        $0.retryAt = nil
                    }
                }
            } catch { storageError = error.localizedDescription }
        }
    }

    static func retryDelay(attempts: Int) -> TimeInterval { min(600, 5 * pow(2, Double(min(10, max(0, attempts - 1))))) }

    private static func canRetry(_ error: Error) -> Bool {
        if case HTTPError.server(let status, _) = error { return status >= 500 && status <= 599 && status != 507 }
        if let error = error as? URLError {
            return [.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotConnectToHost,
                    .cannotFindHost, .dnsLookupFailed, .internationalRoamingOff, .dataNotAllowed].contains(error.code)
        }
        return false
    }

    static func message(_ error: Error) -> String {
        if error is DecodingError { return String(localized: "The server's answer could not be read.") }
        if let error = error as? URLError, error.code == .notConnectedToInternet { return String(localized: "No connection.") }
        if error is CocoaError { return String(localized: "The file could not be read.") }
        return error.localizedDescription
    }

    private func item(_ id: UUID) -> DropOutboxItem? { items.first { $0.id == id } }

    private func update(_ id: UUID, _ change: (inout DropOutboxItem) -> Void) throws {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        change(&items[index])
        try save(items[index])
    }

    private func prepareDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var url = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
    }

    private func save(_ item: DropOutboxItem) throws {
        try JSONEncoder().encode(item).write(to: directory.appendingPathComponent(item.id.uuidString + ".json"), options: .atomic)
    }

    private func discard(_ id: UUID) throws {
        guard let item = item(id) else { return }
        let file = directory.appendingPathComponent(item.localFile)
        if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
        try FileManager.default.removeItem(at: directory.appendingPathComponent(id.uuidString + ".json"))
        items.removeAll { $0.id == id }
    }

    private func scheduleWakeup() {
        wakeup?.cancel()
        guard !removing, session.isSignedIn,
              let next = items.filter({ $0.state != .failed }).map({ $0.retryAt ?? .now }).min() else { return }
        wakeup = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(max(0.1, next.timeIntervalSinceNow))) } catch { return }
            self?.start()
        }
    }

    private func observeLifecycle() {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            if path.status == .satisfied { Task { @MainActor [weak self] in self?.start() } }
        }
        monitor.start(queue: DispatchQueue(label: "de.ares-empire.aresus.drops-network"))
        self.monitor = monitor
        observers.append(NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification,
                                                               object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.start() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification,
                                                               object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.worker != nil else { return }
                self.beginBackgroundTime()
            }
        })
    }

    private func beginBackgroundTime() {
        guard backgroundTask == .invalid else { return }
        backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Drop upload") { [weak self] in
            Task { @MainActor [weak self] in
                self?.worker?.cancel()
                self?.endBackgroundTime()
            }
        }
    }

    private func endBackgroundTime() {
        guard backgroundTask != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTask)
        backgroundTask = .invalid
    }

    isolated deinit {
        monitor?.cancel()
        observers.forEach(NotificationCenter.default.removeObserver)
        wakeup?.cancel()
        worker?.cancel()
        if backgroundTask != .invalid { UIApplication.shared.endBackgroundTask(backgroundTask) }
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
