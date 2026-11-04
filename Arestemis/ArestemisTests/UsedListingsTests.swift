import Foundation
import Testing
@testable import Arestemis

@MainActor
struct UsedListingsTests {
    private func page() throws -> MatchPage { try sample(MatchPage.self, "used-matches") }

    private func fixture(on: Bool = true) async throws -> (ArestemisStore, FakeTransport, EmpireSession) {
        let (store, transport, session) = try await makeStore()
        var overview = try sample(Overview.self, "overview")
        let index = try #require(overview.hunts.firstIndex { $0.id == 12 })
        var search = try #require(overview.hunts[index].hunt.search.price)
        search.includeUsed = on
        overview.hunts[index].hunt.search = .price(search)
        try transport.answer("GET /overview", encoding: overview)
        try transport.answer("GET /hunts/12/used", encoding: page())
        await store.reloadOverview()
        return (store, transport, session)
    }

    @Test func oldDefaultsExplicitRequestsAndPageShape() throws {
        let old = Data(#"{"mode":"everywhere","product":"Lamp","history":true}"#.utf8)
        #expect(try !JSONDecoder().decode(PriceSearch.self, from: old).includeUsed)
        #expect(try !JSONDecoder().decode(PriceSearchDraft.self, from: old).includeUsed)
        for on in [false, true] {
            let search = PriceSearch(product: "Lamp", identity: .init(name: "Lamp"), history: true, alarm: nil,
                                     includeUsed: on)
            let sent = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(search)) as? [String: Any])
            #expect(sent["include_used"] as? Bool == on)
            #expect(try JSONDecoder().decode(PriceSearch.self, from: JSONEncoder().encode(search)) == search)
        }
        var one = PriceSearch(url: "https://example.invalid/lamp", history: true, alarm: nil)
        one.includeUsed = true
        let sent = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(one)) as? [String: Any])
        #expect(Set(sent.keys) == ["url", "history", "alarm", "every"])
        let ignored = try JSONDecoder().decode(PriceSearch.self,
            from: Data(#"{"url":"https://example.invalid/lamp","include_used":true}"#.utf8))
        #expect(!ignored.includeUsed)
    }

    @Test func aUsedEditPersistsEverythingWithoutChangingPreviewIdentity() async throws {
        let original = PriceSearch(product: "Meridian Lamp", details: "Blue", identity: .init(name: "Meridian Lamp Blue"),
                                   sourcesOff: ["parcel"], history: true, alarm: .init(below: 120, backInStock: true),
                                   every: 180, delivery: .pickup, places: [FulfillmentSample.place], radiusKm: 50)
        let baseline = PriceSearchDraft(original, name: "Desk")
        var draft = baseline
        let transport = FakeTransport()
        let (store, _, _) = try await makeStore(transport: transport)
        let preview = store.productPreviewModel()
        preview.ask(nil) // An unchanged saved product asks no HTTP preview.
        draft.includeUsed = true
        draft = try JSONDecoder().decode(PriceSearchDraft.self, from: JSONEncoder().encode(draft))
        let suite = "used-draft-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let kept = KeptSearchDraft(defaults: defaults)
        kept.keep(draft, saved: baseline, account: "fictional-account", huntID: 12)
        draft = kept.restore(saved: baseline, account: "fictional-account", huntID: 12)
        #expect(draft != baseline && draft.isConfirmed && draft.previewQuery == baseline.previewQuery)
        #expect(draft.identity == baseline.identity && draft.identityWords == baseline.identityWords)
        var expected = original
        expected.includeUsed = true
        #expect(draft.search() == expected && draft.sentName == "Desk")
        #expect(transport.requests("POST /price/preview").isEmpty)
        draft.includeUsed = false
        #expect(draft == baseline)
        draft.mode = .page
        var hidden = draft
        hidden.includeUsed = true
        #expect(hidden == draft)
        var switches = MonitorSwitches(expected)
        guard case .save(let changed) = switches.setBackInStock(false, in: expected) else {
            Issue.record("A complete monitor should save"); return
        }
        expected.alarm?.backInStock = false
        #expect(changed == expected && changed.includeUsed)
    }

    @Test func savedFormUsesTheServerValueAndWritesAnExplicitOff() async throws {
        let (store, transport, _) = try await fixture()
        let saved = try #require(store.savedDraft(PriceSearchDraft.self, huntID: 12))
        #expect(saved.includeUsed && saved.isConfirmed)
        var draft = saved
        draft.includeUsed = false
        var hunt = try #require(store.card(12)?.hunt)
        hunt.search = .price(try #require(draft.search()))
        try transport.answer("PUT /hunts/12", encoding: hunt)
        var overview = try #require(store.overview)
        overview.hunts[try #require(overview.hunts.firstIndex { $0.id == 12 })].hunt = hunt
        try transport.answer("GET /overview", encoding: overview)
        _ = await store.saveHunt(id: 12, kind: .price, name: draft.sentName, search: hunt.search)
        let sent = try #require(body(transport.requests("PUT /hunts/12").last)?["search"] as? [String: Any])
        #expect(sent["include_used"] as? Bool == false && sent["product"] as? String == saved.product)
        #expect(store.savedDraft(PriceSearchDraft.self, huntID: 12)?.includeUsed == false)
        #expect(transport.requests("POST /price/preview").isEmpty)
    }

    @Test func requestUsesOnlyDocumentedStateLimitAndCursor() async throws {
        let transport = FakeTransport()
        try transport.answer("GET /hunts/12/used", encoding: page())
        let api = ArestemisAPI(transport: transport, token: { "fictional-token" })
        let loaded = try await api.used(hunt: 12, state: [.new, .saved], limit: 5, before: 1688)
        #expect(loaded.items.allSatisfy { $0.huntID == 12 && $0.listing.item != nil })
        let request = try #require(transport.requests.last)
        let url = try #require(request.url)
        let query = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(Dictionary(uniqueKeysWithValues: query.map { ($0.name, $0.value ?? "") })
                == ["state": "new,saved", "limit": "5", "before": "1688"])
        #expect(request.httpMethod == "GET" && request.httpBody == nil)
    }

    @Test func paginationDeduplicatesAndKeepsItsCursorAcrossRetry() async throws {
        let (store, transport, _) = try await fixture()
        let items = try page().items
        try transport.answer("GET /hunts/12/used", encoding: MatchPage(items: Array(items.prefix(3)), more: true))
        await store.loadUsed(hunt: 12)
        #expect(store.usedMatches(hunt: 12).map(\.id) == Array(items.prefix(3)).map(\.id))
        transport.answer("GET /hunts/12/used", 500, json: Data(#"{"error":"Could not load older listings."}"#.utf8))
        await store.loadUsed(hunt: 12, more: true)
        #expect(store.usedList(hunt: 12).more && store.usedList(hunt: 12).error != nil)
        #expect(store.usedMatches(hunt: 12).count == 3)
        try transport.answer("GET /hunts/12/used", encoding: MatchPage(items: Array(items.dropFirst(2)), more: false))
        await store.loadUsed(hunt: 12, more: true)
        #expect(store.usedMatches(hunt: 12).map(\.id) == items.map(\.id))
        #expect(store.usedList(hunt: 12).ids == items.map(\.id))
        #expect(!store.usedList(hunt: 12).more && store.usedList(hunt: 12).error == nil)
        let requests = transport.requests("GET /hunts/12/used")
        for request in requests.suffix(2) {
            #expect(URLComponents(url: try #require(request.url), resolvingAgainstBaseURL: false)?.queryItems?
                .first { $0.name == "before" }?.value == String(items[2].id))
        }
        await store.loadUsed(hunt: 12, more: true)
        #expect(transport.requests("GET /hunts/12/used").count == requests.count)
    }

    @Test func filteringUsesIndependentPagesAndNoCursorFromThePreviousFilter() async throws {
        let (store, transport, _) = try await fixture()
        await store.loadUsed(hunt: 12)
        let saved = try page().items.filter { $0.state == .saved }
        try transport.answer("GET /hunts/12/used", encoding: MatchPage(items: saved, more: false))
        await store.loadUsed(.saved, hunt: 12)
        #expect(store.usedMatches(.saved, hunt: 12) == saved)
        let query = URLComponents(url: try #require(transport.requests.last?.url), resolvingAgainstBaseURL: false)?.queryItems
        #expect(query?.first { $0.name == "state" }?.value == "saved")
        #expect(query?.contains { $0.name == "before" || $0.name == "q" } == false)
        #expect(store.usedList(.all, hunt: 12).loaded && store.usedList(.saved, hunt: 12).loaded)
    }

    @Test(arguments: [false, true]) func enabledEmptyAndDisabledRetained(on: Bool) async throws {
        let (store, transport, _) = try await fixture(on: on)
        #expect(store.showsUsed(hunt: 12) == on)
        try transport.answer("GET /hunts/12/used", encoding: MatchPage(items: [], more: false))
        await store.loadUsed(hunt: 12)
        #expect(store.showsUsed(hunt: 12) == on && store.usedList(hunt: 12).loaded)
        try transport.answer("GET /hunts/12/used", encoding: MatchPage(items: try page().items.filter { $0.state == .saved }, more: false))
        await store.loadUsed(hunt: 12, force: true)
        #expect(store.showsUsed(hunt: 12) && store.usedMatches(hunt: 12).count == 2)
        #expect(store.card(12)?.hunt.search.price?.includeUsed == on)
    }

    @Test func initialFailureCanRetryAndRefreshKeepsLastGoodValues() async throws {
        let (store, transport, _) = try await fixture()
        transport.failure = URLError(.notConnectedToInternet)
        await store.loadUsed(hunt: 12)
        #expect(!store.usedList(hunt: 12).loaded && store.usedList(hunt: 12).error != nil)
        transport.failure = nil
        await store.loadUsed(hunt: 12)
        let known = store.usedMatches(hunt: 12)
        transport.failure = URLError(.notConnectedToInternet)
        await store.loadUsed(hunt: 12, force: true)
        #expect(store.usedList(hunt: 12).loaded && store.usedList(hunt: 12).error != nil)
        #expect(store.usedMatches(hunt: 12) == known)
    }

    @Test(arguments: [MatchState.saved, .dismissed]) func actionsUpdateInlineFullAndGlobalWithoutStalePageRestoringState(state: MatchState) async throws {
        let (store, transport, _) = try await fixture()
        await store.loadUsed(hunt: 12)
        let original = try #require(store.usedMatches(hunt: 12).first)
        let gate = RequestGate()
        transport.gates["GET /hunts/12/used"] = gate
        let read = Task { await store.loadUsed(hunt: 12, force: true) }
        await gate.waitUntilPaused()
        var changed = original
        changed.state = state
        try transport.answer("POST /matches/\(original.id)/state", encoding: changed)
        await store.setState(state, for: original.id)
        gate.resume()
        await read.value
        #expect(store.match(original.id)?.state == state)
        #expect(!store.usedMatches(.new, hunt: 12).contains { $0.id == original.id })
        #expect(!store.matches(.new).contains { $0.id == original.id })
        #expect(store.usedMatches(.saved, hunt: 12).contains { $0.id == original.id } == (state == .saved))
        #expect(store.matches(.saved).contains { $0.id == original.id } == (state == .saved))
        #expect(store.usedMatches(hunt: 12).contains { $0.id == original.id } == (state != .dismissed))
    }

    @Test func aStateActionDuringAnOlderPageAlsoWins() async throws {
        let (store, transport, _) = try await fixture()
        let items = try page().items
        try transport.answer("GET /hunts/12/used", encoding: MatchPage(items: Array(items.prefix(3)), more: true))
        await store.loadUsed(hunt: 12)
        let original = items[0]
        try transport.answer("GET /hunts/12/used", encoding: MatchPage(items: [original] + Array(items.dropFirst(3)), more: false))
        let gate = RequestGate()
        transport.gates["GET /hunts/12/used"] = gate
        let read = Task { await store.loadUsed(hunt: 12, more: true) }
        await gate.waitUntilPaused()
        var changed = original
        changed.state = .saved
        try transport.answer("POST /matches/\(original.id)/state", encoding: changed)
        await store.setState(.saved, for: original.id)
        gate.resume()
        await read.value
        #expect(store.match(original.id)?.state == .saved)
        #expect(store.usedList(hunt: 12).ids.count == Set(store.usedList(hunt: 12).ids).count)
    }

    @Test(arguments: ["used", "global"]) func readsStartedWhileAStateActionIsPendingCannotUndoIt(route: String) async throws {
        let (store, transport, _) = try await fixture()
        await store.loadUsed(hunt: 12)
        let original = try #require(store.usedMatches(hunt: 12).first)
        var saved = original
        saved.state = .saved
        try transport.answer("POST /matches/\(original.id)/state", encoding: saved)
        try transport.answer("GET /matches", encoding: page())
        let actionGate = RequestGate()
        transport.gates["POST /matches/\(original.id)/state"] = actionGate
        let action = Task { await store.setState(.saved, for: original.id) }
        await actionGate.waitUntilPaused()
        let readGate = RequestGate()
        transport.gates[route == "used" ? "GET /hunts/12/used" : "GET /matches"] = readGate
        let read = Task {
            if route == "used" { await store.loadUsed(hunt: 12, force: true) }
            else { await store.loadMatches(.all) }
        }
        await readGate.waitUntilPaused()
        actionGate.resume()
        await action.value
        readGate.resume()
        await read.value
        #expect(store.match(original.id)?.state == .saved)
        #expect(store.usedMatches(.saved, hunt: 12).contains { $0.id == original.id })
        #expect(store.matches(.saved).contains { $0.id == original.id })
    }

    @Test func aFailedStateActionRollsBackAcrossAllLists() async throws {
        let (store, transport, _) = try await fixture()
        await store.loadUsed(hunt: 12)
        let original = try #require(store.usedMatches(hunt: 12).first)
        transport.answer("POST /matches/\(original.id)/state", 500, json: Data(#"{"error":"Try later."}"#.utf8))
        await store.setState(.dismissed, for: original.id)
        #expect(store.match(original.id) == original)
        #expect(store.usedMatches(.new, hunt: 12).contains { $0.id == original.id })
        #expect(store.matches(.new).contains { $0.id == original.id })
        #expect(store.notice != nil)
    }

    @Test func deletingTheParentDropsLateActionsDetailsAndOverview() async throws {
        let (store, transport, _) = try await fixture()
        await store.loadUsed(hunt: 12)
        let original = try #require(store.usedMatches(hunt: 12).first)
        var saved = original
        saved.state = .saved
        try transport.answer("POST /matches/\(original.id)/state", encoding: saved)
        let gate = RequestGate()
        transport.gates["POST /matches/\(original.id)/state"] = gate
        let action = Task { await store.setState(.saved, for: original.id) }
        await gate.waitUntilPaused()
        transport.answer("DELETE /hunts/12", json: Data())
        // Deliberately keep the old overview answer, as a request from before the deletion might arrive late.
        _ = await store.deleteHunt(id: 12)
        gate.resume()
        await action.value
        #expect(store.card(12) == nil && store.usedMatches(hunt: 12).isEmpty)
        #expect(store.match(original.id) == nil && !store.matches(.all).contains { $0.huntID == 12 })
        try transport.answer("GET /matches/\(original.id)", encoding: original)
        let late = await store.loadMatch(original.id)
        #expect(late == nil && store.match(original.id) == nil)
    }

    @Test(arguments: [401, 403]) func usedAuthFailuresGoThroughTheSession(status: Int) async throws {
        let (store, transport, session) = try await fixture()
        transport.answer("GET /hunts/12/used", status, json: Data(#"{"error":"Access refused."}"#.utf8))
        await store.loadUsed(hunt: 12)
        #expect(!session.isSignedIn && store.usedMatches(hunt: 12).isEmpty)
    }

    @Test func sampleServerRetainsUsedWithTheSwitchOffWithoutCreatingAnotherHunt() async throws {
        var content = try SampleContent.contract()
        let items = try page().items
        content.matches += items
        content.used[12] = Set(items.map(\.id))
        let backend = try SampleBackend(content: content)
        let before = try await backend.hunts()
        let monitor = try #require(before.first { $0.id == 12 })
        #expect(monitor.search.price?.includeUsed == false)
        let first = try await backend.used(hunt: 12, state: nil, limit: 3, before: nil)
        let next = try await backend.used(hunt: 12, state: nil, limit: 50, before: first.items.last?.id)
        #expect(first.more && !next.more && first.items + next.items == items)
        let saved = try await backend.used(hunt: 12, state: [.saved], limit: 50, before: nil)
        #expect(saved.items.count == 2 && saved.items.allSatisfy { $0.state == .saved })
        let overview = try await backend.overview()
        #expect(overview.hunts.count == before.count)
        #expect(overview.hunts.first { $0.id == 12 }?.counts.new == items.filter { $0.state == .new }.count + content.matches.filter { $0.huntID == 12 && $0.isPriceChange && $0.state == .new }.count)
        await #expect(throws: HTTPError.self) { try await backend.used(hunt: 9, state: nil, limit: 50, before: nil) }
        await #expect(throws: HTTPError.self) { try await backend.used(hunt: 2, state: nil, limit: 50, before: nil) }
    }

    @Test(arguments: ["reset", "signout", "delete", "edit", "cancel"]) func lateUsedAnswersAreDiscarded(after: String) async throws {
        let (store, transport, session) = try await fixture()
        let gate = RequestGate()
        transport.gates["GET /hunts/12/used"] = gate
        let read = Task { await store.loadUsed(hunt: 12) }
        await gate.waitUntilPaused()
        switch after {
        case "reset": store.clear()
        case "signout": session.logOut()
        case "delete":
            transport.answer("DELETE /hunts/12", json: Data())
            var overview = try #require(store.overview)
            overview.hunts.removeAll { $0.id == 12 }
            try transport.answer("GET /overview", encoding: overview)
            _ = await store.deleteHunt(id: 12)
        case "edit":
            var hunt = try #require(store.card(12)?.hunt)
            var search = try #require(hunt.search.price)
            search.includeUsed = false
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
        #expect(store.usedMatches(hunt: 12).isEmpty && !store.usedList(hunt: 12).loaded)
        #expect(try page().items.allSatisfy { store.match($0.id) == nil })
        if after == "edit" || after == "cancel" {
            await store.loadUsed(hunt: 12)
            #expect(store.usedList(hunt: 12).loaded)
        }
    }

    @Test func returningToAFilterBeforeItsCancelledTransportFinishesLoadsAgain() async throws {
        let (store, transport, _) = try await fixture()
        let gate = RequestGate()
        transport.gates["GET /hunts/12/used"] = gate
        let old = Task { await store.loadUsed(hunt: 12) }
        await gate.waitUntilPaused()
        old.cancel()
        let saved = try page().items.filter { $0.state == .saved }
        try transport.answer("GET /hunts/12/used", encoding: MatchPage(items: saved, more: false))
        await store.loadUsed(hunt: 12)
        #expect(store.usedList(hunt: 12).loaded && !store.usedList(hunt: 12).isLoading)
        #expect(store.usedMatches(hunt: 12) == saved)
        gate.resume()
        await old.value
        #expect(store.usedMatches(hunt: 12) == saved && store.usedList(hunt: 12).loaded)
        #expect(!store.usedList(hunt: 12).isLoading)
    }

    @Test func usedItemAndPricePushHaveTheirOwnDetailsAndParentRoute() async throws {
        let (store, transport, _) = try await fixture()
        let item = try #require(page().items.first)
        try transport.answer("GET /matches/\(item.id)", encoding: item)
        let loaded = try #require(await store.loadMatch(item.id))
        #expect(store.kind(of: loaded) == .item && loaded.huntID == 12)
        #expect(ListingButton.buttons(for: store.kind(of: loaded), site: loaded.listing.sourceName) == [.openOnSite(loaded.listing.sourceName)])
        let price = try #require(sample(MatchPage.self, "price-matches").items.first { $0.isPriceChange })
        #expect(store.kind(of: price) == .price)
        #expect(ListingButton.buttons(for: store.kind(of: price), site: price.listing.sourceName) == [.openInShop])
        let auction = try #require(page().items.first { $0.listing.item?.priceKind == .auction })
        #expect(auction.listing.item?.price == 130 && auction.listing.item?.bids == 3)
        let navigation = AppNavigation()
        navigation.tab = .hunt
        navigation.huntPath = [.hunt(12), .monitorListings(12, .used)]
        navigation.showMatch(item.id)
        #expect(navigation.huntPath == [.hunt(12), .monitorListings(12, .used), .match(item.id)])
        navigation.open(ArestemisLink(match: item.id))
        #expect(navigation.listingsPath == [.match(item.id)])
    }

    @Test func newGoodsPreviewExcludesTheCheapestSwitchedOffSource() throws {
        let raw = try FulfillmentSample.preview(.init(product: "Lamp", delivery: .either, places: [FulfillmentSample.place]))
        let first = try #require(raw.offers.first)
        let off = try #require(PriceSites.switched(first.source, on: false, off: [], sites: raw.sites, delivery: .either))
        #expect(EverywhereWords.cheapest(raw)?.price == 214)
        #expect(EverywhereWords.cheapest(raw, off: off)?.price == 224)
        #expect(EverywhereWords.found(raw, off: off, language: .english).detail.contains("€224.00"))
        #expect(EverywhereWords.found(raw, off: off, language: .german).detail.contains("224,00"))
        #expect(raw.offers.first == first && raw.offers.count == 4)
        #expect(EverywhereWords.cheapest(raw, off: raw.sites.map(\.id)) == nil)
    }

    @Test func sourceCopyAndStockContextAreBilingualAndQuotesKeepTheirPrice() throws {
        #expect(EverywhereWords.looksIn(3, includeUsed: true, language: .english) == "New goods · 3 sites")
        #expect(EverywhereWords.sites(3, includeUsed: true, language: .german) == "Neuware · 3 Seiten")
        #expect(EverywhereWords.looksIn(3, language: .german) == "Sucht auf 3 Seiten")
        var preview = try FulfillmentSample.preview(.init(product: "Lamp", delivery: .either, places: [FulfillmentSample.place]))
        preview.offers[0].store?.name = "Lumen Home and Lighting Centre"
        preview.offers[0].store?.city = "Lindenfeld an der Morgenau"
        preview.offers[0].checked = "2026-11-01T14:30:00Z"
        preview.sites[0].state = .unreadable
        let offer = preview.offers[0]
        let state = PriceState(host: try #require(offer.store?.name), price: offer.total, currency: "EUR", availability: .inStock, read: .ok)
        let text = PriceCardText(state, compact: false, everywhere: true, offer: offer, language: .german)
        #expect(text.shop?.contains("Lumen Home and Lighting Centre, Lindenfeld an der Morgenau") == true)
        #expect(text.availability == "vorrätig" && text.price?.contains("214,00") == true)
        #expect(PriceCardText(state, compact: false, everywhere: true, offer: offer, language: .english).availability == "in stock")
        #expect(OfferList.line(preview.offers[2], language: .german)?.contains("Im Geschäft") == true)
        #expect(OfferList.line(preview.offers[2], language: .german)?.contains("vorrätig") == true)
        #expect(OfferList.line(preview.offers[1], language: .german)?.contains("lieferbar") == true)
        let retained = try #require(OfferList.lastConfirmed(offer, sites: preview.sites, timeZone: TimeZone(secondsFromGMT: 0)!, language: .german))
        #expect(retained.hasPrefix("Zuletzt bestätigt · ") && retained.contains("1.") && retained.contains("14:30"))
        #expect(OfferList.lastConfirmed(offer, sites: preview.sites, language: .english)?.hasPrefix("Last confirmed · ") == true)
        #expect(OfferList.amount(offer, language: .english) == "€214.00")
        #expect(OfferList.lastConfirmed(offer, sites: [], language: .english) == nil)
        var noTime = offer
        noTime.checked = nil
        #expect(OfferList.lastConfirmed(noTime, sites: preview.sites, language: .english) == "Last confirmed")
    }
}
