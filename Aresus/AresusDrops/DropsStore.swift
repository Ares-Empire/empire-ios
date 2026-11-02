import Foundation

/// Only the two drop answers are shared; the app's other sample models stay in the app.
protocol DropSamples: Sendable {
    func folders() throws -> FolderList
    func drops() throws -> [Drop]
}

import Observation

nonisolated enum DropsItem: Identifiable, Equatable, Sendable {
    case phone(DropOutboxItem)
    case server(Drop)
    var id: String {
        switch self {
        case .phone(let item): "phone-" + item.id.uuidString
        case .server(let drop): "server-\(drop.id)"
        }
    }
}

@MainActor @Observable
final class DropsStore {
    enum Part: Hashable { case folders, drops }
    private(set) var folders: FolderList?
    private(set) var serverDrops: [Drop] = []
    private(set) var errors: [Part: String] = [:]
    private(set) var loading: Set<Part> = []
    private(set) var loadedAt: [Part: Date] = [:]
    private(set) var cacheError: String?
    private(set) var samples: (any DropSamples)?
    private(set) var outbox: DropOutbox?
    private(set) var recentFolders: DropRecentFolders
    /// Server drops deleted on this iPhone (brief 93): out of the list at once, while the DELETE runs and after it (a
    /// list asked for before the DELETE may still hold them). One the server refuses leaves the set and comes back.
    private var deleted: Set<Int> = []
    private let session: EmpireSession
    private let client: AresusAPI
    private var cacheURL: URL?
    private let configuredCacheURL: URL?
    private let directory: URL?
    private let defaults: UserDefaults?
    private let automatic: Bool
    private let activity: (any DropActivity)?
    private let legacyDirectory: URL?
    private let legacyDefaults: UserDefaults?
    private let uploads: (any DropUploading)?
    private var generation = 0
    var isSample: Bool { samples != nil }

    var items: [DropsItem] { Self.merge(outbox: outbox?.items ?? [], server: serverDrops, deleted: deleted) }

    init(session: EmpireSession, client: AresusAPI = AresusAPI(), samples: (any DropSamples)? = nil,
         directory: URL? = nil, cacheURL: URL? = DropContainer.url?.appendingPathComponent("drop-folders.json"),
         defaults: UserDefaults? = UserDefaults(suiteName: DropContainer.appGroup), automatic: Bool = true,
         activity: (any DropActivity)? = nil, legacyDirectory: URL? = nil, legacyDefaults: UserDefaults? = nil,
         uploads: (any DropUploading)? = nil, legacyCacheURL: URL? = nil) {
        self.session = session
        self.client = client
        self.samples = samples
        self.directory = directory
        self.defaults = defaults
        self.automatic = automatic
        self.activity = activity
        self.legacyDirectory = legacyDirectory
        self.legacyDefaults = legacyDefaults
        self.uploads = uploads
        configuredCacheURL = cacheURL
        self.cacheURL = samples == nil ? cacheURL : nil
        recentFolders = DropRecentFolders(defaults: samples == nil ? defaults : nil, legacyDefaults: samples == nil ? legacyDefaults : nil)
        outbox = samples == nil ? DropOutbox(session: session, client: client, directory: directory, automatic: automatic, activity: activity, legacyDirectory: legacyDirectory, uploads: uploads) : nil
        if samples == nil, let cacheURL, let legacyCacheURL, cacheURL != legacyCacheURL,
           FileManager.default.fileExists(atPath: legacyCacheURL.path) {
            do {
                try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                if FileManager.default.fileExists(atPath: cacheURL.path) {
                    try FileManager.default.removeItem(at: legacyCacheURL)
                } else {
                    // Retire the old copy as it is published in the group. Leaving it in Caches would restore stale
                    // folders after logout had deliberately removed the group's cache.
                    try FileManager.default.moveItem(at: legacyCacheURL, to: cacheURL)
                }
            } catch { cacheError = error.localizedDescription }
        }
        if samples == nil, let cacheURL, let data = try? Data(contentsOf: cacheURL) {
            folders = try? AresusJSON.decoder().decode(FolderList.self, from: data)
        }
        observeUploads()
        session.onAppDataReset { [weak self] in self?.clear() }
    }

    /// The list: the phone's own items (oldest first) over the server's drops (newest first). A server drop stands for
    /// the phone's copy it came from. Left out: what is being deleted, the phone's items the outbox is removing (with
    /// their server drop) and the server drops in `deleted`.
    static func merge(outbox: [DropOutboxItem], server: [Drop], deleted: Set<Int> = []) -> [DropsItem] {
        let removing = deleted.union(outbox.filter(\.cancellationRequested).compactMap(\.serverID))
        let shown = server.filter { !removing.contains($0.id) }
        let ids = Set(shown.map(\.id))
        let phone = outbox.filter { !$0.cancellationRequested && ($0.serverID.map { !ids.contains($0) } ?? true) }
            .sorted { $0.created < $1.created }
        return phone.map(DropsItem.phone) + shown.sorted {
            $0.created == $1.created ? $0.id > $1.id : $0.created > $1.created
        }.map(DropsItem.server)
    }

    /// Independent errors and last good values, as in AresusStore. The tab can throttle its minute refresh.
    func refresh(olderThan age: TimeInterval = 0, now: Date = .now) async {
        for part in [Part.folders, .drops] where loadedAt[part].map({ now.timeIntervalSince($0) >= age }) ?? true {
            await load(part)
        }
        outbox?.reload()
        outbox?.start()
    }

    func load(_ part: Part) async {
        guard !loading.contains(part), isSample || session.isSignedIn else { return }
        let epoch = generation
        let login = session.generation
        let token = session.token
        func current() -> Bool { epoch == generation && login == session.generation }
        loading.insert(part)
        errors[part] = nil
        defer { if current() { loading.remove(part) } }
        do {
            switch part {
            case .folders:
                let answer: FolderList
                if let samples { answer = try samples.folders() }
                else {
                    guard let token else { throw HTTPError.unauthorized }
                    answer = try await client.folders(token: token)
                }
                guard current() else { return }
                folders = answer
                if let cacheURL {
                    do {
                        try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                        try AresusJSON.encoder().encode(answer).write(to: cacheURL, options: .atomic)
                        cacheError = nil
                    } catch { cacheError = error.localizedDescription }
                }
            case .drops:
                let answer: [Drop]
                if let samples { answer = try samples.drops() }
                else {
                    guard let token else { throw HTTPError.unauthorized }
                    answer = try await client.drops(token: token)
                }
                guard current() else { return }
                serverDrops = answer
            }
            loadedAt[part] = .now
        } catch {
            guard current() else { return }
            session.handleAuthFailure(error, generation: login, token: token)
            guard current() else { return }
            errors[part] = DropOutbox.message(error)
        }
    }

    /// A suggested file name is kept; photo/camera names use the capture date and original extension.
    /// DropFile.name overrides the default after the user edits it, retaining the original source kind.
    func send(files: [DropFile], target: Target?) async throws {
        guard isSample || session.isSignedIn else { throw HTTPError.unauthorized }
        let names = DropNames.unique(files.map { $0.name ?? DropNames.defaultName(suggested: $0.suggestedName, source: $0.source, date: $0.date) })
        guard names.allSatisfy({ DropNames.newName($0) == nil }) else { throw DropLocalError.invalidName }
        if let target {
            guard DropNames.folderPath(target.folder) == nil,
                  target.newFolder.map({ DropNames.newName($0) == nil }) ?? true else { throw DropLocalError.invalidFolder }
        }
        let epoch = generation
        for (file, name) in zip(files, names) {
            if let outbox { try await outbox.enqueue(file, name: name, target: target) }
            else {
                let size: Int64
                switch file.content {
                case .data(let data): size = Int64(data.count)
                case .file(let url): size = (try await DropFileIO.fingerprint(url)).size
                }
                guard epoch == generation else { throw CancellationError() }
                serverDrops.insert(Drop(id: (serverDrops.map(\.id).max() ?? 0) + 1, kind: .file, name: name, size: size,
                                        target: target, state: .waiting, fallback: false, created: .now, updated: .now), at: 0)
            }
            guard epoch == generation else { throw CancellationError() }
            if let target { recentFolders.use(target, source: file.source) }
        }
    }

    func retry(_ item: DropsItem) async {
        switch item {
        case .phone(let local): await outbox?.retry(local.id)
        case .server(let drop):
            if let local = outbox?.items.first(where: { $0.serverID == drop.id }) { await outbox?.retry(local.id) }
        }
    }

    /// Deletes a drop (brief 93, Mail's Delete, every state): it leaves `items` at once, before any request.
    /// - On this iPhone (or a server drop still uploading from it): the outbox stops the upload and forgets it, telling
    ///   the server (`DELETE`), later if there is no connection now; the upload has stopped, so the Mac never gets it.
    /// - On the server: `DELETE /drops/{id}`; uploading, waiting and failed drops are cancelled (the Mac never gets
    ///   them), landed and cancelled ones only leave the list (a landed file stays on the Mac). A `404` counts as deleted.
    /// If the server refuses, the drop comes back and `errors[.drops]` (the section's "Not refreshed: …") says why.
    func remove(_ item: DropsItem) async {
        switch item {
        case .phone(let local): _ = await removeLocal(local.id)
        case .server(let drop):
            // A server row that stands for a local upload: that upload and its durable copy go, and the outbox's
            // DELETE is this drop's.
            if let local = outbox?.items.first(where: { $0.serverID == drop.id }) {
                deleted.insert(drop.id)
                let epoch = generation
                let refused = await !removeLocal(local.id)
                guard epoch == generation else { return }
                if refused { deleted.remove(drop.id) }
                else if outbox?.items.contains(where: { $0.id == local.id }) == false {
                    serverDrops.removeAll { $0.id == drop.id }
                }
                return
            }
            deleted.insert(drop.id)
            if isSample { serverDrops.removeAll { $0.id == drop.id }; return }
            let epoch = generation
            let login = session.generation
            guard let token = session.token else {
                deleted.remove(drop.id)
                return
            }
            do {
                try await client.delete(drop.id, token: token)
                guard epoch == generation, login == session.generation else { return }
                serverDrops.removeAll { $0.id == drop.id }
                errors[.drops] = nil
            } catch {
                guard epoch == generation, login == session.generation else { return }
                deleted.remove(drop.id)
                session.handleAuthFailure(error, generation: login, token: token)
                guard epoch == generation else { return }
                errors[.drops] = DropOutbox.message(error)
            }
        }
    }

    /// The outbox removes it: gone, or waiting for a connection (out of the list meanwhile); false when the server
    /// refused the DELETE: the item is back in the list (`DropOutbox`) and `errors[.drops]` says why.
    private func removeLocal(_ id: UUID) async -> Bool {
        guard let outbox else { return true }
        let epoch = generation
        await outbox.remove(id)
        guard epoch == generation else { return true }
        guard let left = outbox.items.first(where: { $0.id == id }), !left.cancellationRequested else { return true }
        errors[.drops] = left.lastError
        return false
    }

    func clear() {
        generation += 1
        folders = nil
        serverDrops = []
        errors = [:]
        loading = []
        loadedAt = [:]
        recentFolders.clear()
        deleted = []
        outbox?.clear()
        cacheError = nil
        if let cacheURL, FileManager.default.fileExists(atPath: cacheURL.path) {
            do { try FileManager.default.removeItem(at: cacheURL) } catch { cacheError = error.localizedDescription }
        }
    }

    private func observeUploads() {
        outbox?.onUploaded = { [weak self] drop in
            self?.serverDrops.removeAll { $0.id == drop.id }
            self?.serverDrops.append(drop)
        }
    }

    #if DEBUG
    func leaveSample() {
        clear()
        samples = nil
        cacheURL = configuredCacheURL
        recentFolders = DropRecentFolders(defaults: defaults, legacyDefaults: legacyDefaults)
        outbox = DropOutbox(session: session, client: client, directory: directory, automatic: automatic, activity: activity, legacyDirectory: legacyDirectory, uploads: uploads)
        observeUploads()
    }
    #endif
}
