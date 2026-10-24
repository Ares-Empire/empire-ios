import Foundation

/// The last vault the app had, with what it needs to ask the server whether it is still current.
struct CachedVault: Codable, Equatable, Sendable {
    let vault: Vault
    /// The server's `ETag` for it; nil after an edit (the edit's answer carries no ETag).
    let etag: String?
    /// The Empire account it was loaded with (`EmpireToken.accountID`), so another account never sees it.
    let account: String?
}

/// A quick note typed in the app, waiting to be sent (`quick_note`), possibly offline.
struct PendingQuickNote: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let text: String
    let created: Date
    /// The server refused it (422): it stays, with the reason, until Patrik deletes it; it is not sent again.
    var problem: String?

    init(id: UUID = UUID(), text: String, created: Date = .now, problem: String? = nil) {
        self.id = id
        self.text = text
        self.created = created
        self.problem = problem
    }
}

/// Where the app keeps what must survive a restart: the last vault (so it opens offline) and the quick notes not yet
/// sent. Both are forgotten on logout.
protocol VaultPersistence {
    func loadVault() -> CachedVault?
    func saveVault(_ cached: CachedVault) throws
    func loadQuickNotes() -> [PendingQuickNote]
    func saveQuickNotes(_ notes: [PendingQuickNote]) throws
    /// Logout: everything above is deleted.
    func deleteAll() throws
}

/// Files in Application Support/Arestoteles: `vault.json`, `quick-notes.json`. Written atomically and protected by the
/// device's data protection.
struct FilePersistence: VaultPersistence {
    let directory: URL

    /// The app's own folder in Application Support.
    static var standard: FilePersistence {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return FilePersistence(directory: base.appending(path: "Arestoteles", directoryHint: .isDirectory))
    }

    private var vaultFile: URL { directory.appending(path: "vault.json") }
    private var quickNotesFile: URL { directory.appending(path: "quick-notes.json") }

    func loadVault() -> CachedVault? { read(CachedVault.self, from: vaultFile) }

    func saveVault(_ cached: CachedVault) throws { try write(cached, to: vaultFile) }

    func loadQuickNotes() -> [PendingQuickNote] { read([PendingQuickNote].self, from: quickNotesFile) ?? [] }

    func saveQuickNotes(_ notes: [PendingQuickNote]) throws {
        if notes.isEmpty {
            try remove(quickNotesFile)
        } else {
            try write(notes, to: quickNotesFile)
        }
    }

    func deleteAll() throws {
        try remove(vaultFile)
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
final class MemoryPersistence: VaultPersistence {
    var vault: CachedVault?
    var quickNotes: [PendingQuickNote] = []

    init(vault: CachedVault? = nil, quickNotes: [PendingQuickNote] = []) {
        self.vault = vault
        self.quickNotes = quickNotes
    }

    func loadVault() -> CachedVault? { vault }
    func saveVault(_ cached: CachedVault) throws { vault = cached }
    func loadQuickNotes() -> [PendingQuickNote] { quickNotes }
    func saveQuickNotes(_ notes: [PendingQuickNote]) throws { quickNotes = notes }
    func deleteAll() throws {
        vault = nil
        quickNotes = []
    }
}
