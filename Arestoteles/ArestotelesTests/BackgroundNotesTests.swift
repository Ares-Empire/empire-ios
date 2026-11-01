import Foundation
import Testing
@testable import Arestoteles

@MainActor
struct BackgroundNotesTests {
    @Test func theNoteIsOnDiskBeforeAnyNetworkAndOutlivesItsCaller() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "queued-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let files = FilePersistence(directory: directory)
        let session = await signedInSession()
        let transport = FakeTransport()
        try transport.answer("POST /edits", sample: "edit-result")
        let gate = RequestGate()
        transport.gates["POST /edits"] = gate
        let store = VaultStore(session: session, backend: ArestotelesAPI(transport: transport, token: { session.token }),
                               persistence: files, spotlight: NoSpotlight(), savedAccount: { "account-a" })
        await store.loadingSettled()
        let caller = Task {
            let outcome = store.queueQuickNote("A fictional thought")
            #expect(outcome == .queued)
            #expect(files.loadQuickNotes().only?.text == "A fictional thought")
            #expect(transport.requests.isEmpty)
        }
        await caller.value                                    // the sheet's caller has finished
        caller.cancel()
        await gate.waitUntilPaused()
        #expect(store.pendingQuickNotes.count == 1 && store.waitingQuickNoteCount == 0)
        gate.resume()
        await store.quickNotesSettled()
        #expect(store.pendingQuickNotes.isEmpty && files.loadQuickNotes().isEmpty)
        #expect(store.vault?.commit == "b2c3d4e" && store.notice == nil)
        #expect(try directory.appending(path: "vault.json")
            .resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
    }

    @Test func onlyFailedAttemptsCountAndStayCountedDuringARetry() async throws {
        let h = try await makeStore()
        let first = RequestGate()
        h.transport.gates["POST /edits"] = first
        h.store.queueQuickNote("one")
        #expect(h.store.waitingQuickNoteCount == 0)
        await first.waitUntilPaused()
        #expect(h.store.waitingQuickNoteCount == 0)
        h.transport.failure = URLError(.notConnectedToInternet)
        first.resume()
        await h.store.quickNotesSettled()
        #expect(h.store.isOffline && h.store.waitingQuickNoteCount == 1)

        h.transport.failure = nil
        try h.transport.answer("POST /edits", sample: "edit-result")
        let retry = RequestGate()
        h.transport.gates["POST /edits"] = retry
        let refresh = Task { await h.store.refresh() }
        await retry.waitUntilPaused()
        #expect(h.store.waitingQuickNoteCount == 1)
        retry.resume()
        await refresh.value
        #expect(h.store.waitingQuickNoteCount == 0 && !h.store.isOffline)
        #expect(h.store.notice == nil)
    }

    @Test func notesAddedDuringSendingGoOutOneAtATimeInOrder() async throws {
        let h = try await makeStore()
        try h.transport.answer("POST /edits", sample: "edit-result")
        let gate = RequestGate()
        h.transport.gates["POST /edits"] = gate
        h.store.queueQuickNote("first")
        await gate.waitUntilPaused()
        h.store.queueQuickNote("second")
        #expect(h.transport.requests("POST /edits").count == 1)
        #expect(h.store.waitingQuickNoteCount == 0)
        gate.resume()
        await h.store.quickNotesSettled()
        #expect(try h.transport.edits().map { $0["text"] as? String } == ["first", "second"])
        #expect(h.store.pendingQuickNotes.isEmpty)
    }

    @Test func laterWithNoWordsAlsoQueuesImmediately() async throws {
        let h = try await makeStore()
        try h.transport.answer("POST /edits", sample: "edit-result")
        #expect(h.store.queueQuickNote("", about: "Printing press#2", kind: .discuss) == .queued)
        #expect(h.persistence.quickNotes.only?.kind == .discuss && h.transport.requests.isEmpty)
        await h.store.quickNotesSettled()
        #expect(try h.transport.edits().only as? [String: String]
                == ["op": "quick_note", "text": "", "about": "Printing press#2", "kind": "discuss"])
    }

    @Test func logoutDuringSendingDropsTheAnswerAndTheQueue() async throws {
        let h = try await makeStore()
        await h.store.refresh()
        try h.transport.answer("POST /edits", sample: "edit-result")
        let gate = RequestGate()
        h.transport.gates["POST /edits"] = gate
        h.store.queueQuickNote("leave no trace")
        await gate.waitUntilPaused()
        h.session.logOut()
        gate.resume()
        // clear() releases the current sender; wait for the old request through the serial chain.
        await h.store.sendingSettled()
        await h.store.persistenceSettled()
        await h.store.spotlightSettled()
        #expect(h.store.vault == nil && h.store.pendingQuickNotes.isEmpty && h.store.waitingQuickNoteCount == 0)
        #expect(h.persistence.vault == nil && h.persistence.quickNotes.isEmpty && h.store.notice == nil)
        #expect(h.spotlight.calls.last == .removeAll)
    }

    @Test func aFailedDiskWriteKeepsTheSheetDraftUnqueued() async throws {
        let session = await signedInSession()
        let transport = FakeTransport()
        let store = VaultStore(session: session, backend: ArestotelesAPI(transport: transport, token: { session.token }),
                               persistence: UnwritableQueue(), spotlight: NoSpotlight(), savedAccount: { "account-a" })
        await store.loadingSettled()
        guard case .failed = store.queueQuickNote("keep my draft") else {
            Issue.record("An unwritten note must not dismiss its draft")
            return
        }
        #expect(store.pendingQuickNotes.isEmpty && transport.requests.isEmpty)
    }
}

nonisolated private struct UnwritableQueue: VaultPersistence {
    func loadVault() -> CachedVault? { nil }
    func saveVault(_ cached: CachedVault) throws {}
    func loadQuickNotes() -> [PendingQuickNote] { [] }
    func saveQuickNotes(_ notes: [PendingQuickNote]) throws { throw CocoaError(.fileWriteNoPermission) }
    func deleteVault() throws {}
    func deleteAll() throws {}
}
