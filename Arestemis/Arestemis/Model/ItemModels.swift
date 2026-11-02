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
    var query: String
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
    var extra: String
    var sources: [Source]

    enum CodingKeys: String, CodingKey {
        case query, exclude, auctions, delivery, places, seller, extra, sources
        case priceMin = "price_min", priceMax = "price_max", vbOverMax = "vb_over_max"
        case conditionMin = "condition_min", forParts = "for_parts", radiusKm = "radius_km"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(query, forKey: .query)
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
        try c.encode(sources, forKey: .sources)
    }
}

extension ItemSearch {
    /// A server from before eBay (brief 118) sends no `auctions`: the contract's default, on. Encoding always sends it.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        query = try c.decode(String.self, forKey: .query)
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
        sources = try c.decode([Source].self, forKey: .sources)
    }
}

struct PartialItemSearch: Codable, Equatable, Sendable {
    var query: String?
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
    var extra: String?
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
