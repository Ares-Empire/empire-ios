import Foundation
import Testing
@testable import Arestoteles

/// The search fields of Positions, Topics and Library: `VaultSearch`'s matching (case and accents ignored, every word
/// must appear) over each tab's own items.
@MainActor
struct TabSearchTests {
    private func search() throws -> TabSearch {
        let vault = try sampleVault()
        return TabSearch(vault: vault, index: VaultIndex(vault: vault))
    }

    @Test func onlyAQueryFilters() throws {
        #expect(!TabSearch.isQuery("") && !TabSearch.isQuery("   ") && TabSearch.isQuery(" luther "))
        let search = try search()
        #expect(search.positions("").isEmpty && search.topics(" ").isEmpty && search.library("").isEmpty)
        #expect(TabSearch.empty.positions("print").isEmpty)
    }

    @Test func positionsByTitleAndTextInTheirGroups() throws {
        let groups = try search().positions("PRINTERS")
        #expect(groups.map(\.title) == ["Printing press"])
        #expect(groups.first?.positions.map(\.id) == ["Printing press#2"])
        // Every word, anywhere in the title or text; groups keep the vault's order.
        let copies = try search().positions("copies argument")
        #expect(copies.map(\.note) == ["Positions"] && copies.first?.positions.map(\.id) == ["Positions#1"])
        #expect(try search().positions("print zebra").isEmpty)
        #expect(try search().positions("print").flatMap { $0.positions.map(\.id) } == ["Printing press#1", "Printing press#2"])
    }

    @Test func aMatchOnlyInTheTextShowsTheText() throws {
        // A made-up position whose bold title leaves out the words of its text.
        let vault = try sampleVault()
        let position = try JSONDecoder().decode(Position.self, from: Data("""
            {"id": "Positions#2", "note": "Positions", "number": 2, "draft": false,
             "text": "**Paper was the bottleneck**, not the press itself.", "title": "Paper was the bottleneck"}
            """.utf8))
        let search = TabSearch(vault: try replacingPositions(of: vault, with: [position]), index: VaultIndex(vault: vault))
        #expect(search.positions("bottleneck").first?.positions == [TabSearch.PositionHit(position: position, showsText: false)])
        #expect(search.positions("press itself").first?.positions == [TabSearch.PositionHit(position: position, showsText: true)])
    }

    @Test func topicsByTitleSummaryAndHeadings() throws {
        // In the summary and a heading: the heading comes along, with its anchor.
        let reformation = try search().topics("reformation")
        #expect(reformation.map(\.topic.id) == ["Printing press"])
        #expect(reformation.first?.headings == [TabSearch.Heading(text: "2. Print and the Reformation",
                                                                 anchor: "2. Print and the Reformation")])
        // Only in a heading.
        #expect(try search().topics("sources").first?.headings.map(\.anchor) == ["Sources"])
        // In the title only: no headings to show.
        #expect(try search().topics("printing press").first?.headings == [])
        // Words spread over title and headings; each heading holding one of them is shown, at most three.
        let spread = try search().topics("press how")
        #expect(spread.first?.headings.map(\.text) == ["1. How print spread", "How my view changed"])
        // A letter in four headings: three are shown.
        #expect(try search().topics("n").first?.headings.count == TabSearch.headingLimit)
        // Section pages are not topic overviews: "Trade routes" stands only in one.
        #expect(try search().topics("trade routes").isEmpty)
    }

    @Test func theLibraryFindsEveryKindTitlesFirst() throws {
        let hits = try search().library("reformation")
        // The title that starts with it, then a title that holds it, then a first paragraph; three kinds.
        #expect(hits.map(\.note.id) == ["Reformation", "Did print cause the Reformation", "Martin Luther"])
        #expect(hits.map(\.note.type) == [.event, .question, .actor])
        // A note without a summary is introduced by its first paragraph, as plain text.
        #expect(hits.last?.lead == "Monk and professor in Wittenberg; the most printed author of the Reformation.")
        // A mechanism by its summary; an event by a place; accents ignored.
        #expect(try search().library("copied ideas").map(\.note.id) == ["Information wants to be cheap"])
        #expect(try search().library("Mainz").map(\.note.id) == ["Gutenberg Bible"])
        #expect(try search().library("westfalischer").map(\.note.id) == ["Reformation"])
        // Topics, sessions and the glossary are not in the library.
        #expect(try search().library("printing press").isEmpty)
        #expect(try search().library("druckort").isEmpty)
    }

    @Test func theNoMatchLineNamesTheQuery() {
        #expect(Format.nothingFound(" zebra ", language: .english) == "Nothing found for “zebra”.")
        #expect(Format.nothingFound("zebra", language: .german) == "Nichts gefunden für „zebra“.")
    }

    /// The vault with "Across topics" holding these positions instead.
    private func replacingPositions(of vault: Vault, with positions: [Position]) throws -> Vault {
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(vault)) as! [String: Any]
        var groups = json["positions"] as! [[String: Any]]
        groups[0]["positions"] = try positions.map { try JSONSerialization.jsonObject(with: JSONEncoder().encode($0)) }
        json["positions"] = groups
        return try JSONDecoder().decode(Vault.self, from: JSONSerialization.data(withJSONObject: json))
    }
}
