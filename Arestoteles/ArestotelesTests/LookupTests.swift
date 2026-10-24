import Foundation
import Testing
@testable import Arestoteles

/// Quick lookups (2026-10-24): a position's first sentence, a note's figures and sources, sentence search, editing one
/// passage by its lines, notes and "discuss later" marks about a note or a position.
@MainActor
struct LookupTests {
    @Test func headlineIsTheFirstSentence() {
        #expect(Lookup.headline("Capital interests are dominant. In colonialism, in the fall of Weimar …")
                == "Capital interests are dominant.")
        #expect(Lookup.headline("**Bold** first, e.g. with an abbreviation, still one sentence.")
                == "Bold first, e.g. with an abbreviation, still one sentence.")
        #expect(Lookup.headline("No full stop at the end") == "No full stop at the end")
    }

    @Test func figuresAndSources() throws {
        let vault = try sampleVault()
        let spread = try #require(vault.notes.first { $0.id == "Spread of print" })
        let figures = Lookup.figures(of: spread)
        #expect(figures.contains { $0.text.contains("1450") })
        #expect(figures.allSatisfy { Lookup.holdsFigure($0.text) })
        let press = try #require(vault.notes.first { $0.id == "Printing press" })
        let sources = Lookup.sources(of: press)
        #expect(!sources.isEmpty && sources.allSatisfy { $0.heading == "Sources" })
        // Sources are not figures, even when they carry a year.
        #expect(!Lookup.figures(of: press).contains { $0.heading == "Sources" })
        #expect(Lookup.holdsFigure("90% of Africa") && Lookup.holdsFigure("in 1517") && !Lookup.holdsFigure("one press"))
    }

    @Test func sentenceSearchFindsTheSentenceAndWhereItIs() throws {
        let search = VaultSearch(vault: try sampleVault())
        let hits = search.sentences("Mainz")
        #expect(!hits.isEmpty)
        #expect(hits.allSatisfy { VaultSearch.fold($0.sentence).contains("mainz") })
        let bible = try #require(hits.first { $0.passage.note == "Gutenberg Bible" })
        #expect(bible.title == "Gutenberg Bible" && bible.passage.block >= 0)
        // A phrase ranks before sentences that only hold the words apart; one letter finds nothing.
        #expect(search.sentences("m").isEmpty)
        let phrase = search.sentences("trade routes")
        #expect(phrase.first?.phrase == true)
    }

    @Test func onePassageIsReplacedByItsLines() {
        let body = "# Title\n\nFirst paragraph.\n\n- one\n- two\n"
        let range = LineRange(start: 4, end: 5)
        #expect(VaultStore.slice(body, range) == "- one")
        #expect(VaultStore.replace(range, in: body, with: "- uno") == "# Title\n\nFirst paragraph.\n\n- uno\n- two\n")
        #expect(VaultStore.replace(LineRange(start: 2, end: 3), in: body, with: "A new\nparagraph.\n")
                == "# Title\n\nA new\nparagraph.\n\n- one\n- two\n")
        #expect(VaultStore.slice(body, LineRange(start: 5, end: 99)) == nil)
        #expect(VaultStore.replace(LineRange(start: 3, end: 3), in: body, with: "x") == nil)
    }

    @Test func blockLinesAndInboxInfoDecode() throws {
        let json = #"""
        {"id": "2026-10-24 0900 discuss Colonialism", "path": "Inbox/x.md", "type": "inbox", "title": "x",
         "version": "abc", "blocks": [{"kind": "paragraph", "text": "Why?", "lines": [2, 3]}, {"kind": "rule"}],
         "inbox": {"status": "new", "kind": "discuss", "about": "Colonialism", "position": 2}}
        """#
        let note = try JSONDecoder().decode(Note.self, from: Data(json.utf8))
        #expect(note.blockLines == [LineRange(start: 2, end: 3), nil])
        #expect(note.inbox?.kind == .discuss && note.inbox?.isOpen == true)
        #expect(note.inbox?.positionID == "Colonialism#2")
        #expect(DiscussSubject(inbox: try #require(note.inbox)) == .position("Colonialism#2"))
        // The app's saved copy keeps the lines.
        let again = try JSONDecoder().decode(Note.self, from: try JSONEncoder().encode(note))
        #expect(again.blockLines == note.blockLines && again.inbox == note.inbox)
    }

    @Test func quickNotesCarryWhatTheyAreAbout() throws {
        func body(_ edit: Edit) throws -> [String: String] {
            try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(edit)) as? [String: String])
        }
        // A plain quick note is exactly the first contract's.
        #expect(try body(.quickNote(text: "hello")) == ["op": "quick_note", "text": "hello"])
        #expect(try body(.quickNote(text: "", about: "Colonialism#2", kind: .discuss))
                == ["op": "quick_note", "text": "", "about": "Colonialism#2", "kind": "discuss"])
        #expect(try body(.setInboxStatus(note: "x", status: "processed"))
                == ["op": "set_inbox_status", "note": "x", "status": "processed"])
    }
}

extension LookupTests {
    @Test func theSampleHasLinesAndAnOpenDiscussion() throws {
        let vault = try sampleVault()
        let index = VaultIndex(vault: vault)
        #expect(index.openDiscussions.map(\.id) == ["2026-10-23 2110 discuss Printing press"])
        #expect(index.openDiscussions.first?.inbox?.positionID == "Printing press#1")
        let press = try #require(vault.notes.first { $0.id == "Printing press" })
        #expect(press.blockLines.count == press.blocks.count && press.blockLines.allSatisfy { $0 != nil })
    }
}
