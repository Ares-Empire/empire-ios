import Foundation
import Testing
import UserNotifications
@testable import Arestemis

/// Brief 180 (Patrik's test of builds 18–19, 2026-11-05; the server's brief 179): an Überall monitor saves at once and
/// the server finds its product (the card and page while it is finding it or found none, the chips on the page), the
/// monitor's link and push, "Favorites" with a star on a listing's page, and a listing read as it is opened.
@MainActor
struct SaveFavoritesReadTests {
    private func sampleStore(_ options: SampleBackend.Options = .init()) async throws -> ArestemisStore {
        let session = EmpireSession(app: .arestemis, storage: MemoryTokens(), restoreOnLaunch: false)
        let store = ArestemisStore(session: session, backend: try SampleBackend(options: options), sample: true,
                                   placeDelay: .zero)
        await store.reloadOverview()
        return store
    }

    private func priceState(_ json: String) throws -> PriceState {
        try JSONDecoder().decode(PriceState.self, from: Data(json.utf8))
    }

    private func matchJSON(seen: Any?) throws -> Data {
        var object = try #require(try JSONSerialization.jsonObject(with: ArestemisSamples.data("match")) as? [String: Any])
        object["seen"] = seen
        return try JSONSerialization.data(withJSONObject: object)
    }

    // MARK: 1. Überall saves at once

    @Test func savingSendsTheProductOnlyWhenThePreviewFoundItForTheWords() async throws {
        let (store, transport, _) = try await makeStore()
        await store.reloadOverview()
        var draft = PriceSearchDraft()
        draft.product = "AirPods Max 2"
        draft.details = "Mitternacht oder Navy"
        // Nothing found yet (the preview still reads, failed or was refused): it saves at once, without an identity.
        #expect(draft.isValid && draft.hint() == nil)
        let unconfirmed = try #require(draft.search())
        #expect(unconfirmed.identity == nil)
        let created = Hunt(id: 50, kind: .price, name: nil, active: false, search: .price(unconfirmed),
                           created: "2026-11-05T10:00:00Z", updated: "2026-11-05T10:00:00Z", activated: nil)
        try transport.answer("POST /hunts", 201, encoding: created)
        #expect(await store.saveHunt(id: nil, kind: .price, name: draft.sentName, search: .price(unconfirmed)) != nil)
        var sent = try #require(try body(transport.requests("POST /hunts").last)?["search"] as? [String: Any])
        #expect(sent["identity"] is NSNull && sent["product"] as? String == "AirPods Max 2"
                && sent["details"] as? String == "Mitternacht oder Navy" && sent["mode"] as? String == "everywhere")
        // An answer for other words changes nothing.
        let identity = ProductIdentity(name: "Apple AirPods Max (2. Generation)", eans: ["0195949000000"])
        draft.confirm(identity, for: ProductWords(product: "AirPods Max"))
        #expect(draft.search()?.identity == nil)
        // Found for the words as they are: sent as the confirmed product.
        draft.confirm(identity, for: draft.words)
        let confirmed = try #require(draft.search())
        #expect(confirmed.identity == identity)
        _ = await store.saveHunt(id: nil, kind: .price, name: draft.sentName, search: .price(confirmed))
        sent = try #require(try body(transport.requests("POST /hunts").last)?["search"] as? [String: Any])
        #expect((sent["identity"] as? [String: Any])?["name"] as? String == identity.name)
        // Words changed after it was found: none again.
        draft.details = "Silber"
        #expect(draft.search()?.identity == nil && draft.isValid)
    }

    @Test(arguments: [AppLanguage.english, .german])
    func theProductStateIsReadLeniently(_ language: AppLanguage) throws {
        let german = language == .german
        // Present.
        let finding = try priceState(#"{"host": "", "read": "waiting", "product": "AirPods Max 2", "product_state": "finding"}"#)
        #expect(finding.productState == .finding && finding.refusal == nil)
        let notFound = try priceState("""
            {"host": "", "read": "waiting", "product_state": "not_found",
             "refusal": {"error": "Kein Produkt mit diesem Namen gefunden.", "field": "product",
                         "suggestions": ["AirPods Max (USB-C)"], "item_search": {"query": "AirPods Max 2", "extra": "Navy"}}}
            """)
        #expect(notFound.productState == .notFound)
        #expect(notFound.refusal == ProductRefusal(error: "Kein Produkt mit diesem Namen gefunden.",
                                                   suggestions: ["AirPods Max (USB-C)"],
                                                   itemSearch: ProductItemSearch(query: "AirPods Max 2", extra: "Navy")))
        #expect(notFound.refusal?.choices?.names == ["AirPods Max (USB-C)"])
        // Missing (older monitors, page monitors) and unknown: found, as before.
        #expect(try priceState(#"{"host": "", "read": "ok"}"#).productState == .found)
        #expect(try priceState(#"{"host": "", "read": "ok", "product_state": "pondering"}"#).productState == .found)
        #expect(try priceState(#"{"host": "", "read": "ok", "product_state": 3}"#).productState == .found)
        // A refusal that cannot be read is none; its optional choices never hide the sentence.
        #expect(try priceState(#"{"host": "", "product_state": "not_found", "refusal": "oops"}"#).refusal == nil)
        let bare = try priceState(#"{"host": "", "product_state": "not_found", "refusal": {"error": "Nope.", "suggestions": 4}}"#)
        #expect(bare.refusal == ProductRefusal(error: "Nope.") && bare.refusal?.choices == nil)
        // It goes back as the server sent it (the sample server and the tour build their cards as JSON).
        #expect(try JSONDecoder().decode(PriceState.self, from: JSONEncoder().encode(notFound)) == notFound)
        // The words: the server's own sentence; a missing one in the server's words.
        #expect(PriceCardText.productLine(notFound, language: language) == "Kein Produkt mit diesem Namen gefunden.")
        var silent = notFound
        silent.refusal = nil
        #expect(PriceCardText.productLine(silent, language: language)
                == (german ? "Kein Produkt mit diesem Namen gefunden." : "Found no product with that name."))
        #expect(PriceCardText.productLine(finding, language: language)
                == (german ? "Sucht das Produkt …" : "Looking for the product…"))
        #expect(PriceCardText.productLine(try priceState(#"{"host": "", "read": "ok"}"#), language: language) == nil)
    }

    @Test(arguments: [AppLanguage.english, .german])
    func theCardWhileFindingAndWhenNoneFits(_ language: AppLanguage) throws {
        let german = language == .german
        let finding = try ArestemisSamples.productStateMonitor(id: 13, state: .finding, created: "2026-11-05T10:00:00Z")
        // The words as the name, one quiet line in place of the price, no shop count yet.
        let text = HuntText(finding, language: language)
        let search = try #require(finding.hunt.search.price)
        #expect(text.title == "Nimbus Earbuds 3")
        #expect(text.details == EverywhereWords.mode(.everywhere, language: language) + " · "
                + PriceWords.mode(search, language: language))
        #expect(text.details?.hasPrefix(german ? "Überall · Alarm unter 220" : "Everywhere · Alarm under €220") == true)
        for compact in [true, false] {
            let card = PriceCardText(finding.price, compact: compact, everywhere: true, language: language)
            #expect(card.price == nil && card.shop == nil && card.availability == nil && card.shippingNote == nil)
            #expect(card.note == (german ? "Sucht das Produkt …" : "Looking for the product…"))
        }
        // None fits: the server's sentence in that place, its names and the Dinge route on the page.
        let notFound = try ArestemisSamples.productStateMonitor(id: 13, state: .notFound, created: "2026-11-05T10:00:00Z")
        let card = PriceCardText(notFound.price, compact: false, everywhere: true, language: language)
        #expect(card.price == nil && card.note == notFound.price?.refusal?.error)
        let choices = try #require(notFound.price?.refusal?.choices)
        #expect(choices.names == ["Orbital Headphones 2", "Orbital Headphones 2 Pro"])
        #expect(choices.itemSearch == ProductItemSearch(query: "Orbitel Headphones 2", extra: "blue"))
        // A found monitor is as before: its price, its shop.
        let found = try sample(Overview.self, "overview").hunts.first { $0.id == 12 }
        let price = PriceCardText(found?.price, compact: true, everywhere: true, language: language)
        #expect(price.price != nil && price.note == nil)
        #expect(HuntText(try #require(found), language: language).details?.contains(german ? "Shops" : "shops") == true)
    }

    @Test func aChipOnThePageOpensTheFormWithItsWordsAndSavingLooksAgain() async throws {
        let store = try await sampleStore(SampleBackend.Options(productState: .notFound))
        let id = try #require(store.hunts.last?.id)
        let card = try #require(store.card(id))
        #expect(card.price?.productState == .notFound && card.hunt.search.price?.identity == nil)
        let choices = try #require(card.price?.refusal?.choices)
        // The page's chip: the monitor's own form over its page, with the name in Product.
        let navigation = AppNavigation()
        navigation.huntPath = [.hunt(id)]
        navigation.monitorProduct(id, product: choices.names[0])
        #expect(navigation.tab == .hunt
                && navigation.huntPath == [.hunt(id), .monitorProduct(hunt: id, product: "Orbital Headphones 2")])
        // The form takes it as a chip in the form does: the details stay, no product found yet.
        var draft = try #require(store.savedDraft(PriceSearchDraft.self, huntID: id))
        draft.selectProduct(choices.names[0])
        let search = try #require(draft.search())
        #expect(search.product == "Orbital Headphones 2" && search.details == "blue" && search.identity == nil)
        // Saving starts the server's search again.
        _ = await store.saveHunt(id: id, kind: .price, name: draft.sentName, search: .price(search))
        #expect(store.card(id)?.price?.productState == .finding && store.card(id)?.price?.refusal == nil)
        // The Dinge route: a new Dinge search over the page; once made, back leads to the monitor.
        let things = try #require(choices.itemSearch)
        navigation.huntPath = [.hunt(id)]
        navigation.openItemSearch(things)
        #expect(navigation.huntPath == [.hunt(id), .itemSearch(things)])
        navigation.showCreated(99)
        #expect(navigation.huntPath == [.hunt(id), .hunt(99)])
    }

    @Test func theLaunchArguments() {
        let options = LaunchOptions(arguments: ["-sampleData", "-sampleProductState", "not_found", "-sampleRead", "41,35"])
        #expect(options.productState == .notFound && options.read == [41, 35])
        #expect(LaunchOptions(arguments: ["-sampleData", "-sampleProductState", "finding"]).productState == .finding)
        #expect(LaunchOptions(arguments: ["-sampleData"]).productState == nil)
    }

    // MARK: 2. links to a search

    @Test func aLinkToASearch() throws {
        let url = try #require(URL(string: "arestemis://hunt/12"))
        let link = try #require(ArestemisLink(url: url))
        #expect(link == ArestemisLink(hunt: 12) && link.hunt == 12 && link.match == nil && link.then == .show)
        #expect(ArestemisLink(url: try #require(URL(string: "arestemis:///hunt/7"))) == ArestemisLink(hunt: 7))
        // From anywhere: the search's page on the Hunts tab, nothing over it.
        let navigation = AppNavigation()
        navigation.tab = .listings
        navigation.listingsPath = [.match(41)]
        navigation.huntPath = [.newSearch, .form(.price, hunt: nil)]
        navigation.sheet = .settings
        navigation.showsPlaceSearch = true
        navigation.follow(link)
        #expect(navigation.huntPath == [.newSearch, .form(.price, hunt: nil)])         // queued until the tabs show
        navigation.openPendingLink()
        #expect(navigation.tab == .hunt && navigation.huntPath == [.hunt(12)] && navigation.sheet == nil)
        #expect(!navigation.showsPlaceSearch && navigation.pendingListing == nil && navigation.pendingLink == nil)
        #expect(navigation.listingsPath == [.match(41)])                               // the other tab as it was
    }

    @Test func theNoProductPushOpensTheMonitorsPage() {
        let url = URL(string: "arestemis://hunt/12")
        // Its tap and its "Open in shop" both show the page (there is no shop to open yet); dismissing does nothing.
        #expect(MatchNotification.link(url: url, action: UNNotificationDefaultActionIdentifier) == ArestemisLink(hunt: 12))
        #expect(MatchNotification.link(url: url, action: MatchNotification.openListingAction) == ArestemisLink(hunt: 12))
        #expect(MatchNotification.link(url: url, action: MatchNotification.applicationAction) == ArestemisLink(hunt: 12))
        #expect(MatchNotification.link(url: url, action: UNNotificationDismissActionIdentifier) == nil)
        let navigation = AppNavigation()
        navigation.open(MatchNotification.link(url: url, action: MatchNotification.openListingAction)!)
        #expect(navigation.huntPath == [.hunt(12)] && navigation.pendingListing == nil)
        // A match's push is as before.
        #expect(MatchNotification.link(url: URL(string: "arestemis://match/39"), action: MatchNotification.openListingAction)
                == ArestemisLink(match: 39, then: .openListing))
    }

    @Test func anUnknownSearchShowsThePagesOwnLine() async throws {
        let store = try await sampleStore()
        let navigation = AppNavigation()
        navigation.open(ArestemisLink(hunt: 999))
        // The page for an id the app does not know says "This search is gone." (`HuntPage`); nothing else happens.
        #expect(navigation.huntPath == [.hunt(999)] && store.card(999) == nil)
    }

    // MARK: 3. Favorites

    @Test(arguments: [AppLanguage.english, .german])
    func theWordsOfFavorites(_ language: AppLanguage) throws {
        let german = language == .german
        #expect(MatchFilter.saved.title(language: language) == (german ? "Favoriten" : "Favorites"))
        #expect(MatchState.saved.word(language: language) == (german ? "Favorit" : "Favorite"))
        #expect(language.string("Favorite") == (german ? "Favorit" : "Favorite"))
        #expect(HuntPageActions.figureLabels(.price, language: language).last == (german ? "Favoriten" : "Favorites"))
        #expect(language.string("No favorites yet. Swipe right on a listing to keep it here.")
                == (german ? "Noch keine Favoriten. Wisch ein Angebot nach rechts, um es hier zu behalten."
                           : "No favorites yet. Swipe right on a listing to keep it here."))
        // Searches' quiet line counts them: one, several.
        var card = try #require(try sample(Overview.self, "overview").hunts.first { $0.id == 1 })
        card.counts = .init(new: 0, today: 0, saved: 2, applied: 1)
        #expect(SearchRow(card, language: language).line == (german ? "2 Favoriten · 1 beworben" : "2 favorites · 1 applied"))
        card.counts.saved = 1
        #expect(SearchRow(card, language: language).spoken(language: language).hasSuffix(german ? "1 Favorit · 1 beworben"
                                                                                              : "1 favorite · 1 applied"))
        // The star says what a tap does.
        #expect(FavoriteStar.off.action(language: language) == (german ? "Favorit" : "Favorite"))
        #expect(FavoriteStar.on.action(language: language) == (german ? "Kein Favorit mehr" : "Remove from favorites"))
        // The notice when it fails, and the tour's line.
        #expect(language.string("Could not make the listing a favorite.")
                == (german ? "Das Angebot konnte nicht als Favorit markiert werden." : "Could not make the listing a favorite."))
        #expect(TourStep.newListings.text(language).contains(german ? "Favoriten" : "favorite"))
    }

    @Test func theStarOnAListingsPage() {
        #expect(FavoriteStar(.new) == .off && FavoriteStar(.saved) == .on)
        // Applied and dismissed listings are dealt with: no star (the state menu still offers everything).
        #expect(FavoriteStar(.applied) == nil && FavoriteStar(.dismissed) == nil)
        #expect(FavoriteStar.off.symbol == "star" && FavoriteStar.on.symbol == "star.fill")
        #expect(FavoriteStar.off.next == .saved && FavoriteStar.on.next == .new)
    }

    @Test func theStarTogglesBetweenNewAndFavoriteAndAReadListingStaysRead() async throws {
        let store = try await sampleStore()
        await store.markRead(41)
        await store.reloadOverview()
        let unread = try #require(store.card(1)?.counts.new)
        // A tap: a favorite at once, then new again (read stays read, no dot comes back).
        #expect(store.match(41).flatMap { FavoriteStar($0.state) } == .off)
        var star = FavoriteStar.off
        await store.setState(star.next, for: 41)
        #expect(store.match(41)?.state == .saved)
        #expect(store.match(41).flatMap { FavoriteStar($0.state) } == .on)
        star = .on
        await store.setState(star.next, for: 41)
        let match = try #require(store.match(41))
        #expect(match.state == .new && match.seen && !store.showsNewDot(match))
        #expect(store.card(1)?.counts.new == unread)
        // Applied: no star.
        await store.setState(.applied, for: 41)
        #expect(store.match(41)?.state == .applied && store.match(41).flatMap { FavoriteStar($0.state) } == nil)
    }

    // MARK: 4. read when opened

    @Test func openingAListingReadsItOnceAndDropsTheCountsAtOnce() async throws {
        let (store, transport, _) = try await makeStore()
        await store.reloadOverview()
        transport.answer("POST /matches/41/seen", json: try matchJSON(seen: true))
        let unread = try #require(store.match(41))
        #expect(!unread.seen && store.showsNewDot(unread))
        #expect(store.overview?.counts.new == 7 && store.card(1)?.counts.new == 1)
        await store.markRead(41)
        let read = try #require(store.match(41))
        #expect(read.seen && read.state == .new && !store.showsNewDot(read))
        #expect(store.overview?.counts.new == 6 && store.card(1)?.counts.new == 0)
        #expect(transport.requests("POST /matches/41/seen").count == 1)
        // Again: nothing more is sent, nothing more is counted.
        await store.markRead(41)
        #expect(transport.requests("POST /matches/41/seen").count == 1 && store.overview?.counts.new == 6)
        // A listing that is no longer new is read without touching the counts; one already read is not sent.
        transport.answer("POST /matches/40/seen", json: try matchJSON(seen: true))
        await store.markRead(40)
        #expect(store.match(40)?.seen == true && store.overview?.counts.new == 6
                && transport.requests("POST /matches/40/seen").count == 1)
        // Brief 182: it leaves New (which asks for unread listings only); the other filters keep it.
        #expect(!store.matches(.new).map(\.id).contains(41) && !MatchFilter.new.includes(read))
        #expect(MatchFilter.all.includes(read) && MatchFilter.all.seen == nil)
        #expect(NewListings.groups(store.matches(.new)).first { $0.huntID == 1 } == nil)
    }

    @Test func aFailedReadStaysReadAndIsSentAgainAtTheNextOpening() async throws {
        let (store, transport, _) = try await makeStore()
        await store.reloadOverview()
        transport.answer("POST /matches/41/seen", 503, json: Data(#"{"error":"Try again in a minute."}"#.utf8))
        await store.markRead(41)
        #expect(store.match(41)?.seen == true && store.notice == nil && store.card(1)?.counts.new == 0)
        // A list from the server that does not know it yet keeps it read here.
        try transport.answer("GET /matches", sample: "matches")
        await store.loadMatches(.new)
        let match = try #require(store.match(41))
        #expect(match.seen && !store.showsNewDot(match))
        // The next opening sends it again; once it went through, never again.
        transport.answer("POST /matches/41/seen", json: try matchJSON(seen: true))
        await store.markRead(41)
        await store.markRead(41)
        #expect(transport.requests("POST /matches/41/seen").count == 2)
    }

    @Test func anOverviewAskedForBeforeTheReadDoesNotCountItAgain() async throws {
        let (store, transport, _) = try await makeStore()
        await store.reloadOverview()
        transport.answer("POST /matches/41/seen", json: try matchJSON(seen: true))
        let gate = RequestGate()
        transport.gates["GET /overview"] = gate
        let stale = Task { await store.reloadOverview(quiet: true) }
        await gate.waitUntilPaused()
        await store.markRead(41)
        gate.resume()
        await stale.value
        // The answer still counted it as unread (the fake server's counts never change): taken out again.
        #expect(store.overview?.counts.new == 6 && store.card(1)?.counts.new == 0)
        // An overview asked for after the read is the server's word.
        await store.reloadOverview(quiet: true)
        #expect(store.overview?.counts.new == 7 && store.card(1)?.counts.new == 1)
    }

    @Test func theSampleServerCountsUnreadListings() async throws {
        let plain = try await sampleStore()
        let total = try #require(plain.overview?.counts.new)
        let things = try #require(plain.card(2)?.counts.new)
        let store = try await sampleStore(SampleBackend.Options(read: [31]))
        #expect(store.card(2)?.counts.new == things - 1 && store.overview?.counts.new == total - 1)
        await store.loadMatches(.new)
        // Read, so not in New (brief 182; New asks for unread ones), but read when it is loaded.
        #expect(!store.matches(.new).contains { $0.id == 31 })
        #expect(await store.loadMatch(31)?.seen == true)
        await store.markRead(30)
        await store.reloadOverview()
        #expect(store.card(2)?.counts.new == things - 2 && store.overview?.counts.new == total - 2)
    }

    @Test func whetherAListingWasReadIsReadLeniently() throws {
        #expect(try JSONDecoder().decode(Match.self, from: matchJSON(seen: true)).seen)
        #expect(try !JSONDecoder().decode(Match.self, from: matchJSON(seen: false)).seen)
        // Missing (a server from before it), null or not a boolean: unread.
        #expect(try !JSONDecoder().decode(Match.self, from: matchJSON(seen: nil)).seen)
        #expect(try !JSONDecoder().decode(Match.self, from: matchJSON(seen: NSNull())).seen)
        #expect(try !JSONDecoder().decode(Match.self, from: matchJSON(seen: "yes")).seen)
    }

    @Test func theRoutes() async throws {
        let transport = FakeTransport(fallback: (200, try ArestemisSamples.data("match")))
        let api = ArestemisAPI(transport: transport, token: { "fictional-token" })
        _ = try await api.markSeen(match: 41)
        #expect(FakeTransport.key(try #require(transport.requests.last)) == "POST /matches/41/seen")
        transport.fallback = (200, Data(#"{"items": [], "more": false}"#.utf8))
        _ = try await api.matches(hunt: 2, state: [.new], seen: false, limit: 50, before: nil)
        var query = URLComponents(url: try #require(transport.requests.last?.url), resolvingAgainstBaseURL: false)?.queryItems
        #expect(query?.contains(URLQueryItem(name: "seen", value: "false")) == true)
        _ = try await api.matches(hunt: 2, state: [.new], limit: 50, before: nil)
        query = URLComponents(url: try #require(transport.requests.last?.url), resolvingAgainstBaseURL: false)?.queryItems
        #expect(query?.contains { $0.name == "seen" } == false)
    }
}
