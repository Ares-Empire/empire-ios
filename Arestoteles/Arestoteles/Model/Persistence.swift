import Foundation
import Synchronization

/// The last vault the app had, with what it needs to ask the server whether it is still current.
nonisolated struct CachedVault: Codable, Equatable, Sendable {
    let vault: Vault
    /// The server's `ETag` for it; nil after an edit (the edit's answer carries no ETag).
    let etag: String?
    /// The Empire account it was loaded with (`EmpireToken.accountID`), so another account never sees it.
    let account: String?
}

/// A quick note typed in the app, waiting to be sent (`quick_note`), possibly offline.
nonisolated struct PendingQuickNote: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let text: String
    let created: Date
    /// What it is about (a note id or a position id), and whether it is a note or a "discuss later" mark.
    var about: String?
    var kind: QuickNoteKind
    /// The referenced note as it was shown when written; nil in queues saved by older apps.
    var version: String?
    var needsConfirmation: Bool { about != nil && version == nil }
    /// The server refused it (409/428/422): it stays, with the reason, until Patrik deletes it; it is not sent again.
    var problem: String?

    init(id: UUID = UUID(), text: String, created: Date = .now, about: String? = nil, kind: QuickNoteKind = .note,
         version: String? = nil, problem: String? = nil) {
        self.id = id
        self.text = text
        self.created = created
        self.about = about
        self.kind = kind
        self.version = version
        self.problem = problem
    }

    init(from decoder: Decoder) throws {           // queues saved before `about`, `kind` or `version` existed still load
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        text = try container.decode(String.self, forKey: .text)
        created = try container.decode(Date.self, forKey: .created)
        about = try container.decodeIfPresent(String.self, forKey: .about)
        version = try container.decodeIfPresent(String.self, forKey: .version)
        kind = try container.decodeIfPresent(QuickNoteKind.self, forKey: .kind) ?? .note
        problem = try container.decodeIfPresent(String.self, forKey: .problem)
    }
}

/// Where the app keeps what must survive a restart: the last vault (so it opens offline) and the quick notes not yet
/// sent. Both are forgotten on logout.
nonisolated protocol VaultPersistence: Sendable {
    func loadVault() -> CachedVault?
    func saveVault(_ cached: CachedVault) throws
    func loadQuickNotes() -> [PendingQuickNote]
    func saveQuickNotes(_ notes: [PendingQuickNote]) throws
    func deleteVault() throws
    /// Logout: everything above is deleted.
    func deleteAll() throws
}

/// Files in Application Support/Arestoteles: `vault.json`, `quick-notes.json`. Written atomically and protected by the
/// device's data protection.
nonisolated struct FilePersistence: VaultPersistence {
    let directory: URL

    /// The app's own folder in Application Support.
    static var standard: FilePersistence {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return FilePersistence(directory: base.appending(path: "Arestoteles", directoryHint: .isDirectory))
    }

    private var vaultFile: URL { directory.appending(path: "vault.json") }
    private var quickNotesFile: URL { directory.appending(path: "quick-notes.json") }

    func loadVault() -> CachedVault? { read(CachedVault.self, from: vaultFile) }

    func saveVault(_ cached: CachedVault) throws {
        try write(cached, to: vaultFile)
        // The server's vault can be downloaded again. Atomic writes replace the file, so set this every time.
        var file = vaultFile
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try file.setResourceValues(values)
    }

    func loadQuickNotes() -> [PendingQuickNote] { read([PendingQuickNote].self, from: quickNotesFile) ?? [] }

    func saveQuickNotes(_ notes: [PendingQuickNote]) throws {
        if notes.isEmpty {
            try remove(quickNotesFile)
        } else {
            try write(notes, to: quickNotesFile)
        }
    }

    func deleteVault() throws { try remove(vaultFile) }

    func deleteAll() throws {
        try deleteVault()
        try remove(quickNotesFile)
    }

    /// A file that cannot be read (missing, or written by an older app with other fields) counts as absent.
    private func read<T: Decodable>(_ type: T.Type, from file: URL) -> T? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(type, from: data)
    }

    private func write<T: Encodable>(_ value: T, to file: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(value).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    private func remove(_ file: URL) throws {
        do {
            try FileManager.default.removeItem(at: file)
        } catch CocoaError.fileNoSuchFile {
            return
        }
    }
}

/// In memory only: tests, and sample mode (which must never touch the real files).
nonisolated final class MemoryPersistence: VaultPersistence {
    private struct State: Sendable {
        var vault: CachedVault?
        var quickNotes: [PendingQuickNote]
    }
    private let state: Mutex<State>
    var vault: CachedVault? {
        get { state.withLock { $0.vault } }
        set { state.withLock { $0.vault = newValue } }
    }
    var quickNotes: [PendingQuickNote] {
        get { state.withLock { $0.quickNotes } }
        set { state.withLock { $0.quickNotes = newValue } }
    }

    init(vault: CachedVault? = nil, quickNotes: [PendingQuickNote] = []) {
        state = Mutex(State(vault: vault, quickNotes: quickNotes))
    }

    func loadVault() -> CachedVault? { vault }
    func saveVault(_ cached: CachedVault) throws { vault = cached }
    func loadQuickNotes() -> [PendingQuickNote] { quickNotes }
    func saveQuickNotes(_ notes: [PendingQuickNote]) throws { quickNotes = notes }
    func deleteVault() throws { vault = nil }
    func deleteAll() throws { state.withLock { $0.vault = nil; $0.quickNotes = [] } }
}

#if DEBUG
/// Sample-only write failure hook. An older note needs confirmation, so it stays listed even with an online sample.
nonisolated struct UnwritableSampleQueue: VaultPersistence {
    private let memory: MemoryPersistence

    init(vault: CachedVault?) {
        memory = MemoryPersistence(vault: vault, quickNotes: [
            PendingQuickNote(text: "A sample thought waiting to be sent", about: "Printing press")
        ])
    }

    func loadVault() -> CachedVault? { memory.loadVault() }
    func saveVault(_ cached: CachedVault) throws { try memory.saveVault(cached) }
    func loadQuickNotes() -> [PendingQuickNote] { memory.loadQuickNotes() }
    func saveQuickNotes(_ notes: [PendingQuickNote]) throws { throw CocoaError(.fileWriteNoPermission) }
    func deleteVault() throws { try memory.deleteVault() }
    func deleteAll() throws { try memory.deleteAll() }
}
#endif
