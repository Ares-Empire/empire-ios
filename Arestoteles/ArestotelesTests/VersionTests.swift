import Foundation
import Testing
@testable import Arestoteles

@MainActor
struct VersionTests {
    private let topic = "Printing press"

    @Test(arguments: [PositionDraft.Kind.reword("Printing press#2"), .change("Printing press#2"),
                      .drop("Printing press#2"), .add(note: "Printing press")])
    func aStaleDraftKeepsItsOpeningVersionAndAllItsWords(kind: PositionDraft.Kind) async throws {
        let backend = try SampleBackend()
        let session = EmpireSession(app: .arestoteles, storage: MemoryTokens(), restoreOnLaunch: false)
        let store = VaultStore(session: session, backend: backend, persistence: MemoryPersistence(),
                               spotlight: NoSpotlight(), savedAccount: { nil }, sample: true)
        await store.refresh()
        let draft = PositionDraft(kind, index: store.index)
        draft.text = "Cheap paper changed who could read."
        draft.why = "A made-up book."
        draft.evidence = ["Spread of print"]
        let version = try #require(draft.version)
        #expect(await store.confirmPosition("Printing press#2", version: version) == .applied)
        #expect(store.index.note(topic)?.version != version)
        #expect(await draft.save(with: store) == false)
        #expect(draft.version == version && draft.text == "Cheap paper changed who could read.")
        #expect(draft.why == "A made-up book." && draft.evidence == ["Spread of print"])
        #expect(draft.problem == VaultStore.changedElsewhere && draft.canSave)
        #expect(await draft.save(with: store) == false) // retry never silently approves the stale draft
    }

    @Test func changingAnAddDraftsTargetUsesTheVersionFromOpening() async throws {
        let h = try await makeStore()
        await h.store.refresh()
        let draft = PositionDraft(.add(note: "Positions"), index: h.store.index)
        try h.transport.answer("GET /vault", encoding: sample(EditResult.self, "edit-result").vault)
        await h.store.refresh()
        draft.note = topic
        draft.text = "Cheap paper mattered."
        try h.transport.answer("POST /edits", sample: "edit-result")
        #expect(await draft.save(with: h.store))
        #expect(try h.transport.edits().only?["version"] as? String == sampleVersion(topic))
        #expect(draft.version != h.store.index.note(topic)?.version)
    }

    @Test(arguments: [409, 428])
    func refusedStructuredDraftAndFreeEditorKeepTheirText(status: Int) async throws {
        let h = try await makeStore()
        await h.store.refresh()
        h.transport.answer("POST /edits", status, json: Data(#"{"error":"Version refused."}"#.utf8))
        let draft = PositionDraft(.change("Printing press#2"), index: h.store.index)
        draft.text = "My new view."
        draft.why = "My reason."
        #expect(await draft.save(with: h.store) == false)
        #expect(draft.text == "My new view." && draft.why == "My reason.")
        #expect(draft.problem == VaultStore.changedElsewhere)
        try h.transport.answer("GET /notes/Spread%20of%20print/source", sample: "note-source")
        let editor = NoteEditor(note: "Spread of print", store: h.store)
        await editor.load()
        editor.text = "My full rewrite."
        #expect(await editor.save() == false)
        #expect(editor.text == "My full rewrite." && editor.conflict && !editor.canSave)
    }

    @Test(arguments: [QuickNoteKind.note, .discuss], ["Printing press", "Printing press#2"])
    func linkedNotesKeepTheirOpeningVersionAcrossRefreshAndRelaunch(kind: QuickNoteKind, about: String) async throws {
        let h = try await makeStore()
        await h.store.refresh()
        let draft = QuickNoteDraft(about: about, index: h.store.index)
        draft.text = kind == .discuss ? "" : "Keep these exact words."
        try h.transport.answer("GET /vault", encoding: sample(EditResult.self, "edit-result").vault)
        await h.store.refresh()
        h.transport.failure = URLError(.notConnectedToInternet)
        #expect(draft.save(with: h.store, kind: kind) == .queued)
        await h.store.quickNotesSettled()
        let encoded = try JSONEncoder().encode(h.persistence.quickNotes)
        let restored = try JSONDecoder().decode([PendingQuickNote].self, from: encoded)
        let persistence = MemoryPersistence(quickNotes: restored)
        let relaunched = try await makeStore(persistence: persistence)
        try relaunched.transport.answer("POST /edits", sample: "edit-result")
        await relaunched.store.refresh()
        let sent = try #require(try relaunched.transport.edits().only)
        #expect(sent["version"] as? String == sampleVersion(topic))
        #expect(sent["text"] as? String == draft.text && sent["about"] as? String == about)
        #expect(restored.only?.version == draft.version && restored.only?.kind == kind)
    }

    @Test(arguments: [409, 428])
    func aRefusedQueuedNoteStaysWithItsOriginalVersion(status: Int) async throws {
        let h = try await makeStore()
        await h.store.refresh()
        h.transport.answer("POST /edits", status, json: Data(#"{"error":"Version refused."}"#.utf8))
        let draft = QuickNoteDraft(about: "Printing press#2", index: h.store.index)
        draft.text = "Keep my note."
        #expect(draft.save(with: h.store) == .queued)
        await h.store.quickNotesSettled()
        let kept = try #require(h.persistence.quickNotes.only)
        #expect(kept.text == draft.text && kept.version == draft.version && kept.problem == "This changed elsewhere.")
        await h.store.refresh()
        #expect(h.transport.requests("POST /edits").count == 1)
        #expect(h.persistence.quickNotes.only == kept)
    }

    @Test(arguments: [QuickNoteKind.note, .discuss], ["Printing press", "Printing press#2"])
    func oldLinkedNotesWaitForTheOwnersConfirmation(kind: QuickNoteKind, about: String) async throws {
        let legacy = Data("""
            [{"id":"00000000-0000-0000-0000-000000000228","text":"An older thought.","created":0,
              "about":"\(about)","kind":"\(kind.rawValue)"}]
            """.utf8)
        let notes = try JSONDecoder().decode([PendingQuickNote].self, from: legacy)
        let persistence = MemoryPersistence(quickNotes: notes)
        let h = try await makeStore(persistence: persistence)
        try h.transport.answer("POST /edits", sample: "edit-result")
        await h.store.refresh()
        let old = try #require(h.store.pendingQuickNotes.only)
        #expect(old.needsConfirmation && old.version == nil && h.store.waitingQuickNoteCount == 1)
        #expect(h.transport.requests("POST /edits").isEmpty && persistence.quickNotes == notes)
        // A plain note can pass the old one, which continues waiting across another launch.
        h.store.queueQuickNote("Plain and ready.")
        await h.store.quickNotesSettled()
        #expect(try h.transport.edits().only?["about"] == nil)
        let relaunched = try await makeStore(persistence: persistence)
        await relaunched.store.refresh()
        #expect(relaunched.transport.requests("POST /edits").isEmpty)
        // Opening the question captures this version; a later refresh must not change the approval.
        let approvedVersion = sampleVersion(topic)
        try relaunched.transport.answer("GET /vault", encoding: sample(EditResult.self, "edit-result").vault)
        await relaunched.store.refresh()
        relaunched.transport.answer("POST /edits", 409, json: Data(#"{"error":"Changed again."}"#.utf8))
        #expect(relaunched.store.confirmQuickNote(old.id, version: approvedVersion))
        #expect(persistence.quickNotes.only?.version == approvedVersion) // durable before sending
        await relaunched.store.quickNotesSettled()
        let sent = try #require(try relaunched.transport.edits().only)
        #expect(sent["version"] as? String == approvedVersion)
        #expect(sent["text"] as? String == old.text && sent["about"] as? String == old.about)
        #expect(persistence.quickNotes.only?.problem != nil)
    }

    @Test func versionsAreFixedBeforeWaitingBehindAnotherEdit() async throws {
        let h = try await makeStore()
        await h.store.refresh()
        try h.transport.answer("POST /edits", sample: "edit-result")
        let version = sampleVersion(topic)
        let gate = RequestGate()
        h.transport.gates["POST /edits"] = gate
        let first = Task { await h.store.confirmPosition("Printing press#2", version: version) }
        await gate.waitUntilPaused()
        let second = Task { await h.store.setConfidence(.solid, of: topic, version: version) }
        #expect(await eventually { h.store.operationsRunning == 2 })
        gate.resume()
        #expect(await first.value == .applied)
        #expect(await second.value == .applied)
        #expect(try h.transport.edits().allSatisfy { $0["version"] as? String == version })
    }
    @Test func undoKeepsTheVersionReturnedByDone() async throws {
        let backend = try SampleBackend()
        let session = EmpireSession(app: .arestoteles, storage: MemoryTokens(), restoreOnLaunch: false)
        let store = VaultStore(session: session, backend: backend, persistence: MemoryPersistence(),
                               spotlight: NoSpotlight(), savedAccount: { nil }, sample: true)
        await store.refresh()
        let note = try #require(store.index.openDiscussions.first)
        let offer = try #require(await store.markDiscussed(of: note.id, version: note.version))
        let saved = try #require(store.index.note(note.id)?.version)
        #expect(saved != note.version)
        // A different edit changed this note before Undo was tapped.
        #expect(await store.setInboxStatus(of: note.id, processed: false, version: saved) == .applied)
        let newer = try #require(store.index.note(note.id)?.version)
        let undo = try #require(offer.undo)
        await undo()
        #expect(store.notice?.text == VaultStore.changedElsewhere)
        #expect(store.index.note(note.id)?.version == newer)
    }

    @Test func confirmingAnOldQueueEntryMustBeDurableBeforeItCanSend() async throws {
        let old = PendingQuickNote(text: "Keep this old thought.", about: "Printing press#2")
        let persistence = RefusingQueuePersistence(notes: [old])
        let transport = FakeTransport()
        try transport.answer("GET /vault", sample: "vault")
        let session = await signedInSession()
        let store = VaultStore(session: session, backend: ArestotelesAPI(transport: transport, token: { session.token }),
                               persistence: persistence, spotlight: NoSpotlight(), savedAccount: { "account-a" })
        await store.refresh()
        #expect(!store.confirmQuickNote(old.id, version: sampleVersion(topic)))
        await store.quickNotesSettled()
        #expect(store.pendingQuickNotes.only == old && persistence.loadQuickNotes().only == old)
        #expect(transport.requests("POST /edits").isEmpty)
    }

}

/// Simulates a queue that cannot save the owner's approval; the original must stay intact.
nonisolated private struct RefusingQueuePersistence: VaultPersistence {
    let notes: [PendingQuickNote]
    func loadVault() -> CachedVault? { nil }
    func saveVault(_ cached: CachedVault) throws {}
    func loadQuickNotes() -> [PendingQuickNote] { notes }
    func saveQuickNotes(_ notes: [PendingQuickNote]) throws { throw CocoaError(.fileWriteOutOfSpace) }
    func deleteVault() throws {}
    func deleteAll() throws {}
}
