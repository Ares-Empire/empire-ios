import Foundation
import Testing
@testable import Arestoteles

/// TEST_RUNNER_VAULT_TIMINGS=1 xcodebuild test … -only-testing:ArestotelesTests/VaultTimingTests
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["VAULT_TIMINGS"] == "1"))
@MainActor
struct VaultTimingTests {
    @Test func threeArrivalPaths() async throws {
        let vault = try largeSampleVault()
        print("VAULT DATA notes=\(vault.notes.count) bytes=\(try JSONEncoder().encode(vault).count) passages=\(vault.notes.flatMap { Lookup.passages(of: $0) }.count) positions=\(vault.positions.flatMap(\.positions).count)")
        let directory = FileManager.default.temporaryDirectory.appending(path: "vault-timing-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let files = FilePersistence(directory: directory)
        let session = await signedInSession()
        let transport = FakeTransport()
        try transport.answer("GET /vault", encoding: vault)
        let edited = Vault(version: vault.version, commit: "fictional-new", built: vault.built, notes: vault.notes,
                           positions: vault.positions, glossary: vault.glossary, home: vault.home)
        try transport.answer("POST /edits", encoding: EditResult(vault: edited, changed: [], pushed: true, warnings: []))
        let api = ArestotelesAPI(transport: transport, token: { session.token })
        var results: [String: [Double]] = [:]
        for round in 0..<6 {
            try files.saveVault(CachedVault(vault: vault, etag: nil, account: "account-a"))
            VaultTiming.samples = []
            let saved = VaultStore(session: session, backend: api, persistence: files,
                                   spotlight: TimingSpotlight(), savedAccount: { "account-a" })
            await saved.loadingSettled()
            await saved.spotlightSettled()
            report("saved-launch", round: round, names: ["disk.load", "disk.assign"], results: &results)
            try files.deleteAll()
            let fresh = VaultStore(session: session, backend: api, persistence: files,
                                   spotlight: TimingSpotlight(), savedAccount: { "account-a" })
            await fresh.loadingSettled()
            VaultTiming.samples = []
            await fresh.refresh()
            await fresh.spotlightSettled()
            report("first-download", round: round, names: ["api.decode", "vault.apply", "spotlight.make"], results: &results)
            VaultTiming.samples = []
            await fresh.confirmPosition("Printing press#2", version: sampleVersion("Printing press#2"))
            await fresh.spotlightSettled()
            report("edit-answer", round: round, names: ["api.decode", "vault.apply", "spotlight.make"], results: &results)
        }
        for name in results.keys.sorted() {
            let values = results[name]!.sorted()
            print("VAULT TIMING \(name) main-ms-median=\(values[2]) main-ms-max=\(values.last!)")
        }
    }

    private func report(_ name: String, round: Int, names: Set<String>, results: inout [String: [Double]]) {
        let total = VaultTiming.samples.filter { names.contains($0.name) }.reduce(0) { $0 + $1.milliseconds }
        if round > 0 {
            results[name, default: []].append(total)
            print("VAULT TIMING round=\(round) \(name) main-ms=\(total)")
        }
        VaultTiming.samples = []
    }
}

private struct TimingSpotlight: SpotlightIndexing {
    var language: AppLanguage? { .current }
    func replace(with notes: [Note]) async throws {
        _ = await SpotlightItems.prepare(notes, language: .current)
    }
    func removeAll() async throws {}
}

/// Repeat only bundled fictional notes, renaming identities and links. 540 substantial passages, 80 notes, 30 positions.
@MainActor
func largeSampleVault() throws -> Vault {
    var json = try JSONSerialization.jsonObject(with: ArestotelesSamples.data("vault")) as! [String: Any]
    let templates = (json["notes"] as! [[String: Any]]).filter {
        ["topic", "mechanism", "event", "question", "actor", "session"].contains($0["type"] as! String)
    }
    let paragraph = "Printed copies reached distant towns through booksellers and travelling scholars. Paper prices shaped which books could be made cheaply. **The press changed the conditions**, while readers and rulers chose what followed. A fictional example repeats the bundled sample's questions about evidence and causation. "
    json["notes"] = (0..<80).map { number -> [String: Any] in
        var note = templates[number % templates.count]
        let id = "Sample \(number) \(note["id"]!)"
        note["id"] = id; note["title"] = id; note["path"] = "Samples/\(id).md"
        if note["topic"] != nil { note["topic"] = id }
        note["blocks"] = (0..<(number < 60 ? 7 : 6)).map { index in
            ["kind": "paragraph", "text": "\(index): " + paragraph + String(paragraph.prefix(100))]
        }
        note.removeValue(forKey: "block_lines")
        note["positions"] = []; note["backlinks"] = []; note["links"] = []
        return note
    }
    let group = (json["positions"] as! [[String: Any]])[0]
    var positions = group
    let template = (group["positions"] as! [[String: Any]])[0]
    positions["positions"] = (0..<30).map { number -> [String: Any] in
        var position = template
        position["id"] = "Sample position#\(number)"
        return position
    }
    json["positions"] = [positions]
    return try JSONDecoder().decode(Vault.self, from: JSONSerialization.data(withJSONObject: json))
}
