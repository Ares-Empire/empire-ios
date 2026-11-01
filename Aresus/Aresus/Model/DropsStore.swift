import Foundation
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
    private(set) var samples: AresusSamples?
    private(set) var outbox: DropOutbox?
    private(set) var recentFolders: DropRecentFolders
    private let session: EmpireSession
    private let client: AresusAPI
    private var cacheURL: URL?
    private let configuredCacheURL: URL?
    private let directory: URL?
    private let defaults: UserDefaults?
    private let automatic: Bool
    private var generation = 0
    var isSample: Bool { samples != nil }

    var items: [DropsItem] { Self.merge(outbox: outbox?.items ?? [], server: serverDrops) }

    init(session: EmpireSession, client: AresusAPI = AresusAPI(), samples: AresusSamples? = nil,
         directory: URL? = nil, cacheURL: URL? = URL.cachesDirectory.appendingPathComponent("drop-folders.json"),
         defaults: UserDefaults? = .standard, automatic: Bool = true) {
        self.session = session
        self.client = client
        self.samples = samples
        self.directory = directory
        self.defaults = defaults
        self.automatic = automatic
        configuredCacheURL = cacheURL
        self.cacheURL = samples == nil ? cacheURL : nil
        recentFolders = DropRecentFolders(defaults: samples == nil ? defaults : nil)
        outbox = samples == nil ? DropOutbox(session: session, client: client, directory: directory, automatic: automatic) : nil
        if samples == nil, let cacheURL, let data = try? Data(contentsOf: cacheURL) {
            folders = try? AresusJSON.decoder().decode(FolderList.self, from: data)
        }
        observeUploads()
        session.onAppDataReset { [weak self] in self?.clear() }
    }

    static func merge(outbox: [DropOutboxItem], server: [Drop]) -> [DropsItem] {
        let ids = Set(server.map(\.id))
        let phone = outbox.filter { $0.serverID.map { !ids.contains($0) } ?? true }.sorted { $0.created < $1.created }
        return phone.map(DropsItem.phone) + server.sorted {
            $0.created == $1.created ? $0.id > $1.id : $0.created > $1.created
        }.map(DropsItem.server)
    }

    /// Independent errors and last good values, as in AresusStore. The tab can throttle its minute refresh.
    func refresh(olderThan age: TimeInterval = 0, now: Date = .now) async {
        for part in [Part.folders, .drops] where loadedAt[part].map({ now.timeIntervalSince($0) >= age }) ?? true {
            await load(part)
        }
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

    func remove(_ item: DropsItem) async {
        switch item {
        case .phone(let local): await outbox?.remove(local.id)
        case .server(let drop):
            if isSample { serverDrops.removeAll { $0.id == drop.id }; return }
            let epoch = generation
            let login = session.generation
            guard let token = session.token else { return }
            do {
                // If the merged row hides a local upload, cancel that request and its durable copy as well.
                if let local = outbox?.items.first(where: { $0.serverID == drop.id }) {
                    await outbox?.remove(local.id)
                    guard outbox?.items.contains(where: { $0.id == local.id }) == false else {
                        errors[.drops] = outbox?.items.first(where: { $0.id == local.id })?.lastError
                        return
                    }
                } else { try await client.cancel(drop.id, token: token) }
                guard epoch == generation, login == session.generation else { return }
                serverDrops.removeAll { $0.id == drop.id }
                errors[.drops] = nil
            } catch {
                guard epoch == generation, login == session.generation else { return }
                session.handleAuthFailure(error, generation: login, token: token)
                guard epoch == generation else { return }
                errors[.drops] = DropOutbox.message(error)
            }
        }
    }

    func clear() {
        generation += 1
        folders = nil
        serverDrops = []
        errors = [:]
        loading = []
        loadedAt = [:]
        recentFolders.clear()
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
        recentFolders = DropRecentFolders(defaults: defaults)
        outbox = DropOutbox(session: session, client: client, directory: directory, automatic: automatic)
        observeUploads()
    }
    #endif
}
