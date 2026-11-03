import Foundation
import Testing
@testable import Arestemis

/// Brief 157: the Preismonitor "Überall" (one product watched on every site that sells it; the server's brief 154). The
/// contract's new types read from the server's own samples and leniently; what is sent; the form's two modes keeping
/// their fields; the product's preview and the identity it confirms; "Where it looks" and its switches; "Suggest a
/// shop" starting the contact form; the card's, the page's and an alarm's words in both languages; the offers cheapest
/// first; the store's requests and the sample; and the page mode as it was.
@MainActor
struct PriceEverywhereTests {
    private let en = AppLanguage.english
    private let de = AppLanguage.german
    private final class Token {}

    /// The Arestemis server's own sample answers (`ArestemisTests/ServerSamples`).
    private func server(_ name: String) throws -> Data {
        let url = try #require(Bundle(for: Token.self).url(forResource: "server-\(name)", withExtension: "json"))
        return try Data(contentsOf: url)
    }

    private func spaces(_ text: String?) -> String? { text?.replacingOccurrences(of: "\u{a0}", with: " ") }

    private func sampleStore(_ options: SampleBackend.Options = .init()) async throws -> ArestemisStore {
        let session = EmpireSession(app: .arestemis, storage: MemoryTokens(), restoreOnLaunch: false)
        let store = ArestemisStore(session: session, backend: try SampleBackend(options: options), sample: true,
                                   placeDelay: .zero)
        await store.reloadOverview()
        return store
    }

    private func site(_ id: String, _ state: PriceSite.State = .checking) -> PriceSite {
        PriceSite(id: id, name: id.capitalized, state: state)
    }

    // MARK: decoding

    @Test func theServersSamplesDecode() throws {
        // The monitor's card: the search with its words, identity and sites off; the cheapest offer's state.
        let card = try JSONDecoder().decode(HuntCard.self, from: server("price-everywhere"))
        let search = try #require(card.hunt.search.price)
        #expect(search.mode == .everywhere && search.url == nil && search.product == "Orbital Headphones 2")
        #expect(search.details == "blue" && search.sourcesOff == ["mydealz"] && search.every == 60)
        #expect(search.identity == ProductIdentity(name: "Orbital Headphones 2 Blue", eans: ["4000000000013"]))
        #expect(search.alarm == .init(below: 220, backInStock: true) && search.history)
        let state = try #require(card.price)
        #expect(state.price == 215 && state.host == "Amazon" && state.product == "Orbital Headphones 2 Blue")
        #expect(state.offers == 2 && state.read == .ok && state.low30d == 215 && state.high30d == 229)
        // Its offers: a comparison site's shop and a shop's own, and every site with its kind, state and switch.
        let offers = try JSONDecoder().decode(PriceOffers.self, from: server("price-offers"))
        #expect(offers.offers.map(\.shop) == ["Amazon", "MediaMarkt"])
        #expect(offers.offers.map(\.sourceName) == ["billiger.de", "MediaMarkt"])
        #expect(offers.offers.map(\.shipping) == [0, 4.99] && offers.offers.allSatisfy { $0.availability == .inStock })
        #expect(offers.sites.count == 10 && offers.sites.first == PriceSite(id: "mediamarkt", name: "MediaMarkt",
                                                                           kind: .shop, state: .hasIt, on: true))
        #expect(Set(offers.sites.map(\.kind)) == [.shop, .comparison, .marketplace])
        #expect(offers.sites.filter { !$0.on }.map(\.id) == ["mydealz"])
        // The preview: the identity, what its first look found, every site.
        let preview = try JSONDecoder().decode(ProductPreview.self, from: server("product-preview"))
        #expect(preview.identity.name == "Orbital Headphones 2 Blue" && preview.offers.count == 2 && preview.sites.count == 10)
        // The overview's page monitors carry the new fields as a page's.
        let overview = try JSONDecoder().decode(Overview.self, from: server("overview"))
        let pages = overview.hunts.compactMap(\.hunt.search.price)
        #expect(!pages.isEmpty && pages.allSatisfy { $0.mode == .page && $0.url != nil && $0.identity == nil })
        #expect(overview.hunts.filter { $0.hunt.kind == .price }.allSatisfy { $0.price?.offers == nil })
    }

    @Test func readLeniently() throws {
        func search(_ json: String) throws -> PriceSearch {
            try JSONDecoder().decode(PriceSearch.self, from: Data(json.utf8))
        }
        // No mode: a page, as every monitor before brief 154.
        let old = try search(#"{"url": "https://shop.example/p/1", "history": true}"#)
        #expect(old.mode == .page && old.url == "https://shop.example/p/1" && old.sourcesOff.isEmpty && old.details.isEmpty)
        // Everywhere with only its words: no identity, nothing off.
        let bare = try search(#"{"mode": "everywhere", "url": null, "product": "Helmet"}"#)
        #expect(bare.mode == .everywhere && bare.product == "Helmet" && bare.identity == nil && bare.every == 60)
        // A mode this build does not know, or a page without its link, cannot be read: the hunt needs a newer app.
        #expect(throws: DecodingError.self) { try search(#"{"mode": "somewhere", "url": null}"#) }
        #expect(throws: DecodingError.self) { try search(#"{"mode": "page"}"#) }
        let hunt = try JSONDecoder().decode(Hunt.self, from: Data("""
            {"id": 30, "kind": "price", "active": true, "search": {"mode": "somewhere"}, "created": "", "updated": ""}
            """.utf8))
        #expect(hunt.search == .unsupported && HuntText(hunt, language: en).newerApp == "Needs a newer app")
        // A site's kind and state this build does not know are kept; its switch is on and its name its id when missing.
        let site = try JSONDecoder().decode(PriceSite.self, from: Data(#"{"id": "otto", "kind": "outlet", "state": "asleep"}"#.utf8))
        #expect(site.kind == .unknown("outlet") && site.state == .unknown("asleep") && site.on && site.name == "otto")
        #expect(try JSONDecoder().decode(PriceSite.self, from: JSONEncoder().encode(site)) == site)
        #expect(EverywhereWords.state(site.state, language: en) == nil)
        // An offer without shop, name or availability: the site's own, unknown.
        let offer = try JSONDecoder().decode(Offer.self, from: Data(#"{"source": "otto", "url": "https://otto.de/p", "price": 5}"#.utf8))
        #expect(offer.shop == "otto" && offer.sourceName == "otto" && offer.availability == .unknown && offer.shipping == nil)
        let identity = try JSONDecoder().decode(ProductIdentity.self, from: Data(#"{"name": "Helmet"}"#.utf8))
        #expect(identity.eans.isEmpty && identity.imageURL == nil)
        #expect(try JSONDecoder().decode(PriceOffers.self, from: Data("{}".utf8)) == PriceOffers())
        // A page monitor's state has no offers count.
        #expect(try JSONDecoder().decode(PriceState.self, from: Data(#"{"host": "a.example"}"#.utf8)).offers == nil)
    }

    @Test func whatIsSent() throws {
        let identity = ProductIdentity(name: "Apple AirPods Max (2. Generation)", eans: ["0195949000000"])
        let everywhere = PriceSearch(product: "AirPods Max 2", details: "Mitternacht", identity: identity,
                                     sourcesOff: ["mydealz"], history: true, alarm: .init(below: 500), every: 60)
        let sent = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(everywhere)) as? [String: Any])
        #expect(sent["mode"] as? String == "everywhere" && sent["url"] is NSNull && sent["product"] as? String == "AirPods Max 2")
        #expect(sent["details"] as? String == "Mitternacht" && sent["sources_off"] as? [String] == ["mydealz"])
        #expect((sent["identity"] as? [String: Any])?["name"] as? String == "Apple AirPods Max (2. Generation)")
        #expect((sent["identity"] as? [String: Any])?["image_url"] is NSNull && sent["every"] as? Int == 60)
        #expect(try JSONDecoder().decode(PriceSearch.self, from: JSONEncoder().encode(everywhere)) == everywhere)
        // The page mode is sent as before: its four fields, no mode.
        let page = PriceSearch(url: "https://shop.example/p/1", history: true, alarm: nil)
        let pageSent = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(page)) as? [String: Any])
        #expect(Set(pageSent.keys) == ["url", "history", "alarm", "every"])
        // Only a page opens its link; an everywhere monitor opens its cheapest offer.
        #expect(everywhere.shopURL == nil && page.shopURL != nil)
        #expect(PriceSearch.everyChoices(for: .everywhere) == [60, 180, 360, 720, 1440])
        #expect(PriceSearch.everyChoices(for: .page) == WatchSearch.everyChoices)
    }

    // MARK: the form

    @Test func eachModeKeepsItsFields() throws {
        var draft = PriceSearchDraft()
        #expect(draft.mode == .everywhere && draft.problems == [.product])
        draft.product = "  AirPods Max 2 "
        draft.details = "Blau"
        #expect(draft.problems == [.unconfirmed] && draft.search() == nil)
        // One shop: its own link; the product stays.
        draft.mode = .page
        #expect(draft.problems == [.url])
        draft.url = "https://shop.example/p/1"
        draft.every = 15
        #expect(draft.search() == PriceSearch(url: "https://shop.example/p/1", history: true, alarm: nil, every: 15))
        // Back to Everywhere: the words as they were, hourly at least; the link stays for One shop.
        draft.mode = .everywhere
        #expect(draft.product == "  AirPods Max 2 " && draft.details == "Blau" && draft.url == "https://shop.example/p/1")
        #expect(draft.effectiveEvery == 60)
        let identity = ProductIdentity(name: "Apple AirPods Max (2. Gen.) Blau")
        draft.confirm(identity, for: ProductWords(product: "AirPods Max 2", details: "Blau"))
        draft.sourcesOff = ["mydealz"]
        #expect(draft.search() == PriceSearch(product: "AirPods Max 2", details: "Blau", identity: identity,
                                              sourcesOff: ["mydealz"], history: true, alarm: nil, every: 60))
        draft.mode = .page
        #expect(draft.search()?.every == 15)
        // Each mode compares its own fields: the other mode's are kept, not sent.
        var other = draft
        other.product = "Something else"
        #expect(draft == other)
        draft.mode = .everywhere
        other.mode = .everywhere
        #expect(draft != other)
    }

    @Test(arguments: [AppLanguage.english, .german])
    func theProductIsConfirmedForItsWordsOnly(_ language: AppLanguage) {
        let german = language == .german
        var draft = PriceSearchDraft()
        #expect(draft.hint(language: language) == (german ? "Gib das Produkt ein." : "Type the product."))
        draft.product = "A"
        #expect(draft.productLine(language: language) == (german ? "Mindestens 2 Zeichen." : "At least 2 characters."))
        draft.product = "AirPods Max"
        #expect(draft.productLine(language: language) == nil)
        #expect(draft.hint(language: language)
                == (german ? "Erst muss das Produkt gefunden werden." : "First the product has to be found."))
        // An answer for older words changes nothing; one for the words in the fields confirms them.
        let found = ProductIdentity(name: "Apple AirPods Max")
        draft.confirm(found, for: ProductWords(product: "AirPods"))
        #expect(!draft.isConfirmed)
        draft.confirm(found, for: ProductWords(product: " AirPods Max "))
        #expect(draft.isConfirmed && draft.isValid && draft.hint(language: language) == nil)
        // Other words want it found again; the details count too.
        draft.details = "Silber"
        #expect(!draft.isConfirmed && draft.problems == [.unconfirmed])
        draft.details = String(repeating: "x", count: 301)
        #expect(draft.detailsLine(language: language) == (german ? "Höchstens 300 Zeichen." : "At most 300 characters."))
        // The name's placeholder: the product found, else the words.
        #expect(draft.namePlaceholder(product: "Apple AirPods Max", language: language) == "Apple AirPods Max")
        #expect(draft.namePlaceholder(product: nil, language: language) == "AirPods Max")
    }

    @Test func aSavedMonitorOpensAsSaved() throws {
        let card = try JSONDecoder().decode(HuntCard.self, from: server("price-everywhere"))
        let draft = try #require(PriceSearchDraft(saved: card.hunt))
        #expect(draft.mode == .everywhere && draft.isConfirmed && draft.isValid && draft.sourcesOff == ["mydealz"])
        #expect(draft.search() == card.hunt.search.price)
        // A kept draft from a build before brief 157 has no mode: it was a page monitor's.
        let kept = try JSONDecoder().decode(PriceSearchDraft.self, from: Data("""
            {"name": "", "url": "https://shop.example/p/1", "history": true, "alarm": false, "backInStock": false, "every": 60}
            """.utf8))
        #expect(kept.mode == .page && kept.url == "https://shop.example/p/1" && kept.isValid)
        var round = draft
        round.url = "kept for One shop"
        #expect(try JSONDecoder().decode(PriceSearchDraft.self, from: JSONEncoder().encode(round)).url == "kept for One shop")
    }

    // MARK: the preview

    @Test(arguments: [AppLanguage.english, .german])
    func thePreviewsStates(_ language: AppLanguage) async throws {
        let german = language == .german
        final class Asked { var words: [ProductWords] = [] }
        let asked = Asked()
        let found = try JSONDecoder().decode(ProductPreview.self, from: server("product-preview"))
        let preview = ProductPreviewModel(pause: .milliseconds(20), spacing: .zero) { words in
            asked.words.append(words)
            switch words.product {
            case "Nothing": throw FieldRefusal(field: "product", message: "Found no product with that name.")
            case "Down": throw HTTPError.server(503, "Not available right now, try again in a minute.")
            default: return found
            }
        }
        // Too short: nothing asked.
        preview.update(product: "A", details: "")
        #expect(preview.phase == .idle && preview.line(language: language) == nil)
        // Typed: asked once typing pauses, the words trimmed; reading, then found.
        preview.update(product: "Orbital", details: "")
        preview.update(product: "Orbital Headphones 2 ", details: " blue")
        #expect(preview.phase == .reading
                && preview.line(language: language) == (german ? "Produkt wird gesucht…" : "Looking for the product…"))
        await preview.settle()
        #expect(asked.words == [ProductWords(product: "Orbital Headphones 2", details: "blue")])
        #expect(spaces(preview.line(language: language)) == (german
            ? "Gefunden: Orbital Headphones 2 Blue · in 2 Shops, ab 215,00 €"
            : "Found: Orbital Headphones 2 Blue · in 2 shops, from €215.00"))
        #expect(EverywhereWords.cheapest(try #require(preview.answer))?.price == 215)
        // The server's refusal under the product; a failure as a calm line.
        preview.update(product: "Nothing", details: "")
        await preview.settle()
        #expect(preview.refusal == "Found no product with that name." && preview.line(language: language) == nil)
        preview.update(product: "Down", details: "")
        await preview.settle()
        #expect(preview.line(language: language) == "Not available right now, try again in a minute.")
        // A product found with no offer yet.
        let none = ProductPreview(identity: ProductIdentity(name: "Bike helmet"))
        #expect(EverywhereWords.found(none, language: language).text
                == (german ? "Gefunden: Bike helmet · noch kein Angebot" : "Found: Bike helmet · no offer yet"))
        #expect(EverywhereWords.cheapest(none) == nil)
    }

    // MARK: where it looks

    @Test(arguments: [AppLanguage.english, .german])
    func theSitesAndTheirSwitches(_ language: AppLanguage) throws {
        let german = language == .german
        let sites = [site("saturn", .notFound), site("otto", .checking), site("idealo", .hasIt),
                     site("alternate", .unreadable), site("mediamarkt", .hasIt)]
        // The ones that have it first, then checking, can't be read, doesn't have it; the server's order within each.
        #expect(PriceSites.ordered(sites).map(\.id) == ["idealo", "mediamarkt", "otto", "alternate", "saturn"])
        #expect(sites.map { EverywhereWords.state($0.state, language: language) } == (german
            ? ["hat es nicht", "wird geprüft", "hat es", "gerade nicht lesbar", "hat es"]
            : ["doesn't have it", "checking", "has it", "can't be read now", "has it"]))
        // Switching off and on makes `sources_off`, in the sites' order.
        var off: [String] = []
        off = try #require(PriceSites.switched("mediamarkt", on: false, off: off, sites: sites))
        off = try #require(PriceSites.switched("otto", on: false, off: off, sites: sites))
        #expect(off == ["otto", "mediamarkt"] && PriceSites.onCount(sites, off: off) == 3)
        #expect(spaces(EverywhereWords.looksIn(3, language: language)) == (german ? "Sucht in 3 Shops" : "Looks in 3 shops"))
        #expect(EverywhereWords.looksIn(1, language: language) == (german ? "Sucht in 1 Shop" : "Looks in 1 shop"))
        off = try #require(PriceSites.switched("otto", on: true, off: off, sites: sites))
        #expect(off == ["mediamarkt"])
        // The last site on stays on, with its line.
        let two = [site("a"), site("b")]
        let one = try #require(PriceSites.switched("a", on: false, off: [], sites: two))
        #expect(PriceSites.switched("b", on: false, off: one, sites: two) == nil)
        #expect(PriceSites.lastSiteLine(language: language)
                == (german ? "Mindestens eine Seite bleibt an." : "At least one site stays on."))
        // The line over the sites names the product.
        #expect(EverywhereWords.sitesIntro(product: "AirPods Max", language: language) == (german
            ? "Jede Seite, die Arestemis für „AirPods Max“ prüft. Schalte aus, wo du nie kaufen würdest."
            : "Every site Arestemis checks for “AirPods Max”. Switch off any you would never buy from."))
    }

    @Test(arguments: [AppLanguage.english, .german])
    func suggestingAShopStartsTheContactForm(_ language: AppLanguage) async {
        let start = PriceSites.suggestion(language: language)
        #expect(start.kind == .idea && start.text == (language == .german ? "Shop vorschlagen: " : "Suggest a shop: "))
        let session = await signedInSession()
        let form = SupportForm(session: session, sample: true, sampleDelay: .zero, kind: start.kind, text: start.text)
        // Opened as an idea with its start: nothing written yet, so closing asks nothing and Send waits.
        #expect(form.kind == .idea && form.text == start.text && form.startsWithText)
        #expect(!form.hasUnsentText && !form.canSend)
        form.text += "Otto"
        #expect(form.hasUnsentText && form.canSend)
        await form.send()
        #expect(form.phase == .sent)
        // The form opened without a start is as before.
        let plain = SupportForm(session: session, sample: true)
        #expect(plain.kind == .problem && plain.text.isEmpty && !plain.startsWithText && !plain.canSend)
    }

    // MARK: the card, the page and an alarm

    @Test(arguments: [AppLanguage.english, .german])
    func theCardsWords(_ language: AppLanguage) throws {
        let german = language == .german
        let card = try #require(try sample(Overview.self, "overview").hunts.first { $0.id == 12 })
        let text = HuntText(card, language: language)
        #expect(text.kind == .price && text.title == "Orbital Headphones 2 Blue")
        #expect(spaces(text.details) == (german ? "Überall · 6 Shops · Alarm unter 220 € oder wieder lieferbar"
                                         : "Everywhere · 6 shops · Alarm under €220 or back in stock"))
        // Under an own name the product leads; before the first read there is no count.
        var named = card
        named.hunt.name = "Headphones"
        named.price?.offers = nil
        #expect(spaces(HuntText(named, language: language).details) == (german
            ? "Orbital Headphones 2 Blue · Überall · Alarm unter 220 € oder wieder lieferbar"
            : "Orbital Headphones 2 Blue · Everywhere · Alarm under €220 or back in stock"))
        // The automatic name is the product, never the cheapest shop; before any read the identity, else the words.
        #expect(HuntText.automaticTitle(card.hunt.search, price: card.price) == "Orbital Headphones 2 Blue")
        #expect(HuntText.automaticTitle(card.hunt.search, price: nil) == "Orbital Headphones 2 Blue")
        // The cheapest price with its shop beside it.
        let lines = PriceCardText(card.price, compact: true, everywhere: true, now: Clock.now, calendar: Clock.berlin,
                                  language: language)
        #expect(spaces(lines.price) == (german ? "215,00 €" : "€215.00"))
        #expect(lines.shop == (german ? "bei Amazon" : "at Amazon") && lines.availability == (german ? "lieferbar" : "in stock"))
        // Looking, no offer, the shops not readable: its own words, never a page's.
        let waiting = PriceCardText(PriceState(host: "", read: .waiting), compact: true, everywhere: true, language: language)
        #expect(waiting.note == (german ? "Shops werden durchsucht…" : "Looking in the shops…") && waiting.price == nil)
        let none = PriceCardText(PriceState(host: "", read: .ok, offers: 0), compact: true, everywhere: true,
                                 language: language)
        #expect(none.note == (german ? "Gerade bietet es kein Shop an." : "No shop offers it right now.") && none.shop == nil)
        let failing = PriceCardText(PriceState(host: "", read: .failing), compact: true, everywhere: true, language: language)
        #expect(failing.note == (german ? "Die Shops sind gerade nicht lesbar." : "The shops can't be read right now."))
        // A page monitor's lines name no shop.
        #expect(PriceCardText(card.price, compact: true, language: language).shop == nil)
    }

    @Test(arguments: [AppLanguage.english, .german])
    func theOffersCheapestFirst(_ language: AppLanguage) {
        let german = language == .german
        let offers = [
            Offer(source: "otto", sourceName: "Otto", shop: "Otto", url: "https://otto.de/p", price: 549),
            Offer(source: "x", sourceName: "X", shop: "Abroad", url: "https://x.example/p", price: 10, currency: "USD"),
            Offer(source: "idealo", sourceName: "idealo", shop: "Amazon", url: "https://idealo.de/a", price: 545,
                  shipping: 0),
            Offer(source: "geizhals", sourceName: "Geizhals", shop: "Nobody", url: "https://geizhals.de/n", price: nil),
            Offer(source: "billiger", sourceName: "billiger.de", shop: "Amazon", url: "https://billiger.de/a", price: 529,
                  shipping: 4.99, availability: .preorder),
            Offer(source: "mydealz", sourceName: "mydealz", shop: "Saturn", url: "https://mydealz.de/s", price: 499),
        ]
        // Euros first, priced first, by price; one row per shop (its cheapest); a site switched off left out.
        #expect(OfferList.sorted(offers).map(\.price) == [499, 529, 545, 549, nil, 10])
        let shown = OfferList.shown(offers, off: ["mydealz"])
        #expect(shown.map(\.shop) == ["Amazon", "Otto", "Nobody", "Abroad"] && shown.first?.source == "billiger")
        #expect(spaces(OfferList.line(shown[0], language: language)) == (german
            ? "vorbestellbar · Versand 4,99 € · über billiger.de" : "preorder · shipping €4.99 · via billiger.de"))
        #expect(OfferList.line(offers[0], language: language) == (german ? "lieferbar" : "in stock"))
        #expect(spaces(OfferList.line(offers[2], language: language)) == (german
            ? "lieferbar · Versand 0 € · über idealo" : "in stock · shipping €0 · via idealo"))
        #expect(OfferList.more(6, language: language) == (german ? "+ 6 weitere Shops" : "+ 6 more shops"))
        #expect(offers[0].link?.host() == "otto.de")
    }

    @Test(arguments: [AppLanguage.english, .german])
    func anAlarmNamesTheShop(_ language: AppLanguage) {
        let german = language == .german
        let lower = PriceChange(old: 483.99, new: 449, kind: .below)
        #expect(spaces(PriceWords.alarm(product: "AirPods Max", change: lower, shop: "MediaMarkt", language: language))
                == (german ? "AirPods Max: 449,00 € bei MediaMarkt (vorher 483,99 €)"
                           : "AirPods Max: €449.00 at MediaMarkt (was €483.99)"))
        #expect(PriceWords.alarm(product: "AirPods Max", change: PriceChange(old: nil, new: 1, kind: .back),
                                 shop: "Otto", language: language)
                == (german ? "AirPods Max ist bei Otto wieder lieferbar" : "AirPods Max is back in stock at Otto"))
        // Without a shop (a page monitor's), as before.
        #expect(spaces(PriceWords.alarm(product: "AirPods Max", change: lower, language: language))
                == (german ? "AirPods Max: 449,00 € (vorher 483,99 €)" : "AirPods Max: €449.00 (was €483.99)"))
        #expect(EverywhereWords.mode(.page, language: language) == (german ? "Ein Shop" : "One shop"))
        #expect(EverywhereWords.mode(.everywhere, language: language) == (german ? "Überall" : "Everywhere"))
    }

    // MARK: the store and the sample

    @Test func theStoreAsksForOffersAndThePreview() async throws {
        let transport = FakeTransport()
        let (store, _, _) = try await makeStore(transport: transport)
        try transport.answer("GET /hunts/12/offers", sample: "price-offers")
        try transport.answer("POST /price/preview", sample: "product-preview")
        await store.reloadOverview()
        await store.loadOffers(hunt: 12)
        #expect(store.offers(hunt: 12).offers?.sites.count == 10 && transport.requests("GET /hunts/12/offers").count == 1)
        // Asked again only after a newer read.
        await store.loadOffers(hunt: 12)
        #expect(transport.requests("GET /hunts/12/offers").count == 1)
        // A page monitor has none.
        await store.loadOffers(hunt: 9)
        #expect(transport.requests("GET /hunts/9/offers").isEmpty)
        // The preview sends the words, product and details.
        let found = try await store.productPreview(ProductWords(product: " Orbital Headphones 2", details: "blue "))
        #expect(found.identity.name == "Orbital Headphones 2 Blue")
        let sent = try body(transport.requests("POST /price/preview").first)
        #expect(sent?["product"] as? String == "Orbital Headphones 2" && sent?["details"] as? String == "blue")
        // The alarm of an everywhere monitor names its shop; a page monitor's names none.
        let alarm = try #require(try sample(MatchPage.self, "price-matches").items.first { $0.id == 42 })
        let pageAlarm = try #require(try sample(MatchPage.self, "price-matches").items.first { $0.id == 39 })
        #expect(store.alarmShop(of: alarm) == "Amazon" && store.alarmShop(of: pageAlarm) == nil)
        #expect(alarm.priceTitle(shop: store.alarmShop(of: alarm), language: .english)
                == "Orbital Headphones 2 Blue: €215.00 at Amazon (was €229.00)")
        // Switching a site off saves the whole search with it.
        let monitor = try #require(store.card(12)?.hunt.search.price)
        var changed = monitor
        changed.sourcesOff = ["mydealz", "ebay"]
        try transport.answer("PUT /hunts/12", encoding: Hunt(id: 12, kind: .price, active: true, search: .price(changed),
                                                             created: "", updated: ""))
        await store.saveMonitor(id: 12, search: changed)
        let put = try body(transport.requests("PUT /hunts/12").first)
        let search = try #require(put?["search"] as? [String: Any])
        #expect(search["sources_off"] as? [String] == ["mydealz", "ebay"] && search["mode"] as? String == "everywhere")
        #expect(search["identity"] != nil && search["url"] is NSNull)
    }

    @Test func theSampleImitatesTheServer() async throws {
        let store = try await sampleStore()
        // Its offers: the sites switched off left out, cheapest first, one per shop; the sites with their switches.
        await store.loadOffers(hunt: 12)
        let offers = try #require(store.offers(hunt: 12).offers)
        #expect(offers.sites.first { $0.id == "mydealz" }?.on == false && offers.sites.count == 10)
        #expect(OfferList.shown(offers.offers, off: ["mydealz"]).first?.price == 215)
        await store.loadPrices(hunt: 12, days: 30)
        #expect(store.prices(hunt: 12, days: 30).prices?.low == 215)
        // Its preview: the words found, every site on.
        let found = try await store.productPreview(ProductWords(product: "AirPods Max 2", details: "Blau"))
        #expect(found.identity.name == "AirPods Max 2 Blau" && found.sites.allSatisfy(\.on))
        // Saving needs the product found, at most hourly; then it waits for its first look.
        let unconfirmed = PriceSearch(product: "AirPods Max 2", identity: nil, history: true, alarm: nil)
        #expect(await store.saveHunt(id: nil, kind: .price, name: nil, search: .price(unconfirmed)) == nil)
        #expect(store.searchErrorField == "search.identity")
        let often = PriceSearch(product: "AirPods Max 2", identity: found.identity, history: true, alarm: nil, every: 15)
        #expect(await store.saveHunt(id: nil, kind: .price, name: nil, search: .price(often)) == nil)
        #expect(store.searchErrorField == "search.every")
        let made = try #require(await store.saveHunt(id: nil, kind: .price, name: nil,
                                                     search: .price(PriceSearch(product: "AirPods Max 2",
                                                                                identity: found.identity,
                                                                                history: true, alarm: nil))))
        #expect(store.card(made.id)?.price?.read == .waiting && store.card(made.id)?.price?.product == "AirPods Max 2 Blau")
        await store.loadOffers(hunt: made.id)
        #expect(store.offers(hunt: made.id).offers?.offers.isEmpty == true
                && store.offers(hunt: made.id).offers?.sites.allSatisfy { $0.state == .checking } == true)
        // The launch arguments for its screens.
        let cards = try sample(Overview.self, "overview").hunts
        let navigation = AppNavigation()
        LaunchOptions(arguments: ["-sampleData", "-openHunt", "12", "-scrollTo", "offers"])
            .apply(to: navigation, hunts: cards, firstMatch: nil)
        #expect(navigation.huntPath == [.hunt(12)] && navigation.formScroll == "offers")
    }
}
