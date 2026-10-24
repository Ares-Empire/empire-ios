import CoreSpotlight
import Foundation
import Testing
@testable import Arestoteles

/// The Discuss prompt, the Spotlight items, the lookups of `VaultIndex`, and the formatting of the vault's values.
@MainActor
struct FeatureTests {
    // MARK: Discuss

    @Test func discussANote() throws {
        let prompt = DiscussPrompt.make(.note("Spread of print"), index: try sampleIndex())
        #expect(prompt == "Weltbild vault, repo carlsenares/opinions: read CLAUDE.md first. Let's discuss the note "
                + "\"Spread of print\" (Topics/Printing press/Spread of print.md).")
    }

    @Test func discussAPositionWithAQuestion() throws {
        let prompt = DiscussPrompt.make(.position("Printing press#2"), question: "  Is this too cynical?\n",
                                        index: try sampleIndex())
        #expect(prompt == """
            Weltbild vault, repo carlsenares/opinions: read CLAUDE.md first. Let's discuss my position 2 on \
            "Printing press" (Topics/Printing press/Printing press.md) (still a draft): "Printers were businessmen \
            first; they printed what sold."

            Is this too cynical?
            """)
        let confirmed = try #require(DiscussPrompt.make(.position("Positions#1"), question: " ", index: try sampleIndex()))
        #expect(confirmed.hasSuffix("Let's discuss my position 1 on \"My positions\" (Positions.md): "
                                    + "\"Who controls the copies controls the argument.\""))
    }

    @Test func discussSomethingGone() throws {
        #expect(DiscussPrompt.make(.note("No such note"), index: try sampleIndex()) == nil)
        #expect(DiscussPrompt.make(.position("Printing press#9"), index: try sampleIndex()) == nil)
        #expect(DiscussPrompt.target.absoluteString == "https://claude.ai/code")
    }

    // MARK: Spotlight

    @Test func spotlightItems() throws {
        let vault = try sampleVault()
        let items = SpotlightItems.make(vault.notes, language: .english)
        #expect(items.count == 12 && Set(items.map(\.uniqueIdentifier)).count == 12)
        let topic = try #require(items.first { $0.attributeSet.title == "Printing press" })
        #expect(topic.uniqueIdentifier == "arestoteles://note/Printing%20press")
        #expect(topic.domainIdentifier == SpotlightItems.domain)
        #expect(topic.attributeSet.contentDescription?.hasPrefix("Movable type made copying cheap") == true)
        #expect(topic.attributeSet.keywords?.contains("Topic") == true)
        let question = try #require(items.first { $0.uniqueIdentifier.contains("Did%20print") })
        #expect(question.attributeSet.title == "Did print cause the Reformation?")
        #expect(question.attributeSet.contentDescription == "Question")         // no summary: its type
        #expect(NoteLink(string: question.uniqueIdentifier) == NoteLink(note: "Did print cause the Reformation"))
        // A summary's Markdown is left out.
        let note = try JSONDecoder().decode(Note.self, from: Data("""
            {"id":"X","path":"X.md","type":"mechanism","title":"X","summary":"**Cheap** [copies](arestoteles://note/Y) win",
             "version":"v"}
            """.utf8))
        #expect(SpotlightItems.item(for: note).attributeSet.contentDescription == "Cheap copies win")
    }

    @Test func aTappedResultOpensItsNote() {
        let activity = NSUserActivity(activityType: CSSearchableItemActionType)
        activity.userInfo = [CSSearchableItemActivityIdentifier: "arestoteles://note/Hitler%27s%20rise"]
        #expect(SpotlightItems.link(from: activity) == NoteLink(note: "Hitler's rise"))
        #expect(SpotlightItems.link(from: NSUserActivity(activityType: "other")) == nil)
    }

    // MARK: lookups

    @Test func lookups() throws {
        let index = try sampleIndex()
        #expect(index.topics.map(\.id) == ["Printing press"])                  // section pages are not overviews
        #expect(index.positionTargets.map(\.id) == ["Positions", "Printing press"])
        #expect(index.mechanisms.map(\.id) == ["Information wants to be cheap"])
        // Linked from Positions, Printing press and Reformation; the Positions page is an index, not a use.
        #expect(index.note("Information wants to be cheap")?.backlinks.count == 3)
        #expect(index.mechanismUses("Information wants to be cheap") == 2)
        #expect(index.questions.map(\.id) == ["Did print cause the Reformation"])
        #expect(index.actors.map(\.id) == ["Martin Luther"])
        #expect(index.backlinks(of: "Printing press").map(\.id)
                == ["2026-10-20 Printing press", "Home", "Positions", "Spread of print"])
        #expect(index.title("Reformation") == "Reformation" && index.title("Unknown") == "Unknown")
        let position = try #require(index.position("Printing press#1"))
        #expect(index.evidence(of: position).map(\.id) == ["Did print cause the Reformation", "Reformation"])
        #expect(index.positions(["Positions#1", "Gone#4"]).map(\.id) == ["Positions#1"])
    }

    @Test func theEventsTimeline() throws {
        let index = try sampleIndex()
        #expect(index.events.map(\.id) == ["Gutenberg Bible", "Reformation"])
        #expect(index.regions == ["Europe"])
        #expect(index.timeline().map(\.year) == [1454, 1517])
        #expect(index.timeline(region: "Europe").count == 2 && index.timeline(region: "Asia").isEmpty)
        #expect(index.events(inYear: 1517).map(\.id) == ["Reformation"])
        let gutenberg = try #require(index.note("Gutenberg Bible"))
        #expect(index.followed(gutenberg).map(\.id) == ["Reformation"])
    }

    @Test func eventsWithoutYearsGoLastAndSameYearsShareAnEntry() throws {
        func event(_ id: String, _ from: Int?, _ places: [String]) throws -> Note {
            let span = from.map { "{\"from\":\($0),\"to\":null,\"where\":[\(places.map { "\"\($0)\"" }.joined(separator: ","))]}" }
            return try JSONDecoder().decode(Note.self, from: Data("""
                {"id":"\(id)","path":"Library/Events/\(id).md","type":"event","title":"\(id)","event":\(span ?? "null"),
                 "version":"v"}
                """.utf8))
        }
        let vault = Vault(version: 1, commit: "c", built: "2026-10-24T18:00:00Z",
                          notes: [try event("Zama", -202, ["Africa"]), try event("Undated", nil, []),
                                  try event("Cannae", -216, ["Italy"]), try event("Metaurus", -207, ["Italy"]),
                                  try event("Ilipa", -206, ["Iberia", "Italy"]), try event("Baecula", -208, ["Iberia"]),
                                  try event("Also 208", -208, ["Italy"])],
                          positions: [], glossary: [], home: Home(learnNext: []))
        let index = VaultIndex(vault: vault)
        #expect(index.events.map(\.id) == ["Cannae", "Also 208", "Baecula", "Metaurus", "Ilipa", "Zama", "Undated"])
        #expect(index.timeline().map(\.year) == [-216, -208, -207, -206, -202, nil])
        #expect(index.timeline().first { $0.year == -208 }?.events.count == 2)
        #expect(index.regions == ["Africa", "Iberia", "Italy"])
        #expect(index.timeline(region: "Iberia").flatMap(\.events).map(\.id) == ["Baecula", "Ilipa"])
    }

    @Test func anEmbedShowsItsSection() throws {
        let index = try sampleIndex()
        #expect(index.section(of: "Printing press", anchor: "My position") == [
            .heading(level: 2, text: "My position", anchor: "My position"),
            .positions(ids: ["Printing press#1", "Printing press#2"]),
        ])
        let section = index.section(of: "Printing press", anchor: "2. Print and the Reformation")
        #expect(section.count == 3)                                             // heading, paragraph, callout
        #expect(index.section(of: "Reformation", anchor: nil).count == 3)       // the whole note
        #expect(index.section(of: "Printing press", anchor: "No such heading").isEmpty)
        #expect(index.section(of: "No such note", anchor: nil).isEmpty)
    }

    // MARK: formatting

    @Test func years() {
        #expect(Format.years(from: 1517, to: 1648, language: .english) == "1517–1648")
        #expect(Format.years(from: 1454, to: 1454, language: .english) == "1454")
        #expect(Format.years(from: 1789, to: nil, language: .english) == "1789")
        #expect(Format.years(from: nil, to: nil, language: .english) == nil)
        #expect(Format.years(from: -490, to: -479, language: .english) == "490–479 BCE")
        #expect(Format.years(from: -44, to: 14, language: .english) == "44 BCE – 14 CE")
        #expect(Format.year(-44, language: .english) == "44 BCE")
    }

    @Test func wordsAndDates() {
        #expect(Format.confidence(.myRead, language: .english) == "My read")
        #expect(Format.type(.question, language: .english) == "Question")
        #expect(Format.types(.mechanism, language: .english) == "Mechanisms")
        #expect(Format.day("2026-10-20", language: .english) == "20 Oct 2026")
        #expect(Format.day("not a date", language: .english) == "not a date")
        #expect(Format.timestamp("2026-10-24T18:00:00Z") == Date(timeIntervalSince1970: 1_792_864_800))
        let now = Date(timeIntervalSince1970: 1_792_864_800)
        #expect(Format.age(now.addingTimeInterval(-20), now: now, language: .english) == "just now")
        #expect(Format.age(now.addingTimeInterval(-300), now: now, language: .english) == "5 min ago")
        #expect(Format.age(now.addingTimeInterval(-7200), now: now, language: .english) == "2 h ago")
    }
}
