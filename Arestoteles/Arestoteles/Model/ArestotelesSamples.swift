import Foundation

/// The contract's made-up samples (Samples/, copies of Arestoteles/docs/samples/), for the tests and for `-sampleData`.
enum ArestotelesSamples {
    nonisolated static let files = ["vault", "note-source", "edit-result"]

    static func data(_ name: String) throws -> Data {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try Data(contentsOf: url)
    }

    static func decode<T: Decodable>(_ type: T.Type, from name: String) throws -> T {
        try JSONDecoder().decode(type, from: data(name))
    }
}

#if DEBUG
/// `-sampleData`: the samples as a server in memory. `GET /vault` answers the sample (304 with its ETag); every edit is
/// answered with `edit-result.json` (whose vault then stays), or with a 409 / 422 when asked; the source of any note is
/// `note-source.json` for its note and a short made-up body for the others. Nothing leaves the device.
final class SampleBackend: VaultBackend {
    struct Options {
        var conflict = false            // -sampleEditConflict: every edit answers 409
        var invalid = false             // -sampleEditInvalid: every edit answers 422
        var pushLater = false           // -samplePushLater: edits saved with pushed: false
        var offline = false             // -sampleOffline: the server cannot be reached
    }

    private(set) var current: Vault
    private let source: NoteSource
    private let result: EditResult
    private let options: Options

    init(options: Options = Options()) throws {
        self.options = options
        current = try ArestotelesSamples.decode(Vault.self, from: "vault")
        source = try ArestotelesSamples.decode(NoteSource.self, from: "note-source")
        result = try ArestotelesSamples.decode(EditResult.self, from: "edit-result")
    }

    /// The sample vault as the device would have saved it (for `-sampleOffline`).
    static func savedVault() throws -> CachedVault {
        let vault = try ArestotelesSamples.decode(Vault.self, from: "vault")
        return CachedVault(vault: vault, etag: etag(vault), account: VaultStore.sampleAccount)
    }

    private static func etag(_ vault: Vault) -> String { "\"\(vault.commit)\"" }

    func vault(ifNoneMatch etag: String?) async throws -> VaultFetch {
        try reachable()
        let currentTag = Self.etag(current)
        return etag == currentTag ? .notModified : .fresh(current, etag: currentTag)
    }

    func source(note id: String) async throws -> NoteSource {
        try reachable()
        if id == source.id { return source }
        guard let note = current.notes.first(where: { $0.id == id }) else {
            throw HTTPError.server(404, "This note is not in the vault.")
        }
        var markdown = "# \(note.title)\n"
        if let summary = note.summary { markdown += "\n> [!summary]\n> \(summary)\n" }
        markdown += "\nA made-up body for the sample.\n"
        return NoteSource(id: note.id, version: note.version, markdown: markdown)
    }

    func send(_ edit: Edit) async throws -> EditResult {
        try reachable()
        try await Task.sleep(for: .milliseconds(400))
        if options.conflict {
            throw VaultAPIError.conflict(message: "This note changed since you loaded it.",
                                         current: edit.note.flatMap { id in current.notes.first { $0.id == id } })
        }
        if options.invalid {
            throw VaultAPIError.invalid(message: "A position must be one sentence.")
        }
        current = result.vault
        return EditResult(vault: result.vault, changed: result.changed, pushed: result.pushed && !options.pushLater,
                          warnings: result.warnings)
    }

    private func reachable() throws {
        if options.offline { throw URLError(.notConnectedToInternet) }
    }
}
#endif
