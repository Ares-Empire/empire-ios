import Foundation
import Testing
@testable import Arestemis

/// The store's actions against a fake server: what shows at once, what the server sends, rollbacks, and the login rules
/// (401 logs out everywhere, 403 closes this app, answers after a logout are dropped).
@MainActor
struct StoreTests {
    /// The sample match 41 in another state, as the server would return it.
    private func matchJSON(state: MatchState) throws -> Data {
        var match = try sample(Match.self, "match")
        match.state = state
        return try JSONEncoder().encode(match)
    }

    @Test func overviewLoadsAndRemembersTheLatest() async throws {
        let (store, transport, _) = try await makeStore()
        await store.reloadOverview()
        #expect(store.overview?.hunt?.active == true && store.overviewError == nil && !store.isLoadingOverview)
        #expect(store.latest.map(\.id) == [41, 40, 38])
        #expect(store.match(40)?.state == .saved)
        #expect(transport.requests("GET /overview").count == 1)
    }

    @Test func loadingDeduplicates() async throws {
        let (store, transport, _) = try await makeStore()
        let gate = RequestGate()
        transport.gates["GET /overview"] = gate
        let load = Task { await store.reloadOverview() }
        await gate.waitUntilPaused()
        await store.reloadOverview()
        #expect(store.isLoadingOverview && transport.requests.count == 1)
        gate.resume()
        await load.value
        #expect(store.overview != nil)
    }

    // MARK: optimistic state changes

    @Test func savingShowsAtOnceThenTakesTheServersMatch() async throws {
        let (store, transport, _) = try await makeStore()
        await store.reloadOverview()
        transport.answer("POST /matches/41/state", json: try matchJSON(state: .saved))
        let gate = RequestGate()
        transport.gates["POST /matches/41/state"] = gate
        let save = Task { await store.setState(.saved, for: 41) }
        await gate.waitUntilPaused()
        #expect(store.match(41)?.state == .saved && store.changingState == [41])
        #expect(store.matches(.new).isEmpty && store.matches(.saved).map(\.id) == [41, 40])
        await store.setState(.dismissed, for: 41)                  // one change per match at a time
        #expect(transport.requests("POST /matches/41/state").count == 1)
        gate.resume()
        await save.value
        #expect(store.match(41)?.state == .saved && store.changingState.isEmpty && store.notice == nil)
        #expect(try body(transport.requests("POST /matches/41/state").first)?["state"] as? String == "saved")
        #expect(transport.requests("GET /overview").count == 2)     // the counts are the server's
    }

    @Test func aRefusedChangeRollsBackWithANotice() async throws {
        let (store, transport, session) = try await makeStore()
        await store.reloadOverview()
        transport.answer("POST /matches/41/state", 500, json: Data(#"{"error":"Made-up failure"}"#.utf8))
        await store.setState(.dismissed, for: 41)
        #expect(store.match(41)?.state == .new)
        #expect(store.latest.map(\.id) == [41, 40, 38])
        #expect(store.notice?.text == "Could not dismiss the listing. Made-up failure")
        #expect(session.isSignedIn)
        store.dismissNotice()
        #expect(store.notice == nil)
    }

    @Test func dismissedMatchesLeaveEveryList() async throws {
        let (store, transport, _) = try await makeStore()
        await store.reloadOverview()
        var dismissed = try sample(MatchPage.self, "matches").items[2]
        dismissed.state = .dismissed
        try transport.answer("POST /matches/38/state", encoding: dismissed)
        await store.setState(.dismissed, for: 38)
        #expect(store.matches(.all).map(\.id) == [41, 40])
        #expect(store.latest.map(\.id) == [41, 40])
        #expect(store.matches(.applied).isEmpty)
    }

    // MARK: login rules

    @Test func unauthorizedLogsOutAndForgets() async throws {
        let storage = MemoryTokens()
        let (store, transport, session) = try await makeStore(session: await signedInSession(storage: storage))
        await store.reloadOverview()
        transport.answer("GET /matches", 401, json: Data())
        await store.loadMatches(.new)
        #expect(!session.isSignedIn && storage.token == nil)
        #expect(store.overview == nil && store.matchesByID.isEmpty && store.list(.new).error == nil)
    }

    @Test func forbiddenClosesOnlyThisApp() async throws {
        let storage = MemoryTokens()
        let (store, transport, session) = try await makeStore(session: await signedInSession(storage: storage))
        await store.reloadOverview()
        transport.answer("GET /settings", 403, json: Data(#"{"error":"No arestemis service"}"#.utf8))
        await store.loadSettings()
        #expect(session.isDenied && session.access == .denied("No arestemis service"))
        #expect(storage.token != nil)                              // the other apps keep the login
        #expect(store.overview == nil && store.settings == nil)
    }

    @Test func answersAfterALogoutAreDropped() async throws {
        let (store, transport, session) = try await makeStore()
        let gate = RequestGate()
        transport.gates["GET /overview"] = gate
        let load = Task { await store.reloadOverview() }
        await gate.waitUntilPaused()
        session.logOut()
        gate.resume()
        await load.value
        #expect(store.overview == nil && store.overviewError == nil)
    }

    @Test func aFailedFirstLoadShowsItsError() async throws {
        let transport = FakeTransport()
        transport.answer("GET /overview", 500, json: Data(#"{"error":"Made-up outage"}"#.utf8))
        let (store, _, _) = try await makeStore(transport: transport)
        await store.reloadOverview()
        #expect(store.overview == nil && store.overviewError == "Made-up outage")
    }

    // MARK: hunt

    @Test func startingShowsAtOnceAndRollsBack() async throws {
        let (store, transport, _) = try await makeStore()
        await store.reloadOverview()
        transport.answer("POST /hunts/1/active", 503, json: Data())
        let gate = RequestGate()
        transport.gates["POST /hunts/1/active"] = gate
        let pause = Task { await store.setHuntActive(false) }
        await gate.waitUntilPaused()
        #expect(store.hunt?.active == false && store.isTogglingHunt)
        gate.resume()
        await pause.value
        #expect(store.hunt?.active == true && !store.isTogglingHunt)
        #expect(store.notice?.text == "Could not pause the hunt. Login service unavailable, try again")
        #expect(try body(transport.requests("POST /hunts/1/active").first)?["active"] as? Bool == false)
    }

    @Test func savingASearchCreatesOrReplaces() async throws {
        let (store, transport, _) = try await makeStore()
        let overview = try sample(Overview.self, "overview")
        var withoutHunt = overview
        withoutHunt.hunt = nil
        withoutHunt.latest = []
        try transport.answer("GET /overview", encoding: withoutHunt)
        await store.reloadOverview()
        let hunt = try #require(overview.hunt)
        try transport.answer("POST /hunts", encoding: hunt)
        #expect(await store.saveSearch(hunt.search))
        #expect(transport.requests("POST /hunts").count == 1 && transport.requests("PUT /hunts/1").isEmpty)

        try transport.answer("GET /overview", sample: "overview")
        await store.reloadOverview()
        try transport.answer("PUT /hunts/1", encoding: hunt)
        #expect(await store.saveSearch(hunt.search))
        let sent = try #require(try body(transport.requests("PUT /hunts/1").first)?["search"] as? [String: Any])
        #expect(sent["rent_warm_max"] as? Double == 1000 && sent["people"] as? Int == 1)

        transport.answer("PUT /hunts/1", 400, json: Data(#"{"error":"At least one place","field":"places"}"#.utf8))
        #expect(await store.saveSearch(hunt.search) == false)
        #expect(store.searchError == "At least one place")
    }

    @Test func deletingTheSearchForgetsItsMatches() async throws {
        let (store, transport, _) = try await makeStore()
        await store.reloadOverview()
        try transport.answer("GET /matches", sample: "matches")
        await store.loadMatches(.all)
        transport.answer("DELETE /hunts/1", 204, json: Data())
        var afterDelete = try sample(Overview.self, "overview")
        afterDelete.hunt = nil
        afterDelete.latest = []
        try transport.answer("GET /overview", encoding: afterDelete)
        #expect(await store.deleteSearch())
        #expect(store.hunt == nil)
        #expect(store.matchesByID.isEmpty && store.list(.all).loaded == false)
        #expect(transport.requests("DELETE /hunts/1").count == 1)
    }

    @Test func describeIt() async throws {
        let (store, transport, _) = try await makeStore()
        transport.answer("POST /search/parse", json: Data(#"{"search":{"rooms_min":2},"unclear":["Which city?"]}"#.utf8))
        let parsed = await store.parse("  2 rooms  ")
        #expect(parsed?.search.roomsMin == 2 && parsed?.unclear == ["Which city?"])
        #expect(try body(transport.requests.last)?["text"] as? String == "2 rooms")
        #expect(await store.parse("   ") == nil && transport.requests("POST /search/parse").count == 1)
    }

    // MARK: lists

    @Test func aPageIsTheTruthForItsFilter() async throws {
        let (store, transport, _) = try await makeStore()
        try transport.answer("GET /matches", sample: "matches")
        await store.loadMatches(.all)
        #expect(store.matches(.all).map(\.id) == [41, 40, 38] && store.list(.all).loaded)
        // 41 was saved elsewhere: the "new" page no longer lists it.
        try transport.answer("GET /matches", encoding: MatchPage(items: [], more: false))
        await store.loadMatches(.new)
        #expect(store.matches(.new).isEmpty && store.match(41) == nil)
        #expect(store.matches(.all).map(\.id) == [40, 38])
    }

    @Test func olderPagesUseTheLowestID() async throws {
        let (store, transport, _) = try await makeStore()
        let page = try sample(MatchPage.self, "matches")
        try transport.answer("GET /matches", encoding: MatchPage(items: Array(page.items.prefix(2)), more: true))
        await store.loadMatches(.all)
        try transport.answer("GET /matches", encoding: MatchPage(items: [page.items[2]], more: false))
        await store.loadMatches(.all, more: true)
        let query = URLComponents(url: try #require(transport.requests.last?.url), resolvingAgainstBaseURL: false)?.queryItems
        #expect(query?.contains(.init(name: "before", value: "40")) == true)
        #expect(store.list(.all).ids == [41, 40, 38] && !store.list(.all).more)
    }

    @Test func aLinkedMatchIsFetchedOnce() async throws {
        let (store, transport, _) = try await makeStore()
        try transport.answer("GET /matches/41", sample: "match")
        #expect(await store.loadMatch(41)?.id == 41)
        #expect(await store.loadMatch(41)?.id == 41)
        #expect(transport.requests("GET /matches/41").count == 1)
        transport.answer("GET /matches/99", 404, json: Data(#"{"error":"Not yours"}"#.utf8))
        #expect(await store.loadMatch(99) == nil && store.matchErrors[99] == "Not yours")
    }

    @Test func seenKeepsTheStateAndHidesTheDot() async throws {
        let (store, _, _) = try await makeStore()
        await store.reloadOverview()
        let match = try #require(store.match(41))
        #expect(store.showsNewDot(match))
        store.markSeen(41)
        #expect(!store.showsNewDot(match) && store.match(41)?.state == .new)
    }

    // MARK: applications

    @Test func aWrittenApplicationIsReused() async throws {
        let (store, transport, _) = try await makeStore()
        await store.reloadOverview()
        try transport.answer("GET /settings", sample: "settings")
        await store.loadSettings()                                  // mode "ai", like match 40's text
        await store.loadApplication(for: 40)
        #expect(store.application(40).application?.mode == .ai)
        #expect(transport.requests("POST /matches/40/application").isEmpty)
    }

    @Test func applicationsAreWrittenAndRewritten() async throws {
        let (store, transport, _) = try await makeStore()
        await store.reloadOverview()
        transport.answer("POST /matches/41/application",
                         json: Data(#"{"text":"Hallo zusammen","mode":"ai","created":"2026-10-24T10:00:00Z"}"#.utf8))
        await store.loadApplication(for: 41)
        #expect(store.application(41).application?.text == "Hallo zusammen" && !store.application(41).isLoading)
        #expect(try body(transport.requests.last)?.isEmpty == true)
        #expect(store.match(41)?.application?.text == "Hallo zusammen")
        await store.loadApplication(for: 41, regenerate: true)
        #expect(try body(transport.requests.last)?["regenerate"] as? Bool == true)
    }

    @Test func aTextFromTheOtherModeIsReplaced() async throws {
        let (store, transport, _) = try await makeStore()
        await store.reloadOverview()
        var settings = try sample(Settings.self, "settings")
        settings.applicationMode = .own
        try transport.answer("GET /settings", encoding: settings)
        await store.loadSettings()
        transport.answer("POST /matches/40/application",
                         json: Data(#"{"text":"Mein Text","mode":"own","created":"2026-10-24T10:00:00Z"}"#.utf8))
        await store.loadApplication(for: 40)
        #expect(try body(transport.requests.last)?["regenerate"] as? Bool == true)
        #expect(store.application(40).application?.mode == .own)
    }

    @Test func aFailedApplicationSaysWhy() async throws {
        let (store, transport, _) = try await makeStore()
        await store.reloadOverview()
        transport.answer("POST /matches/41/application", 502, json: Data(#"{"error":"The AI did not answer"}"#.utf8))
        await store.loadApplication(for: 41)
        #expect(store.application(41).error == "The AI did not answer" && store.application(41).application == nil)
    }

    // MARK: settings

    @Test func settingsSaveAtOnceAndRollBack() async throws {
        let (store, transport, _) = try await makeStore()
        let original = try sample(Settings.self, "settings")
        try transport.answer("GET /settings", encoding: original)
        await store.loadSettings()
        var changed = original
        changed.notify.timeSensitive = false
        try transport.answer("PUT /settings", encoding: changed)
        await store.saveSettings(changed)
        #expect(store.settings == changed && transport.requests("PUT /settings").count == 1)
        await store.saveSettings(changed)                           // nothing changed: nothing sent
        #expect(transport.requests("PUT /settings").count == 1)

        var again = changed
        again.aboutMe = "Made-up facts"
        transport.answer("PUT /settings", 500, json: Data(#"{"error":"Made-up failure"}"#.utf8))
        await store.saveSettings(again)
        #expect(store.settings == changed && store.notice?.text == "Settings not saved. Made-up failure")
    }

    /// The notes go with the settings (brief 62's `application_notes`), the other texts as they were.
    @Test func notesAreSaved() async throws {
        let (store, transport, _) = try await makeStore()
        let original = try sample(Settings.self, "settings")
        try transport.answer("GET /settings", encoding: original)
        await store.loadSettings()
        var changed = original
        changed.applicationNotes = "Made-up notes"
        try transport.answer("PUT /settings", encoding: changed)
        await store.saveSettings(changed)
        let sent = try #require(try body(transport.requests("PUT /settings").last))
        #expect(sent["application_notes"] as? String == "Made-up notes" && sent["own_text"] as? String == original.ownText)
        #expect(store.settings?.applicationNotes == "Made-up notes")
    }

    // MARK: places

    @Test func placesAreAskedOnceTypingPauses() async throws {
        let (store, transport, _) = try await makeStore()
        try transport.answer("GET /places", sample: "places")
        store.places.update("g")
        #expect(!store.places.isSearching && store.places.results.isEmpty)
        store.places.update("ga")
        store.places.update("gar")
        store.places.update("garch")
        #expect(store.places.isSearching)
        await store.places.settle()
        #expect(transport.requests("GET /places").count == 1)
        let query = URLComponents(url: try #require(transport.requests.last?.url), resolvingAgainstBaseURL: false)?.queryItems
        #expect(query == [.init(name: "q", value: "garch")])
        #expect(store.places.results.count == 2 && !store.places.isSearching)
        store.places.update("x")
        #expect(store.places.results.isEmpty)
    }

    @Test func aFailedPlaceSearchSaysWhy() async throws {
        let (store, transport, session) = try await makeStore()
        transport.answer("GET /places", 503, json: Data())
        store.places.update("mün")
        await store.places.settle()
        #expect(store.places.error == "Login service unavailable, try again" && session.isSignedIn)
        transport.answer("GET /places", 401, json: Data())
        store.places.update("münc")
        await store.places.settle()
        #expect(!session.isSignedIn && store.places.query.isEmpty)
    }

    // MARK: foreground

    @Test func theForegroundRefreshesWhatIsOld() async throws {
        let (store, transport, _) = try await makeStore()
        await store.reloadOverview()
        let loaded = try #require(store.lastOverviewLoad)
        await store.refreshOnForeground(now: loaded.addingTimeInterval(20))
        #expect(transport.requests("GET /overview").count == 1)
        await store.refreshOnForeground(now: loaded.addingTimeInterval(31))
        #expect(transport.requests("GET /overview").count == 2)
    }
}
