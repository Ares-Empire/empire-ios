import Foundation
import Testing
@testable import Arestoteles

/// One link parser for links in notes, deep links and Spotlight: ids with spaces, apostrophes and other characters,
/// anchors; what is not a note link stays out. And what the navigation does with a link.
@MainActor
struct LinkTests {
    @Test func theContractsLinks() throws {
        let plain = try #require(NoteLink(string: "arestoteles://note/Printing%20press"))
        #expect(plain == NoteLink(note: "Printing press") && plain.anchor == nil)
        let heading = try #require(NoteLink(string: "arestoteles://note/Printing%20press#My%20position"))
        #expect(heading == NoteLink(note: "Printing press", anchor: "My position"))
        let numbered = try #require(NoteLink(string: "arestoteles://note/Printing%20press#2.%20Print%20and%20the%20Reformation"))
        #expect(numbered.anchor == "2. Print and the Reformation")
    }

    @Test func apostrophesEncodedOrNot() throws {
        #expect(NoteLink(string: "arestoteles://note/Hitler%27s%20rise") == NoteLink(note: "Hitler's rise"))
        #expect(NoteLink(string: "arestoteles://note/Hitler's%20rise") == NoteLink(note: "Hitler's rise"))
        #expect(NoteLink(string: "arestoteles://note/Hitler's%20rise#Who%20paid%3F")
                == NoteLink(note: "Hitler's rise", anchor: "Who paid?"))
    }

    @Test(arguments: ["Printing press", "Hitler's rise", "2026-10-20 Printing press", "Glossary (Begriffe)",
                      "Westfälischer Frieden", "Was it 100% certain?", "Rome & Carthage", "Q: why; how/"])
    func everyIDSurvivesTheRoundTrip(id: String) throws {
        let link = NoteLink(note: id, anchor: "A heading: with # and spaces")
        #expect(NoteLink(url: link.url) == link)
        #expect(NoteLink(string: link.url.absoluteString) == link)
        #expect(link.url.absoluteString.hasPrefix("arestoteles://note/"))
    }

    @Test func otherLinksAreNotNoteLinks() {
        for text in ["https://en.wikipedia.org/wiki/Printing_press", "arestoteles://", "arestoteles://note/",
                     "arestoteles://note", "arestoteles://match/41", "arestemis://note/Printing%20press", "mailto:x@y.z"] {
            #expect(NoteLink(string: text) == nil, "\(text)")
        }
        #expect(NoteLink(string: "ARESTOTELES://NOTE/Reformation") == NoteLink(note: "Reformation"))
        #expect(NoteLink(string: "arestoteles://note/Reformation#") == NoteLink(note: "Reformation"))
    }

    /// The links inside the sample's Markdown, as `AttributedString` makes them, open the right notes.
    @Test func linksInTheSampleText() throws {
        let vault = try sampleVault()
        let paragraph = try #require(vault.notes.first { $0.id == "Printing press" }?.blocks.compactMap {
            if case let .paragraph(text) = $0 { text } else { nil }
        }.last)
        let text = InlineMarkdown.attributed(paragraph)
        let links = text.runs.compactMap(\.link).compactMap(NoteLink.init(url:))
        #expect(links == [NoteLink(note: "Information wants to be cheap"), NoteLink(note: "Did print cause the Reformation")])
        #expect(String(text.characters).contains("see Information wants to be cheap and Did print cause the Reformation."))

        // Every note link of the sample names a note of the sample.
        let ids = Set(vault.notes.map(\.id))
        let all = vault.notes.flatMap { note in note.blocks.flatMap { VaultSearchLinks.texts(of: $0) } }
            .flatMap { InlineMarkdown.attributed($0).runs.compactMap(\.link) }
        let notes = all.compactMap(NoteLink.init(url:))
        #expect(!notes.isEmpty && notes.allSatisfy { ids.contains($0.note) })
        #expect(all.contains(URL(string: "https://en.wikipedia.org/wiki/Printing_press")!))
    }

    @Test func inlineMarkdown() {
        #expect(InlineMarkdown.plain("**Yes, it was the cause:** without *cheap* `copies`") ==
                "Yes, it was the cause: without cheap copies")
        #expect(InlineMarkdown.plain("[A (rival) view](arestoteles://note/A%20(rival)%20view) here") == "A (rival) view here")
        #expect(InlineMarkdown.plain("snake_case stays, _emphasis_ goes, \\*kept\\*") == "snake_case stays, emphasis goes, *kept*")
        #expect(InlineMarkdown.plain("[not a link] (really)") == "[not a link] (really)")
        let bold = InlineMarkdown.attributed("**Bold** text")
        #expect(String(bold.characters) == "Bold text")
        #expect(String(InlineMarkdown.attributed("Unclosed **bold").characters).contains("bold"))
    }

    // MARK: navigation

    @Test func openingALinkPushesTheNote() {
        let navigation = AppNavigation()
        navigation.sheet = .quickNote
        navigation.open(NoteLink(note: "Reformation"))
        #expect(navigation.positionsPath == [.note(NoteLink(note: "Reformation"))] && navigation.sheet == nil)
        // A heading of the note on top: scroll, do not push it again.
        navigation.open(NoteLink(note: "Reformation", anchor: "Mechanisms at work"))
        #expect(navigation.positionsPath.count == 1 && navigation.scrollRequest?.anchor == "Mechanisms at work")
        navigation.scrolled()
        #expect(navigation.scrollRequest == nil)
        // Another tab keeps its own pages.
        navigation.tab = .library
        navigation.open(NoteLink(note: "Martin Luther"))
        #expect(navigation.libraryPath == [.note(NoteLink(note: "Martin Luther"))] && navigation.positionsPath.count == 1)
    }

    @Test func linksFromOutsideWaitForTheTabs() {
        let navigation = AppNavigation()
        navigation.follow(NoteLink(note: "Gutenberg Bible"))
        #expect(navigation.positionsPath.isEmpty && navigation.pendingLink != nil)
        navigation.openPendingLink()
        #expect(navigation.positionsPath == [.note(NoteLink(note: "Gutenberg Bible"))] && navigation.pendingLink == nil)
    }

    @Test func aDroppedPositionClosesItsPage() {
        let navigation = AppNavigation()
        navigation.showPosition("Printing press#2")
        navigation.open(NoteLink(note: "Reformation"))
        navigation.tab = .topics
        navigation.showPosition("Printing press#2")
        navigation.closePosition("Printing press#2")
        #expect(navigation.positionsPath.isEmpty && navigation.topicsPath.isEmpty)
    }

    @Test func launchArguments() throws {
        let options = LaunchOptions(arguments: ["-sampleData", "-tab", "library", "-openNote", "Printing press#My position",
                                                "-openSheet", "brief", "-sampleOffline"])
        #expect(options.sample && options.offline && options.tab == .library)
        #expect(options.openNote == NoteLink(note: "Printing press", anchor: "My position"))
        let navigation = AppNavigation()
        options.apply(to: navigation, index: try sampleIndex())
        #expect(navigation.tab == .library && navigation.sheet == nil)  // the sheet comes with the note
        navigation.openPendingLink()
        #expect(navigation.libraryPath == [.note(NoteLink(note: "Printing press", anchor: "My position"))])
        #expect(navigation.sheet == .brief("Printing press"))

        let position = LaunchOptions(arguments: ["-sampleData", "-openPosition", "Printing press#2", "-openSheet", "drop"])
        let other = AppNavigation()
        position.apply(to: other, index: try sampleIndex())
        #expect(other.positionsPath == [.position("Printing press#2")] && other.sheet == .position(.drop("Printing press#2")))

        let notSample = LaunchOptions(arguments: ["-tab", "search"])
        let untouched = AppNavigation()
        notSample.apply(to: untouched, index: try sampleIndex())
        #expect(untouched.tab == .positions)
    }
}

/// The inline texts of a block (tests only).
enum VaultSearchLinks {
    static func texts(of block: Block) -> [String] {
        switch block {
        case let .heading(_, text, _), let .paragraph(text), let .quote(text): [text]
        case let .list(_, items): items.map(\.text)
        case let .callout(_, title, text, _): [title, text].compactMap { $0 }
        case let .table(header, rows): header + rows.flatMap { $0 }
        default: []
        }
    }
}
