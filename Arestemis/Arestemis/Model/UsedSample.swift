#if DEBUG
import Foundation

/// Fictional used listings and retained new-goods quotes; ordinary model, API and action paths throughout.
enum UsedSample {
    static func content(_ original: SampleContent, state: String, now: Date) throws -> SampleContent {
        var content = original
        if LaunchArguments.value("-fulfillmentSample") == nil {
            content = try FulfillmentSample.content(content, state: "either", now: now)
        }
        let page = try ArestemisSamples.decode(MatchPage.self, from: "used-matches")
        let last = page.items.first.flatMap { Timestamp.parse($0.found) } ?? now
        let shifted = try JSONDecoder().decode(MatchPage.self, from:
            ArestemisSamples.shifted(JSONEncoder().encode(page), by: now.timeIntervalSince(last) - 240))
        let matches = state == "alarms" ? Array(shifted.items.prefix(1))
            : state == "off" ? shifted.items.filter { $0.state == .saved }
            : ["empty", "error", "loading"].contains(state) ? [] : shifted.items
        content.matches += matches
        if state == "alarms" {
            let original = try ArestemisSamples.decode(MatchPage.self, from: "price-matches").items[0]
            for index in 0..<6 {
                let listing = Listing(source: original.listing.source, sourceName: "Lumen North",
                                      url: "https://example.invalid/meridian-lamp", title: "Meridian Desk Lamp 2",
                                      kind: nil, rentWarm: nil, rentCold: nil, sqm: nil, rooms: nil, flatmates: nil,
                                      city: nil, district: nil, address: nil, availableFrom: nil, availableUntil: nil,
                                      furnished: nil, posted: nil, imageURL: nil, description: "",
                                      priceChange: PriceChange(old: 249 - Double(index * 5), new: 214 - Double(index * 5), kind: .below))
                content.matches.append(Match(id: 1680 - index * 2, huntID: 12, state: index.isMultiple(of: 2) ? .new : .saved,
                                             found: ArestemisSamples.iso(now.addingTimeInterval(-Double(index + 1) * 3600)),
                                             listing: listing, reason: "", warnings: []))
            }
        }
        content.used[12] = Set(matches.map(\.id))
        if let index = content.overview.hunts.firstIndex(where: { $0.id == 12 }),
           var search = content.overview.hunts[index].hunt.search.price {
            search.includeUsed = state != "off"
            content.overview.hunts[index].hunt.search = .price(search)
        }
        return content
    }

    static func quotes(_ original: SampleContent, now: Date,
                       longStore: Bool = LaunchArguments.current.contains("-longStore"),
                       retainedOffer: Bool = LaunchArguments.current.contains("-retainedOffer")) -> SampleContent {
        var content = original
        guard var quotes = content.offers[12] else { return content }
        if longStore, let index = quotes.offers.firstIndex(where: { $0.fulfillment == .pickup }) {
            quotes.offers[index].store?.name = "Lumen Home and Lighting Centre"
            quotes.offers[index].store?.city = "Lindenfeld an der Morgenau"
            if let card = content.overview.hunts.firstIndex(where: { $0.id == 12 }) {
                content.overview.hunts[card].price?.host = "Lumen Home and Lighting Centre"
            }
        }
        if retainedOffer, let source = quotes.offers.first?.source,
           let index = quotes.sites.firstIndex(where: { $0.id == source }) {
            quotes.sites[index].state = .unreadable
            quotes.offers[0].checked = ArestemisSamples.iso(now.addingTimeInterval(-2 * 3600))
        }
        content.offers[12] = quotes
        return content
    }
}
#endif
