import Foundation
import Testing
@testable import Arestemis

@MainActor
struct PriceAlarmsTests {
    private func query(_ request: URLRequest?) throws -> [String: String] {
        let url = try #require(request?.url)
        return Dictionary(uniqueKeysWithValues:
            (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
    }

    private func alarm(_ id: Int, hunt: Int = 12, state: MatchState = .new) throws -> Match {
        let original = try #require(sample(MatchPage.self, "price-matches").items.first { $0.huntID == 12 })
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        json["id"] = id
        json["hunt_id"] = hunt
        json["state"] = state.rawValue
        return try JSONDecoder().decode(Match.self, from: JSONSerialization.data(withJSONObject: json))
    }

    private func fixture() async throws -> (ArestemisStore, FakeTransport, EmpireSession) {
        let (store, transport, session) = try await makeStore()
        await store.reloadOverview()
        try transport.answer("GET /matches", encoding: MatchPage(items: [try alarm(42)], more: false))
        return (store, transport, session)
    }

    @Test func liveRequestSelectsPriceKindWithDocumentedFiltersAndCursor() async throws {
        let transport = FakeTransport()
        try transport.answer("GET /matches", encoding: MatchPage(items: [try alarm(42)], more: true))
        let api = ArestemisAPI(transport: transport, token: { "fictional-token" })
        let page = try await api.priceAlarms(hunt: 12, state: [.new, .saved], limit: 3, before: 43)
        #expect(page.items.map(\.id) == [42] && page.more)
        #expect(try query(transport.requests.last) == ["hunt": "12", "state": "new,saved", "limit": "3", "before": "43", "kind": "price"])
        #expect(transport.requests.last?.httpMethod == "GET" && transport.requests.last?.httpBody == nil)
        _ = try await api.priceAlarms(hunt: 12, state: nil, limit: 50, before: nil)
        #expect(try query(transport.requests.last) == ["hunt": "12", "limit": "50", "kind": "price"])
        _ = try await api.matches(hunt: 12, state: nil, limit: 3, before: nil)
        #expect(try query(transport.requests.last) == ["hunt": "12", "limit": "3"])
    }

    @Test(arguments: [false, true]) func latestAndFullPageFindAlarmsBehindMultipleInterleavedPages(includeUsed: Bool) async throws {
        var content = try SampleContent.contract()
        let template = try #require(sample(MatchPage.self, "used-matches").items.first)
        var used: [Match] = []
        var alarms: [Match] = []
        // Over two full mixed pages of newer used listings precede an older alarm, followed by interleaved pages.
        for id in (2000..<2130).reversed() {
            var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(template)) as? [String: Any])
            json["id"] = id
            used.append(try JSONDecoder().decode(Match.self, from: JSONSerialization.data(withJSONObject: json)))
        }
        for offset in 0..<105 {
            alarms.append(try alarm(1900 - offset * 2, state: offset.isMultiple(of: 3) ? .saved : .new))
            var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(template)) as? [String: Any])
            json["id"] = 1899 - offset * 2
            used.append(try JSONDecoder().decode(Match.self, from: JSONSerialization.data(withJSONObject: json)))
        }
        content.matches = used + alarms
        content.used[12] = Set(used.map(\.id))
        let index = try #require(content.overview.hunts.firstIndex { $0.id == 12 })
        var search = try #require(content.overview.hunts[index].hunt.search.price)
        search.includeUsed = includeUsed
        content.overview.hunts[index].hunt.search = .price(search)
        let backend = try SampleBackend(content: content)
        let session = await signedInSession()
        let store = ArestemisStore(session: session, backend: backend, sample: true)
        await store.reloadOverview()
        await store.loadLatest(hunt: 12)
        #expect(store.latest(hunt: 12)?.map(\.id) == Array(alarms.prefix(3)).map(\.id))
        // Opening Show all expands the inline first page, then walks only this feed's cursor.
        await store.loadMonitorListings(.alarms, hunt: 12)
        #expect(store.monitorList(.alarms, hunt: 12).ids.count == 50)
        await store.loadMonitorListings(.alarms, hunt: 12, more: true)
        #expect(store.monitorList(.alarms, hunt: 12).ids.count == 100)
        await store.loadMonitorListings(.alarms, hunt: 12, more: true)
        #expect(!store.monitorList(.alarms, hunt: 12).more)
        #expect(store.monitorMatches(.alarms, hunt: 12).map(\.id) == alarms.map(\.id))
        #expect(store.latest(hunt: 12)?.map(\.id) == Array(alarms.prefix(3)).map(\.id))
        await store.loadUsed(hunt: 12)
        await store.loadUsed(hunt: 12, more: true)
        #expect(store.usedMatches(hunt: 12).allSatisfy { $0.isThing && !$0.isPriceChange })
        #expect(store.showsUsed(hunt: 12))
        let mixed = try await backend.matches(hunt: 12, state: nil, limit: 200, before: nil)
        #expect(mixed.items.contains { $0.isPriceChange } && mixed.items.contains { $0.isThing })
        #expect(mixed.items.prefix(3).allSatisfy { $0.isThing })
        await store.loadMonitorListings(.alarms, hunt: 12, filter: .saved)
        #expect(store.monitorMatches(.alarms, hunt: 12, filter: .saved).allSatisfy { $0.state == .saved })
        #expect(store.monitorMatches(.alarms, hunt: 12, filter: .saved).count == 35)
    }

    @Test func allPriceMonitorsUseThreeAlarmsAndOrdinaryHuntsKeepMixedRequests() async throws {
        let (store, transport, _) = try await fixture()
        for id in [9, 10, 11, 12] {
            try transport.answer("GET /matches", encoding: MatchPage(items: [try alarm(40 + id, hunt: id)], more: false))
            await store.loadLatest(hunt: id)
            #expect(try query(transport.requests("GET /matches").last) == ["hunt": String(id), "kind": "price", "limit": "3"])
            #expect(store.latest(hunt: id)?.count == 1)
        }
        for id in [1, 2, 6] {
            guard store.card(id)?.hunt.search.price == nil else { continue }
            await store.loadLatest(hunt: id)
            #expect(try query(transport.requests("GET /matches").last)["kind"] == nil)
        }
    }

    @Test func pendingInlineReadExpandsWhenShowAllOpens() async throws {
        let (store, transport, _) = try await fixture()
        let first = try (1...3).map { try alarm(50 - $0) }
        try transport.answer("GET /matches", encoding: MatchPage(items: first, more: true))
        let gate = RequestGate()
        transport.gates["GET /matches"] = gate
        let inline = Task { await store.loadLatest(hunt: 12) }
        await gate.waitUntilPaused()
        let all = first + [try alarm(40)]
        try transport.answer("GET /matches", encoding: MatchPage(items: all, more: false))
        await store.loadMonitorListings(.alarms, hunt: 12)
        gate.resume()
        await inline.value
        #expect(store.monitorMatches(.alarms, hunt: 12).map(\.id) == all.map(\.id))
        #expect(try transport.requests("GET /matches").map { try query($0)["limit"] } == ["3", "50"])
        #expect(!store.monitorList(.alarms, hunt: 12).isLoading)
    }

    @Test func kindsAndFiltersKeepDistinctCursorsAndRetryDeduplicates() async throws {
        let (store, transport, _) = try await fixture()
        let items = try sample(MatchPage.self, "used-matches").items
        try transport.answer("GET /hunts/12/used", encoding: MatchPage(items: Array(items.prefix(2)), more: true))
        await store.loadUsed(hunt: 12)
        try transport.answer("GET /matches", encoding: MatchPage(items: [try alarm(80), try alarm(70)], more: true))
        await store.loadMonitorListings(.alarms, hunt: 12)
        try transport.answer("GET /matches", encoding: MatchPage(items: [try alarm(60, state: .saved)], more: true))
        await store.loadMonitorListings(.alarms, hunt: 12, filter: .saved)
        #expect(try query(transport.requests.last)["before"] == nil)
        #expect(try query(transport.requests.last)["state"] == "saved")
        transport.answer("GET /matches", 500, json: Data(#"{"error":"Could not load older listings."}"#.utf8))
        await store.loadMonitorListings(.alarms, hunt: 12, more: true)
        #expect(store.monitorList(.alarms, hunt: 12).error != nil && store.monitorList(.alarms, hunt: 12).more)
        #expect(store.monitorMatches(.alarms, hunt: 12).map(\.id) == [80, 70, 60])
        #expect(try query(transport.requests.last)["before"] == "70")
        try transport.answer("GET /matches", encoding: MatchPage(items: [try alarm(70), try alarm(50)], more: false))
        await store.loadMonitorListings(.alarms, hunt: 12, more: true)
        #expect(store.monitorList(.alarms, hunt: 12).ids == [80, 70, 50])
        #expect(store.monitorList(.alarms, hunt: 12).error == nil)
        #expect(try query(transport.requests.last)["before"] == "70")
        try transport.answer("GET /matches", encoding: MatchPage(items: [try alarm(40, state: .saved)], more: false))
        await store.loadMonitorListings(.alarms, hunt: 12, filter: .saved, more: true)
        #expect(try query(transport.requests.last)["before"] == "60")
        try transport.answer("GET /hunts/12/used", encoding: MatchPage(items: Array(items.dropFirst(2)), more: false))
        await store.loadUsed(hunt: 12, more: true)
        #expect(try query(transport.requests.last)["before"] == String(items[1].id))
        #expect(store.usedMatches(hunt: 12).map(\.id) == items.map(\.id))
        #expect(store.monitorMatches(.alarms, hunt: 12).allSatisfy { $0.isPriceChange })
    }

    @Test(arguments: [MatchState.saved, .dismissed]) func sharedActionsWinAgainstOlderAlarmPagesAndOverview(state: MatchState) async throws {
        let (store, transport, _) = try await fixture()
        await store.loadLatest(hunt: 12)
        let original = try #require(store.latest(hunt: 12)?.first)
        let gate = RequestGate()
        transport.gates["GET /matches"] = gate
        let read = Task { await store.loadMonitorListings(.alarms, hunt: 12) }
        await gate.waitUntilPaused()
        var changed = original
        changed.state = state
        try transport.answer("POST /matches/42/state", encoding: changed)
        await store.setState(state, for: 42)
        gate.resume()
        await read.value
        #expect(store.match(42)?.state == state)
        #expect(store.monitorMatches(.alarms, hunt: 12, filter: .saved).contains { $0.id == 42 } == (state == .saved))
        #expect(store.matches(.saved).contains { $0.id == 42 } == (state == .saved))
        #expect(store.latest(hunt: 12)?.contains { $0.id == 42 } == (state != .dismissed))
        let navigation = AppNavigation()
        navigation.huntPath = [.hunt(12), .monitorListings(12, .alarms)]
        navigation.showMatch(42)
        #expect(navigation.huntPath == [.hunt(12), .monitorListings(12, .alarms), .match(42)])
    }

    @Test(arguments: ["edit", "signout", "delete", "cancel"]) func staleAlarmRepliesCannotRepopulate(after: String) async throws {
        let (store, transport, session) = try await fixture()
        let gate = RequestGate()
        transport.gates["GET /matches"] = gate
        let read = Task { await store.loadLatest(hunt: 12) }
        await gate.waitUntilPaused()
        switch after {
        case "signout": session.logOut()
        case "delete":
            transport.answer("DELETE /hunts/12", json: Data())
            _ = await store.deleteHunt(id: 12)
        case "edit":
            var hunt = try #require(store.card(12)?.hunt)
            var search = try #require(hunt.search.price)
            search.includeUsed.toggle()
            hunt.search = .price(search)
            try transport.answer("PUT /hunts/12", encoding: hunt)
            var overview = try #require(store.overview)
            overview.hunts[try #require(overview.hunts.firstIndex { $0.id == 12 })].hunt = hunt
            try transport.answer("GET /overview", encoding: overview)
            await store.saveMonitor(id: 12, search: search)
        default: read.cancel()
        }
        gate.resume()
        await read.value
        #expect(!store.monitorList(.alarms, hunt: 12).loaded)
        #expect(store.monitorMatches(.alarms, hunt: 12).isEmpty)
        if after == "edit" || after == "cancel" {
            await store.loadLatest(hunt: 12)
            #expect(store.latest(hunt: 12)?.map(\.id) == [42])
        }
    }

    @Test func retainedOfferUsesTheInjectedTwoHourOldConfirmation() throws {
        let content = try SampleContent.contract(now: Clock.now)
        let offer = try #require(content.offers[12]?.offers.first)
        let fixture = UsedSample.quotes(content, now: Clock.now, retainedOffer: true)
        let retained = try #require(fixture.offers[12]?.offers.first)
        let sites = try #require(fixture.offers[12]?.sites)
        #expect(Timestamp.parse(try #require(retained.checked)) == Clock.now.addingTimeInterval(-7200))
        #expect(OfferList.lastConfirmed(retained, sites: sites, timeZone: TimeZone(secondsFromGMT: 0)!, language: .english)?.contains("8:02") == true)
        #expect(OfferList.amount(retained) == OfferList.amount(offer))
    }

    @Test func alarmFailuresRetainRowsAndRetryTheFirstPage() async throws {
        let (store, transport, _) = try await fixture()
        transport.failure = URLError(.notConnectedToInternet)
        await store.loadLatest(hunt: 12)
        #expect(!store.monitorList(.alarms, hunt: 12).loaded && store.monitorList(.alarms, hunt: 12).error != nil)
        transport.failure = nil
        await store.loadLatest(hunt: 12)
        let known = store.latest(hunt: 12)
        transport.failure = URLError(.notConnectedToInternet)
        await store.loadMonitorListings(.alarms, hunt: 12, force: true)
        #expect(store.latest(hunt: 12) == known && store.monitorList(.alarms, hunt: 12).error != nil)
        transport.failure = nil
        await store.loadMonitorListings(.alarms, hunt: 12, force: true)
        #expect(store.monitorList(.alarms, hunt: 12).error == nil)
        #expect(try query(transport.requests.last)["before"] == nil)
    }

    @Test(arguments: [401, 403]) func alarmAuthFailuresEndTheSession(status: Int) async throws {
        let (store, transport, session) = try await fixture()
        transport.answer("GET /matches", status, json: Data(#"{"error":"Access refused."}"#.utf8))
        await store.loadLatest(hunt: 12)
        #expect(!session.isSignedIn && store.monitorMatches(.alarms, hunt: 12).isEmpty)
    }

    @Test func cancelledAlarmFilterCanRestartBeforeItsTransportFinishes() async throws {
        let (store, transport, _) = try await fixture()
        let gate = RequestGate()
        transport.gates["GET /matches"] = gate
        let old = Task { await store.loadMonitorListings(.alarms, hunt: 12, filter: .saved) }
        await gate.waitUntilPaused()
        old.cancel()
        let saved = try alarm(30, state: .saved)
        try transport.answer("GET /matches", encoding: MatchPage(items: [saved], more: false))
        await store.loadMonitorListings(.alarms, hunt: 12, filter: .saved)
        gate.resume()
        await old.value
        #expect(store.monitorMatches(.alarms, hunt: 12, filter: .saved) == [saved])
        #expect(!store.monitorList(.alarms, hunt: 12, filter: .saved).isLoading)
        #expect(!store.monitorList(.alarms, hunt: 12).loaded)
    }
}
