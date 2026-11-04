#if DEBUG
import Foundation

/// Fictional fulfillment quotes with explicit server totals, exercising the regular decoding and presentation paths.
enum FulfillmentSample {
    static var place: Place { Place(id: "sample:lindenfeld", name: "Lindenfeld", region: "Example region", sources: []) }

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
