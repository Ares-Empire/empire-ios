import Foundation

enum Condition: String, Codable, CaseIterable, Sendable {
    case new, likeNew = "like_new", good, ok, forParts = "for_parts"
}
enum Delivery: String, Codable, CaseIterable, Sendable { case pickup, shipping, either }
enum SearchSeller: String, Codable, CaseIterable, Sendable { case `private`, any }
enum PriceKind: String, Codable, Sendable { case fixed, negotiable, free, auction, onRequest = "on_request" }
enum Shipping: String, Codable, Sendable { case yes, pickupOnly = "pickup_only" }
enum Seller: String, Codable, Sendable { case `private`, commercial }

// Unknown optional enum values from a newer server are absent information, not a broken listing or hunt.
extension KeyedDecodingContainer {
    func decodeIfPresent<T: RawRepresentable & Decodable>(_ type: T.Type, forKey key: Key) throws -> T? where T.RawValue == String {
        try decodeIfPresent(String.self, forKey: key).flatMap(T.init(rawValue:))
    }
}

struct ItemSearch: Codable, Equatable, Sendable {
    /// The first search word.
    var query: String
    /// Up to four more search words (brief 149, server brief 148): every word is searched on every chosen site, and
    /// `extra` says what fits per word. A server from before them sends none.
    var moreQueries: [String] = []
    var exclude: [String]
    var priceMin: Double?
    var priceMax: Double?
    var vbOverMax: Double
    var conditionMin: Condition?
    var forParts: Bool
    var auctions: Bool = true      // auctions on sites that have them (eBay); kept when the search is edited
    var delivery: Delivery
    var places: [Place]
    var radiusKm: Double
    var seller: SearchSeller
    /// Must have ("Muss sein", server brief 185): a listing that clearly breaks one of these wishes is filtered out.
    var extra: String
    /// Nice to have ("Wäre schön", server brief 185): never filters a listing out. A server or a search from before it
    /// has none (""); the app always sends it.
    var nice: String = ""
    var sources: [Source]

    enum CodingKeys: String, CodingKey {
        case query, exclude, auctions, delivery, places, seller, extra, nice, sources
        case moreQueries = "more_queries"
        case priceMin = "price_min", priceMax = "price_max", vbOverMax = "vb_over_max"
        case conditionMin = "condition_min", forParts = "for_parts", radiusKm = "radius_km"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(query, forKey: .query)
        try c.encode(moreQueries, forKey: .moreQueries)
        try c.encode(exclude, forKey: .exclude)
        try c.encode(priceMin, forKey: .priceMin)
        try c.encode(priceMax, forKey: .priceMax)
        try c.encode(vbOverMax, forKey: .vbOverMax)
        try c.encode(conditionMin, forKey: .conditionMin)
        try c.encode(forParts, forKey: .forParts)
        try c.encode(auctions, forKey: .auctions)
        try c.encode(delivery, forKey: .delivery)
        try c.encode(places, forKey: .places)
        try c.encode(radiusKm, forKey: .radiusKm)
        try c.encode(seller, forKey: .seller)
        try c.encode(extra, forKey: .extra)
        try c.encode(nice, forKey: .nice)
        try c.encode(sources, forKey: .sources)
    }
}

extension ItemSearch {
    /// A server from before eBay (brief 118) sends no `auctions`: the contract's default, on; one from before several
    /// search words (brief 148) no `more_queries`: none; one from before must and nice wishes (brief 185) no `nice`:
    /// none, its old text stays under Must have. Encoding always sends all three.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        query = try c.decode(String.self, forKey: .query)
        moreQueries = try c.decodeIfPresent([String].self, forKey: .moreQueries) ?? []
        exclude = try c.decode([String].self, forKey: .exclude)
        priceMin = try c.decodeIfPresent(Double.self, forKey: .priceMin)
        priceMax = try c.decodeIfPresent(Double.self, forKey: .priceMax)
        vbOverMax = try c.decode(Double.self, forKey: .vbOverMax)
        conditionMin = try c.decodeIfPresent(Condition.self, forKey: .conditionMin)
        forParts = try c.decode(Bool.self, forKey: .forParts)
        auctions = try c.decodeIfPresent(Bool.self, forKey: .auctions) ?? true
        delivery = try c.decode(Delivery.self, forKey: .delivery)
        places = try c.decode([Place].self, forKey: .places)
        radiusKm = try c.decode(Double.self, forKey: .radiusKm)
        seller = try c.decode(SearchSeller.self, forKey: .seller)
        extra = try c.decode(String.self, forKey: .extra)
        nice = try c.decodeIfPresent(String.self, forKey: .nice) ?? ""
        sources = try c.decode([Source].self, forKey: .sources)
    }

    /// Every search word in order: `query`, then `more_queries`.
    var words: [String] { [query] + moreQueries }
}

struct PartialItemSearch: Codable, Equatable, Sendable {
    var query: String?
    var moreQueries: [String]?
    var exclude: [String]?
    var priceMin: Double?
    var priceMax: Double?
    var vbOverMax: Double?
    var conditionMin: Condition?
    var forParts: Bool?
    var auctions: Bool?
    var delivery: Delivery?
    var places: [Place]?
    var radiusKm: Double?
    var seller: SearchSeller?
    /// "Describe it" (server brief 185): the hard wishes it read, for Must have …
    var extra: String?
    /// … and the soft ones, for Nice to have.
    var nice: String?
    var sources: [Source]?
    typealias CodingKeys = ItemSearch.CodingKeys
}

/// The parse route's result is selected by the requested kind; the wire body stays `{search, unclear}`.
enum HuntParseResult: Equatable, Sendable {
    case flat(ParsedSearch), item(ParsedItemSearch)
}
struct ParsedItemSearch: Codable, Equatable, Sendable {
    let search: PartialItemSearch
    let unclear: [String]
}

struct ItemDetails: Codable, Equatable, Sendable {
    var price: Double?
    var priceKind: PriceKind?
    var shipping: Shipping?
    var shippingCost: Double?
    var condition: Condition?
    var conditionLabel: String?
    var seller: Seller?
    var distanceKm: Double?
    var reserved: Bool?
    var bids: Int?                 // an auction's bid count
    var ends: String?              // an auction's end, ISO 8601 UTC

    enum CodingKeys: String, CodingKey {
        case price, shipping, condition, seller, reserved, bids, ends
        case priceKind = "price_kind", shippingCost = "shipping_cost", conditionLabel = "condition_label"
        case distanceKm = "distance_km"
    }
}
