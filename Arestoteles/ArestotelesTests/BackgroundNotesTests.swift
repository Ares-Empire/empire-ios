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
            let outcome = store.queueQuickNote("A fictional thought", about: "Printing press#2",
                                               version: sampleVersion("Printing press"))
            #expect(outcome == .queued)
            #expect(files.loadQuickNotes().only?.text == "A fictional thought")
            #expect(FilePersistence(directory: directory).loadQuickNotes().only?.version == sampleVersion("Printing press"))
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
        #expect(h.store.queueQuickNote("", about: "Printing press#2", kind: .discuss, version: sampleVersion("Printing press")) == .queued)
        #expect(h.persistence.quickNotes.only?.kind == .discuss && h.transport.requests.isEmpty)
        await h.store.quickNotesSettled()
        #expect(try h.transport.edits().only as? [String: String]
                == ["op": "quick_note", "text": "", "about": "Printing press#2", "kind": "discuss", "version": sampleVersion("Printing press")])
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

    private func queueStore(_ persistence: SwitchableQueuePersistence, transport: FakeTransport = FakeTransport()) async -> VaultStore {
        let session = await signedInSession()
        let store = VaultStore(session: session, backend: ArestotelesAPI(transport: transport, token: { session.token }),
                               persistence: persistence, spotlight: NoSpotlight(), savedAccount: { "account-a" })
        await store.loadingSettled()
        return store
    }

    private func waiting(_ text: String) -> PendingQuickNote {
        PendingQuickNote(text: text, about: "Printing press") // an older note waiting for confirmation
    }

    private func expectWriteProblem(_ store: VaultStore, prefix: String, sourceLocation: SourceLocation = #_sourceLocation) {
        let reason = CocoaError(.fileWriteNoPermission).localizedDescription
        #expect(store.quickNoteQueueProblem == prefix + reason, sourceLocation: sourceLocation)
        #expect(store.notice?.text == store.quickNoteQueueProblem, sourceLocation: sourceLocation)
        #expect(store.notice?.tone == .problem, sourceLocation: sourceLocation)
    }

    @Test func aFailedDeleteKeepsTheNoteInMemoryAndOnDiskUntilTheOwnerRetries() async {
        let notes = [waiting("first"), waiting("delete this"), waiting("last")]
        let persistence = SwitchableQueuePersistence(notes: notes)
        let store = await queueStore(persistence)
        persistence.failsWrites = true

        #expect(!store.deleteQuickNote(notes[1].id))
        expectWriteProblem(store, prefix: "This note could not be deleted on this iPhone: ")
        #expect(store.pendingQuickNotes == notes && store.waitingQuickNoteCount == 3)
        let restarted = await queueStore(persistence)
        #expect(restarted.pendingQuickNotes == notes)

        persistence.failsWrites = false
        #expect(store.deleteQuickNote(notes[1].id))
        #expect(store.quickNoteQueueProblem == nil)
        #expect(store.pendingQuickNotes == [notes[0], notes[2]] && store.waitingQuickNoteCount == 2)
        let afterRetry = await queueStore(persistence)
        #expect(afterRetry.pendingQuickNotes == [notes[0], notes[2]])
    }

    @Test func aFailedConfirmationKeepsTheOlderNoteAndReportsInsideTheSheet() async {
        let notes = [waiting("first"), waiting("confirm this"), waiting("last")]
        let persistence = SwitchableQueuePersistence(notes: notes)
        let store = await queueStore(persistence)
        persistence.failsWrites = true

        #expect(!store.confirmQuickNote(notes[1].id, version: sampleVersion("Printing press")))
        expectWriteProblem(store, prefix: "This iPhone could not update its list of notes: ")
        #expect(store.pendingQuickNotes == notes)
        let restarted = await queueStore(persistence)
        #expect(restarted.pendingQuickNotes == notes)
    }

    @Test(arguments: [false, true])
    func aSentNoteLeavesMemoryOnceAndTheNextSaveClosesItsReplayWindow(pushWaits: Bool) async throws {
        let notes = [waiting("first"), PendingQuickNote(text: "send this"), waiting("last")]
        let persistence = SwitchableQueuePersistence(notes: notes)
        let transport = FakeTransport()
        let result: EditResult = try sample(EditResult.self, "edit-result")
        try transport.answer("POST /edits", encoding: EditResult(vault: result.vault, changed: result.changed,
                                                                pushed: !pushWaits, warnings: result.warnings))
        let store = await queueStore(persistence, transport: transport)
        persistence.failsWrites = true

        await store.flushQuickNotes()
        expectWriteProblem(store, prefix: "Sent, but this iPhone could not update its list; the note may be sent again after a restart: ")
        #expect(store.pendingQuickNotes == [notes[0], notes[2]])
        #expect(store.waitingQuickNoteCount == 2)
        await store.flushQuickNotes()
        #expect(transport.requests("POST /edits").count == 1)
        let restarted = await queueStore(persistence)
        #expect(restarted.pendingQuickNotes == notes) // documented replay if killed before the disk catches up

        persistence.failsWrites = false
        #expect(store.queueQuickNote("new waiting note", about: "Printing press") == .queued)
        await store.quickNotesSettled()
        #expect(store.quickNoteQueueProblem == nil)
        #expect(transport.requests("POST /edits").count == 1)
        let afterSave = await queueStore(persistence)
        #expect(afterSave.pendingQuickNotes == store.pendingQuickNotes)
        #expect(afterSave.pendingQuickNotes.map(\.text) == ["first", "last", "new waiting note"])
    }

    @Test(arguments: [false, true])
    func anEmptyQueueRetriesItsWriteOnFlushOrForegroundEvenWithTheServerOffline(foreground: Bool) async throws {
        let persistence = SwitchableQueuePersistence(notes: [PendingQuickNote(text: "send this")])
        let transport = FakeTransport()
        try transport.answer("POST /edits", sample: "edit-result")
        let store = await queueStore(persistence, transport: transport)
        persistence.failsWrites = true
        await store.flushQuickNotes()
        #expect(store.pendingQuickNotes.isEmpty && store.quickNoteQueueProblem != nil)
        let restarted = await queueStore(persistence)
        #expect(restarted.pendingQuickNotes.map(\.text) == ["send this"])

        persistence.failsWrites = false
        transport.failure = URLError(.notConnectedToInternet)
        if foreground {
            await store.update(renewsLogin: false)
        } else {
            await store.flushQuickNotes()
        }
        #expect(store.quickNoteQueueProblem == nil && store.pendingQuickNotes.isEmpty)
        #expect(transport.requests("POST /edits").count == 1)
        let afterRetry = await queueStore(persistence)
        #expect(afterRetry.pendingQuickNotes.isEmpty)
    }

    @Test func laterNotesStillSendInOrderWhenEveryQueueWriteFails() async throws {
        let notes = [PendingQuickNote(text: "first"), waiting("keep waiting"),
                     PendingQuickNote(text: "second"), PendingQuickNote(text: "third")]
        let persistence = SwitchableQueuePersistence(notes: notes)
        let transport = FakeTransport()
        try transport.answer("POST /edits", sample: "edit-result")
        let store = await queueStore(persistence, transport: transport)
        persistence.failsWrites = true
        await store.flushQuickNotes()
        #expect(try transport.edits().map { $0["text"] as? String } == ["first", "second", "third"])
        #expect(store.pendingQuickNotes == [notes[1]])
        expectWriteProblem(store, prefix: "Sent, but this iPhone could not update its list; the note may be sent again after a restart: ")
        let restarted = await queueStore(persistence)
        #expect(restarted.pendingQuickNotes == notes)

        persistence.failsWrites = false
        await store.flushQuickNotes()
        #expect(transport.requests("POST /edits").count == 3 && store.quickNoteQueueProblem == nil)
        let afterRetry = await queueStore(persistence)
        #expect(afterRetry.pendingQuickNotes == [notes[1]])
    }

    @Test(arguments: [409, 428, 422])
    func aRefusalStaysInMemoryAndIsSavedOnTheNextFlush(status: Int) async {
        let notes = [waiting("first"), PendingQuickNote(text: "refuse this", about: "Printing press",
                                                      version: sampleVersion("Printing press")), waiting("last")]
        let persistence = SwitchableQueuePersistence(notes: notes)
        let transport = FakeTransport()
        transport.answer("POST /edits", status, json: Data(#"{"error":"Made-up refusal"}"#.utf8))
        let store = await queueStore(persistence, transport: transport)
        persistence.failsWrites = true
        await store.flushQuickNotes()

        expectWriteProblem(store, prefix: "This iPhone could not update its list of notes: ")
        var refused = notes[1]
        refused.problem = status == 422 ? "Made-up refusal" : "This changed elsewhere."
        let expected = [notes[0], refused, notes[2]]
        #expect(store.pendingQuickNotes == expected && store.waitingQuickNoteCount == 2)
        await store.flushQuickNotes()
        #expect(transport.requests("POST /edits").count == 1)
        let restarted = await queueStore(persistence)
        #expect(restarted.pendingQuickNotes == notes)

        persistence.failsWrites = false
        await store.flushQuickNotes()
        #expect(store.quickNoteQueueProblem == nil && store.pendingQuickNotes == expected)
        #expect(transport.requests("POST /edits").count == 1)
        let afterRetry = await queueStore(persistence)
        #expect(afterRetry.pendingQuickNotes == expected)
    }

    @Test func aFailedClearIsReportedAndRetriedWhileSignedOut() async {
        let notes = [waiting("first"), waiting("last")]
        let persistence = SwitchableQueuePersistence(notes: notes)
        let store = await queueStore(persistence)
        persistence.failsWrites = true
        store.session.logOut()
        expectWriteProblem(store, prefix: "This iPhone could not update its list of notes: ")
        #expect(store.pendingQuickNotes.isEmpty)
        let restarted = await queueStore(persistence)
        #expect(restarted.pendingQuickNotes == notes)

        persistence.failsWrites = false
        await store.update()
        #expect(store.quickNoteQueueProblem == nil)
        let afterRetry = await queueStore(persistence)
        #expect(afterRetry.pendingQuickNotes.isEmpty)
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
