import Foundation
import Testing
@testable import Arestoteles

/// Quick notes are kept on the phone first: sent at once when the server answers, otherwise later, in order; a note the
/// server refuses stays aside with its reason until deleted; a logout forgets them.
@MainActor
struct QuickNoteTests {
    private func online() async throws -> Harness {
        let h = try await makeStore()
        await h.store.refresh()
        try h.transport.answer("POST /edits", sample: "edit-result")
        return h
    }

    @Test func sentAtOnceAndVerbatim() async throws {
        let h = try await online()
        #expect(h.store.queueQuickNote("  paper was the bottleneck?? check\n") == .queued)
        await h.store.quickNotesSettled()
        #expect(try h.transport.edits().only as? [String: String]
                == ["op": "quick_note", "text": "  paper was the bottleneck?? check\n"])
        #expect(h.store.pendingQuickNotes.isEmpty && h.persistence.quickNotes.isEmpty)
        #expect(h.store.vault?.commit == "b2c3d4e")
    }

    @Test func emptyNotesAreNotKept() async throws {
        let h = try await online()
        #expect(h.store.queueQuickNote(" \n ") == .empty)
        #expect(h.store.pendingQuickNotes.isEmpty && h.transport.requests("POST /edits").isEmpty)
    }

    @Test func offlineTheyWaitAndGoOutInOrder() async throws {
        let h = try await online()
        h.transport.failure = URLError(.notConnectedToInternet)
        #expect(h.store.queueQuickNote("first") == .queued)
        await h.store.quickNotesSettled()
        #expect(h.store.queueQuickNote("second") == .queued)
        await h.store.quickNotesSettled()
        #expect(h.store.pendingQuickNotes.map(\.text) == ["first", "second"])
        #expect(h.persistence.quickNotes.map(\.text) == ["first", "second"])
        #expect(h.store.isOffline)

        h.transport.failure = nil
        h.transport.answer("GET /vault", 304, json: Data())
        await h.store.refresh()                                   // the server answers again: the queue goes out
        let texts = try h.transport.edits().map { $0["text"] as? String }
        #expect(texts == ["first", "first", "first", "second"])  // two failed attempts, then both in order
        #expect(h.store.pendingQuickNotes.isEmpty && h.persistence.quickNotes.isEmpty && !h.store.isOffline)
    }

    @Test func theQueueSurvivesARestart() async throws {
        let persistence = MemoryPersistence(quickNotes: [PendingQuickNote(text: "typed on the train")])
        let h = try await makeStore(persistence: persistence)
        #expect(h.store.pendingQuickNotes.map(\.text) == ["typed on the train"])
        try h.transport.answer("POST /edits", sample: "edit-result")
        await h.store.refresh()
        #expect(try h.transport.edits().map { $0["text"] as? String } == ["typed on the train"])
        #expect(persistence.quickNotes.isEmpty)
    }

    @Test func aRefusedNoteStaysAsideUntilDeleted() async throws {
        let h = try await online()
        h.transport.answer("POST /edits", 422, json: Data(#"{"error":"Made-up refusal"}"#.utf8))
        #expect(h.store.queueQuickNote("odd one") == .queued)
        await h.store.quickNotesSettled()
        let refused = try #require(h.store.pendingQuickNotes.only)
        #expect(refused.problem == "Made-up refusal" && h.persistence.quickNotes.first?.problem == "Made-up refusal")
        #expect(h.store.notice?.text == "A quick note was not saved: Made-up refusal")
        #expect(h.store.waitingQuickNoteCount == 0)

        try h.transport.answer("POST /edits", sample: "edit-result")
        #expect(h.store.queueQuickNote("next one") == .queued)  // the refused one does not block the queue
        await h.store.quickNotesSettled()
        #expect(try h.transport.edits().map { $0["text"] as? String } == ["odd one", "next one"])
        h.store.deleteQuickNote(refused.id)
        #expect(h.store.pendingQuickNotes.isEmpty && h.persistence.quickNotes.isEmpty)
    }

    @Test func aServerErrorKeepsTheNoteForLater() async throws {
        let h = try await online()
        h.transport.answer("POST /edits", 409, json: Data(#"{"error":"Push conflict, try again."}"#.utf8))
        #expect(h.store.queueQuickNote("keep me") == .queued)
        await h.store.quickNotesSettled()
        #expect(h.store.pendingQuickNotes.only?.problem == nil && h.store.waitingQuickNoteCount == 1)
    }

    @Test func theyWaitWhileTheLoginWaits() async throws {
        let auth = authServer()
        auth.failure = URLError(.cannotConnectToHost)
        let storage = MemoryTokens(token: fakeToken(account: "account-a"))
        let session = EmpireSession(app: .arestoteles, storage: storage, client: EmpireAuthClient(transport: auth))
        let h = try await makeStore(session: session)
        await session.restore()
        #expect(h.store.queueQuickNote("no login yet") == .queued)
        await h.store.quickNotesSettled()
        #expect(h.transport.requests.isEmpty)
    }

    @Test func aLogoutForgetsThem() async throws {
        let h = try await online()
        h.transport.failure = URLError(.notConnectedToInternet)
        h.store.queueQuickNote("unsent")
        await h.store.quickNotesSettled()
        h.session.logOut()
        await h.store.persistenceSettled()
        #expect(h.store.pendingQuickNotes.isEmpty && h.persistence.quickNotes.isEmpty)
    }
}
