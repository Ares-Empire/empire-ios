import Foundation
import Testing
@testable import Arestoteles

@MainActor
struct ComfortTests {
    @Test func newTextOnlyHasChangesWhileSomethingIsWritten() {
        var text = ""
        #expect(!DraftChanges.hasChanges(text))
        text = "A thought for later."
        #expect(DraftChanges.hasChanges(text))
        text = ""
        #expect(!DraftChanges.hasChanges(text))
        #expect(!DraftChanges.hasChanges(" \n\t"))
    }

    @Test func loadedPassageOnlyHasChangesWhenItDiffers() {
        let original = "A **passage** with [[links]].\n"
        #expect(!DraftChanges.hasChanges(original, original: original))
        #expect(DraftChanges.hasChanges("Rewritten.", original: original))
        #expect(DraftChanges.hasChanges("", original: original)) // deleting loaded text is an edit
        var text = original + " More."
        #expect(DraftChanges.hasChanges(text, original: original))
        text = original
        #expect(!DraftChanges.hasChanges(text, original: original))
    }

    @Test(arguments: [PositionDraft.Kind.reword("Printing press#2"), .change("Printing press#2")])
    func loadedPositionTracksTextAndReason(kind: PositionDraft.Kind) throws {
        let draft = PositionDraft(kind, index: try sampleIndex())
        let original = draft.text
        #expect(!draft.hasChanges)
        draft.text += " More."
        #expect(draft.hasChanges)
        draft.text = ""
        #expect(draft.hasChanges)
        draft.text = original
        #expect(!draft.hasChanges)
        if draft.needsWhy {
            draft.why = "New evidence."
            #expect(draft.hasChanges)
            draft.why = ""
            #expect(!draft.hasChanges)
        }
    }

    @Test func newPositionTracksTextDestinationAndEvidence() throws {
        let draft = PositionDraft(.add(note: "Positions"), index: try sampleIndex())
        #expect(!draft.hasChanges)
        draft.text = "A sentence."
        #expect(draft.hasChanges)
        draft.text = ""
        #expect(!draft.hasChanges)
        draft.note = "Printing press"
        #expect(draft.hasChanges)
        draft.note = "Positions"
        #expect(!draft.hasChanges)
        draft.toggleEvidence("Spread of print")
        #expect(draft.hasChanges)
        draft.toggleEvidence("Spread of print")
        #expect(!draft.hasChanges)
    }

    @Test func doneOffersUndoForTheSameNote() async throws {
        let h = try await makeStore()
        await h.store.refresh()
        try h.transport.answer("POST /edits", sample: "edit-result")
        let note = try #require(h.store.index.openDiscussions.first?.id)
        let offer = try #require(await h.store.markDiscussed(of: note))
        await offer.undo()
        let edits = try h.transport.edits()
        #expect(edits.count == 2)
        #expect(edits.map { $0["op"] as? String } == ["set_inbox_status", "set_inbox_status"])
        #expect(edits.map { $0["note"] as? String } == [note, note])
        #expect(edits.map { $0["status"] as? String } == ["processed", "new"])
    }

    @Test(arguments: [409, 422, 500])
    func failedDoneDoesNotOfferUndo(status: Int) async throws {
        let h = try await makeStore()
        await h.store.refresh()
        h.transport.answer("POST /edits", status, json: Data(#"{"error":"Made-up refusal"}"#.utf8))
        let offer = await h.store.markDiscussed(of: "2026-10-23 2110 discuss Printing press")
        #expect(offer == nil)
        #expect(h.transport.requests("POST /edits").count == 1)
    }
}
