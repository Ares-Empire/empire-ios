import Foundation
import Testing
@testable import Arestoteles

/// Every edit op through the store: what is sent, the returned vault swapped in, and the answers that are not a plain
/// success (409 reloads, 422 shows the server's reason, `pushed: false` says the laptops get it later).
@MainActor
struct EditTests {
    /// A store with the sample vault loaded and `POST /edits` answered with the sample result.
    private func loaded() async throws -> Harness {
        let h = try await makeStore()
        await h.store.refresh()
        try h.transport.answer("POST /edits", sample: "edit-result")
        return h
    }

    enum Op: String, CaseIterable {
        case confirm, reword, change, drop, add, confidence, adopt, dismiss, editNote, status

        func run(_ store: VaultStore) async -> VaultStore.EditOutcome {
            switch self {
            case .status: await store.setInboxStatus(of: "2026-10-23 2110 discuss Printing press", processed: true,
                                                     version: sampleVersion("2026-10-23 2110 discuss Printing press"))
            case .confirm: await store.confirmPosition("Printing press#2", version: sampleVersion("Printing press#2"))
            case .reword: await store.rewordPosition("Printing press#2", text: "Printers printed what sold.", version: sampleVersion("Printing press#2"))
            case .change: await store.changePosition("Positions#1", text: "Who is read controls the argument.",
                                                     why: "Pamphlets outsold books.", version: sampleVersion("Positions#1"))
            case .drop: await store.dropPosition("Printing press#2", why: "Too simple.", version: sampleVersion("Printing press#2"))
            case .add: await store.addPosition(to: "Printing press", text: "Paper mattered as much as type.",
                                               evidence: ["Spread of print", "Gutenberg Bible"], version: sampleVersion("Printing press"))
            case .confidence: await store.setConfidence(.solid, of: "Reformation", version: sampleVersion("Reformation"))
            case .adopt: await store.adoptCallout(0, of: "Printing press", version: sampleVersion("Printing press"))
            case .dismiss: await store.dismissCallout(0, of: "Printing press", version: sampleVersion("Printing press"))
            case .editNote: await store.saveNote("Spread of print", markdown: "# Spread of print\n\nNew text.\n",
                                                 version: "8b1d2e3f4a5c6d7e8f9a0b1c2d3e4f5a6b7c8d9e")
            }
        }

        /// The body the contract wants for it.
        var expected: [String: AnyHashable] {
            let topicVersion = "3f2a9c1e4b7d8a0f6e5c2b1a9d8e7f6c5b4a3921"
            switch self {
            case .status: return ["op": "set_inbox_status", "note": "2026-10-23 2110 discuss Printing press",
                                  "status": "processed", "version": sampleVersion("2026-10-23 2110 discuss Printing press")]
            case .confirm: return ["op": "confirm_position", "version": sampleVersion("Printing press"), "position": "Printing press#2"]
            case .reword: return ["op": "reword_position", "version": sampleVersion("Printing press"), "position": "Printing press#2", "text": "Printers printed what sold."]
            case .change: return ["op": "change_position", "version": sampleVersion("Positions"), "position": "Positions#1",
                                  "text": "Who is read controls the argument.", "why": "Pamphlets outsold books."]
            case .drop: return ["op": "drop_position", "version": sampleVersion("Printing press"), "position": "Printing press#2", "why": "Too simple."]
            case .add: return ["op": "add_position", "version": sampleVersion("Printing press"), "note": "Printing press", "text": "Paper mattered as much as type.",
                               "evidence": ["Spread of print", "Gutenberg Bible"] as [String]]
            case .confidence: return ["op": "set_confidence", "version": sampleVersion("Reformation"), "note": "Reformation", "confidence": "solid"]
            case .adopt: return ["op": "adopt_callout", "note": "Printing press", "callout": 0, "version": topicVersion]
            case .dismiss: return ["op": "dismiss_callout", "note": "Printing press", "callout": 0, "version": topicVersion]
            case .editNote: return ["op": "edit_note", "note": "Spread of print",
                                    "version": "8b1d2e3f4a5c6d7e8f9a0b1c2d3e4f5a6b7c8d9e",
                                    "markdown": "# Spread of print\n\nNew text.\n"]
            }
        }
    }

    @Test(arguments: Op.allCases)
    func everyOpIsSentAndItsVaultSwappedIn(op: Op) async throws {
        let h = try await loaded()
        #expect(await op.run(h.store) == .applied)
        let sent = try #require(try h.transport.edits().only as? [String: AnyHashable])
        #expect(sent == op.expected)
        #expect(h.store.vault?.commit == "b2c3d4e" && h.store.index.position("Printing press#2")?.draft == false)
        #expect(h.store.notice == nil && !h.store.isSending)
        #expect(h.persistence.vault?.vault.commit == "b2c3d4e" && h.persistence.vault?.etag == nil)
        await h.store.spotlightSettled()
        #expect(h.spotlight.calls.count == 2)                      // the first load, then the edit's vault
        // The edit's vault has no ETag: the next refresh asks without one.
        await h.store.refresh()
        #expect(h.transport.requests("GET /vault").last?.value(forHTTPHeaderField: "If-None-Match") == nil)
    }

    @Test func aConflictSaysSoAndReloads() async throws {
        let h = try await loaded()
        h.transport.answer("POST /edits", 409, json: Data(#"{"error":"This position no longer exists."}"#.utf8))
        #expect(await h.store.confirmPosition("Printing press#2", version: sampleVersion("Printing press#2")) == .conflict)
        #expect(h.store.notice?.text == VaultStore.changedElsewhere && h.store.notice?.tone == .problem)
        #expect(h.transport.requests("GET /vault").count == 2)
    }

    @Test func anInvalidEditShowsTheServersReason() async throws {
        let h = try await loaded()
        h.transport.answer("POST /edits", 422, json: Data(#"{"error":"A position must be one sentence."}"#.utf8))
        #expect(await h.store.rewordPosition("Positions#1", text: "Two. Sentences.", version: sampleVersion("Positions#1")) == .invalid("A position must be one sentence."))
        #expect(h.store.notice?.text == "A position must be one sentence." && h.store.notice?.tone == .problem)
        #expect(h.store.vault?.commit == "a1b2c3d")
    }

    @Test func aSheetShowsItsOwnFailures() async throws {
        let h = try await loaded()
        h.transport.answer("POST /edits", 422, json: Data(#"{"error":"Made-up refusal"}"#.utf8))
        #expect(await h.store.dropPosition("Positions#1", why: "x", version: sampleVersion("Positions#1"), reportsFailure: false) == .invalid("Made-up refusal"))
        #expect(h.store.notice == nil)
    }

    @Test func aPushThatWaitsIsSaid() async throws {
        let h = try await loaded()
        var result = try sample(EditResult.self, "edit-result")
        result = EditResult(vault: result.vault, changed: result.changed, pushed: false, warnings: [])
        try h.transport.answer("POST /edits", encoding: result)
        #expect(await h.store.confirmPosition("Printing press#2", version: sampleVersion("Printing press#2")) == .applied)
        #expect(h.store.notice?.tone == .info)
        #expect(h.store.notice?.text == "Saved. It reaches the laptops once the server can push it to GitHub.")
    }

    @Test func savedNotices() throws {
        let vault = try sampleVault()
        #expect(VaultStore.savedNotice(for: EditResult(vault: vault, changed: [], pushed: true, warnings: [])) == nil)
        #expect(VaultStore.savedNotice(for: EditResult(vault: vault, changed: [], pushed: true,
                                                       warnings: ["Topics/X.md: no summary", "Y: long"]))
                == "The vault's check warns: Topics/X.md: no summary; Y: long")
        let german = VaultStore.savedNotice(for: EditResult(vault: vault, changed: [], pushed: false, warnings: []),
                                            language: .german)
        #expect(german != nil)
    }

    @Test func offlineEditsFailWithoutLosingAnything() async throws {
        let h = try await loaded()
        h.transport.failure = URLError(.networkConnectionLost)
        #expect(await h.store.setConfidence(.shaky, of: "Reformation", version: sampleVersion("Reformation")) == .failed(VaultStore.offlineMessage))
        #expect(h.store.isOffline && h.store.vault?.commit == "a1b2c3d" && h.store.notice?.tone == .problem)
    }

    @Test func aDeletedCalloutIsRefusedWithoutSubstitutingAVersion() async throws {
        let h = try await loaded()
        h.transport.answer("POST /edits", 409, json: Data(#"{"error":"Gone"}"#.utf8))
        #expect(await h.store.adoptCallout(0, of: "No such note", version: "shown") == .conflict)
        #expect(h.transport.requests("POST /edits").count == 1)
    }

    @Test func editsReachTheServerOneAtATime() async throws {
        let h = try await loaded()
        let gate = RequestGate()
        h.transport.gates["POST /edits"] = gate
        let first = Task { await h.store.confirmPosition("Printing press#2", version: sampleVersion("Printing press#2")) }
        await gate.waitUntilPaused()
        #expect(h.store.isSending)
        let second = Task { await h.store.setConfidence(.solid, of: "Reformation", version: sampleVersion("Reformation")) }
        try await Task.sleep(for: .milliseconds(50))
        #expect(h.transport.requests("POST /edits").count == 1)    // the second waits for the first
        gate.resume()
        let outcomes = (await first.value, await second.value)
        #expect(outcomes.0 == .applied && outcomes.1 == .applied)
        #expect(try h.transport.edits().map { $0["op"] as? String } == ["confirm_position", "set_confidence"])
        #expect(!h.store.isSending)
    }

    // MARK: the position sheets

    @Test func positionDrafts() async throws {
        let h = try await loaded()
        let reword = PositionDraft(.reword("Printing press#2"), index: h.store.index)
        #expect(reword.text == "Printers were businessmen first; they printed what sold." && reword.canSave)
        reword.text = "   "
        #expect(!reword.canSave)

        let change = PositionDraft(.change("Printing press#1"), index: h.store.index)
        #expect(!change.canSave && change.needsWhy)               // a changed view needs its why
        change.why = "A new book."
        #expect(change.canSave)
        #expect(await change.save(with: h.store))
        #expect(try h.transport.edits().last?["op"] as? String == "change_position")

        let drop = PositionDraft(.drop("Printing press#1"), index: h.store.index)
        #expect(!drop.needsText && !drop.canSave)
        drop.why = "No longer held."
        h.transport.answer("POST /edits", 409, json: Data(#"{"error":"Gone"}"#.utf8))
        #expect(await drop.save(with: h.store) == false)
        #expect(drop.problem == VaultStore.changedElsewhere && h.store.notice == nil)

        let add = PositionDraft(.add(note: "Positions"), index: h.store.index)
        add.text = "Cheap copies favour the loud."
        add.toggleEvidence("Reformation")
        add.toggleEvidence("Printing press")
        add.toggleEvidence("Reformation")
        add.toggleEvidence("Gutenberg Bible")
        #expect(add.evidence == ["Printing press", "Gutenberg Bible"])
        try h.transport.answer("POST /edits", sample: "edit-result")
        #expect(await add.save(with: h.store))
        #expect(try h.transport.edits().last?["evidence"] as? [String] == ["Printing press", "Gutenberg Bible"])
        #expect(try h.transport.edits().last?["note"] as? String == "Positions")
    }

    // MARK: the free editor

    @Test func theEditorLoadsAndSavesAgainstItsVersion() async throws {
        let h = try await loaded()
        try h.transport.answer("GET /notes/Spread%20of%20print/source", sample: "note-source")
        let editor = NoteEditor(note: "Spread of print", store: h.store)
        await editor.load()
        #expect(editor.state == .editing && editor.version == "8b1d2e3f4a5c6d7e8f9a0b1c2d3e4f5a6b7c8d9e")
        #expect(!editor.canSave)                                  // nothing changed yet
        editor.text += "\nOne more line.\n"
        #expect(editor.canSave)
        #expect(await editor.save())
        let sent = try #require(try h.transport.edits().only)
        #expect(sent["version"] as? String == "8b1d2e3f4a5c6d7e8f9a0b1c2d3e4f5a6b7c8d9e")
        #expect((sent["markdown"] as? String)?.hasSuffix("One more line.\n") == true)
    }

    @Test func aConflictKeepsTheTypedTextAndStopsSaving() async throws {
        let h = try await loaded()
        try h.transport.answer("GET /notes/Spread%20of%20print/source", sample: "note-source")
        let editor = NoteEditor(note: "Spread of print", store: h.store)
        await editor.load()
        editor.text = "My rewrite."
        h.transport.answer("POST /edits", 409, json: Data(#"{"error":"Changed."}"#.utf8))
        #expect(await editor.save() == false)
        #expect(editor.conflict && editor.text == "My rewrite." && !editor.canSave && editor.problem != nil)
        #expect(h.transport.requests("GET /vault").count == 2)    // the vault was reloaded
        await editor.loadCurrentVersion()
        #expect(!editor.conflict && editor.text.hasPrefix("# Spread of print") && editor.problem == nil)
    }

    @Test func theEditorShowsRefusalsAndLoadFailures() async throws {
        let h = try await loaded()
        try h.transport.answer("GET /notes/Spread%20of%20print/source", sample: "note-source")
        let editor = NoteEditor(note: "Spread of print", store: h.store)
        await editor.load()
        editor.text = "No title any more."
        h.transport.answer("POST /edits", 422, json: Data(#"{"error":"A note needs its title."}"#.utf8))
        #expect(await editor.save() == false)
        #expect(editor.problem == "A note needs its title." && !editor.conflict && editor.canSave)

        let missing = NoteEditor(note: "Reformation", store: h.store)
        await missing.load()
        #expect(missing.state == .failed("Not found"))
    }
}
