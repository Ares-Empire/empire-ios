import Foundation
import Testing
@testable import Arestemis

/// Brief 133: the Listings tab as "New | Searches" and the search over found listings. New's groups and their order,
/// the rows of Searches, a search's own lists and filters, where links and the hunt's page lead, the remembered part,
/// the search's request (the pause in typing, the search it is limited to, the length) and its states.
@MainActor
struct ListingsTests {
    private func sampleStore() async throws -> ArestemisStore {
        let session = EmpireSession(app: .arestemis, storage: MemoryTokens(), restoreOnLaunch: false)
        let store = ArestemisStore(session: session, backend: try SampleBackend(), sample: true, placeDelay: .zero,
                                   findDelay: .zero)
        await store.reloadOverview()
        return store
    }

    private func defaults() -> UserDefaults {
        let name = "ListingsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    /// The server's own answer to `GET /matches?q=kallax&limit=2` (brief 132's sample).
    private func serverSearch() throws -> Data {
        final class Token {}
        let url = try #require(Bundle(for: Token.self).url(forResource: "server-matches-search", withExtension: "json"))
        return try Data(contentsOf: url)
    }

    private func query(_ request: URLRequest?) -> [String: String] {
        let items = request?.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?.queryItems ?? []
        return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { $1 })
    }

    private func match(_ id: Int, hunt: Int, found: String, state: MatchState = .new) throws -> Match {
        let listing = try sample(Match.self, "match").listing
        return Match(id: id, huntID: hunt, state: state, found: found, listing: listing, reason: "", warnings: [])
    }

    // MARK: New

    @Test func newIsGroupedBySearchTheNewestFindingFirst() async throws {
        let store = try await sampleStore()
        await store.loadMatches(.new)
        let groups = NewListings.groups(store.matches(.new))
        // Found 09:59 (flat), 09:58 (the Aeron auction), 09:55 (jeans), 09:41 (bookcase), 09:00 (KALLAX), 3 days ago
        // (the Mensa, read at the watch's start).
        #expect(groups.map(\.huntID) == [1, 2, 5, 4, 6, 9, 8])
        #expect(groups[1].matches.map(\.id) == [32, 31, 30, 29, 28])        // 31–28 found together: the higher id first
        #expect(groups.flatMap(\.matches).allSatisfy { $0.state == .new })
        // A group goes with its last new listing.
        await store.setState(.saved, for: 41)
        #expect(NewListings.groups(store.matches(.new)).map(\.huntID) == [2, 5, 4, 6, 9, 8])
        for id in [32, 31, 30, 29, 28] { await store.setState(.dismissed, for: id) }
        #expect(NewListings.groups(store.matches(.new)).map(\.huntID) == [5, 4, 6, 9, 8])
    }

    @Test func newestByWhenFoundThenById() throws {
        let matches = [try match(1, hunt: 7, found: "2026-10-24T08:00:00Z"),
                       try match(2, hunt: 8, found: "2026-10-24T09:00:00Z"),
                       try match(3, hunt: 7, found: "2026-10-24T09:00:00Z"),
                       try match(4, hunt: 9, found: "not a time"),
                       try match(5, hunt: 8, found: "2026-10-24T10:00:00Z", state: .saved)]
        let groups = NewListings.groups(matches)
        #expect(groups.map(\.huntID) == [7, 8, 9])
        #expect(groups.map { $0.matches.map(\.id) } == [[3, 1], [2], [4]])
        #expect(NewListings.groups([]).isEmpty)
        // One search: no headings.
        #expect(!NewListings.showsHeadings(searches: 1) && NewListings.showsHeadings(searches: 2))
    }

    // MARK: Searches

    @Test(arguments: [AppLanguage.english, .german])
    func searchRows(_ language: AppLanguage) throws {
        let de = language == .german
        let cards = try sample(Overview.self, "overview").hunts
        let rows = cards.map { SearchRow($0, language: language) }
        #expect(rows.map(\.huntID) == [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11])
        #expect(rows.map(\.newCount) == [1, 4, 0, 1, 1, 1, 0, 1, 1, 0, 0])
        #expect(rows.map(\.text.kind) == [.flat, .item, .flat, .item, .item, .watch, .watch, .watch, .price, .price, .price])
        #expect(rows[0].line == (de ? "1 gespeichert · 1 beworben" : "1 saved · 1 applied"))
        // Counts of zero are left out: nothing kept, no line; paused alone says so.
        #expect(rows[1].line == nil)
        #expect(rows[2].line == (de ? "Pausiert" : "Paused"))
        #expect(rows[5].line == nil)
        #expect(rows[1].spoken(language: language) == (de ? "Herman Miller Aeron, 4 neue" : "Herman Miller Aeron, 4 new"))
        // A kind this build does not know: its name only.
        let newer = HuntCard(hunt: Hunt(id: 9, kind: .unknown("car"), name: "Camper van", active: true,
                                        search: .unsupported, created: "2026-10-24T08:12:00Z",
                                        updated: "2026-10-24T08:12:00Z", activated: nil),
                             counts: .init(new: 3, today: 0, saved: 1, applied: 0), sources: [], slowed: false)
        let row = SearchRow(newer, language: language)
        #expect(row.text.title == "Camper van" && row.text.kind == nil && row.newCount == nil && row.line == nil)
        #expect(row.spoken(language: language) == "Camper van")
    }

    @Test func searchesFollowTheCounts() async throws {
        let store = try await sampleStore()
        await store.loadMatches(.new)
        await store.setState(.saved, for: 31)
        let row = try #require(store.card(2).map { SearchRow($0, language: .english) })
        #expect(row.newCount == 4 && row.line == "1 saved")
    }

    // MARK: one search's listings

    @Test func aSearchsPageHasItsOwnListsAndFilters() async throws {
        let (store, transport, _) = try await makeStore()
        await store.reloadOverview()
        try transport.answer("GET /matches", sample: "item-matches")
        try transport.answer("GET /rejected", encoding: RejectedPage(items: []))
        await store.loadMatches(.saved, hunt: 2)
        await store.loadRejected(hunt: 2)
        #expect(query(transport.requests("GET /matches").last) == ["hunt": "2", "state": "saved", "limit": "50"])
        #expect(query(transport.requests("GET /rejected").last) == ["hunt": "2", "limit": "50"])
        #expect(store.list(.saved, hunt: 2).loaded && !store.list(.saved).loaded && !store.list(.saved, hunt: 1).loaded)
        #expect(store.rejected(hunt: 2).loaded && !store.rejected().loaded)
        // New of every search, without a hunt.
        try transport.answer("GET /matches", sample: "matches")
        await store.loadMatches(.new)
        #expect(query(transport.requests("GET /matches").last) == ["state": "new", "limit": "50"])
        // Only its own matches show on its page.
        #expect(store.matches(.all, hunt: 1).allSatisfy { $0.huntID == 1 } && !store.matches(.all, hunt: 1).isEmpty)
    }

    @Test(arguments: [AppLanguage.english, .german])
    func theFiltersOfASearch(_ language: AppLanguage) {
        let de = language == .german
        #expect(MatchFilter.choices(for: .flat) == [.new, .saved, .applied, .all])
        #expect(MatchFilter.choices(for: .item).map { $0.title(asked: true, language: language) }
                == (de ? ["Neu", "Gespeichert", "Angefragt", "Alle"] : ["New", "Saved", "Asked", "All"]))
        #expect(MatchFilter.choices(for: .watch) == [.new, .saved, .all])           // a watch's change is never applied for
        #expect(MatchFilter.choices(for: nil) == MatchFilter.allCases)
        #expect(MatchFilter.opening(.init(new: 2, today: 0, saved: 0, applied: 0)) == .new)
        #expect(MatchFilter.opening(.init(new: 0, today: 0, saved: 3, applied: 0)) == .all)
        #expect(MatchFilter.opening(nil) == .all)
        #expect(ListingsPart.allCases.map { $0.title(language: language) } == (de ? ["Neu", "Suchen"] : ["New", "Searches"]))
    }

    // MARK: navigation

    @Test func aNotificationOpensItsMatchOverNew() {
        let navigation = AppNavigation(defaults: defaults())
        navigation.choose(.searches)
        navigation.listingsPath = [.hunt(2)]
        navigation.open(ArestemisLink(match: 41))
        #expect(navigation.tab == .listings && navigation.part == .new && navigation.listingsPath == [.match(41)])
        // The user's own choice is kept for the next launch.
        navigation.reset()
        #expect(navigation.part == .searches)
    }

    @Test func aHuntsPageOpensItsListings() {
        let navigation = AppNavigation(defaults: defaults())
        navigation.huntPath = [.hunt(2)]
        navigation.showSearch(2, filter: .applied)
        #expect(navigation.tab == .listings && navigation.part == .searches)
        #expect(navigation.listingsPath == [.hunt(2)] && navigation.filter == .applied)
        #expect(navigation.huntPath == [.hunt(2)])                // the Hunts tab keeps its page
        // From Searches (or New's heading), pushed on what is there.
        navigation.listingsPath = []
        navigation.openSearch(4, filter: .new)
        navigation.find(hunt: 4)
        navigation.showMatch(33)
        #expect(navigation.listingsPath == [.hunt(4), .find(hunt: 4), .match(33)] && navigation.filter == .new)
        // The Hunts tab's "All listings": the tab at its start, the part as it was.
        navigation.part = .new
        navigation.showListings()
        #expect(navigation.listingsPath.isEmpty && navigation.part == .new && navigation.tab == .listings)
    }

    @Test func aDeletedSearchLeavesTheListingsTab() {
        let navigation = AppNavigation(defaults: defaults())
        navigation.listingsPath = [.find(hunt: nil), .match(41), .hunt(2), .find(hunt: 2), .match(31)]
        navigation.leaveDeleted(3)
        #expect(navigation.listingsPath.count == 5)
        navigation.leaveDeleted(2)
        #expect(navigation.listingsPath == [.find(hunt: nil), .match(41)] && navigation.huntPath.isEmpty)
        #expect(ListingsRoute.find(hunt: nil).hunt == nil && ListingsRoute.match(2).hunt == nil)
    }

    @Test func theChosenPartIsRemembered() {
        let defaults = defaults()
        let first = AppNavigation(defaults: defaults)
        #expect(first.part == .new)
        first.choose(.searches)
        #expect(AppNavigation(defaults: defaults).part == .searches)
        // A part shown by a link or a hunt's page is not a choice.
        first.open(ArestemisLink(match: 41))
        first.showSearch(2, filter: .new)
        first.part = .new
        #expect(AppNavigation(defaults: defaults).part == .searches)
        first.choose(.new)
        #expect(AppNavigation(defaults: defaults).part == .new)
        defaults.set("something else", forKey: ListingsPartMemory.key)
        #expect(AppNavigation(defaults: defaults).part == .new)
    }

    @Test func launchArgumentsForTheListingsTab() throws {
        let cards = try sample(Overview.self, "overview").hunts
        func apply(_ arguments: [String]) -> AppNavigation {
            let navigation = AppNavigation(defaults: defaults())
            LaunchOptions(arguments: ["-sampleData"] + arguments).apply(to: navigation, hunts: cards, firstMatch: nil)
            return navigation
        }
        let searches = apply(["-listings", "searches"])
        #expect(searches.tab == .listings && searches.part == .searches && searches.listingsPath.isEmpty)
        let page = apply(["-openSearch", "2"])
        #expect(page.tab == .listings && page.part == .searches && page.listingsPath == [.hunt(2)] && page.filter == .new)
        #expect(apply(["-openSearch", "3"]).filter == .all)                  // nothing new: All
        #expect(apply(["-openSearch", "1", "-filter", "saved"]).filter == .saved)
        let find = apply(["-search", "Aeron"])
        #expect(find.tab == .listings && find.listingsPath == [.find(hunt: nil)] && find.findQuery == "Aeron")
        #expect(apply(["-openSearch", "2", "-search", "size"]).listingsPath == [.hunt(2), .find(hunt: 2)])
        #expect(apply(["-openSheet", "rejected"]).sheet == .rejected(nil))
        #expect(apply(["-openSearch", "1", "-openSheet", "rejected"]).sheet == .rejected(1))
        #expect(RootSheet.rejected(1).id != RootSheet.rejected(nil).id)
    }

    // MARK: the search over listings

    @Test func theSearchAsksOnceTypingPauses() async throws {
        let (store, transport, _) = try await makeStore()
        transport.answer("GET /matches", json: try serverSearch())
        let search = ListingSearch(hunt: nil, delay: .milliseconds(80)) { try await store.findMatches($0, hunt: nil) }
        search.update("k")
        #expect(search.phase == .typing)
        search.update("ka")
        search.update("kal")
        search.update("kallax")
        #expect(search.phase == .searching)
        await search.settle()
        #expect(transport.requests("GET /matches").count == 1)
        #expect(query(transport.requests("GET /matches").first) == ["q": "kallax", "limit": "50"])
        // The server's order is kept: the older title match before the newer description match.
        #expect(search.phase == .found && search.results.map(\.id) == [301, 302] && search.more)
        #expect(store.match(301)?.listing.title == "IKEA KALLAX Regal 2x3 weiß")     // remembered for the swipes
        // A space at the end, or around, asks nothing new.
        search.update(" kallax  ")
        await search.settle()
        #expect(transport.requests("GET /matches").count == 1)
    }

    @Test func fewerThanTwoLettersAskNothing() async throws {
        let (store, transport, _) = try await makeStore()
        let search = store.listingSearch(hunt: nil)
        for text in ["", " ", "k", "  k  "] {
            search.update(text)
            await search.settle()
            #expect(search.phase == .typing)
        }
        #expect(transport.requests("GET /matches").isEmpty)
        #expect(ListingSearch.words(" ab ") == "ab" && ListingSearch.words("a") == nil)
        // At most 100 characters go to the server.
        let long = String(repeating: "a", count: 150)
        #expect(ListingSearch.words(long)?.count == 100)
    }

    @Test func aSearchsOwnSearchSendsItsHunt() async throws {
        let (store, transport, _) = try await makeStore()
        await store.reloadOverview()
        transport.answer("GET /matches", json: try serverSearch())
        let search = ListingSearch(hunt: 2, delay: .zero) { try await store.findMatches($0, hunt: 2) }
        search.update("c++ Regal")
        await search.settle()
        let request = try #require(transport.requests("GET /matches").last)
        #expect(query(request) == ["q": "c++ Regal", "hunt": "2", "limit": "50"])
        #expect(request.url?.query(percentEncoded: true)?.contains("q=c%2B%2B%20Regal") == true)   // a plus stays a plus
        #expect(store.listingSearch(hunt: 2).hunt == 2 && store.listingSearch(hunt: nil).hunt == nil)
    }

    @Test(arguments: [AppLanguage.english, .german])
    func theSearchsStates(_ language: AppLanguage) async throws {
        let de = language == .german
        let (store, transport, _) = try await makeStore()
        let search = ListingSearch(hunt: nil, delay: .zero) { try await store.findMatches($0, hunt: nil) }
        // Asking: nothing to show yet.
        transport.answer("GET /matches", json: try serverSearch())
        let gate = RequestGate()
        transport.gates["GET /matches"] = gate
        search.update("kallax")
        await gate.waitUntilPaused()
        #expect(search.phase == .searching && search.isSearching)
        gate.resume()
        await search.settle()
        #expect(search.phase == .found && !search.isSearching)
        // Nothing found.
        try transport.answer("GET /matches", encoding: MatchPage(items: [], more: false))
        search.update("schwabing")
        await search.settle()
        #expect(search.phase == .nothingFound("schwabing") && search.results.isEmpty)
        #expect(ListingSearchWords.nothingFound("schwabing", language: language)
                == (de ? "Nichts gefunden für „schwabing“." : "Nothing found for “schwabing”."))
        // A failure, calm, and Try again asks at once.
        transport.answer("GET /matches", 500, json: Data(#"{"error":"Made-up search failure"}"#.utf8))
        search.update("aeron")
        await search.settle()
        #expect(search.phase == .failed("Made-up search failure") && search.results.isEmpty)
        transport.answer("GET /matches", json: try serverSearch())
        search.retry()
        await search.settle()
        #expect(search.phase == .found && transport.requests("GET /matches").count == 4)
        // Back under two letters: the hint again.
        search.update("a")
        #expect(search.phase == .typing && search.results.isEmpty)
    }

    @Test func theSampleSearchesToo() async throws {
        let store = try await sampleStore()
        let all = try await store.findMatches("aeron", hunt: nil)
        #expect(all.items.first.map { $0.huntID } == 2 && all.items.allSatisfy { $0.huntID == 2 })
        let garching = try await store.findMatches("garching", hunt: nil)
        #expect(Set(garching.items.map(\.huntID)).count > 1)
        #expect(try await store.findMatches("garching", hunt: 1).items.allSatisfy { $0.huntID == 1 })
        #expect(try await store.findMatches("nothing-like-it", hunt: nil).items.isEmpty)
    }

    @Test(arguments: [AppLanguage.english, .german])
    func theSearchsWords(_ language: AppLanguage) throws {
        let de = language == .german
        #expect(ListingSearchWords.prompt(language: language) == (de ? "Nach Name oder Ort suchen" : "Search by name or place"))
        #expect(ListingSearchWords.hint(language: language)
                == (de ? "Gib mindestens zwei Buchstaben ein. Die besten Treffer kommen zuerst."
                       : "Type at least two letters. The best matches come first."))
        #expect(ListingSearchWords.title(hunt: nil, language: language) == (de ? "Alle Suchen" : "All searches"))
        let card = try sample(Overview.self, "overview").hunts[1]
        #expect(ListingSearchWords.title(hunt: HuntText(card.hunt, language: language), language: language)
                == "Herman Miller Aeron")
        #expect(ListingSearchWords.more(language: language)
                == (de ? "Es passen noch mehr Angebote. Ein weiteres Wort grenzt ein."
                       : "More listings match. Another word narrows it down."))
    }

    /// The server's sample of a search decodes, in its order (brief 132's contract).
    @Test func theServersSearchAnswer() throws {
        let page = try JSONDecoder().decode(MatchPage.self, from: serverSearch())
        #expect(page.items.map(\.id) == [301, 302] && page.more)
        #expect(page.items.map(\.state) == [.new, .saved] && page.items.allSatisfy { $0.listing.item != nil })
    }
}
