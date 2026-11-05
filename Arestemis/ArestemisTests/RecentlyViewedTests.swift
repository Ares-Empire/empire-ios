import Foundation
import Testing
@testable import Arestemis

/// Brief 182 (Patrik, 2026-11-05: an opened listing "should leave neu … Like a past / history sort of thing but limited
/// time"; the server's brief 181): New asks for unread listings only, an opened listing leaves it when its page closes
/// and goes on top of Recently viewed (`GET /matches?recent=true`), which holds the listings opened in the last 7 days
/// that are still new, the latest opened first; a favorite, an application or a dismissal takes one out. The rows at a
/// list's end (`QuietLink`), the route, the words and the sample server.
@MainActor
struct RecentlyViewedTests {
    private func sampleStore(_ options: SampleBackend.Options = .init(), now: Date = .now,
                             readsListings: Bool = true) async throws -> ArestemisStore {
        let session = EmpireSession(app: .arestemis, storage: MemoryTokens(), restoreOnLaunch: false)
        let store = ArestemisStore(session: session, backend: try SampleBackend(options: options, now: now), sample: true,
                                   readsListings: readsListings, placeDelay: .zero, findDelay: .zero)
        await store.reloadOverview()
        return store
    }

    /// The server's own answer to `GET /matches?recent=true` (brief 181's sample): a flat (41), a thing (103) and a
    /// watch's change (400), the latest opened first.
    private func serverRecent() throws -> Data {
        final class Token {}
        let url = try #require(Bundle(for: Token.self).url(forResource: "server-matches-recent", withExtension: "json"))
        return try Data(contentsOf: url)
    }

    private let emptyPage = Data(#"{"items": [], "more": false}"#.utf8)

    private func query(_ request: URLRequest?) -> [String: String] {
        let items = request?.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?.queryItems ?? []
        return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { $1 })
    }

    /// The sample match with `seen_at` set to a value, or left out (`missing`).
    private func matchJSON(seenAt: Any?, missing: Bool = false) throws -> Data {
        var object = try #require(try JSONSerialization.jsonObject(with: ArestemisSamples.data("match")) as? [String: Any])
        object["seen"] = true
        if missing { object.removeValue(forKey: "seen_at") } else { object["seen_at"] = seenAt }
        return try JSONSerialization.data(withJSONObject: object)
    }

    // MARK: New asks for unread listings

    @Test func newAsksForUnreadListingsOnly() async throws {
        #expect(MatchFilter.new.seen == false)
        #expect(MatchFilter.allCases.filter { $0 != .new }.allSatisfy { $0.seen == nil })
        let (store, transport, _) = try await makeStore()
        await store.reloadOverview()
        try transport.answer("GET /matches", sample: "matches")
        // Angebote → Neu, and a search's own New.
        await store.loadMatches(.new)
        var sent = query(transport.requests("GET /matches").last)
        #expect(sent["state"] == "new" && sent["seen"] == "false" && sent["hunt"] == nil)
        await store.loadMatches(.new, hunt: 1)
        sent = query(transport.requests("GET /matches").last)
        #expect(sent["state"] == "new" && sent["seen"] == "false" && sent["hunt"] == "1")
        // The other filters ask for read and unread alike.
        await store.loadMatches(.all, hunt: 1)
        #expect(query(transport.requests("GET /matches").last)["seen"] == nil)
        // A read listing is not New's, whatever its state says.
        var read = try #require(store.match(41))
        read.seen = true
        #expect(!MatchFilter.new.includes(read) && MatchFilter.all.includes(read))
    }

    // MARK: seen_at and the server's answer

    @Test func whenAListingWasFirstOpenedIsReadLeniently() throws {
        #expect(try JSONDecoder().decode(Match.self, from: matchJSON(seenAt: "2026-11-05T14:20:00Z")).seenAt
                == "2026-11-05T14:20:00Z")
        // Missing (a server from before it), null, or not a string: none.
        #expect(try JSONDecoder().decode(Match.self, from: matchJSON(seenAt: nil, missing: true)).seenAt == nil)
        #expect(try JSONDecoder().decode(Match.self, from: matchJSON(seenAt: NSNull())).seenAt == nil)
        #expect(try JSONDecoder().decode(Match.self, from: matchJSON(seenAt: 42)).seenAt == nil)
        // It goes back as the server sent it (the sample server and the tour build their matches as JSON).
        let match = try JSONDecoder().decode(Match.self, from: matchJSON(seenAt: "2026-11-05T14:20:00Z"))
        #expect(try JSONDecoder().decode(Match.self, from: JSONEncoder().encode(match)) == match)
    }

    // MARK: opening a listing

    @Test func anOpenedListingLeavesNewAsItsPageClosesAndTopsRecentlyViewed() async throws {
        let store = try await sampleStore(.init(read: [35, 39]))
        await store.loadMatches(.new)
        await store.loadRecent()
        #expect(store.recentMatches().map(\.id) == [35, 39])
        #expect(store.matches(.new).contains { $0.id == 31 } && !store.matches(.new).contains { $0.id == 35 })
        // The page opens: read at once (no dot, out of the counts), but New stays as it was under the page.
        let things = try #require(store.card(2)?.counts.new)
        await store.pageOpened(31)
        let read = try #require(store.match(31))
        #expect(read.seen && read.seenAt != nil && !store.showsNewDot(read) && store.card(2)?.counts.new == things - 1)
        #expect(store.matches(.new).contains { $0.id == 31 } && store.matches(.new, hunt: 2).contains { $0.id == 31 })
        #expect(store.recentMatches().map(\.id) == [35, 39])
        // It closes: gone from New, on top of Recently viewed.
        store.pageClosed(31)
        #expect(!store.matches(.new).contains { $0.id == 31 } && !store.matches(.new, hunt: 2).contains { $0.id == 31 })
        #expect(store.recentMatches().map(\.id) == [31, 35, 39])
        // The server agrees at the next load (the sample imitates it: the first opening's time, the latest first).
        await store.loadRecent()
        #expect(store.recentMatches().map(\.id) == [31, 35, 39])
        // Opened again from Recently viewed: it stays where it is (its first opening counts).
        await store.pageOpened(39)
        store.pageClosed(39)
        #expect(store.recentMatches().map(\.id) == [31, 35, 39])
        // A group of New goes with its last unread listing.
        for id in store.matches(.new, hunt: 2).map(\.id) {
            await store.pageOpened(id)
            store.pageClosed(id)
        }
        #expect(!NewListings.groups(store.matches(.new)).contains { $0.huntID == 2 })
    }

    @Test func aSearchsOwnRecentlyViewedTakesItsListingsOnly() async throws {
        let store = try await sampleStore(.init(read: [35, 31]))
        await store.loadMatches(.new)
        await store.loadRecent(hunt: 2)
        #expect(store.recentMatches(hunt: 2).map(\.id) == [31])
        await store.markRead(30)
        #expect(store.recentMatches(hunt: 2).map(\.id) == [30, 31])
        // A listing of another search goes on top of every search's list only.
        await store.loadRecent()
        await store.markRead(41)
        #expect(store.recentMatches().map(\.id) == [41, 30, 35, 31] && store.recentMatches(hunt: 2).map(\.id) == [30, 31])
    }

    @Test func aFavoriteAnApplicationOrADismissalTakesItOut() async throws {
        let store = try await sampleStore(.init(read: [41, 31, 30]))
        await store.loadRecent()
        #expect(store.recentMatches().map(\.id) == [41, 31, 30])
        await store.setState(.saved, for: 41)
        #expect(store.recentMatches().map(\.id) == [31, 30])
        // Set back to new (the star on its page): back in its place.
        await store.setState(.new, for: 41)
        #expect(store.recentMatches().map(\.id) == [41, 31, 30])
        await store.setState(.applied, for: 41)
        await store.setState(.dismissed, for: 31)
        #expect(store.recentMatches().map(\.id) == [30])
        // Undo of the dismissal brings it back.
        await store.undo?.undo?()
        #expect(store.recentMatches().map(\.id) == [31, 30])
        // The next load agrees.
        await store.loadRecent()
        #expect(store.recentMatches().map(\.id) == [31, 30])
    }

    // MARK: the server's list and reads on their way

    @Test func aListAskedForBeforeAReadReachedTheServerKeepsItOnTop() async throws {
        let (store, transport, _) = try await makeStore()
        await store.reloadOverview()
        try transport.answer("GET /matches", sample: "item-matches")
        await store.loadMatches(.new)
        transport.answer("GET /matches", json: try serverRecent())
        await store.loadRecent()
        #expect(store.recentMatches().map(\.id) == [41, 103, 400])
        // Opened while Recently viewed is asked for: the answer does not know it yet.
        transport.answer("POST /matches/31/seen", json: try matchJSON(seenAt: "2026-11-05T15:00:00Z"))
        transport.answer("GET /matches", json: emptyPage)
        let gate = RequestGate()
        transport.gates["GET /matches"] = gate
        let stale = Task { await store.loadRecent() }
        await gate.waitUntilPaused()
        await store.markRead(31)
        gate.resume()
        await stale.value
        #expect(store.recentMatches().map(\.id) == [31])
        // A list asked for after the read went through is the server's word.
        await store.loadRecent()
        #expect(store.recentMatches().isEmpty && store.recentList().loaded)
        // A read that failed stays read here, and on top, until the server knows it.
        transport.answer("POST /matches/30/seen", 503, json: Data(#"{"error":"Try again in a minute."}"#.utf8))
        await store.markRead(30)
        await store.loadRecent()
        #expect(store.recentMatches().map(\.id) == [30] && store.notice == nil)
        // A stale answer keeps the time it was first opened.
        try transport.answer("GET /matches", sample: "item-matches")
        let opened = try #require(store.match(30)?.seenAt)
        await store.loadMatches(.all)
        #expect(store.match(30)?.seen == true && store.match(30)?.seenAt == opened)
    }

    @Test func theRoute() async throws {
        let transport = FakeTransport(fallback: (200, emptyPage))
        let api = ArestemisAPI(transport: transport, token: { "fictional-token" })
        _ = try await api.recent(hunt: nil, limit: 200)
        var request = try #require(transport.requests.last)
        #expect(FakeTransport.key(request) == "GET /matches")
        #expect(query(request) == ["recent": "true", "limit": "200"])
        // A search's own row asks with its hunt; never with state, seen, q or before (the server refuses them).
        _ = try await api.recent(hunt: 2, limit: 200)
        request = try #require(transport.requests.last)
        #expect(query(request) == ["recent": "true", "hunt": "2", "limit": "200"])
        // The store asks for the server's most (one page, no `before`).
        let (store, fake, _) = try await makeStore()
        await store.reloadOverview()
        fake.answer("GET /matches", json: try serverRecent())
        await store.loadRecent(hunt: 1)
        #expect(query(fake.requests("GET /matches").last) == ["recent": "true", "hunt": "1", "limit": "200"])
        #expect(ArestemisStore.recentLimit == 200)
    }

    @Test func aFailureIsTheListsAndTryAgainLoadsIt() async throws {
        let (store, transport, _) = try await makeStore()
        await store.reloadOverview()
        transport.answer("GET /matches", 503, json: Data(#"{"error":"Try again in a minute."}"#.utf8))
        await store.loadRecent()
        #expect(store.recentList().error == "Try again in a minute." && !store.recentList().loaded)
        #expect(QuietLink(.recentlyViewed, count: store.recentMatches().count) == nil)
        transport.answer("GET /matches", json: try serverRecent())
        await store.loadRecent()
        #expect(store.recentList().error == nil && store.recentMatches().count == 3)
    }

    // MARK: the row, the page and the route

    @Test func theRowShowsOnlyWithListingsAndItsCount() async throws {
        #expect(QuietLink(.recentlyViewed, count: 0) == nil && QuietLink(.filteredOut, count: 0) == nil)
        let recent = try #require(QuietLink(.recentlyViewed, count: 3))
        #expect(recent.countText == "3" && recent.symbol == "clock.arrow.circlepath")
        #expect(try #require(QuietLink(.recentlyViewed, count: 200, more: true)).countText == "200+")
        #expect(try #require(QuietLink(.filteredOut, count: 2)).symbol == "line.3.horizontal.decrease")
        // In the sample: none until a listing was opened, then one, counting what Recently viewed holds now.
        let store = try await sampleStore()
        await store.loadMatches(.new)
        await store.loadRecent()
        #expect(store.recentList().loaded && QuietLink(.recentlyViewed, count: store.recentMatches().count) == nil)
        await store.markRead(41)
        await store.markRead(31)
        #expect(QuietLink(.recentlyViewed, count: store.recentMatches().count)?.countText == "2")
        await store.setState(.saved, for: 41)
        #expect(QuietLink(.recentlyViewed, count: store.recentMatches().count)?.countText == "1")
        #expect(QuietLink(.recentlyViewed, count: store.recentMatches(hunt: 1).count) == nil)
    }

    @Test func thePageIsPushedOnTheListingsTabForEverySearchOrOne() {
        let navigation = AppNavigation(defaults: UserDefaults(suiteName: "RecentlyViewedTests-\(UUID().uuidString)")!)
        navigation.tab = .listings
        navigation.showRecent(hunt: nil)
        #expect(navigation.listingsPath == [.recent(hunt: nil)])
        navigation.listingsPath = [.hunt(2)]
        navigation.showRecent(hunt: 2)
        #expect(navigation.listingsPath == [.hunt(2), .recent(hunt: 2)] && ListingsRoute.recent(hunt: 2).hunt == 2)
        // A deleted search takes its own pages with it.
        navigation.leaveDeleted(2)
        #expect(navigation.listingsPath.isEmpty)
    }

    @Test func theLaunchArguments() {
        var options = LaunchOptions(arguments: ["-sampleData", "-sampleRead", "35,41,31", "-openRecent"])
        #expect(options.read == [35, 41, 31] && options.openRecent && options.tab == .listings)
        var navigation = AppNavigation(defaults: UserDefaults(suiteName: "RecentlyViewedTests-\(UUID().uuidString)")!)
        navigation.part = .searches
        options.apply(to: navigation, firstMatch: nil)
        #expect(navigation.tab == .listings && navigation.part == .new && navigation.listingsPath == [.recent(hunt: nil)])
        // With a search: over its own listings.
        options = LaunchOptions(arguments: ["-sampleData", "-openSearch", "2", "-openRecent"])
        navigation = AppNavigation(defaults: UserDefaults(suiteName: "RecentlyViewedTests-\(UUID().uuidString)")!)
        options.apply(to: navigation, firstMatch: nil)
        #expect(navigation.listingsPath == [.hunt(2), .recent(hunt: 2)])
        #expect(!LaunchOptions(arguments: ["-sampleData"]).openRecent)
    }

    // MARK: the sample server and the tour

    @Test func theSampleImitatesTheServer() async throws {
        // The given order is the order of opening, the latest first; only new listings.
        let store = try await sampleStore(.init(read: [36, 41, 40, 31]))
        await store.loadRecent()
        #expect(store.recentMatches().map(\.id) == [36, 41, 31])
        // Read more than 7 days ago: not there.
        let old = try await sampleStore(.init(read: [41]), now: .now.addingTimeInterval(-8 * 24 * 3600))
        await old.loadRecent()
        #expect(old.recentList().loaded && old.recentMatches().isEmpty)
        // The first opening's time is kept.
        let backend = try SampleBackend(options: .init(read: [41]))
        let first = try await backend.match(id: 41).seenAt
        #expect(first != nil)
        #expect(try await backend.markSeen(match: 41).seenAt == first)
        let opened = try await backend.markSeen(match: 31).seenAt
        #expect(opened != nil && (opened.flatMap(Timestamp.parse) ?? .distantPast) > (first.flatMap(Timestamp.parse) ?? .now))
        #expect(try await backend.recent(hunt: nil, limit: 1) == MatchPage(items: [try await backend.match(id: 31)], more: true))
    }

    @Test func theToursListingsStayUnread() async throws {
        let store = try await sampleStore(readsListings: false)
        await store.loadMatches(.new)
        await store.pageOpened(41)
        store.pageClosed(41)
        #expect(store.match(41)?.seen == false && store.matches(.new).contains { $0.id == 41 })
        // The tour's world is made so.
        let world = try await TourWorld.make()
        defer { world.forget() }
        #expect(!world.store.readsListings)
    }

    // MARK: words

    @Test(arguments: [AppLanguage.english, .german])
    func theWords(_ language: AppLanguage) throws {
        let german = language == .german
        #expect(RecentlyViewedWords.title(language: language) == (german ? "Zuletzt angesehen" : "Recently viewed"))
        #expect(RecentlyViewedWords.line(language: language)
                == (german ? "Angebote, die du in den letzten 7 Tagen geöffnet hast. Um eins zu behalten, markiere es als Favorit."
                           : "Listings you opened in the last 7 days. To keep one, make it a favorite."))
        #expect(RecentlyViewedWords.empty(language: language)
                == (german ? "Gerade keine Angebote hier." : "No listings here right now."))
        let recent = try #require(QuietLink(.recentlyViewed, count: 3))
        #expect(recent.title(language: language) == RecentlyViewedWords.title(language: language))
        #expect(recent.spoken(language: language) == (german ? "Zuletzt angesehen, 3 Angebote" : "Recently viewed, 3 listings"))
        let filtered = try #require(QuietLink(.filteredOut, count: 1))
        #expect(filtered.title(language: language) == (german ? "Aussortiert" : "Filtered out"))
        #expect(filtered.spoken(language: language) == (german ? "Aussortiert, 1 Angebot" : "Filtered out, 1 listing"))
        // No "KI" / "AI" in any of them.
        let words = [RecentlyViewedWords.title(language: language), RecentlyViewedWords.line(language: language),
                     RecentlyViewedWords.empty(language: language), recent.spoken(language: language)]
        #expect(words.allSatisfy { $0.range(of: #"\b(KI|AI)\b"#, options: .regularExpression) == nil })
    }
}
