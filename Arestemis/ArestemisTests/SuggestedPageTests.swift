import Foundation
import Testing
@testable import Arestemis

/// Brief 178 (the server's brief 177): a watch whose page only names or links to the thing gets the thing's own page
/// suggested. `PageState.suggested` as the contract sends it (present, null, missing, malformed), its line in both
/// languages, and "Watch this page" opening the watch's form with the new address, unsaved until Save.
@MainActor
struct SuggestedPageTests {
    private let url = ArestemisSamples.suggestedPageURL

    private func page(_ suggested: String?) throws -> PageState {
        let field = suggested.map { #", "suggested": \#($0)"# } ?? ""
        return try JSONDecoder().decode(PageState.self, from: Data("""
            {"page_title": "Beispiel Bandshop", "host": "shop.example.com", "now": null, "read": "ok", "checked": null,
             "changed": null, "note": null\(field)}
            """.utf8))
    }

    // MARK: the contract

    @Test func aSuggestionDecodesAndIsKept() throws {
        let card = try ArestemisSamples.suggestedPageWatch(id: 13)
        #expect(card.hunt.kind == .watch && card.hunt.search.watch?.url == ArestemisSamples.suggestedPageShop)
        #expect(card.page?.suggested == SuggestedPage(url: url, title: "Adventskalender 2026"))
        // Encoded back as it came.
        let encoded = try JSONEncoder().encode(try #require(card.page))
        let object = try #require(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect((object["suggested"] as? [String: String]) == ["url": url, "title": "Adventskalender 2026"])
        #expect(try JSONDecoder().decode(PageState.self, from: encoded) == card.page)
    }

    @Test func noSuggestionIsNone() throws {
        #expect(try page(nil).suggested == nil)                                  // a server from before brief 177
        #expect(try page("null").suggested == nil)
        // One that cannot be read never costs the page's state.
        let odd = try page(#""somewhere""#)
        #expect(odd.suggested == nil && odd.read == .ok && odd.pageTitle == "Beispiel Bandshop")
        #expect(try page(#"{"title": "No address"}"#).suggested == nil)
        // A missing title is empty (the line then names the address).
        #expect(try page(#"{"url": "https://shop.example.com/a"}"#).suggested == SuggestedPage(url: "https://shop.example.com/a", title: ""))
        // Encoded as null, as the other fields.
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(try page(nil))) as? [String: Any]
        #expect(object?.keys.contains("suggested") == true && object?["suggested"] is NSNull)
        // The contract's own overview has none.
        #expect(try sample(Overview.self, "overview").hunts.allSatisfy { $0.page?.suggested == nil })
    }

    // MARK: the line

    @Test(arguments: [AppLanguage.english, .german])
    func theLineNamesTheTitleAsThePageHasIt(_ language: AppLanguage) throws {
        let de = language == .german
        let text = try #require(SuggestedPageText(try ArestemisSamples.suggestedPageWatch(id: 13), language: language))
        #expect(text.quotedTitle == (de ? "„Adventskalender 2026“" : "“Adventskalender 2026”"))
        #expect(text.rest == (de ? "hat eine eigene Seite" : "has its own page"))
        #expect(text.sentence == (de ? "„Adventskalender 2026“ hat eine eigene Seite" : "“Adventskalender 2026” has its own page"))
        #expect(text.action == (de ? "Diese Seite beobachten" : "Watch this page"))
        #expect(text.page.url == url)
        // A long title stays as it is (the screen cuts it in the middle on one line).
        let long = try #require(SuggestedPageText(try ArestemisSamples.suggestedPageWatch(id: 13, long: true), language: language))
        #expect(long.quotedTitle.contains("Adventskalender 2026 – limitierte Sonderedition mit 24 Überraschungen, Poster und Tour-Pass"))
    }

    @Test func theLineShowsOnlyForAnotherPage() throws {
        var card = try ArestemisSamples.suggestedPageWatch(id: 13)
        // Without a title: the address's last part, else its host.
        card.page?.suggested = SuggestedPage(url: url, title: "  ")
        #expect(SuggestedPageText(card, language: .english)?.quotedTitle == "“adventskalender-2026.html”")
        #expect(SuggestedPageText.title("", url: "https://shop.example.com/") == "shop.example.com")
        #expect(SuggestedPageText.title("Advent\n  calendar", url: url) == "Advent calendar")
        // The page the watch reads already, or none: no line.
        card.page?.suggested = SuggestedPage(url: ArestemisSamples.suggestedPageShop, title: "Home")
        #expect(SuggestedPageText(card) == nil)
        card.page?.suggested = nil
        #expect(SuggestedPageText(card) == nil)
        // Another kind has no page.
        let thing = try #require(try sample(Overview.self, "overview").hunts.first { $0.hunt.kind == .item })
        #expect(SuggestedPageText(thing) == nil)
    }

    // MARK: Watch this page

    @Test func watchThisPageOpensTheWatchsFormWithTheNewAddress() throws {
        let navigation = AppNavigation(defaults: UserDefaults(suiteName: "arestemis.tests.178")!)
        navigation.huntPath = [.hunt(13)]
        navigation.watchSuggestedPage(13, address: url)
        #expect(navigation.tab == .hunt && navigation.huntPath == [.hunt(13), .watchAddress(hunt: 13, address: url)])

        // The form: the watch as saved, with that address in place of its own; nothing else changes, and it is unsaved.
        let card = try ArestemisSamples.suggestedPageWatch(id: 13)
        let saved = try #require(WatchSearchDraft(saved: card.hunt))
        let adopted = saved.adopting(address: " \(url) ")
        #expect(adopted.url == url && adopted.change == saved.change && adopted.every == saved.every
                && adopted.name == saved.name)
        #expect(adopted != saved)
        #expect(adopted.search() == WatchSearch(url: url, change: "the Advent calendar can be ordered", every: 60))
    }

    @Test func savingTheNewAddressReadsItFromTheStart() async throws {
        let session = EmpireSession(app: .arestemis, storage: MemoryTokens(), restoreOnLaunch: false)
        let store = ArestemisStore(session: session, backend: try SampleBackend(options: .init(suggestedPage: "short")),
                                   sample: true, placeDelay: .zero)
        await store.reloadOverview()
        let card = try #require(store.card(13))
        #expect(card.page?.suggested?.url == url && SuggestedPageText(card) != nil)
        let search = try #require(WatchSearchDraft(saved: card.hunt)?.adopting(address: url).search())
        #expect(await store.saveHunt(id: 13, kind: .watch, name: nil, search: .watch(search)) != nil)
        let after = try #require(store.card(13))
        #expect(after.hunt.search.watch?.url == url)
        #expect(after.page?.read == .waiting && after.page?.suggested == nil && SuggestedPageText(after) == nil)
        #expect(LaunchOptions(arguments: ["-sampleData", "-sampleSuggestedPage", "long"]).suggestedPage == "long")
    }
}
