import Foundation
import Testing
@testable import Arestemis

@MainActor
struct PriceShippingUnknownTests {
    private func decode<T: Decodable>(_ type: T.Type, _ text: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(text.utf8))
    }

    private func json<T: Encodable>(_ value: T) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as? [String: Any])
    }

    @Test func newFieldsDecodeAndRoundTripWithOlderDefaults() throws {
        for field in ["", #", "total_from": null"#, #", "total_from": 179"#] {
            let offer = try decode(Offer.self, #"{"source":"fable","url":"https://shop.example/chair","price":179,"currency":"EUR""# + field + "}")
            #expect(offer.totalFrom == (field.contains("179") ? 179 : nil))
            #expect(offer.shippingUnknown == (offer.totalFrom != nil))
            #expect(try JSONDecoder().decode(Offer.self, from: JSONEncoder().encode(offer)) == offer)
            if let totalFrom = offer.totalFrom {
                #expect(try json(offer)["total_from"] as? Double == totalFrom)
            } else {
                #expect(try json(offer)["total_from"] is NSNull)
            }
        }
        for field in ["", #", "shipping_unknown": null"#, #", "shipping_unknown": false"#, #", "shipping_unknown": true"#] {
            let unknown = field.contains("true")
            let state = try decode(PriceState.self, #"{"price":179"# + field + "}")
            let change = try decode(PriceChange.self, #"{"new":179"# + field + "}")
            #expect(state.shippingUnknown == unknown && change.shippingUnknown == unknown)
            #expect(try json(state)["shipping_unknown"] as? Bool == unknown)
            #expect(try json(change)["shipping_unknown"] as? Bool == unknown)
            #expect(try JSONDecoder().decode(PriceState.self, from: JSONEncoder().encode(state)) == state)
            #expect(try JSONDecoder().decode(PriceChange.self, from: JSONEncoder().encode(change)) == change)
        }
    }

    @Test func comparisonUsesServerAmountsAndFallsBackWithoutSumming() throws {
        var offer = try decode(Offer.self, #"{"source":"parcel","url":"https://shop.example/chair","price":199,"shipping":25,"total":224,"currency":"EUR"}"#)
        #expect(offer.comparable == 224 && offer.selectedTotal == 224 && !offer.shippingUnknown)
        offer.total = nil
        #expect(offer.comparable == nil) // Raw price and shipping never become a local total.
        offer.shipping = nil
        offer.totalFrom = 199
        #expect(offer.comparable == 199 && offer.selectedTotal == nil && offer.shippingUnknown)
        offer.availability = .unknown
        #expect(offer.comparable == 199) // Shipping keeps the existing stock guard.
        offer.fulfillment = .pickup
        #expect(offer.comparable == nil)
        offer.availability = .outOfStock
        #expect(offer.comparable == nil)
        offer.availability = .preorder
        #expect(offer.comparable == 199)
        offer.fulfillment = .unknown
        #expect(offer.comparable == nil)
        offer.fulfillment = .shipping
        offer.currency = "USD"
        #expect(offer.comparable == nil)
        offer.currency = nil
        #expect(offer.comparable == nil)
        offer.currency = "eur"
        #expect(offer.comparable == 199)
        for invalid in [-1.0, .infinity, .nan] {
            offer.totalFrom = invalid
            offer.total = 224
            #expect(offer.comparable == nil && offer.selectedTotal == 224)
        }
        offer.totalFrom = 219
        #expect(offer.comparable == 219 && offer.selectedTotal == 224 && !offer.shippingUnknown)
    }

    @Test(arguments: [AppLanguage.english, .german])
    func cheapestPreviewAndAlarmPrefillFollowComparable(_ language: AppLanguage) throws {
        let found = try sample(ProductPreview.self, "shipping-unknown-preview")
        let cheapest = try #require(EverywhereWords.cheapest(found))
        #expect(cheapest.price == 1179 && cheapest.currency == "EUR" && cheapest.shippingUnknown)
        let known = try #require(EverywhereWords.cheapest(found, off: ["prism"]))
        #expect(known.price == 1224 && !known.shippingUnknown)
        let last = try #require(EverywhereWords.cheapest(found, off: ["prism", "parcel", "lumen"]))
        #expect(last.price == 1289 && last.shippingUnknown)
        #expect(EverywhereWords.cheapest(found, off: found.sites.map(\.id)) == nil)
        let lines = EverywhereWords.found(found, language: language)
        let note = language == .german ? "+ Versand unbekannt" : "+ shipping unknown"
        #expect(lines.shippingNote == note && lines.text.contains(note))
        #expect(lines.detail.contains(PriceWords.money(1179, language: language)))
        #expect(lines.detail.contains(language == .german ? "4 Shops" : "4 shops"))
        #expect(EverywhereWords.found(found, off: ["prism"], language: language).shippingNote == nil)
        var draft = PriceSearchDraft()
        let waits = draft.turnAlarmOn(price: cheapest.price, currency: cheapest.currency)
        #expect(!waits && draft.below == 1100 && draft.backInStock)
        // A later unknown-shipping offer cannot displace the first known total in the server's order.
        let above = ProductPreview(identity: found.identity, offers: Array(found.offers.dropFirst()))
        #expect(EverywhereWords.cheapest(above)?.shippingUnknown == false)
    }

    @Test(arguments: [AppLanguage.english, .german])
    func offerAmountQuietLineAndSelectedQuote(_ language: AppLanguage) throws {
        let found = try sample(ProductPreview.self, "shipping-unknown-preview")
        let unknown = found.offers[0], known = found.offers[1]
        #expect(OfferList.amount(unknown, language: language) == PriceWords.money(1179, language: language))
        #expect(OfferList.amount(known, language: language) == PriceWords.money(1224, language: language))
        #expect(OfferList.shippingNote(unknown, language: language) == (language == .german ? "+ Versand unbekannt" : "+ shipping unknown"))
        #expect(OfferList.shippingNote(known, language: language) == nil)
        #expect(OfferList.line(unknown, language: language) == (language == .german ? "lieferbar · über Prism Compare" : "in stock · via Prism Compare"))
        #expect(OfferList.line(known, language: language)?.contains(PriceWords.money(1199, language: language)) == true)
        let state = PriceState(host: unknown.shop, price: 1179, currency: "EUR", read: .ok, shippingUnknown: true)
        #expect(OfferList.selected(found.offers, state: state, off: []) == unknown)
        #expect(OfferList.selected(found.offers, state: state, off: [unknown.source]) == nil)
        var mismatched = state
        mismatched.shippingUnknown = false
        #expect(OfferList.selected(found.offers, state: mismatched, off: []) == nil)
        mismatched = state
        mismatched.price = 1224
        #expect(OfferList.selected(found.offers, state: mismatched, off: []) == nil)
        let oldUnknown = Offer(source: "old", sourceName: "Old Shop", shop: "Old Shop", url: "https://shop.example/old", price: 99)
        #expect(OfferList.amount(oldUnknown, language: language) == (language == .german ? "Gesamtpreis unbekannt" : "Total unknown"))
        #expect(OfferList.shippingNote(oldUnknown, language: language) == nil)
    }

    @Test(arguments: [AppLanguage.english, .german], [true, false])
    func cardAndAlarmWords(_ language: AppLanguage, _ compact: Bool) throws {
        let content = try FulfillmentSample.unknownShipping(SampleContent.contract(now: Clock.now), now: Clock.now)
        let card = try #require(content.overview.hunts.first { $0.id == 12 })
        let note = language == .german ? "+ Versand unbekannt" : "+ shipping unknown"
        let text = PriceCardText(card.price, compact: compact, everywhere: true, language: language)
        #expect(text.price == PriceWords.money(1179, language: language) && text.shippingNote == note)
        #expect(text.shop?.contains("Morgenlicht Möbel und Wohnideen Versandhaus") == true)
        var state = try #require(card.price)
        state.shippingUnknown = false
        #expect(PriceCardText(state, compact: compact, everywhere: true, language: language).shippingNote == nil)
        for read in [PageState.Read.waiting, .failing, .unreadable, .blocked] {
            state.read = read
            state.shippingUnknown = true
            #expect(PriceCardText(state, compact: compact, everywhere: true, language: language).shippingNote == nil)
        }
        let match = try #require(content.matches.first { $0.id == 42 })
        let sentence = match.priceTitle(language: language)
        #expect(sentence.contains(PriceWords.money(1179, language: language) + " " + note))
        #expect(sentence.contains(language == .german ? "vorher" : "was"))
        #expect(match.priceTitle(shop: "Fable Shop", language: language).contains(note))
        #expect(!match.priceTitle(includingShippingNote: false, language: language).contains(note))
        var back = try #require(match.listing.priceChange)
        back.kind = .back
        #expect(PriceWords.alarm(product: "Chair", change: back, language: language).contains(note))
        #expect(PriceWords.alarm(product: "Chair", change: back, shop: "Fable Shop", language: language).contains(note))
        let history = try #require(content.histories[12])
        #expect(history.map(\.price) == [1299, 1279, 1249, 1224, 1224])
        let quotes = try #require(content.offers[12])
        #expect(OfferList.selected(quotes.offers, state: card.price, off: []) == quotes.offers[0])
    }
}
