import Foundation
import Testing
@testable import Arestemis

@MainActor
struct PriceFulfillmentTests {
    private var place: Place { FulfillmentSample.place }
    private var identity: ProductIdentity { ProductIdentity(name: "Meridian Desk Lamp 2") }

    private func json<T: Encodable>(_ value: T) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
    }

    @Test func oldSearchesAndDraftsHaveShippingDefaults() throws {
        let data = Data(#"{"mode":"everywhere","product":"Lamp","history":true}"#.utf8)
        let search = try JSONDecoder().decode(PriceSearch.self, from: data)
        let draft = try JSONDecoder().decode(PriceSearchDraft.self, from: data)
        #expect(search.delivery == .shipping && search.places.isEmpty && search.radiusKm == 20)
        #expect(draft.delivery == .shipping && draft.places.isEmpty && draft.radiusKm == 20)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(PriceSearch.self, from: Data(#"{"mode":"everywhere","delivery":"drone"}"#.utf8))
        }
        let future = try JSONDecoder().decode(Hunt.self, from: Data(#"{"id":30,"kind":"price","active":true,"search":{"mode":"everywhere","delivery":"drone"},"created":"","updated":""}"#.utf8))
        #expect(future.search == .unsupported)
        #expect(throws: EncodingError.self) { try JSONEncoder().encode(future.search) }
    }

    @Test func everySelectionIsExplicitAndPageEncodingStaysTheSame() throws {
        for delivery in Delivery.allCases {
            let query = ProductPreviewQuery(product: " Lamp ", details: " Blue ", delivery: delivery, places: [place], radiusKm: 50)
            let body = try json(query)
            #expect(Set(body.keys) == ["product", "details", "delivery", "places", "radius_km"])
            #expect(body["product"] as? String == "Lamp" && body["details"] as? String == "Blue")
            #expect(body["delivery"] as? String == delivery.rawValue && body["radius_km"] as? Double == 50)
            let search = PriceSearch(product: "Lamp", identity: identity, history: true, alarm: nil,
                                     delivery: delivery, places: [place], radiusKm: 50)
            let sent = try json(search)
            #expect(sent["delivery"] as? String == delivery.rawValue && sent["radius_km"] as? Double == 50)
            #expect((sent["places"] as? [[String: Any]])?.first?["id"] as? String == place.id)
            #expect(try JSONDecoder().decode(PriceSearch.self, from: JSONEncoder().encode(search)) == search)
        }
        var draft = PriceSearchDraft()
        draft.mode = .page
        draft.url = "https://shop.example/lamp"
        draft.delivery = .pickup
        draft.radiusKm = -1
        #expect(draft.isValid)
        #expect(Set(try json(try #require(draft.search())).keys) == ["url", "history", "alarm", "every"])
    }

    @Test func theAPIAndStoreSendTheSelection() async throws {
        let transport = FakeTransport()
        let (store, _, _) = try await makeStore(transport: transport)
        try transport.answer("POST /price/preview", sample: "fulfillment-preview")
        let query = ProductPreviewQuery(product: "Lamp", details: "Blue", delivery: .pickup, places: [place], radiusKm: 50)
        _ = try await store.productPreview(query)
        let request = try #require(transport.requests("POST /price/preview").first)
        let data = try #require(request.httpBody)
        let object = try JSONSerialization.jsonObject(with: data)
        let sent = try #require(object as? [String: Any])
        #expect(sent["delivery"] as? String == "pickup" && sent["radius_km"] as? Double == 50)
        #expect((sent["places"] as? [[String: Any]])?.first?["id"] as? String == place.id)
        #expect(sent["product"] as? String == "Lamp" && sent["details"] as? String == "Blue")
    }

    @Test func handoverChangesKeepTheWholeDraftAndIdentity() throws {
        let search = PriceSearch(product: "Lamp", details: "Blue", identity: identity, sourcesOff: ["parcel"],
                                 history: true, alarm: .init(below: 200, backInStock: true), every: 180,
                                 delivery: .pickup, places: [place], radiusKm: 50)
        var draft = PriceSearchDraft(search, name: "My lamp")
        draft.delivery = .shipping
        #expect(draft.isConfirmed && draft.places == [place] && draft.radiusKm == 50)
        draft.delivery = .either
        draft = try JSONDecoder().decode(PriceSearchDraft.self, from: JSONEncoder().encode(draft))
        let sent = try #require(draft.search())
        #expect(sent.delivery == .either && sent.places == search.places && sent.radiusKm == 50)
        #expect(sent.identity == identity && sent.product == "Lamp" && sent.details == "Blue")
        #expect(sent.sourcesOff == ["parcel"] && sent.history && sent.alarm == search.alarm && sent.every == 180)
        #expect(draft.sentName == "My lamp")
        draft.confirm(ProductIdentity(name: "Another product"), for: draft.previewQuery)
        #expect(draft.identity == identity)
        var changed = draft
        changed.radiusKm = 20
        #expect(changed != draft)
        changed = draft
        changed.delivery = .shipping
        #expect(changed != draft)
    }

    @Test func placesAndRadiusValidateOnlyAtFullSave() throws {
        var draft = PriceSearchDraft()
        draft.product = "Lamp"
        draft.delivery = .pickup
        draft.confirm(identity, for: draft.previewQuery)
        #expect(draft.isConfirmed && draft.problems == [.places] && draft.search() == nil)
        #expect(draft.previewQuery.words.canBeAsked)
        let added = draft.add(place)
        let repeated = draft.add(place)
        #expect(added && !repeated)
        #expect(draft.isValid)
        for index in 1...4 {
            let added = draft.add(Place(id: "sample:\(index)", name: "Town \(index)", region: nil, sources: []))
            #expect(added)
        }
        let overLimit = draft.add(Place(id: "sample:6", name: "Town 6", region: nil, sources: []))
        #expect(!overLimit)
        draft.places.append(place)
        #expect(draft.problems.contains(.places))
        draft.places = [place]
        for radius in [-1.0, 201, .infinity, .nan] {
            draft.radiusKm = radius
            #expect(draft.problems.contains(.radius))
        }
        for radius in [0.0, 20, 200] {
            draft.radiusKm = radius
            #expect(draft.isValid)
        }
        draft.places = [Place(id: "", name: "Unresolved", region: nil, sources: [])]
        #expect(draft.problems.contains(.places))
        draft.places = []
        draft.delivery = .shipping
        #expect(draft.isValid)
    }

    @Test func capabilitiesPreserveUserChoicesAndRequireOneCompatibleSite() throws {
        let sites = [PriceSite(id: "ship", name: "Parcel Works", delivery: .shipping),
                     PriceSite(id: "pick", name: "Nearby Market", delivery: .pickup),
                     PriceSite(id: "both", name: "Prism Compare", kind: .comparison, state: .hasIt, delivery: .either)]
        let off = ["both", "old-site"]
        #expect(PriceSites.onCount(sites, off: off, delivery: .pickup) == 1)
        #expect(PriceSites.onCount(sites, off: off, delivery: .shipping) == 1)
        #expect(PriceSites.switched("pick", on: false, off: off, sites: sites, delivery: .pickup) == nil)
        #expect(PriceSites.switched("ship", on: true, off: off, sites: sites, delivery: .pickup) == nil)
        let changed = try #require(PriceSites.switched("both", on: true, off: off, sites: sites, delivery: .pickup))
        #expect(changed == ["old-site"])
        #expect(PriceSites.onCount(sites, off: changed, delivery: .pickup) == 2)
        #expect(PriceSites.detail(sites[2], delivery: .pickup, language: .english) == "Price comparison · has it")
        #expect(PriceSites.detail(sites[0], delivery: .pickup, language: .german) == "Nur Versand")
        let unknown = try JSONDecoder().decode(PriceSite.self, from: Data(#"{"id":"future","delivery":"drone"}"#.utf8))
        #expect(unknown.serves(.pickup) && unknown.serves(.shipping))
    }

    @Test func totalsFeesUnknownCostsAndSelectionComeFromTheServer() throws {
        let preview = try FulfillmentSample.preview(ProductPreviewQuery(product: "Lamp", delivery: .either, places: [place]))
        let offers = preview.offers
        let noPlace = try FulfillmentSample.preview(ProductPreviewQuery(product: "Lamp", delivery: .pickup))
        #expect(noPlace.identity == identity && noPlace.offers.isEmpty)
        #expect(offers.map(\.price) == [209, 199, 225, 179])
        #expect(offers.map(\.selectedTotal) == [214, 224, 225, nil])
        #expect(EverywhereWords.cheapest(preview)?.price == 214)
        #expect(OfferList.amount(offers[0], language: .english) == "€214.00")
        #expect(offers[0].pickupFee == 5 && offers[0].store?.distanceKm == 4.2)
        #expect(OfferList.title(offers[0]) == "Lumen North, Lindenfeld")
        let line = try #require(OfferList.line(offers[0], language: .english))
        #expect(line.contains("€209.00") && line.contains("Click & Collect") && line.contains("fee €5") && line.contains("4.2 km"))
        #expect(OfferList.line(offers[2], language: .german)?.contains("Im Einrichtungshaus") == true)
        #expect(OfferList.line(offers[3], language: .english)?.contains("Shipping unknown") == true)
        #expect(OfferList.line(offers[3], language: .german)?.contains("Versandkosten unbekannt") == true)
        let state = PriceState(host: "Lumen North", price: 214, currency: "EUR", read: .ok)
        #expect(OfferList.selected(offers, state: state, off: [])?.link == offers[0].link)
        #expect(OfferList.selected(offers, state: state, off: ["lumen"]) == nil)
        #expect(OfferList.selected(offers, state: PriceState(host: "Fable Shop", read: .ok), off: []) == nil)
        var unknown = offers[3]
        unknown.total = 179
        unknown.availability = .unknown
        #expect(unknown.selectedTotal == 179)
        let unknownState = PriceState(host: unknown.shop, price: 179, currency: "EUR", availability: .unknown, read: .ok)
        #expect(OfferList.selected([unknown], state: unknownState, off: [])?.link == unknown.link)
        unknown.fulfillment = .pickup
        #expect(unknown.selectedTotal == nil)
        unknown.availability = .outOfStock
        #expect(unknown.selectedTotal == nil)
        unknown.fulfillment = .shipping
        #expect(unknown.selectedTotal == 179)
        unknown.availability = .inStock
        unknown.currency = "USD"
        #expect(unknown.selectedTotal == nil)
        let old = try JSONDecoder().decode(Offer.self, from: Data(#"{"source":"old","url":"https://shop.example/lamp","price":99,"shipping":0,"availability":"in_stock","currency":"EUR"}"#.utf8))
        #expect(old.fulfillment == .shipping && old.total == nil && old.selectedTotal == nil)
        #expect(OfferList.amount(old, language: .english) == "Total unknown")
        let future = try JSONDecoder().decode(Offer.self, from: Data(#"{"source":"future","url":"https://shop.example/lamp","fulfillment":"drone","pickup_method":"locker"}"#.utf8))
        #expect(future.fulfillment == .unknown && future.pickupMethod == .unknown)
        #expect(try JSONDecoder().decode(Offer.self, from: JSONEncoder().encode(offers[0])) == offers[0])
    }

    @Test func bothHandoversAndStoresSurviveGrouping() throws {
        let preview = try FulfillmentSample.preview(ProductPreviewQuery(product: "Lamp", delivery: .either, places: [place]))
        let pickup = preview.offers[0]
        var shipping = preview.offers[1]
        shipping.shop = pickup.shop
        var secondStore = pickup
        secondStore.store?.id = "lumen-south"
        var inStore = pickup
        inStore.pickupMethod = .inStore
        inStore.pickupFee = 0
        inStore.total = inStore.price
        let shown = OfferList.shown([pickup, shipping, secondStore, inStore, pickup], off: [])
        #expect(shown == [pickup, shipping, secondStore, inStore])
        #expect(Set(shown.map(\.id)).count == 4)
    }

    @Test(arguments: [AppLanguage.english, .german])
    func stateAndCurveClearlyNameTotals(_ language: AppLanguage) throws {
        let german = language == .german
        let found = try FulfillmentSample.preview(ProductPreviewQuery(product: "Lamp", delivery: .either, places: [place]))
        let state = PriceState(host: "Lumen North", price: 214, currency: "EUR", availability: .inStock, read: .ok)
        let text = PriceCardText(state, compact: false, everywhere: true, offer: found.offers[0], language: language)
        #expect(text.price == PriceWords.money(214, language: language))
        #expect(text.shop?.contains("Lumen North, Lindenfeld") == true)
        #expect(text.shop?.contains(german ? "Abholung" : "Pickup") == true)
        #expect(PriceWords.historyTitle(everywhere: true, language: language) == (german ? "Günstigster Gesamtpreis" : "Lowest total price"))
        #expect(PriceWords.historyTitle(everywhere: false, language: language) == (german ? "Preisverlauf" : "Price history"))
        let chart = PriceChart(Prices(points: [.init(at: "2026-11-04T12:00:00Z", price: 214)], low: 214, high: 214), everywhere: true)
        #expect(chart.spoken(try #require(chart.newest), language: language).hasPrefix(german ? "Gesamtpreis" : "Total price"))
        #expect(PriceWords.curveLabel(everywhere: true, language: language).contains(german ? "Gesamtpreis" : "Total price"))
        let empty = PriceCardText(PriceState(host: "", read: .ok), compact: false, everywhere: true, language: language)
        #expect(empty.note == (german ? "Gerade kein bekannter Gesamtpreis." : "No known total right now."))
    }

    private final class Gate {
        var requests: [ProductPreviewQuery] = []
        var replies: [CheckedContinuation<ProductPreview, any Error>] = []
        var listener: (Int, CheckedContinuation<Void, Never>)?
        func fetch(_ query: ProductPreviewQuery) async throws -> ProductPreview {
            try await withCheckedThrowingContinuation {
                requests.append(query)
                replies.append($0)
                if let (count, listener) = listener, requests.count >= count {
                    self.listener = nil
                    listener.resume()
                }
            }
        }
        func started(_ count: Int) async {
            if requests.count >= count { return }
            await withCheckedContinuation { listener = (count, $0) }
        }
    }

    @Test(arguments: ["found", "refused", "429", "cancelled"], ["delivery", "place", "radius"])
    func changingSelectionDropsStaleAnswers(outcome: String, field: String) async throws {
        let gate = Gate()
        let model = ProductPreviewModel(pause: .zero, spacing: .zero, fetch: gate.fetch)
        let shipping = ProductPreviewQuery(product: "Lamp", delivery: .either, places: [place])
        var pickup = shipping
        switch field {
        case "delivery": pickup.delivery = .pickup
        case "place": pickup.places = [Place(id: "sample:west", name: "Westfield", region: nil, sources: [])]
        default: pickup.radiusKm = 50
        }
        model.update(shipping)
        await gate.started(1)
        model.update(pickup)
        switch outcome {
        case "refused": gate.replies[0].resume(throwing: FieldRefusal(field: "product", message: "Old refusal"))
        case "429": gate.replies[0].resume(throwing: HTTPError.server(429, "Wait"))
        case "cancelled": gate.replies[0].resume(throwing: CancellationError())
        default: gate.replies[0].resume(returning: ProductPreview(identity: ProductIdentity(name: "Stale")))
        }
        await gate.started(2)
        #expect(model.query == pickup && model.answer == nil && model.fieldRefusal == nil)
        gate.replies[1].resume(returning: ProductPreview(identity: identity))
        await model.settle()
        #expect(model.answer?.identity == identity && gate.requests == [shipping, pickup])
    }
}
