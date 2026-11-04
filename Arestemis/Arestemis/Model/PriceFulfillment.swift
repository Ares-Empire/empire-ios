import Foundation

/// The server's quote method, separate from the search's "either" choice. Future values remain unknown.
enum Fulfillment: String, Codable, Sendable {
    case shipping, pickup, unknown

    init(from decoder: Decoder) throws {
        self = (try? decoder.singleValueContainer().decode(String.self)).flatMap(Self.init(rawValue:)) ?? .unknown
    }
}

enum PickupMethod: String, Codable, Sendable {
    case inStore = "in_store"
    case clickCollect = "click_collect"
    case unknown

    init(from decoder: Decoder) throws {
        self = (try? decoder.singleValueContainer().decode(String.self)).flatMap(Self.init(rawValue:)) ?? .unknown
    }
}

struct OfferStore: Codable, Equatable, Sendable {
    var id: String
    var name: String
    var city: String?
    var lat: Double
    var lon: Double
    var distanceKm: Double?

    enum CodingKeys: String, CodingKey {
        case id, name, city, lat, lon
        case distanceKm = "distance_km"
    }
}

/// A preview's full selection. Product confirmation belongs only to `words`; changing the handover refreshes offers.
struct ProductPreviewQuery: Encodable, Equatable, Sendable {
    var words: ProductWords
    var delivery: Delivery
    var places: [Place]
    var radiusKm: Double

    var product: String { words.product }
    var details: String { words.details }

    init(product: String, details: String = "", delivery: Delivery = .shipping, places: [Place] = [],
         radiusKm: Double = 20) {
        words = ProductWords(product: product, details: details)
        self.delivery = delivery
        self.places = places
        self.radiusKm = radiusKm
    }

    enum CodingKeys: String, CodingKey {
        case product, details, delivery, places
        case radiusKm = "radius_km"
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(product, forKey: .product)
        try c.encode(details, forKey: .details)
        try c.encode(delivery, forKey: .delivery)
        try c.encode(places, forKey: .places)
        try c.encode(radiusKm, forKey: .radiusKm)
    }
}

extension PriceSearchDraft {
    var asksPlaces: Bool { delivery != .shipping }
    var previewQuery: ProductPreviewQuery {
        ProductPreviewQuery(product: product, details: details, delivery: delivery, places: places, radiusKm: radiusKm)
    }

    @discardableResult
    mutating func add(_ place: Place) -> Bool {
        guard places.count < ItemSearchDraft.maxPlaces, !places.contains(where: { $0.id == place.id }) else { return false }
        places.append(place)
        return true
    }

    /// A resolved Place comes from the existing place search. The server validates its id and resolves its position.
    var validPlaces: Bool {
        places.count <= ItemSearchDraft.maxPlaces && (!asksPlaces || !places.isEmpty)
            && Set(places.map(\.id)).count == places.count
            && places.allSatisfy { !$0.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    /// A selection preview may refresh prices, never silently replace an already confirmed product for the same words.
    mutating func confirm(_ found: ProductIdentity, for query: ProductPreviewQuery) {
        guard query == previewQuery, !isConfirmed else { return }
        confirm(found, for: query.words)
    }
}

extension PriceSite {
    func serves(_ selection: Delivery) -> Bool {
        switch (delivery, selection) {
        case (.pickup?, .shipping), (.shipping?, .pickup): false
        default: true
        }
    }
}

extension Offer {
    /// Only a server-provided eligible EUR total can win. No local sum or stock inference.
    var selectedTotal: Double? {
        guard currency?.uppercased() == "EUR", fulfillment != .unknown,
              fulfillment == .shipping || availability == .inStock || availability == .preorder,
              let total, total.isFinite, total >= 0 else { return nil }
        return total
    }
}
