import Foundation
import Testing
@testable import Arestemis

/// Brief 129: sites that only ship or only hand over. `GET /kinds` says how each site's listings change hands
/// (`KindSource.delivery`, absent or unknown = both); the thing form greys a site its delivery cannot serve, says why in
/// the server's words, and switches it off at once (also in a saved search), never on again by itself. The OpenStreetMap
/// credit in Fonts & licences, and the new sites' listings on their row and page.
@MainActor
struct DeliverySitesTests {
    private let ikea = Source("ikea_preowned")
    private let vinted = Source("vinted")
    private let mydealz = Source("mydealz")
    private let bikemarkt = Source("bikemarkt")

    private func spaces(_ value: String?) -> String? { value?.replacingOccurrences(of: "\u{a0}", with: " ") }

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

    private func form(_ delivery: Delivery?, chosen: Set<Source> = [.kleinanzeigen], notReady: Set<Source> = [],
                      kind: SearchKind = .item) throws -> SiteChoices {
        SiteChoices(kind: kind, kinds: try kinds(notReady: notReady), chosen: chosen, names: SiteNames(), delivery: delivery)
    }

    /// What the thing form does when its delivery or the server's sites change.
    private func switchOff(_ draft: inout ItemSearchDraft, kinds: [OfferedKind]?) {
        let choices = SiteChoices(kind: .item, kinds: kinds, chosen: draft.sources, names: SiteNames(), delivery: draft.delivery)
        draft.switchOffSitesThatCannotServe(choices.sites)
    }

    // MARK: the rule

    @Test func eachDeliveryAgainstEachKindOfSite() {
        #expect(SiteDelivery.both.serves(.pickup) && SiteDelivery.both.serves(.shipping) && SiteDelivery.both.serves(.either))
        #expect(SiteDelivery.pickup.serves(.pickup) && !SiteDelivery.pickup.serves(.shipping) && SiteDelivery.pickup.serves(.either))
        #expect(!SiteDelivery.shipping.serves(.pickup) && SiteDelivery.shipping.serves(.shipping)
                && SiteDelivery.shipping.serves(.either))
    }

    @Test func deliveryDecodesLeniently() throws {
        func decode(_ delivery: String?) throws -> SiteDelivery {
            let field = delivery.map { #", "delivery": "\#($0)""# } ?? ""
            let json = #"{"source": "newportal", "name": "New Portal", "ready": true, "auctions": false\#(field)}"#
            return try JSONDecoder().decode(KindSource.self, from: Data(json.utf8)).delivery
        }
        #expect(try decode("pickup") == .pickup)
        #expect(try decode("shipping") == .shipping)
        #expect(try decode("both") == .both)
        #expect(try decode(nil) == .both)                 // a server from before brief 129
        #expect(try decode("drone") == .both)             // a delivery this build does not know: the app greys nothing
        // It goes back as it came.
        let site = KindSource(source: ikea, name: "IKEA Preowned", delivery: .pickup)
        #expect(try JSONDecoder().decode(KindSource.self, from: JSONEncoder().encode(site)) == site)
    }

    @Test func shippingGreysThePickupOnlySite() throws {
        let choices = try form(.shipping)
        let greyed = choices.sites.filter { !choices.isOpen($0) }.map(\.source)
        #expect(greyed == [ikea])
        let site = try #require(choices.sites.first { $0.source == ikea })
        #expect(site.ready && !choices.serves(site))
        #expect(!choices.canSwitch(site, chosen: [.kleinanzeigen]))
        #expect(choices.canSwitch(site, chosen: [ikea]))   // one that is on can still be switched off
        #expect(choices.notReadyLine(language: .english) == nil)
    }

    @Test func pickupGreysTheShippingOnlySites() throws {
        let choices = try form(.pickup)
        #expect(choices.sites.filter { !choices.isOpen($0) }.map(\.source) == [mydealz, vinted])
        #expect(choices.sites.filter { choices.isOpen($0) }.map(\.source) == [.kleinanzeigen, .ebay, bikemarkt, ikea])
    }

    @Test func eitherAndTheFlatFormGreyNothing() throws {
        let either = try form(.either, chosen: [.kleinanzeigen, ikea, vinted])
        #expect(either.sites.allSatisfy(either.isOpen) && either.line(language: .english) == nil)
        let flat = try form(nil, chosen: Set(Source.flatPortals), kind: .flat)
        #expect(flat.sites.allSatisfy(flat.isOpen) && flat.deliveryLine(language: .english) == nil)
        // Without an answer the app knows no site's delivery and greys none.
        let offline = SiteChoices(kind: .item, kinds: nil, chosen: [.kleinanzeigen, ikea], names: SiteNames(), delivery: .shipping)
        #expect(offline.sites.allSatisfy { offline.isOpen($0) })
    }

    // MARK: the line

    @Test(arguments: [AppLanguage.english, .german])
    func theLineInTheServersWords(_ language: AppLanguage) throws {
        let de = language == .german
        #expect(try form(.shipping).line(language: language)
                == (de ? "IKEA Preowned gibt es nur zur Abholung." : "IKEA Preowned is pickup only."))
        #expect(try form(.pickup).line(language: language)
                == (de ? "mydealz und Vinted gibt es nur mit Versand." : "mydealz and Vinted only ship."))
        #expect(try form(.either).line(language: language) == nil)
        // One shipping-only site, and two pickup-only ones.
        let one = [OfferedKind(kind: .item, name: "Things", sources: [
            KindSource(source: .kleinanzeigen, name: "Kleinanzeigen"),
            KindSource(source: vinted, name: "Vinted", delivery: .shipping)])]
        #expect(SiteChoices(kind: .item, kinds: one, chosen: [], names: SiteNames(), delivery: .pickup).line(language: language)
                == (de ? "Vinted gibt es nur mit Versand." : "Vinted only ships."))
        let two = [OfferedKind(kind: .item, name: "Things", sources: [
            KindSource(source: ikea, name: "IKEA Preowned", delivery: .pickup),
            KindSource(source: Source("abholmarkt"), name: "Abholmarkt", delivery: .pickup)])]
        #expect(SiteChoices(kind: .item, kinds: two, chosen: [], names: SiteNames(), delivery: .shipping).line(language: language)
                == (de ? "IKEA Preowned und Abholmarkt gibt es nur zur Abholung." : "IKEA Preowned and Abholmarkt are pickup only."))
    }

    /// Both reasons at once: the sites not set up first, then the delivery's; a site both ruled out and not set up is
    /// named once, for its delivery (that holds even once it is set up).
    @Test(arguments: [AppLanguage.english, .german])
    func notSetUpAndDeliveryTogether(_ language: AppLanguage) throws {
        let de = language == .german
        let pickup = try form(.pickup, notReady: [.ebay, vinted])
        #expect(pickup.line(language: language) == (de
            ? "eBay ist noch nicht eingerichtet. mydealz und Vinted gibt es nur mit Versand."
            : "eBay is not set up yet. mydealz and Vinted only ship."))
        // Shipping: Vinted serves it, so it is named as not set up; IKEA Preowned for its delivery.
        let shipping = try form(.shipping, notReady: [.ebay, vinted])
        #expect(shipping.line(language: language) == (de
            ? "eBay und Vinted sind noch nicht eingerichtet. IKEA Preowned gibt es nur zur Abholung."
            : "eBay and Vinted are not set up yet. IKEA Preowned is pickup only."))
        #expect(try form(.either, notReady: [.ebay]).line(language: language)
                == (de ? "eBay ist noch nicht eingerichtet." : "eBay is not set up yet."))
    }

    // MARK: switched off

    @Test func changingTheDeliverySwitchesOffAndNeverBackOn() throws {
        let kinds = try kinds()
        var draft = ItemSearchDraft()
        draft.words = ["Made-up bookcase"]
        draft.places = [Place(id: "wg:400", name: "Garching bei München", region: "Bayern", sources: [])]
        draft.sources = [.kleinanzeigen, ikea, vinted]
        switchOff(&draft, kinds: kinds)
        #expect(draft.sources == [.kleinanzeigen, ikea, vinted])          // either: every site serves
        draft.delivery = .shipping
        switchOff(&draft, kinds: kinds)
        #expect(draft.sources == [.kleinanzeigen, vinted])
        draft.delivery = .either
        switchOff(&draft, kinds: kinds)
        #expect(draft.sources == [.kleinanzeigen, vinted])                // back: IKEA Preowned stays off
        draft.delivery = .pickup
        switchOff(&draft, kinds: kinds)
        #expect(draft.sources == [.kleinanzeigen])
        draft.delivery = .shipping
        switchOff(&draft, kinds: kinds)
        #expect(draft.sources == [.kleinanzeigen] && draft.search()?.sources == [.kleinanzeigen])
        // Nothing to switch off: the draft is not touched.
        let sites = SiteChoices(kind: .item, kinds: kinds, chosen: draft.sources, names: SiteNames(), delivery: draft.delivery).sites
        let switched = draft.switchOffSitesThatCannotServe(sites)
        #expect(!switched)
    }

    /// An edited search: its saved sites go off with the delivery, the form has a change to save, and they do not come
    /// back with the delivery.
    @Test func anEditedSearchsSavedSites() async throws {
        let session = EmpireSession(app: .arestemis, storage: MemoryTokens(), restoreOnLaunch: false)
        let store = ArestemisStore(session: session, backend: try SampleBackend(), sample: true, placeDelay: .zero)
        await store.reloadOverview()
        await store.loadKinds()
        func switchOffAsTheForm(_ draft: inout ItemSearchDraft) {
            draft.switchOffSitesThatCannotServe(store.siteChoices(.item, chosen: draft.sources, delivery: draft.delivery).sites)
        }
        // The jeans: shipping on Kleinanzeigen and Vinted.
        let jeans = try #require(store.card(5)?.hunt.search.item)
        var draft = store.itemSearchDraft(huntID: 5)
        switchOffAsTheForm(&draft)
        #expect(draft.search() == jeans)                                  // opened as saved: nothing switched off
        draft.delivery = .pickup
        switchOffAsTheForm(&draft)
        #expect(draft.sources == [.kleinanzeigen] && draft.search() != jeans)
        draft.delivery = .shipping
        switchOffAsTheForm(&draft)
        #expect(draft.sources == [.kleinanzeigen] && draft.search()?.sources == [.kleinanzeigen])
        // The bookcase: pickup on Kleinanzeigen and IKEA Preowned; shipping takes IKEA Preowned off.
        var bookcase = store.itemSearchDraft(huntID: 4)
        #expect(bookcase.sources == [.kleinanzeigen, ikea])
        bookcase.delivery = .shipping
        switchOffAsTheForm(&bookcase)
        #expect(bookcase.sources == [.kleinanzeigen])
        bookcase.delivery = .either
        switchOffAsTheForm(&bookcase)
        #expect(bookcase.sources == [.kleinanzeigen])
    }

    /// A search saved before the server refused such sites (a pickup search with mydealz) loses it when the form opens.
    @Test func aSearchSavedBeforeTheRuleOpensWithoutTheSite() throws {
        var object = try #require(try JSONSerialization.jsonObject(with: ArestemisSamples.data("hunts")) as? [[String: Any]])
        var search = try #require(object[3]["search"] as? [String: Any])
        search["sources"] = ["kleinanzeigen", "mydealz", "ikea_preowned"]
        object[3]["search"] = search
        let saved = try #require(try JSONDecoder().decode([Hunt].self, from: JSONSerialization.data(withJSONObject: object))[3]
            .search.item)
        #expect(saved.delivery == .pickup)
        var draft = ItemSearchDraft(saved)
        switchOff(&draft, kinds: try kinds())
        #expect(draft.sources == [.kleinanzeigen, ikea] && draft.search() != saved)
    }

    @Test func theSitesAnswerArrivingLaterSwitchesOffToo() throws {
        var draft = ItemSearchDraft()
        draft.delivery = .shipping
        draft.sources = [.kleinanzeigen, ikea]
        switchOff(&draft, kinds: nil)                                     // no answer yet: the app knows no delivery
        #expect(draft.sources == [.kleinanzeigen, ikea])
        switchOff(&draft, kinds: try kinds())
        #expect(draft.sources == [.kleinanzeigen])
    }

    @Test func theOnlySiteRuledOutLeavesTheFormAskingForOne() throws {
        var draft = ItemSearchDraft()
        draft.delivery = .shipping
        draft.words = ["Made-up bookcase"]
        draft.sources = [ikea]
        switchOff(&draft, kinds: try kinds())
        #expect(draft.sources.isEmpty && draft.problems == [.sources] && draft.search() == nil)
        #expect(draft.fieldLine(.sources, language: .english) == "Choose at least one portal.")
    }

    @Test func aSiteTheListDoesNotNameServesEveryDelivery() throws {
        var draft = ItemSearchDraft()
        draft.delivery = .pickup
        draft.places = [Place(id: "wg:400", name: "Garching bei München", region: "Bayern", sources: [])]
        draft.sources = [.kleinanzeigen, Source("newportal")]
        switchOff(&draft, kinds: try kinds())
        #expect(draft.sources == [.kleinanzeigen, Source("newportal")])
    }

    // MARK: the OpenStreetMap credit

    @Test func theOpenStreetMapEntry() throws {
        let english = BundledLicence.townLocations(language: .english)
        let german = BundledLicence.townLocations(language: .german)
        #expect(english.name == "© OpenStreetMap contributors" && german.name == "© OpenStreetMap-Mitwirkende")
        #expect(english.purpose == "Town locations for thing searches" && german.purpose == "Ortslagen für Suchen nach Dingen")
        #expect(english.licenceName == "ODbL 1.0" && german.licenceName == "ODbL 1.0")
        #expect(english.links.map(\.url.absoluteString)
                == ["https://www.openstreetmap.org/copyright", "https://opendatacommons.org/licenses/odbl/1-0/"])
        #expect(german.links.map(\.title) == ["OpenStreetMap: Urheberrecht und Mitwirkende", "Open Database License (ODbL) 1.0"])
        let text = try #require(english.text())
        #expect(text.hasPrefix("© OpenStreetMap contributors") && text.contains("Open Database License (ODbL) 1.0"))
        #expect(english.links.allSatisfy { text.contains($0.url.absoluteString) })
        // The app ships no OpenStreetMap data: nothing to download.
        #expect(!text.localizedCaseInsensitiveContains("download") && !text.contains("aresium.de"))
    }

    // MARK: the new sites' listings

    @Test(arguments: [AppLanguage.english, .german])
    func anIKEAPreownedListing(_ language: AppLanguage) throws {
        let de = language == .german
        let match = try sample(Match.self, "ikea-match")
        #expect(match.listing.source == ikea && match.listing.sourceName == "IKEA Preowned" && match.huntID == 4)
        // "Preis vorschlagen": negotiable without an amount, shown as VB alone.
        #expect(match.itemPrice(language: language) == ItemPrice(amount: nil, label: "VB"))
        #expect(spaces(match.listing.itemRowFacts(language: language))
                == (de ? "Gut · Abholung, 5,5 km · Garching" : "Good · Pickup, 5.5 km · Garching"))
        let facts = match.listing.itemDetailFacts(now: Clock.now, calendar: Clock.berlin, language: language)
        #expect(facts.map(\.label) == (de ? ["Zustand", "Übergabe", "Entfernung", "Verkäufer", "Ort", "Eingestellt"]
                                          : ["Condition", "Delivery", "Distance", "Seller", "Place", "Posted"]))
        #expect(facts[0].value == (de ? "Gut (Gebraucht)" : "Good (Gebraucht)"))
        #expect(facts[1].value == (de ? "Nur Abholung" : "Pickup only") && facts[2].value == (de ? "5,5" : "5.5"))
    }

    @Test(arguments: [AppLanguage.english, .german])
    func aVintedListing(_ language: AppLanguage) throws {
        let de = language == .german
        let match = try sample(Match.self, "vinted-match")
        #expect(match.listing.source == vinted && match.listing.sourceName == "Vinted" && match.huntID == 5)
        #expect(spaces(match.itemPrice(language: language)?.amount) == (de ? "30 €" : "€30"))
        #expect(match.itemPrice(language: language)?.label == nil)
        #expect(match.listing.itemRowFacts(language: language) == (de ? "Wie neu · Versand" : "Like new · Shipping"))
        let facts = match.listing.itemDetailFacts(now: Clock.now, calendar: Clock.berlin, language: language)
        #expect(facts.map(\.label) == (de ? ["Zustand", "Übergabe", "Verkäufer"] : ["Condition", "Delivery", "Seller"]))
        #expect(facts[0].value == (de ? "Wie neu (Sehr gut)" : "Like new (Sehr gut)"))
        // Brand, size and the buyer-protection fee are the description (the server's, in German).
        #expect(match.listing.description.contains("Größe: W32") && match.listing.description.contains("Käuferschutz"))
    }

    @Test func theSampleHasAHuntForEachNewDelivery() async throws {
        let session = EmpireSession(app: .arestemis, storage: MemoryTokens(), restoreOnLaunch: false)
        let store = ArestemisStore(session: session, backend: try SampleBackend(), sample: true, placeDelay: .zero)
        await store.reloadOverview()
        #expect(store.card(4)?.hunt.search.item?.delivery == .pickup && store.card(4)?.sources == [.kleinanzeigen, ikea])
        #expect(store.card(5)?.hunt.search.item?.delivery == .shipping && store.card(5)?.sources == [.kleinanzeigen, vinted])
        await store.loadLatest(hunt: 4)
        await store.loadLatest(hunt: 5)
        #expect(store.latest(hunt: 4)?.map(\.id) == [33] && store.latest(hunt: 5)?.map(\.id) == [34])
        #expect(store.siteNames.name(ikea) == "IKEA Preowned")
    }
}
