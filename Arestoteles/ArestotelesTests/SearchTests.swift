import Foundation
import Testing
@testable import Arestoteles

/// Search on the device: titles first, then summaries, glossary terms (English and German), text; every word must
/// appear; case and accents do not matter; the type filter.
@MainActor
struct SearchTests {
    private func search() throws -> VaultSearch { VaultSearch(vault: try sampleVault()) }

    private func ids(_ results: [VaultSearch.Result]) -> [String] {
        results.map {
            switch $0 {
            case let .note(id, _): id
            case let .term(term, _): "term:" + term.english
            }
        }
    }

    @Test func titlesRankFirst() throws {
        let results = try search().results("printing press")
        #expect(results.first == .note(id: "Printing press", rank: .titleStart))
        #expect(results.dropFirst().first == .note(id: "2026-10-20 Printing press", rank: .title))
        // Further down: notes that only mention it in their text.
        #expect(ids(results).contains("Home") && results.last?.rank ?? .titleStart > .title)
    }

    @Test func summariesBeforeText() throws {
        let results = try search().results("trade routes")
        #expect(results.first == .note(id: "Spread of print", rank: .summary))
        let cheap = try search().results("most copied ideas")
        #expect(cheap == [.note(id: "Information wants to be cheap", rank: .summary)])
    }

    @Test func theGlossaryInBothLanguages() throws {
        #expect(try search().results("Druckort").contains(.term(Term(english: "printing town", german: "Druckort",
                                                                     note: "Spread of print"), rank: .term)))
        let trading = try search().results("trading city")
        #expect(ids(trading).contains("term:trading city"))
        // The term first, then the notes whose text has the word (the Glossary page's table, "Handelsstädte").
        #expect(ids(try search().results("handelsstadt")) == ["term:trading city", "Glossary", "Spread of print"])
    }

    @Test func caseAndAccentsDoNotMatter() throws {
        // "Handelsstädte" in the text of Spread of print, typed without the umlaut.
        #expect(ids(try search().results("HANDELSSTADTE")) == ["Spread of print"])
        #expect(ids(try search().results("westfalischer")) == ["Reformation"])
    }

    @Test func everyWordMustAppear() throws {
        #expect(try search().results("luther wittenberg").map(\.id) == ["note:Martin Luther"])
        #expect(try search().results("luther zebra").isEmpty)
        // Words spread over the title and the text.
        #expect(try search().results("gutenberg mainz") == [.note(id: "Gutenberg Bible", rank: .spread)])
    }

    @Test func positionsAreSearchedOnTheirNote() throws {
        let results = ids(try search().results("impossible to stop"))
        #expect(results.contains("Printing press"))
    }

    @Test func theTypeFilter() throws {
        #expect(ids(try search().results("reformation", type: .event)) == ["Reformation"])
        #expect(ids(try search().results("print", type: .question)) == ["Did print cause the Reformation"])
        #expect(!ids(try search().results("druckort", type: .topic)).contains { $0.hasPrefix("term:") })
        #expect(ids(try search().results("druckort", type: .glossary)).contains("term:printing town"))
    }

    @Test func nothingForNothing() throws {
        #expect(try search().results("").isEmpty && search().results("   ").isEmpty)
        #expect(VaultSearch.empty.results("print").isEmpty)
    }

    @Test func markdownIsLeftOutOfTheText() {
        let text = VaultSearch.text(of: [
            .paragraph(text: "See [Information wants to be cheap](arestoteles://note/Information%20wants%20to%20be%20cheap)."),
            .list(ordered: false, items: [ListItem(text: "**Bold** and *italic*", depth: 0)]),
            .table(header: ["City"], rows: [["`Mainz`"]]),
            .callout(style: .claude, title: "A rival view", text: "Pettegree", index: 0),
            .positions(ids: ["X#1"]), .rule,
        ])
        #expect(text == "See Information wants to be cheap.\nBold and italic\nCity\nMainz\nA rival view Pettegree")
    }
}
