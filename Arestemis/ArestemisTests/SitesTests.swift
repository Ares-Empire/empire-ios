import Foundation
import Testing
@testable import Arestemis

/// Brief 119: the sites come from the server. Any site it names is kept and shown by its name (`Source`, `SiteNames`),
/// the forms offer `GET /kinds`' sites for their kind (or the lists of before without an answer), a site that is not
/// set up is greyed with a line, the auction switch shows only for a chosen site with auctions, and an auction's bid,
/// time left, bid count and end.
@MainActor
struct SitesTests {
    private func spaces(_ value: String?) -> String? { value?.replacingOccurrences(of: "\u{a0}", with: " ") }
    private let ikea = Source("ikea_preowned")
    private let vinted = Source("vinted")
    private let mydealz = Source("mydealz")
    private let bikemarkt = Source("bikemarkt")
    /// The server's thing sites in its order (the sample's `/kinds`).
    private var thingSites: [Source] { [.kleinanzeigen, .ebay, mydealz, bikemarkt, ikea, vinted] }

    /// The sample's `/kinds` (every site set up), with the sites named here not set up.
    private func kinds(notReady: Set<Source> = []) throws -> [OfferedKind] {
        try sample([OfferedKind].self, "kinds").map { offered in
            OfferedKind(kind: offered.kind, name: offered.name, sources: offered.sources.map { site in
                var site = site
                if notReady.contains(site.source) { site.ready = false }
                return site
            })
        }
    }

    /// Lets the store's own tasks (the sites asked for after the overview) run.
    private func settle(until done: () -> Bool = { false }) async {
        for _ in 0..<50 {
            if done() { return }
            await Task.yield()
        }
    }

    // MARK: an open site

    @Test func anySiteIsKeptInItsOrderAndSentBackAsItCame() throws {
        #expect(Source(rawValue: "ebay") == .ebay && Source("newportal").id == "newportal")
        #expect(Source.ordered([Source("zeta"), .ebay, Source("alpha"), .immowelt, .wgGesucht])
                == [.wgGesucht, .immowelt, .ebay, Source("alpha"), Source("zeta")])
        var object = try #require(try JSONSerialization.jsonObject(with: ArestemisSamples.data("hunts")) as? [[String: Any]])
        var search = try #require(object[1]["search"] as? [String: Any])
        search["sources"] = ["newportal", "kleinanzeigen"]
        object[1]["search"] = search
        let hunt = try JSONDecoder().decode([Hunt].self, from: JSONSerialization.data(withJSONObject: object))[1]
        let item = try #require(hunt.search.item)
        #expect(item.sources == [Source("newportal"), .kleinanzeigen])
        let sent = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(item)) as? [String: Any])
        #expect(sent["sources"] as? [String] == ["newportal", "kleinanzeigen"])
        // The form keeps it and sends it after the known ones.
        #expect(ItemSearchDraft(item).search()?.sources == [.kleinanzeigen, Source("newportal")])
    }

    @Test func namesAreTheServers() throws {
        let overview = try sample(Overview.self, "overview")
        var names = SiteNames(statuses: overview.sources, kinds: try kinds())
        #expect(names.name(.ebay) == "eBay" && names.name(ikea) == "IKEA Preowned" && names.name(bikemarkt) == "MTB-News Bikemarkt")
        #expect(names.name(Source("newportal")) == "newportal")        // named by no answer: its id, nothing made up
        // Without any answer, the four sites of before keep the names they had.
        names = SiteNames()
        #expect(Source.flatPortals.map(names.name) == ["WG-Gesucht", "Kleinanzeigen", "Immowelt", "ImmoScout24"])
        #expect(names.name(.ebay) == "ebay")
        // The overview's name wins over `/kinds`' (both are the server's; the overview is the newer answer).
        let renamed = [KindSource(source: .ebay, name: "eBay.de", ready: true, auctions: true)]
        names = SiteNames(statuses: overview.sources, kinds: [OfferedKind(kind: .item, name: "Things", sources: renamed)])
        #expect(names.name(.ebay) == "eBay")
    }

    // MARK: GET /kinds

    @Test func kindsDecodeLeniently() throws {
        let kinds = try sample([OfferedKind].self, "kinds")
        // The names brief 134 gives the kinds; the Preismonitor (`price`) is kept as a kind this build does not know.
        #expect(kinds.map(\.kind) == [.flat, .item, .unknown("price"), .watch]
                && kinds.map(\.name) == ["Flat", "Things", "Price monitor", "Watch a website"])
        #expect(kinds[2].sources.isEmpty && kinds[3].sources.isEmpty)
        #expect(kinds[1].sources.map(\.source) == thingSites)
        #expect(kinds[1].sources.map(\.auctions) == [false, true, false, false, false, false])
        #expect(kinds[1].sources.allSatisfy { $0.ready })
        #expect(kinds[1].sources.map(\.delivery) == [.both, .both, .shipping, .both, .pickup, .shipping])
        // A server without `ready`, `auctions` or `delivery` means set up, no auctions, both ways; a kind this build does
        // not know is kept.
        let older = try JSONDecoder().decode([OfferedKind].self, from: Data("""
            [{"kind": "car", "name": "A car", "sources": [{"source": "newportal", "name": "New Portal"}]}]
            """.utf8))
        #expect(older.first?.kind == .unknown("car"))
        #expect(older.first?.sources == [KindSource(source: Source("newportal"), name: "New Portal", ready: true, auctions: false,
                                                    delivery: .both)])
    }

    @Test func theFormsTakeTheServersSitesInItsOrder() throws {
        let names = SiteNames()
        let item = SiteChoices(kind: .item, kinds: try kinds(), chosen: [.kleinanzeigen], names: names)
        #expect(item.sites.map(\.source) == thingSites)
        #expect(item.sites.map(\.name) == ["Kleinanzeigen", "eBay", "mydealz", "MTB-News Bikemarkt", "IKEA Preowned", "Vinted"])
        let flat = SiteChoices(kind: .flat, kinds: try kinds(), chosen: Set(Source.flatPortals), names: names)
        #expect(flat.sites.map(\.source) == Source.flatPortals)
        // A site the search chose that the list leaves out stays, after it, so it can be switched off.
        let kept = SiteChoices(kind: .flat, kinds: try kinds(), chosen: [.wgGesucht, Source("newportal")],
                               names: SiteNames(statuses: [SourceStatus(source: Source("newportal"), name: "New Portal",
                                                                        state: .idle, checked: nil, note: nil)]))
        #expect(kept.sites.map(\.name) == ["WG-Gesucht", "Kleinanzeigen", "Immowelt", "ImmoScout24", "New Portal"])
        #expect(kept.canSwitch(try #require(kept.sites.last), chosen: [Source("newportal")]))
    }

    @Test func withoutAnAnswerTheFormsShowTheListsOfBefore() throws {
        let names = SiteNames()
        #expect(SiteChoices(kind: .flat, kinds: nil, chosen: [], names: names).sites.map(\.source) == Source.flatPortals)
        #expect(SiteChoices(kind: .item, kinds: nil, chosen: [.kleinanzeigen], names: names).sites.map(\.source)
                == [.kleinanzeigen])
        // An answer without this kind is no answer for it.
        let flatOnly = try kinds().filter { $0.kind == .flat }
        #expect(SiteChoices(kind: .item, kinds: flatOnly, chosen: [], names: names).sites.map(\.source) == [.kleinanzeigen])
        // A saved thing search's eBay still shows, every site switchable, none greyed.
        let saved = SiteChoices(kind: .item, kinds: nil, chosen: [.kleinanzeigen, .ebay], names: names)
        #expect(saved.sites.map(\.source) == [.kleinanzeigen, .ebay] && saved.sites.allSatisfy(\.ready))
        #expect(saved.notReadyLine(language: .english) == nil)
    }

    @Test func theStoreLoadsTheSitesWithTheOverviewAndKeepsThem() async throws {
        let (store, transport, session) = try await makeStore()
        try transport.answer("GET /kinds", sample: "kinds")
        await store.reloadOverview()
        await settle { store.kinds != nil }
        #expect(store.kinds?.map(\.kind) == [.flat, .item, .unknown("price"), .watch]
                && transport.requests("GET /kinds").count == 1)
        let form = store.siteChoices(.item, chosen: [.kleinanzeigen])
        #expect(form.sites.map(\.name) == ["Kleinanzeigen", "eBay", "mydealz", "MTB-News Bikemarkt", "IKEA Preowned", "Vinted"])
        // The quiet reloads after an action ask again only while there is no answer.
        await store.reloadOverview(quiet: true)
        await settle()
        #expect(transport.requests("GET /kinds").count == 1)
        // A failure keeps the last answer and says nothing.
        transport.answer("GET /kinds", 500, json: Data(#"{"error":"Made-up failure"}"#.utf8))
        await store.reloadOverview()
        await settle { transport.requests("GET /kinds").count == 2 }
        await settle()
        #expect(transport.requests("GET /kinds").count == 2 && store.kinds?.count == 4)
        #expect(store.notice == nil && store.overviewError == nil && session.isSignedIn)
        // Forgotten with the account's data.
        store.clear()
        #expect(store.kinds == nil)
    }

    @Test func aServerFromBeforeTheSitesLeavesTheListsOfBefore() async throws {
        let (store, transport, session) = try await makeStore()      // no route: the server answers 404
        await store.reloadOverview()
        await settle { !transport.requests("GET /kinds").isEmpty }
        await store.loadKinds()
        #expect(store.kinds == nil && session.isSignedIn && store.notice == nil)
        #expect(store.siteChoices(.flat, chosen: []).sites.map(\.name) == ["WG-Gesucht", "Kleinanzeigen", "Immowelt", "ImmoScout24"])
        // A saved search's eBay is named by the overview.
        #expect(store.siteChoices(.item, chosen: [.kleinanzeigen, .ebay]).sites.map(\.name) == ["Kleinanzeigen", "eBay"])
    }

    @Test func aRefusedLoginForTheSitesLogsOut() async throws {
        let (store, transport, session) = try await makeStore()
        transport.answer("GET /kinds", 401, json: Data(#"{"error":"Made-up refusal"}"#.utf8))
        await store.loadKinds()
        #expect(!session.isSignedIn && store.kinds == nil)
    }

    // MARK: a site not set up, and the auction switch

    @Test(arguments: [AppLanguage.english, .german])
    func aSiteNotSetUpIsGreyedWithALine(_ language: AppLanguage) throws {
        let de = language == .german
        var form = SiteChoices(kind: .item, kinds: try kinds(notReady: [vinted]), chosen: [.kleinanzeigen], names: SiteNames())
        let notSetUp = try #require(form.sites.last)
        #expect(notSetUp.source == vinted && !notSetUp.ready && !form.isOpen(notSetUp))
        #expect(!form.canSwitch(notSetUp, chosen: [.kleinanzeigen]))
        #expect(form.canSwitch(notSetUp, chosen: [vinted]))          // one that is on can still be switched off
        #expect(form.sites.filter { $0.source != vinted }.allSatisfy { form.canSwitch($0, chosen: []) })
        #expect(form.notReadyLine(language: language)
                == (de ? "Vinted ist noch nicht eingerichtet." : "Vinted is not set up yet."))
        #expect(form.line(language: language) == form.notReadyLine(language: language))
        form = SiteChoices(kind: .item, kinds: try kinds(notReady: [.ebay, vinted]), chosen: [], names: SiteNames())
        #expect(!form.canSwitch(form.sites[1], chosen: []))
        #expect(form.notReadyLine(language: language)
                == (de ? "eBay und Vinted sind noch nicht eingerichtet." : "eBay and Vinted are not set up yet."))
        // Every site set up: no line.
        #expect(SiteChoices(kind: .flat, kinds: try kinds(), chosen: [], names: SiteNames()).notReadyLine(language: language) == nil)
    }

    @Test func theAuctionSwitchShowsOnlyWhileAChosenSiteHasAuctions() throws {
        let form = SiteChoices(kind: .item, kinds: try kinds(), chosen: [], names: SiteNames())
        #expect(!form.showsAuctions(chosen: []) && !form.showsAuctions(chosen: [.kleinanzeigen]))
        #expect(form.showsAuctions(chosen: [.ebay]) && form.showsAuctions(chosen: [.kleinanzeigen, .ebay]))
        #expect(!form.showsAuctions(chosen: [.kleinanzeigen, ikea, vinted]))
        let flat = SiteChoices(kind: .flat, kinds: try kinds(), chosen: Set(Source.flatPortals), names: SiteNames())
        #expect(!flat.showsAuctions(chosen: Set(Source.flatPortals)))
        // Without an answer the app knows of no auctions.
        #expect(!SiteChoices(kind: .item, kinds: nil, chosen: [.ebay], names: SiteNames()).showsAuctions(chosen: [.ebay]))
    }

    @Test func auctionsAreOnByDefaultAndKeptWhenEditing() throws {
        var object = try #require(try JSONSerialization.jsonObject(with: ArestemisSamples.data("hunts")) as? [[String: Any]])
        var search = try #require(object[1]["search"] as? [String: Any])
        search.removeValue(forKey: "auctions")                      // a server from before eBay
        object[1]["search"] = search
        var item = try #require(try JSONDecoder().decode([Hunt].self, from: JSONSerialization.data(withJSONObject: object))[1]
            .search.item)
        #expect(item.auctions)
        item.auctions = false
        let draft = ItemSearchDraft(item)
        #expect(!draft.auctions && draft.search()?.auctions == false && draft.search() == item)
        let sent = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(item)) as? [String: Any])
        #expect(sent["auctions"] as? Bool == false)
        #expect(ItemSearchDraft().auctions)
        var described = ItemSearchDraft()
        described.apply(PartialItemSearch(auctions: false))
        #expect(!described.auctions)
    }

    /// A draft kept by build 6 (no `auctions`) still opens, with auctions on; one kept now keeps its choice.
    @Test func aKeptDraftFromBeforeStillOpens() throws {
        var draft = ItemSearchDraft()
        draft.query = "Made-up chair"
        draft.priceMax = "300"
        draft.sources = [.kleinanzeigen, .ebay]
        draft.auctions = false
        let data = try JSONEncoder().encode(draft)
        #expect(try JSONDecoder().decode(ItemSearchDraft.self, from: data) == draft)
        var object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "auctions")
        let older = try JSONDecoder().decode(ItemSearchDraft.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(older.auctions && older.query == "Made-up chair" && older.vbOverMax == "30" && older.sources == [.kleinanzeigen, .ebay])
    }

    // MARK: an auction on screen

    private func auction(ends: String?) -> ItemDetails {
        ItemDetails(price: 62, priceKind: .auction, bids: 3, ends: ends)
    }

    @Test(arguments: [AppLanguage.english, .german])
    func theTimeLeft(_ language: AppLanguage) {
        let de = language == .german
        func left(_ seconds: TimeInterval) -> String? {
            auction(ends: ArestemisSamples.iso(Clock.now.addingTimeInterval(seconds))).timeLeft(now: Clock.now, language: language)
        }
        #expect(left(2 * 3600 + 12 * 60) == (de ? "noch 2 Std." : "2 h left"))
        #expect(left(45 * 60 + 30) == (de ? "noch 45 Min." : "45 min left"))
        #expect(left(20) == (de ? "noch 1 Min." : "1 min left"))
        #expect(left(30 * 3600) == (de ? "noch 30 Std." : "30 h left"))
        #expect(left(3 * 86_400 + 600) == (de ? "noch 3 Tage" : "3 days left"))
        #expect(left(0) == (de ? "beendet" : "ended") && left(-600) == (de ? "beendet" : "ended"))
        // No auction, or no end that can be read: nothing.
        var item = auction(ends: "soon")
        #expect(item.timeLeft(now: Clock.now, language: language) == nil)
        item = auction(ends: ArestemisSamples.iso(Clock.now.addingTimeInterval(3600)))
        item.priceKind = .fixed
        #expect(item.timeLeft(now: Clock.now, language: language) == nil && item.auctionEnd == nil)
    }

    @Test(arguments: [AppLanguage.english, .german])
    func anAuctionsRowAndPage(_ language: AppLanguage) throws {
        let de = language == .german
        let match = try sample(Match.self, "ebay-match")
        #expect(match.listing.sourceName == "eBay" && match.isThing)
        let price = try #require(match.itemPrice(now: Clock.now, language: language))
        #expect(spaces(price.amount) == (de ? "310 €" : "€310"))
        #expect(price.label == (de ? "Gebot · noch 2 Std." : "bid · 2 h left"))
        let facts = match.listing.itemDetailFacts(now: Clock.now, calendar: Clock.berlin, language: language)
        #expect(facts.map(\.label) == (de ? ["Gebote", "Endet", "Zustand", "Übergabe", "Versandkosten", "Verkäufer", "Ort", "Eingestellt"]
                                          : ["Bids", "Ends", "Condition", "Delivery", "Shipping cost", "Seller", "Place", "Posted"]))
        #expect(facts[0].value == "7" && facts[0].numeric)
        #expect(facts[1].value == (de ? "heute 14:15" : "today 14:15"))
        // Once past: "ended" beside the bid.
        let later = Clock.now.addingTimeInterval(3 * 3600)
        #expect(match.itemPrice(now: later, language: language)?.label == (de ? "Gebot · beendet" : "bid · ended"))
        // A thing that is no auction has neither.
        let fixed = try sample(MatchPage.self, "item-matches").items[2]
        #expect(!fixed.listing.itemDetailFacts(now: Clock.now, calendar: Clock.berlin, language: language)
            .contains { $0.label == (de ? "Gebote" : "Bids") || $0.label == (de ? "Endet" : "Ends") })
    }

    @Test(arguments: [AppLanguage.english, .german])
    func aMomentBeforeOrAfterNow(_ language: AppLanguage) {
        let de = language == .german
        func moment(_ timestamp: String) -> String {
            Format.moment(Timestamp.parse(timestamp)!, now: Clock.now, calendar: Clock.berlin, language: language)
        }
        #expect(moment("2026-10-24T12:15:00Z") == (de ? "heute 14:15" : "today 14:15"))
        #expect(moment("2026-10-25T08:30:00Z") == (de ? "morgen 09:30" : "tomorrow 09:30"))   // after the clocks go back
        #expect(moment("2026-10-23T16:05:00Z") == (de ? "gestern 18:05" : "yesterday 18:05"))
        #expect(moment("2026-10-29T13:00:00Z") == (de ? "Do 14:00" : "Thu 14:00"))
        #expect(moment("2026-11-12T13:00:00Z") == (de ? "12. Nov. 14:00" : "12 Nov 14:00"))
    }

    // MARK: samples

    @Test func theSampleHasAnEBayAuctionAndSitesForEveryState() async throws {
        let session = EmpireSession(app: .arestemis, storage: MemoryTokens(), restoreOnLaunch: false)
        var store = ArestemisStore(session: session, backend: try SampleBackend(), sample: true, placeDelay: .zero)
        await store.reloadOverview()
        await store.loadKinds()
        #expect(store.siteChoices(.item, chosen: []).sites.map(\.ready) == [true, true, true, true, true, true])
        #expect(store.card(2)?.hunt.search.item?.sources == [.kleinanzeigen, .ebay])
        #expect(store.overview?.sources.first { $0.source == .ebay }?.state == .ok)
        #expect(await store.loadMatch(32)?.listing.item?.priceKind == .auction)
        // eBay without its keys: greyed in the form, read by no hunt.
        store = ArestemisStore(session: session, backend: try SampleBackend(options: .init(ebayNotReady: true)), sample: true,
                               placeDelay: .zero)
        await store.reloadOverview()
        await store.loadKinds()
        #expect(store.siteChoices(.item, chosen: []).sites.map(\.ready) == [true, false, true, true, true, true])
        #expect(store.card(2)?.hunt.search.item?.sources == [.kleinanzeigen])
        #expect(store.overview?.sources.first { $0.source == .ebay }?.state == .idle)
        let options = LaunchOptions(arguments: ["-sampleData", "-sampleEbayNotReady"])
        #expect(options.ebayNotReady)
    }
}
