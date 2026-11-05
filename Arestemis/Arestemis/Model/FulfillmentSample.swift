#if DEBUG
import Foundation

/// Fictional fulfillment quotes with explicit server totals, exercising the regular decoding and presentation paths.
enum FulfillmentSample {
    static var place: Place { Place(id: "sample:lindenfeld", name: "Lindenfeld", region: "Example region", sources: []) }

    /// `-shippingUnknownSample`: a lower item price ahead of known totals, plus another unknown-shipping row.
    static func unknownShipping(_ original: SampleContent, now: Date) throws -> SampleContent {
        var content = original
        var found = try ArestemisSamples.decode(ProductPreview.self, from: "shipping-unknown-preview")
        for index in found.offers.indices { found.offers[index].checked = ArestemisSamples.iso(now) }
        content.productPreview = found
        content.offers[12] = PriceOffers(offers: found.offers, sites: found.sites)
        if let index = content.overview.hunts.firstIndex(where: { $0.id == 12 }) {
            var card = content.overview.hunts[index]
            card.hunt.search = .price(PriceSearch(product: found.identity.name, identity: found.identity, history: true,
                                                 alarm: .init(below: 1200)))
            card.hunt.name = nil
            card.price = PriceState(product: found.identity.name, host: found.offers[0].shop, price: 1179,
                                    currency: "EUR", availability: .inStock, read: .ok,
                                    checked: ArestemisSamples.iso(now), low30d: 1224, high30d: 1299,
                                    offers: 4, shippingUnknown: true)
            card.counts = Overview.Counts(new: 1, today: 1, saved: 0, applied: 0)
            content.overview.hunts[index] = card
        }
        // Known totals only: the current item price without shipping never enters this history.
        content.histories[12] = [1299.0, 1279, 1249, 1224, 1224].enumerated().map { index, total in
            PricePoint(at: ArestemisSamples.iso(now.addingTimeInterval(Double(index - 4) * 4 * 86_400)), price: total)
        }
        let listing = Listing(source: .page, sourceName: found.offers[0].shop, url: found.offers[0].url,
                              title: found.identity.name, kind: nil, rentWarm: nil, rentCold: nil, sqm: nil,
                              rooms: nil, flatmates: nil, city: nil, district: nil, address: nil,
                              availableFrom: nil, availableUntil: nil, furnished: nil, posted: nil,
                              imageURL: nil, description: "",
                              priceChange: PriceChange(old: 1224, new: 1179, kind: .below, shippingUnknown: true))
        let alarm = Match(id: 42, huntID: 12, state: .new, found: ArestemisSamples.iso(now.addingTimeInterval(-240)),
                          listing: listing, reason: "", warnings: [])
        content.matches.removeAll { $0.huntID == 12 }
        content.matches.append(alarm)
        return content
    }

    static func preview(_ selection: ProductPreviewQuery) throws -> ProductPreview {
        var found = try ArestemisSamples.decode(ProductPreview.self, from: "fulfillment-preview")
        found.offers = found.offers.filter {
            switch selection.delivery {
            case .shipping: $0.fulfillment == .shipping
            case .pickup: $0.fulfillment == .pickup && !selection.places.isEmpty
            case .either: $0.fulfillment == .shipping || !selection.places.isEmpty
            }
        }
        found.sites = found.sites.map { site in
            var site = site
            site.on = site.serves(selection.delivery)
            return site
        }
        return found
    }

    static func content(_ original: SampleContent, state: String, now: Date) throws -> SampleContent {
        var content = original
        let delivery = Delivery(rawValue: state) ?? .either
        let query = ProductPreviewQuery(product: "Meridian Desk Lamp 2", delivery: delivery,
                                        places: delivery == .shipping ? [] : [place])
        let found = try preview(query)
        content.places = [place]
        content.productPreview = found
        if let index = content.overview.hunts.firstIndex(where: { $0.id == 12 }) {
            var card = content.overview.hunts[index]
            card.hunt.search = .price(PriceSearch(product: query.product, identity: found.identity, history: true,
                                                  alarm: nil, delivery: delivery, places: query.places))
            card.hunt.name = nil
            card.counts = Overview.Counts(new: 0, today: 0, saved: 0, applied: 0)
            content.matches.removeAll { $0.huntID == 12 }
            let shipping = delivery == .shipping
            card.price = PriceState(product: found.identity.name, host: shipping ? "Parcel Works" : "Lumen North",
                                    price: shipping ? 224 : 214, currency: "EUR",
                                    availability: .inStock, read: .ok, checked: ArestemisSamples.iso(now),
                                    low30d: shipping ? 224 : 214, high30d: 249, offers: state == "unknown" ? 1 : found.offers.count)
            if state == "unknown" {
                card.price?.price = nil
                card.price?.host = ""
                card.price?.availability = .unknown
                card.price?.low30d = nil
                card.price?.high30d = nil
                content.histories[12] = []
            } else {
                let values: [Double] = [249, 239, 229, 224, shipping ? 224 : 214]
                content.histories[12] = values.enumerated().map { index, total in
                    PricePoint(at: ArestemisSamples.iso(now.addingTimeInterval(Double(index - 4) * 4 * 86_400)), price: total)
                }
            }
            content.overview.hunts[index] = card
            content.offers[12] = PriceOffers(offers: state == "unknown" ? found.offers.filter { $0.total == nil } : found.offers,
                                            sites: found.sites)
        }
        return content
    }
}
#endif
