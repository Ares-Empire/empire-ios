import Foundation
import Testing
@testable import Arestemis

/// Brief 187 (the server's briefs 185 and 186, 2026-11-06). A thing search has two wishes, Must have (`extra`: a
/// listing that clearly breaks one is filtered out) and Nice to have (`nice`: never filters one out), each in its own
/// place in the form; and the listings the server could not check in time are counted on each search
/// (`Counts.not_checked`) and listed (`GET /not-checked`), so nothing vanishes unseen.
@MainActor
struct WishesAndNotCheckedTests {
    private final class Token {}

    /// One of the server's own sample answers (`ArestemisTests/ServerSamples/`).
    private func server(_ name: String) throws -> Data {
        let url = try #require(Bundle(for: Token.self).url(forResource: "server-\(name)", withExtension: "json"))
        return try Data(contentsOf: url)
    }

    private func query(_ request: URLRequest?) -> [String: String] {
        let items = request?.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?.queryItems ?? []
        return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { $1 })
    }

    private func sampleStore(_ options: SampleBackend.Options = .init()) async throws -> ArestemisStore {
        let session = EmpireSession(app: .arestemis, storage: MemoryTokens(), restoreOnLaunch: false)
        let store = ArestemisStore(session: session, backend: try SampleBackend(options: options), sample: true,
                                   placeDelay: .zero, findDelay: .zero)
        await store.reloadOverview()
        return store
    }

    /// A thing search as the server sends it, with `nice` set to a value or left out (`nil`).
    private func itemSearchJSON(nice: String?) throws -> Data {
        var object: [String: Any] = [
            "query": "Silk shirt", "more_queries": [], "exclude": [], "price_min": NSNull(), "price_max": 80,
            "vb_over_max": 8, "condition_min": NSNull(), "for_parts": false, "auctions": true, "delivery": "shipping",
            "places": [], "radius_km": 20, "seller": "any", "extra": "Size 43, 100% silk", "sources": ["kleinanzeigen"],
        ]
        if let nice { object["nice"] = nice }
        return try JSONSerialization.data(withJSONObject: object)
    }

    private func valid() -> ItemSearchDraft {
        var draft = ItemSearchDraft()
        draft.words = ["Silk shirt"]
        draft.delivery = .shipping
        return draft
    }

    // MARK: nice: coding

    @Test func niceIsReadWhenSentAndEmptyWhenMissing() throws {
        let present = try JSONDecoder().decode(ItemSearch.self, from: itemSearchJSON(nice: "Red or burgundy"))
        #expect(present.extra == "Size 43, 100% silk" && present.nice == "Red or burgundy")
        // A server or a search from before the wishes (brief 185) sends none: empty, the old text stays under Must have.
        let missing = try JSONDecoder().decode(ItemSearch.self, from: itemSearchJSON(nice: nil))
        #expect(missing.extra == "Size 43, 100% silk" && missing.nice == "")
        // Always sent, also when empty.
        for search in [present, missing] {
            let object = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(search)) as? [String: Any])
            #expect(object["nice"] as? String == search.nice)
            #expect(try JSONDecoder().decode(ItemSearch.self, from: JSONEncoder().encode(search)) == search)
        }
        // The draft sends both, trimmed, under their own keys.
        var draft = valid()
        draft.extra = "  Size 43, 100% silk "
        draft.nice = " Red or burgundy  "
        let sent = try #require(draft.search())
        #expect(sent.extra == "Size 43, 100% silk" && sent.nice == "Red or burgundy")
        #expect(ItemSearchDraft(sent).search() == sent)
    }

    @Test func aDraftKeptBeforeTheWishesOpensWithNiceEmpty() throws {
        var draft = valid()
        draft.extra = "Size 43"
        draft.nice = "Red"
        let data = try JSONEncoder().encode(draft)
        #expect(try JSONDecoder().decode(ItemSearchDraft.self, from: data) == draft)
        var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "nice")
        let older = try JSONDecoder().decode(ItemSearchDraft.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(older.extra == "Size 43" && older.nice == "" && older.words == ["Silk shirt"])
    }

    // MARK: validation and Save

    @Test func eachWishHoldsAtMostAThousandCharacters() throws {
        var draft = valid()
        draft.nice = String(repeating: "a", count: ItemSearchDraft.maxWishLength)
        draft.extra = String(repeating: "b", count: 1000)
        #expect(draft.isValid && draft.search() != nil)
        draft.nice += "a"
        #expect(draft.problems == [.nice] && draft.search() == nil)
        #expect(draft.fieldLine(.nice) == "At most 1,000 characters." && draft.fieldLine(.extra) == nil)
        #expect(draft.fieldLine(.nice, language: .german) == "Höchstens 1.000 Zeichen.")
        #expect(draft.hint() == "At most 1,000 characters.")
        draft.extra += "b"
        #expect(draft.problems == [.extra, .nice] && draft.fieldLine(.extra) == "At most 1,000 characters.")
        draft.nice = ""
        draft.extra = ""
        #expect(draft.isValid)
        // Each wish names its own text and line.
        #expect(Wish.allCases == [.must, .nice])
        #expect(Wish.must.text == \ItemSearchDraft.extra && Wish.nice.text == \ItemSearchDraft.nice)
        #expect(Wish.must.problem == .extra && Wish.nice.problem == .nice)
    }

    @Test func aChangedWishEnablesSave() throws {
        let card = try #require(try sample(Overview.self, "overview").hunts.first { $0.id == 5 })
        let hunt = card.hunt
        var draft = try #require(ItemSearchDraft(saved: hunt))
        #expect(!draft.isChanged(from: hunt))
        draft.nice = "Dark blue"
        #expect(draft.isChanged(from: hunt))
        // Only spaces send nothing new.
        draft.nice = "   "
        #expect(!draft.isChanged(from: hunt))
        draft.extra += " W33 too."
        #expect(draft.isChanged(from: hunt))
        // A new form: anything typed, a wish too.
        var new = ItemSearchDraft()
        #expect(!new.isChanged(from: nil))
        new.nice = "Red"
        #expect(new.isChanged(from: nil))
    }

    // MARK: an old search, describe it, Product suggestions

    @Test func anOldSearchOpensWithItsTextUnderMustHaveAndNiceToHaveEmpty() async throws {
        // The app's sample (a search from before the wishes, no `nice`): hunt 5's text.
        let store = try await sampleStore()
        let draft = store.itemSearchDraft(huntID: 5)
        #expect(draft.extra == "Levi's and Lee only in dark blue, Denimwerk any colour. W32, L32 or L34.")
        #expect(draft.nice == "")
        #expect(!draft.isChanged(from: store.card(5)?.hunt))
        // The server's own: its thing search has `nice: ""`; nothing moved out of `extra`.
        let hunts = try JSONDecoder().decode([Hunt].self, from: server("hunts"))
        let chairs = try #require(hunts.first { $0.kind == .item }?.search.item)
        #expect(chairs.extra == "Aeron nur Größe B, Leap oder Gesture mit Armlehnen" && chairs.nice == "")
    }

    @Test func describeItFillsBothWishes() async throws {
        let (store, transport, _) = try await makeStore()
        await store.reloadOverview()
        transport.answer("POST /search/parse", json: Data(#"""
            {"search": {"query": "Seidenhemd", "extra": "Größe 43, 100 % Seide", "nice": "Rot oder Bordeaux"},
             "unclear": []}
            """#.utf8))
        let parsed = await store.parse(text: "Seidenhemd Größe 43, am liebsten rot", kind: .item)
        guard case .item(let answer) = parsed else { Issue.record("no thing search"); return }
        #expect(answer.search.extra == "Größe 43, 100 % Seide" && answer.search.nice == "Rot oder Bordeaux")
        var draft = ItemSearchDraft()
        draft.apply(answer.search)
        #expect(draft.words == ["Seidenhemd"] && draft.extra == "Größe 43, 100 % Seide" && draft.nice == "Rot oder Bordeaux")
        // An empty or missing wish keeps what is typed (as `extra` always did).
        draft.apply(PartialItemSearch(extra: "", nice: ""))
        draft.apply(PartialItemSearch())
        #expect(draft.extra == "Größe 43, 100 % Seide" && draft.nice == "Rot oder Bordeaux")
        draft.apply(PartialItemSearch(nice: "Bordeaux"))
        #expect(draft.extra == "Größe 43, 100 % Seide" && draft.nice == "Bordeaux")
    }

    @Test func productSuggestionsKeepWritingMustHaveOnly() {
        let draft = ProductItemSearch(query: "Orbital Headphones 2", extra: "blue").draft
        #expect(draft.extra == "blue" && draft.nice == "")
    }

    // MARK: Counts.not_checked

    @Test func notCheckedIsCountedWhenSentAndZeroWhenMissing() throws {
        let present = try JSONDecoder().decode(Overview.Counts.self, from: Data(
            #"{"new": 6, "today": 5, "saved": 1, "applied": 1, "not_checked": 4}"#.utf8))
        #expect(present.notChecked == 4 && present.new == 6)
        let missing = try JSONDecoder().decode(Overview.Counts.self, from: Data(
            #"{"new": 6, "today": 5, "saved": 1, "applied": 1}"#.utf8))
        #expect(missing.notChecked == 0)
        let object = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(present)) as? [String: Any])
        #expect(object["not_checked"] as? Int == 4)
        // The server's overview: on the whole account and on each search's card.
        let overview = try JSONDecoder().decode(Overview.self, from: server("overview"))
        #expect(overview.counts.notChecked == 4)
        #expect(overview.hunts.first { $0.id == 3 }?.counts.notChecked == 4)
        #expect(overview.hunts.filter { $0.id != 3 }.allSatisfy { $0.counts.notChecked == 0 })
        // The app's own sample is from before them: none anywhere.
        let old = try sample(Overview.self, "overview")
        #expect(old.counts.notChecked == 0 && old.hunts.allSatisfy { $0.counts.notChecked == 0 })
    }

    // MARK: the row, the store and the route

    @Test func theRowShowsOnlyAboveZeroWithItsCountAndItsListAsksWithTheHunt() async throws {
        #expect(QuietLink(.notChecked, count: 0) == nil)
        let link = try #require(QuietLink(.notChecked, count: 4))
        #expect(link.countText == "4" && link.symbol == "hourglass")
        let transport = FakeTransport()
        transport.answer("GET /overview", json: try server("overview"))
        let (store, _, _) = try await makeStore(transport: transport)
        await store.reloadOverview()
        // Over every search the account's count, per search its own.
        #expect(QuietLink(.notChecked, count: store.notCheckedCount())?.countText == "4")
        #expect(QuietLink(.notChecked, count: store.notCheckedCount(hunt: 3))?.countText == "4")
        #expect(QuietLink(.notChecked, count: store.notCheckedCount(hunt: 1)) == nil)
        #expect(store.notCheckedCount(hunt: 999) == 0)
        // The list: of every search without `hunt`, of one with it; the server's most, one page.
        transport.answer("GET /not-checked", json: try server("not-checked"))
        await store.loadNotChecked()
        #expect(query(transport.requests("GET /not-checked").last) == ["limit": "200"])
        #expect(store.notChecked().loaded && store.notChecked().items.map(\.id) == [12])
        await store.loadNotChecked(hunt: 3)
        #expect(query(transport.requests("GET /not-checked").last) == ["limit": "200", "hunt": "3"])
        #expect(store.notChecked(hunt: 3).items.map(\.huntID) == [3])
        #expect(ArestemisStore.notCheckedLimit == 200)
    }

    @Test func aFailureIsTheListsAndTryAgainLoadsIt() async throws {
        let (store, transport, _) = try await makeStore()
        await store.reloadOverview()
        transport.answer("GET /not-checked", 503, json: Data(#"{"error":"Try again in a minute."}"#.utf8))
        await store.loadNotChecked()
        #expect(store.notChecked().error == "Try again in a minute." && !store.notChecked().loaded)
        transport.answer("GET /not-checked", json: try server("not-checked"))
        await store.loadNotChecked()
        #expect(store.notChecked().error == nil && store.notChecked().items.count == 1)
    }

    @Test func thePageIsPushedOnTheListingsTabForEverySearchOrOne() {
        let navigation = AppNavigation(defaults: UserDefaults(suiteName: "WishesAndNotCheckedTests-\(UUID().uuidString)")!)
        navigation.tab = .listings
        navigation.showNotChecked(hunt: nil)
        #expect(navigation.listingsPath == [.notChecked(hunt: nil)] && ListingsRoute.notChecked(hunt: nil).hunt == nil)
        navigation.listingsPath = [.hunt(2)]
        navigation.showNotChecked(hunt: 2)
        #expect(navigation.listingsPath == [.hunt(2), .notChecked(hunt: 2)] && ListingsRoute.notChecked(hunt: 2).hunt == 2)
        // A deleted search takes its own pages with it.
        navigation.leaveDeleted(2)
        #expect(navigation.listingsPath.isEmpty)
    }

    @Test func theLaunchArguments() {
        var options = LaunchOptions(arguments: ["-sampleData", "-openNotChecked"])
        #expect(options.openNotChecked && options.tab == .listings)
        var navigation = AppNavigation(defaults: UserDefaults(suiteName: "WishesAndNotCheckedTests-\(UUID().uuidString)")!)
        navigation.part = .searches
        options.apply(to: navigation, firstMatch: nil)
        #expect(navigation.tab == .listings && navigation.part == .new && navigation.listingsPath == [.notChecked(hunt: nil)])
        options = LaunchOptions(arguments: ["-sampleData", "-openSearch", "2", "-openNotChecked"])
        navigation = AppNavigation(defaults: UserDefaults(suiteName: "WishesAndNotCheckedTests-\(UUID().uuidString)")!)
        options.apply(to: navigation, firstMatch: nil)
        #expect(navigation.listingsPath == [.hunt(2), .notChecked(hunt: 2)])
        #expect(!LaunchOptions(arguments: ["-sampleData"]).openNotChecked)
    }

    // MARK: a row's link

    @Test func aRowWithoutAWebLinkOpensNothing() throws {
        let page = try JSONDecoder().decode(NotCheckedPage.self, from: server("not-checked"))
        let item = try #require(page.items.only)
        #expect(item.link == URL(string: "https://www.kleinanzeigen.de/s-anzeige/invented-chair/1234567890"))
        func with(url: Any) throws -> NotChecked {
            var object = try #require(try JSONSerialization.jsonObject(with: server("not-checked")) as? [String: Any])
            var items = try #require(object["items"] as? [[String: Any]])
            items[0]["url"] = url
            object["items"] = items
            return try #require(try JSONDecoder().decode(NotCheckedPage.self,
                                                          from: JSONSerialization.data(withJSONObject: object)).items.first)
        }
        #expect(try with(url: NSNull()).link == nil)
        #expect(try with(url: "").link == nil)
        #expect(try with(url: "kleinanzeigen://s-anzeige/1").link == nil)
        #expect(try with(url: "javascript:alert(1)").link == nil)
        // The sample's listing without title or link.
        let samples = try sample(NotCheckedPage.self, "not-checked").items
        let bare = try #require(samples.first { $0.url == nil })
        #expect(bare.link == nil && !bare.hasTitle && bare.shownTitle() == "Untitled" && bare.price == nil)
    }

    // MARK: the sample server

    @Test func theSampleImitatesTheServer() async throws {
        let store = try await sampleStore()
        #expect(store.notCheckedCount() == 4)
        #expect(store.notCheckedCount(hunt: 2) == 2 && store.notCheckedCount(hunt: 5) == 1 && store.notCheckedCount(hunt: 1) == 0)
        await store.loadNotChecked()
        #expect(store.notChecked().items.map(\.id) == [24, 23, 22, 21])
        await store.loadNotChecked(hunt: 2)
        #expect(store.notChecked(hunt: 2).items.map(\.id) == [24, 22])
        let backend = try SampleBackend()
        await #expect(throws: HTTPError.self) { _ = try await backend.notChecked(hunt: 999, limit: 200) }
        #expect(try await backend.notChecked(hunt: nil, limit: 1).items.map(\.id) == [24])
        // A deleted search takes its listings with it, and the lists are asked again.
        #expect(await store.deleteHunt(id: 2))
        #expect(store.notCheckedCount() == 2 && !store.notChecked().loaded)
        await store.loadNotChecked()
        #expect(store.notChecked().items.map(\.id) == [23, 21])
        // No search, nothing.
        let empty = try await sampleStore(.init(noHunt: true))
        #expect(empty.notCheckedCount() == 0)
    }

    // MARK: words

    @Test(arguments: [AppLanguage.english, .german])
    func theWords(_ language: AppLanguage) throws {
        let german = language == .german
        #expect(Wish.heading(language: language) == (german ? "Wünsche" : "Wishes"))
        #expect(Wish.must.title(language: language) == (german ? "Muss sein" : "Must have"))
        #expect(Wish.nice.title(language: language) == (german ? "Wäre schön" : "Nice to have"))
        #expect(Wish.must.placeholder(language: language) == (german ? "Größe 43, 100 % Seide" : "Size 43, 100% silk"))
        #expect(Wish.nice.placeholder(language: language) == (german ? "Rot oder Bordeaux" : "Red or burgundy"))
        #expect(Wish.must.caption(language: language)
                == (german ? "Angebote, die klar nicht passen, werden aussortiert."
                           : "Listings that clearly don't match are filtered out."))
        #expect(Wish.nice.caption(language: language)
                == (german ? "Sortiert nie ein Angebot aus." : "Never filters a listing out."))
        #expect(NotCheckedWords.title(language: language) == (german ? "Nicht rechtzeitig geprüft" : "Not checked in time"))
        #expect(NotCheckedWords.line(language: language)
                == (german ? "Diese Angebote konnten nicht rechtzeitig geprüft werden. Schau sie dir selbst an; sie bleiben 7 Tage hier."
                           : "These listings couldn't be checked in time. Have a look yourself; they stay here for 7 days."))
        #expect(NotCheckedWords.empty(language: language) == (german ? "Gerade keine Angebote hier." : "No listings here right now."))
        #expect(NotCheckedWords.untitled(language: language) == (german ? "Ohne Titel" : "Untitled"))
        let link = try #require(QuietLink(.notChecked, count: 4))
        #expect(link.title(language: language) == NotCheckedWords.title(language: language))
        #expect(link.spoken(language: language)
                == (german ? "Nicht rechtzeitig geprüft, 4 Angebote" : "Not checked in time, 4 listings"))
        // A row's line: the price, the site, when its search first saw it.
        let items = try sample(NotCheckedPage.self, "not-checked").items
        let chair = try #require(items.first { $0.id == 24 })
        let bare = try #require(items.first { $0.id == 22 })
        #expect(chair.line(now: Clock.now, calendar: Clock.berlin, language: language)
                == (german ? "420\u{a0}€ · Kleinanzeigen · gestern 11:12" : "€420 · Kleinanzeigen · yesterday 11:12"))
        #expect(bare.line(now: Clock.now, calendar: Clock.berlin, language: language)
                == (german ? "eBay · gestern 06:40" : "eBay · yesterday 06:40"))
        #expect(bare.spoken(now: Clock.now, calendar: Clock.berlin, language: language)
                == (german ? "Ohne Titel, eBay, gestern 06:40" : "Untitled, eBay, yesterday 06:40"))
        // No "KI" / "AI" in any of them.
        let words = Wish.allCases.flatMap { [$0.title(language: language), $0.placeholder(language: language),
                                              $0.caption(language: language)] }
            + [Wish.heading(language: language), NotCheckedWords.title(language: language),
               NotCheckedWords.line(language: language), NotCheckedWords.untitled(language: language)]
        #expect(words.allSatisfy { $0.range(of: #"\b(KI|AI)\b"#, options: .regularExpression) == nil })
    }
}
