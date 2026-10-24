import Foundation
import Testing
@testable import Arestoteles

/// The contract's samples (Samples/ = Arestoteles/docs/samples/) decode into the app's models and survive the round
/// trip through the app's own cache; edits encode exactly as API.md → Edits says.
@MainActor
struct DecodingTests {
    @Test(arguments: ArestotelesSamples.files)
    func everySampleDecodesAndRoundTrips(file: String) throws {
        switch file {
        case "vault": try roundTrip(Vault.self, file)
        case "note-source": try roundTrip(NoteSource.self, file)
        case "edit-result": try roundTrip(EditResult.self, file)
        case "search": try roundTrip(SearchAnswer.self, file)
        default: Issue.record("No model for \(file)")
        }
    }

    private func roundTrip<T: Codable & Equatable>(_ type: T.Type, _ file: String) throws {
        let decoded = try sample(type, file)
        #expect(try JSONDecoder().decode(type, from: JSONEncoder().encode(decoded)) == decoded)
    }

    @Test func vaultSample() throws {
        let vault = try sampleVault()
        #expect(vault.version == 1 && vault.commit == "a1b2c3d" && vault.built == "2026-10-24T18:00:00Z")
        #expect(vault.notes.count == 13)
        #expect(vault.positions.map(\.title) == ["Across topics", "Printing press"])
        #expect(vault.glossary.map(\.german) == ["Druckort", "Handelsstadt"])
        #expect(vault.home.learnNext.count == 2)

        let topic = try #require(vault.notes.first { $0.id == "Printing press" })
        #expect(topic.type == .topic && topic.isTopicOverview && topic.confidence == .myRead)
        #expect(topic.path == "Topics/Printing press/Printing press.md" && topic.tags == ["media", "europe"])
        #expect(topic.positions == ["Printing press#1", "Printing press#2"])
        #expect(topic.callouts == [Callout(index: 0, style: .claude, title: "A rival view", text: topic.callouts[0].text)])
        #expect(topic.version == "3f2a9c1e4b7d8a0f6e5c2b1a9d8e7f6c5b4a3921")
        #expect(topic.blocks.first == .heading(level: 2, text: "My position", anchor: "My position"))
        #expect(topic.blocks.contains(.positions(ids: ["Printing press#1", "Printing press#2"])))
        #expect(topic.blocks.contains(.sectionLink(note: "Spread of print")))
        let brief = try #require(topic.brief)
        #expect(brief.positions.count == 2 && brief.sections.map(\.note) == ["Spread of print", nil])
        #expect(brief.counterpoints.first?.title == "A rival view" && brief.shaky.first?.note == "Spread of print")
        #expect(brief.terms.map(\.english) == ["printing town", "trading city"])
        #expect(brief.questions == ["Did print cause the Reformation"])

        let section = try #require(vault.notes.first { $0.id == "Spread of print" })
        #expect(section.topic == "Printing press" && !section.isTopicOverview)
        #expect(section.partOf == PartOf(note: "Printing press", section: 1))
        #expect(section.blocks.contains(.table(header: ["City", "First press"],
                                               rows: [["Mainz", "1450"], ["Venice", "1469"], ["Lyon", "1473"]])))
        #expect(section.blocks.contains(.callout(style: .shaky, title: nil, text: section.callouts[0].text, index: 0)))

        let event = try #require(vault.notes.first { $0.id == "Gutenberg Bible" })
        #expect(event.event == EventSpan(from: 1454, to: 1455, where: ["Europe"]) && event.ledTo == ["Reformation"])

        let positions = try #require(vault.notes.first { $0.id == "Positions" })
        #expect(positions.blocks.last == .embed(note: "Printing press", anchor: "My position"))

        let changed = try #require(vault.positions[1].positions.first)
        #expect(changed.id == "Printing press#1" && changed.number == 1 && !changed.draft)
        #expect(changed.evidence == ["Did print cause the Reformation", "Reformation"])
        #expect(changed.history == [PositionChange(date: "2026-10-20", text: "Print caused the Reformation.",
                                                   why: "Earlier reformers failed without a press, but the press alone convinced nobody.")])
        #expect(vault.positions[1].positions[1].draft)
    }

    @Test func sourceAndEditResultSamples() throws {
        let source = try sample(NoteSource.self, "note-source")
        #expect(source.id == "Spread of print" && source.version == "8b1d2e3f4a5c6d7e8f9a0b1c2d3e4f5a6b7c8d9e")
        #expect(source.markdown.hasPrefix("# Spread of print\n"))

        let result = try sample(EditResult.self, "edit-result")
        #expect(result.changed == ["Printing press"] && result.pushed && result.warnings.isEmpty)
        #expect(result.vault.commit == "b2c3d4e")
        #expect(result.vault.positions[1].positions[1].draft == false)
    }

    /// Kinds the sample does not use, and values the app does not know: read, never fatal.
    @Test func otherBlocksAndUnknownValues() throws {
        let blocks = try JSONDecoder().decode([Block].self, from: Data("""
            [{"kind":"quote","text":"*Sapere aude.*"},{"kind":"rule"},
             {"kind":"callout","style":"note","title":null,"text":"A plain callout","index":3},
             {"kind":"embed","note":"Reformation","anchor":null},
             {"kind":"timeline","years":[1517]}]
            """.utf8))
        #expect(blocks == [.quote(text: "*Sapere aude.*"), .rule,
                           .callout(style: .note, title: nil, text: "A plain callout", index: 3),
                           .embed(note: "Reformation", anchor: nil), .unknown(kind: "timeline")])

        var json = try #require(try JSONSerialization.jsonObject(with: ArestotelesSamples.data("vault")) as? [String: Any])
        var notes = try #require(json["notes"] as? [[String: Any]])
        notes[0]["type"] = "person"
        notes[0]["confidence"] = "certain"
        json["notes"] = notes
        let vault = try JSONDecoder().decode(Vault.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(vault.notes[0].type == NoteType(rawValue: "person") && vault.notes[0].confidence == nil)
        #expect(Format.type(vault.notes[0].type) == "Person")
    }

    /// Every op, with exactly the contract's fields.
    @Test func editsEncodeAsTheContractSays() throws {
        let cases: [(Edit, [String: AnyHashable])] = [
            (.confirmPosition(position: "Colonialism#2"), ["op": "confirm_position", "position": "Colonialism#2"]),
            (.rewordPosition(position: "Colonialism#2", text: "New words."),
             ["op": "reword_position", "position": "Colonialism#2", "text": "New words."]),
            (.changePosition(position: "Positions#3", text: "A new view.", why: "A new book."),
             ["op": "change_position", "position": "Positions#3", "text": "A new view.", "why": "A new book."]),
            (.dropPosition(position: "Positions#3", why: "No longer true."),
             ["op": "drop_position", "position": "Positions#3", "why": "No longer true."]),
            (.addPosition(note: "Printing press", text: "One more.", evidence: ["Reformation", "Gutenberg Bible"]),
             ["op": "add_position", "note": "Printing press", "text": "One more.",
              "evidence": ["Reformation", "Gutenberg Bible"] as [String]]),
            (.setConfidence(note: "Reformation", confidence: .myRead),
             ["op": "set_confidence", "note": "Reformation", "confidence": "my-read"]),
            (.adoptCallout(note: "Printing press", callout: 0, version: "abc"),
             ["op": "adopt_callout", "note": "Printing press", "callout": 0, "version": "abc"]),
            (.dismissCallout(note: "Printing press", callout: 1, version: "abc"),
             ["op": "dismiss_callout", "note": "Printing press", "callout": 1, "version": "abc"]),
            (.editNote(note: "Spread of print", version: "v1", markdown: "# Spread of print\n"),
             ["op": "edit_note", "note": "Spread of print", "version": "v1", "markdown": "# Spread of print\n"]),
            (.quickNote(text: "  paper first?  "), ["op": "quick_note", "text": "  paper first?  "]),
        ]
        for (edit, expected) in cases {
            let json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(edit)) as? [String: AnyHashable])
            #expect(json == expected, "\(edit.op)")
        }
        #expect(Edit.dropPosition(position: "Printing press#2", why: "x").note == "Printing press")
        #expect(Edit.quickNote(text: "x").note == nil)
    }

    @Test func positionIDs() {
        #expect(Position.note(ofID: "Printing press#2") == "Printing press")
        #expect(Position.note(ofID: "Positions#13") == "Positions")
        #expect(Position.note(ofID: "No number") == "No number")
    }
}
