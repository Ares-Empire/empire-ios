import Foundation

/// Editable item filters. Number text remains intact until conversion, so malformed input cannot silently clear a filter.
struct ItemSearchDraft: Codable, Equatable {
    var query = ""
    var exclude: [String] = []
    var priceMin = ""
    var priceMax = "" {
        didSet { if !vbOverMaxTouched { updateVBDefault() } }
    }
    private var vbText = "0"
    private(set) var vbOverMaxTouched = false
    var vbOverMax: String {
        get { vbText }
        set { vbText = newValue; vbOverMaxTouched = true }
    }
    var conditionMin: Condition?
    var forParts = false
    var delivery: Delivery = .either
    var places: [Place] = []
    var radiusKm = "20"
    var seller: SearchSeller = .any
    var extra = ""
    var sources: Set<Source> = [.kleinanzeigen]

    init() {}
    init(_ search: ItemSearch) {
        query = search.query
        exclude = search.exclude
        priceMin = Self.text(search.priceMin)
        priceMax = Self.text(search.priceMax)
        vbText = Self.text(search.vbOverMax)
        // A saved value is intentional, even when it equals the suggested default.
        vbOverMaxTouched = true
        conditionMin = search.conditionMin
        forParts = search.forParts
        delivery = search.delivery
        places = search.places
        radiusKm = Self.text(search.radiusKm)
        seller = search.seller
        extra = search.extra
        sources = Set(search.sources)
    }

    enum Problem: Equatable {
        case query, exclude, priceMin, priceMax, priceOrder, vbOverMax, condition, radius, places, extra, sources
    }
    var problems: [Problem] {
        var result: [Problem] = []
        if !(2...100).contains(query.trimmingCharacters(in: .whitespacesAndNewlines).count) { result.append(.query) }
        if exclude.count > 20 || exclude.contains(where: { $0.count > 40 }) { result.append(.exclude) }
        if !priceMin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && Self.number(priceMin) == nil { result.append(.priceMin) }
        if !priceMax.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && Self.number(priceMax) == nil { result.append(.priceMax) }
        if let min = Self.number(priceMin), let max = Self.number(priceMax), min > max { result.append(.priceOrder) }
        if Self.number(vbText).map({ $0 >= 0 }) != true { result.append(.vbOverMax) }
        if conditionMin == .forParts { result.append(.condition) }
        if Self.number(radiusKm).map({ (0...200).contains($0) }) != true { result.append(.radius) }
        if places.count > 5 || (delivery != .shipping && places.isEmpty) { result.append(.places) }
        if extra.count > 1000 { result.append(.extra) }
        if sources.isEmpty { result.append(.sources) }
        return result
    }
    var isValid: Bool { problems.isEmpty }

    /// Invalid input has no contract value; the form can show `problems` without losing what was typed.
    func search() -> ItemSearch? {
        guard isValid, let vb = Self.number(vbText), let radius = Self.number(radiusKm) else { return nil }
        return ItemSearch(query: query.trimmingCharacters(in: .whitespacesAndNewlines), exclude: exclude,
                          priceMin: Self.number(priceMin), priceMax: Self.number(priceMax), vbOverMax: vb,
                          conditionMin: conditionMin, forParts: forParts, delivery: delivery, places: places,
                          radiusKm: radius, seller: seller, extra: extra.trimmingCharacters(in: .whitespacesAndNewlines),
                          sources: Source.allCases.filter(sources.contains))
    }

    /// Like the flat form: omitted/null fields stay; places and words merge; empty extra/sites do not erase edits.
    mutating func apply(_ partial: PartialItemSearch) {
        if let query = partial.query, !query.isEmpty { self.query = query }
        if let exclude = partial.exclude {
            for word in exclude where !self.exclude.contains(word) { self.exclude.append(word) }
        }
        if let value = partial.priceMin { priceMin = Self.text(value) }
        if let value = partial.priceMax { priceMax = Self.text(value) }
        if let value = partial.vbOverMax { vbOverMax = Self.text(value) }
        if let value = partial.conditionMin { conditionMin = value }
        if let value = partial.forParts { forParts = value }
        if let value = partial.delivery { delivery = value }
        if let places = partial.places {
            for place in places where !self.places.contains(where: { $0.id == place.id }) { self.places.append(place) }
        }
        if let value = partial.radiusKm { radiusKm = Self.text(value) }
        if let value = partial.seller { seller = value }
        if let value = partial.extra, !value.isEmpty { extra = value }
        if let value = partial.sources, !value.isEmpty { sources = Set(value) }
    }

    private mutating func updateVBDefault() {
        vbText = Self.number(priceMax).map { Self.text(($0 * 0.1).rounded()) } ?? "0"
    }
    private static func number(_ text: String) -> Double? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: ",", with: ".")
        guard let value = Double(text), value.isFinite else { return nil }
        return value
    }
    private static func text(_ value: Double?) -> String {
        guard let value else { return "" }
        return value.formatted(.number.locale(Locale(identifier: "en_US_POSIX")).grouping(.never).precision(.fractionLength(0...10)))
    }
}
