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
    /// Auctions on the sites that have them (eBay); the form's switch shows only while such a site is chosen.
    var auctions = true
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
        auctions = search.auctions
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
                          conditionMin: conditionMin, forParts: forParts, auctions: auctions, delivery: delivery,
                          places: places, radiusKm: radius, seller: seller,
                          extra: extra.trimmingCharacters(in: .whitespacesAndNewlines), sources: Source.ordered(sources))
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
        if let value = partial.auctions { auctions = value }
        if let value = partial.delivery { delivery = value }
        if let places = partial.places {
            for place in places where !self.places.contains(where: { $0.id == place.id }) { self.places.append(place) }
        }
        if let value = partial.radiusKm { radiusKm = Self.text(value) }
        if let value = partial.seller { seller = value }
        if let value = partial.extra, !value.isEmpty { extra = value }
        if let value = partial.sources, !value.isEmpty { sources = Set(value) }
    }

    private enum CodingKeys: String, CodingKey {
        case query, exclude, priceMin, priceMax, vbText, vbOverMaxTouched, conditionMin, forParts, auctions, delivery
        case places, radiusKm, seller, extra, sources
    }

    /// A draft kept by a build from before brief 119 has no `auctions`: on, as a new search.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        query = try c.decode(String.self, forKey: .query)
        exclude = try c.decode([String].self, forKey: .exclude)
        priceMin = try c.decode(String.self, forKey: .priceMin)
        priceMax = try c.decode(String.self, forKey: .priceMax)
        vbText = try c.decode(String.self, forKey: .vbText)
        vbOverMaxTouched = try c.decode(Bool.self, forKey: .vbOverMaxTouched)
        conditionMin = try c.decodeIfPresent(Condition.self, forKey: .conditionMin)
        forParts = try c.decode(Bool.self, forKey: .forParts)
        auctions = try c.decodeIfPresent(Bool.self, forKey: .auctions) ?? true
        delivery = try c.decode(Delivery.self, forKey: .delivery)
        places = try c.decode([Place].self, forKey: .places)
        radiusKm = try c.decode(String.self, forKey: .radiusKm)
        seller = try c.decode(SearchSeller.self, forKey: .seller)
        extra = try c.decode(String.self, forKey: .extra)
        sources = try c.decode(Set<Source>.self, forKey: .sources)
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

// MARK: - the form's helpers and lines

extension ItemSearchDraft {
    static let maxPlaces = 5

    /// Adds a place (up to five); false when it is there already or five are chosen.
    @discardableResult
    mutating func add(_ place: Place) -> Bool {
        guard places.count < Self.maxPlaces, !places.contains(where: { $0.id == place.id }) else { return false }
        places.append(place)
        return true
    }

    /// Adds a word to leave out; false for an empty or repeated one (any case).
    @discardableResult
    mutating func addExclude(_ text: String) -> Bool {
        let word = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty, !exclude.contains(where: { $0.caseInsensitiveCompare(word) == .orderedSame }) else { return false }
        exclude.append(word)
        return true
    }

    /// Places and the radius apply unless the thing is only to be shipped.
    var asksPlaces: Bool { delivery != .shipping }

    /// What is wrong, in a sentence.
    func message(_ problem: Problem, language: AppLanguage = .current) -> String {
        let l = language
        switch problem {
        case .query:
            return query.trimmingCharacters(in: .whitespacesAndNewlines).count > 100
                ? l.string("At most 100 characters.") : l.string("Type what you look for.")
        case .exclude: return l.string("Up to 20 words, each at most 40 characters.")
        case .priceMin, .priceMax, .vbOverMax: return l.string("Type an amount in euros.")
        case .priceOrder: return l.string("The lowest price is above the highest.")
        case .condition: return l.string("Choose a condition.")
        case .radius: return l.string("The radius goes up to 200 km.")
        case .places:
            return places.count > Self.maxPlaces ? l.string("At most 5 places.") : l.string("Choose a place, or Shipping.")
        case .extra: return l.string("At most 1,000 characters.")
        case .sources: return l.string("Choose at least one portal.")
        }
    }

    /// The line under a field: what is wrong with what is there. A field that is simply still empty (what you look
    /// for, the place) says so only under Save (`hint`), so a new form opens without warnings.
    func fieldLine(_ problem: Problem, language: AppLanguage = .current) -> String? {
        guard problems.contains(problem) else { return nil }
        switch problem {
        case .query where query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty: return nil
        case .places where places.isEmpty: return nil
        default: return message(problem, language: language)
        }
    }

    /// One calm line under Save: the first thing still missing or wrong.
    func hint(language: AppLanguage = .current) -> String? {
        problems.first.map { message($0, language: language) }
    }
}
