import Foundation
import Testing
@testable import Arestoteles

/// Every route of Arestoteles/docs/API.md: path, method, headers, body; 304, 409, 422 and the shared statuses.
@MainActor
struct APITests {
    private func api(_ transport: FakeTransport, token: String? = "fictional-token") -> ArestotelesAPI {
        ArestotelesAPI(transport: transport, token: { token })
    }

    @Test func vaultIsAskedWithTheTokenAndTheETag() async throws {
        let transport = FakeTransport()
        try transport.answer("GET /vault", sample: "vault", headers: ["ETag": "\"a1b2c3d\""])
        let fetched = try await api(transport).vault(ifNoneMatch: nil)
        guard case let .fresh(vault, etag) = fetched else { Issue.record("Expected a vault"); return }
        #expect(vault.commit == "a1b2c3d" && etag == "\"a1b2c3d\"")

        let request = try #require(transport.requests.only)
        #expect(request.url?.absoluteString == "https://www.ares-empire.de/api/arestoteles/vault")
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fictional-token")
        #expect(request.value(forHTTPHeaderField: "If-None-Match") == nil)
        #expect(request.cachePolicy == .reloadIgnoringLocalCacheData)

        transport.answer("GET /vault", 304, json: Data())
        #expect(try await api(transport).vault(ifNoneMatch: "\"a1b2c3d\"") == .notModified)
        #expect(transport.requests.last?.value(forHTTPHeaderField: "If-None-Match") == "\"a1b2c3d\"")
    }

    @Test func sourceEncodesTheNoteID() async throws {
        let transport = FakeTransport()
        let source = NoteSource(id: "Hitler's rise (1933)", version: "v1", markdown: "# Hitler's rise\n")
        try transport.answer("GET /notes/Hitler%27s%20rise%20%281933%29/source", encoding: source)
        #expect(try await api(transport).source(note: "Hitler's rise (1933)") == source)
        #expect(transport.requests.only?.url?.absoluteString
                == "https://www.ares-empire.de/api/arestoteles/notes/Hitler%27s%20rise%20%281933%29/source")
    }

    @Test func editsArePostedAsJSON() async throws {
        let transport = FakeTransport()
        try transport.answer("POST /edits", sample: "edit-result")
        let result = try await api(transport).send(.confirmPosition(position: "Printing press#2", version: "shown"))
        #expect(result.changed == ["Printing press"])
        let request = try #require(transport.requests.only)
        #expect(request.httpMethod == "POST" && request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(try body(request) as? [String: String] == ["op": "confirm_position", "version": "shown", "position": "Printing press#2"])
    }

    @Test(arguments: [409, 428])
    func conflictCarriesTheCurrentNote(status: Int) async throws {
        let transport = FakeTransport()
        let current = try #require(try sampleVault().notes.first { $0.id == "Printing press" })
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(current))
        transport.answer("POST /edits", status, json: try JSONSerialization.data(withJSONObject: [
            "error": "This note changed since you loaded it.", "current": json]))
        await #expect(throws: VaultAPIError.conflict(message: "This note changed since you loaded it.", current: current)) {
            try await api(transport).send(.adoptCallout(note: "Printing press", callout: 0, version: "old"))
        }
        // A position that no longer exists: 409 without a note.
        transport.answer("POST /edits", 409, json: Data(#"{"error":"This position no longer exists."}"#.utf8))
        await #expect(throws: VaultAPIError.conflict(message: "This position no longer exists.", current: nil)) {
            try await api(transport).send(.confirmPosition(position: "Printing press#9", version: "shown"))
        }
    }

    @Test func invalidEditsCarryTheServersReason() async throws {
        let transport = FakeTransport()
        transport.answer("POST /edits", 422, json: Data(#"{"error":"A position must be one sentence."}"#.utf8))
        await #expect(throws: VaultAPIError.invalid(message: "A position must be one sentence.")) {
            try await api(transport).send(.rewordPosition(position: "Positions#1", text: "Two. Sentences.", version: "shown"))
        }
    }

    @Test func sharedStatuses() async throws {
        let transport = FakeTransport()
        transport.answer("GET /vault", 401, json: Data(#"{"error":"Token rejected."}"#.utf8))
        await #expect(throws: HTTPError.self) { try await api(transport).vault(ifNoneMatch: nil) }
        do {
            _ = try await api(transport).vault(ifNoneMatch: nil)
        } catch HTTPError.unauthorized {
        } catch { Issue.record("401 should be unauthorized, got \(error)") }

        transport.answer("POST /edits", 403, json: Data(#"{"error":"No arestoteles service."}"#.utf8))
        do {
            _ = try await api(transport).send(.quickNote(text: "x"))
            Issue.record("403 should throw")
        } catch HTTPError.server(403, "No arestoteles service.") {
        } catch { Issue.record("403 should be server(403), got \(error)") }

        transport.answer("GET /notes/Reformation/source", 404, json: Data(#"{"error":"Unknown note."}"#.utf8))
        do {
            _ = try await api(transport).source(note: "Reformation")
            Issue.record("404 should throw")
        } catch HTTPError.server(404, "Unknown note.") {
        } catch { Issue.record("404 should be server(404), got \(error)") }
    }

    /// Before its first index the server answers 503 with its own sentence; without one, the shared message.
    @Test func stillLoadingKeepsTheServersWords() async throws {
        let transport = FakeTransport()
        transport.answer("GET /vault", 503, json: Data(#"{"error":"The vault is still loading."}"#.utf8))
        do {
            _ = try await api(transport).vault(ifNoneMatch: nil)
            Issue.record("503 should throw")
        } catch HTTPError.server(503, "The vault is still loading.") {
        } catch { Issue.record("Expected the server's sentence, got \(error)") }
        transport.answer("GET /vault", 503, json: Data())
        do {
            _ = try await api(transport).vault(ifNoneMatch: nil)
        } catch let HTTPError.server(503, message) {
            #expect(message == "Login service unavailable, try again")
        } catch { Issue.record("Expected a 503, got \(error)") }
    }

    @Test func noTokenNoRequest() async throws {
        let transport = FakeTransport()
        await #expect(throws: HTTPError.self) { try await api(transport, token: nil).vault(ifNoneMatch: nil) }
        #expect(transport.requests.isEmpty)
    }
}
