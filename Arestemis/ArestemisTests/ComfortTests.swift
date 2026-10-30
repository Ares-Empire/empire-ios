import Foundation
import Testing
@testable import Arestemis

@MainActor
struct ComfortTests {
    @Test(arguments: [MatchState.new, .saved, .applied])
    func undoRestoresTheEarlierStateAndOrder(_ earlier: MatchState) async throws {
        let (store, transport, _) = try await makeStore()
        var overview = try sample(Overview.self, "overview")
        overview.latest[0].state = earlier
        try transport.answer("GET /overview", encoding: overview)
        await store.reloadOverview()
        let original = store.matches(.all).map(\.id)
        var changed = overview.latest[0]
        changed.state = .dismissed
        try transport.answer("POST /matches/41/state", encoding: changed)
        overview.latest.removeFirst()
        try transport.answer("GET /overview", encoding: overview)
        await store.setState(.dismissed, for: 41)
        #expect(store.matches(.all).map(\.id) == [40, 38])
        #expect(store.latest.map(\.id) == [40, 38])
        let undo = try #require(store.undo)
        changed.state = earlier
        try transport.answer("POST /matches/41/state", encoding: changed)
        overview.latest.insert(changed, at: 0)
        try transport.answer("GET /overview", encoding: overview)
        await undo.undo()
        #expect(store.match(41)?.state == earlier)
        #expect(store.matches(.all).map(\.id) == original)
        #expect(store.latest.map(\.id) == original)
        #expect(try body(transport.requests("POST /matches/41/state").last)?["state"] as? String == earlier.rawValue)
    }

    @Test func failedDismissHasNoUndo() async throws {
        let (store, transport, _) = try await makeStore()
        await store.reloadOverview()
        transport.answer("POST /matches/41/state", 500, json: Data(#"{"error":"Made-up failure"}"#.utf8))
        await store.setState(.dismissed, for: 41)
        #expect(store.undo == nil && store.match(41)?.state == .new)
    }

    @Test func undoCannotActAfterLogout() async throws {
        let (store, transport, session) = try await makeStore()
        await store.reloadOverview()
        var match = try sample(Match.self, "match")
        match.state = .dismissed
        try transport.answer("POST /matches/41/state", encoding: match)
        await store.setState(.dismissed, for: 41)
        let offer = try #require(store.undo)
        session.logOut()
        #expect(store.undo == nil)
        await offer.undo()
        #expect(transport.requests("POST /matches/41/state").count == 1)
    }

    @Test func loadingMoreDoesNotAskTwiceAndCanRetry() async throws {
        let (store, transport, _) = try await makeStore()
        let page = try sample(MatchPage.self, "matches")
        try transport.answer("GET /matches", encoding: MatchPage(items: Array(page.items.prefix(2)), more: true))
        await store.loadMatches(.all)
        transport.answer("GET /matches", 500, json: Data(#"{"error":"Made-up page failure"}"#.utf8))
        let gate = RequestGate()
        transport.gates["GET /matches"] = gate
        let load = Task { await store.loadMatches(.all, more: true) }
        await gate.waitUntilPaused()
        await store.loadMatches(.all, more: true)
        #expect(transport.requests("GET /matches").count == 2)
        #expect(store.list(.all).isLoading)
        gate.resume()
        await load.value
        #expect(store.list(.all).error == "Made-up page failure")
        #expect(store.list(.all).ids == [41, 40] && !store.list(.all).isLoading)
        try transport.answer("GET /matches", encoding: MatchPage(items: [page.items[2]], more: false))
        await store.loadMatches(.all, more: true)
        #expect(store.list(.all).ids == [41, 40, 38] && store.list(.all).error == nil)
        await store.loadMatches(.all, more: true)
        #expect(transport.requests("GET /matches").count == 3)
    }

    private func defaults() -> UserDefaults {
        UserDefaults(suiteName: "arestemis-comfort-tests-\(UUID().uuidString)")!
    }

    @Test func draftSurvivesRecreatingPersistenceAndKeepsInvalidFields() throws {
        let defaults = defaults()
        defer { KeptSearchDraft(defaults: defaults).clear() }
        let search = try #require(try sample(Overview.self, "overview").hunt?.search)
        var draft = SearchDraft(search)
        draft.warmRent = .init(min: 1500, max: 1000)
        draft.moveInFrom = Clock.now
        draft.extra = "  Fictional balcony preference  "
        let kept = KeptSearchDraft(defaults: defaults)
        kept.keep(draft, baseline: search, account: "account-a")
        let reopened = KeptSearchDraft(defaults: defaults)
        #expect(reopened.restore(for: search, account: "account-a") == draft)
        #expect(!draft.isValid)
    }

    @Test func changedServerSearchDropsTheDraft() throws {
        let defaults = defaults()
        defer { KeptSearchDraft(defaults: defaults).clear() }
        var search = try #require(try sample(Overview.self, "overview").hunt?.search)
        let baseline = search
        var draft = SearchDraft(search)
        draft.extra = "Fictional draft"
        let kept = KeptSearchDraft(defaults: defaults)
        kept.keep(draft, baseline: baseline, account: "account-a")
        search.people = 3
        #expect(kept.restore(for: search, account: "account-a") == SearchDraft(search))
        #expect(kept.restore(for: baseline, account: "account-a") == SearchDraft(baseline))
    }

    @Test func anotherAccountsDraftIsNeverShown() throws {
        let defaults = defaults()
        defer { KeptSearchDraft(defaults: defaults).clear() }
        let search = try #require(try sample(Overview.self, "overview").hunt?.search)
        var draft = SearchDraft(search)
        draft.extra = "Fictional draft"
        let kept = KeptSearchDraft(defaults: defaults)
        kept.keep(draft, baseline: search, account: "account-a")
        #expect(kept.restore(for: search, account: "account-b") == SearchDraft(search))
        #expect(kept.restore(for: search, account: "account-a") == draft)
    }

    @Test(arguments: ["save", "delete", "logout"])
    func draftIsDroppedByAccountActions(_ action: String) async throws {
        let defaults = defaults()
        defer { KeptSearchDraft(defaults: defaults).clear() }
        let (_, transport, session) = try await makeStore()
        let store = ArestemisStore(session: session, backend: ArestemisAPI(transport: transport, token: { session.token }),
                                   defaults: defaults)
        await store.reloadOverview()
        let search = try #require(store.hunt?.search)
        var draft = SearchDraft(search)
        draft.extra = "Fictional draft"
        store.keepSearchDraft(draft, baseline: search)
        #expect(store.searchDraft() == draft)
        switch action {
        case "save":
            let hunt = try #require(store.hunt)
            try transport.answer("PUT /hunts/1", encoding: hunt)
            #expect(await store.saveSearch(search))
        case "delete":
            transport.answer("DELETE /hunts/1", 204, json: Data())
            var empty = try sample(Overview.self, "overview")
            empty.hunt = nil
            empty.latest = []
            try transport.answer("GET /overview", encoding: empty)
            #expect(await store.deleteSearch())
        default: session.logOut()
        }
        #expect(KeptSearchDraft(defaults: defaults).restore(for: search, account: "fictional-account") == SearchDraft(search))
    }

    @Test func unsavedNewSearchIsKeptAndReturningToBaselineDropsIt() {
        let defaults = defaults()
        defer { KeptSearchDraft(defaults: defaults).clear() }
        let kept = KeptSearchDraft(defaults: defaults)
        var draft = SearchDraft()
        draft.extra = "Fictional draft"
        kept.keep(draft, baseline: nil, account: "account-a")
        #expect(kept.restore(for: nil, account: "account-a") == draft)
        kept.keep(SearchDraft(), baseline: nil, account: "account-a")
        #expect(kept.restore(for: nil, account: "account-a") == SearchDraft())
    }
}
