import Foundation

extension Condition {
    func title(language: AppLanguage = .current) -> String {
        switch self {
        case .new: language == .german ? "Neu" : "New"
        case .likeNew: language == .german ? "Wie neu" : "Like new"
        case .good: language == .german ? "Gut" : "Good"
        case .ok: language == .german ? "In Ordnung" : "OK"
        case .forParts: language == .german ? "Defekt" : "For parts"
        }
    }
}

extension ItemDetails {
    func priceLine(language: AppLanguage = .current) -> String? {
        let amount = price.map { Format.money($0, language: language) }
        switch priceKind {
        case .fixed: return amount
        case .negotiable: return amount.map { $0 + " VB" } ?? "VB"
        case .free: return language == .german ? "Zu verschenken" : "Free"
        case .auction: return amount.map { $0 + " (bid)" }
        case .onRequest: return language == .german ? "Preis auf Anfrage" : "Price on request"
        case nil: return nil
        }
    }
    func shippingLine(language: AppLanguage = .current) -> String? {
        switch shipping {
        case .pickupOnly: return language == .german ? "Nur Abholung" : "Pickup only"
        case .yes:
            let label = language == .german ? "Versand" : "Shipping"
            guard let shippingCost else { return label }
            let amount = shippingCost.formatted(.number.precision(.fractionLength(2)).locale(language.locale))
            return label + (language == .german ? " ab \(amount) €" : " from \(amount) €")
        case nil: return nil
        }
    }
    func distanceLine(language: AppLanguage = .current) -> String? {
        distanceKm.map { Format.number($0, language: language) + " km" }
    }
    func sellerLine(language: AppLanguage = .current) -> String? {
        switch seller {
        case .private: language == .german ? "Privat" : "Private"
        case .commercial: language == .german ? "Gewerblich" : "Commercial"
        case nil: nil
        }
    }
    func reservedLine(language: AppLanguage = .current) -> String? {
        reserved == true ? (language == .german ? "Reserviert" : "Reserved") : nil
    }
}

extension Listing {
    func itemFacts(language: AppLanguage = .current) -> String {
        guard let item else { return "" }
        let location = [city, item.distanceLine(language: language).map { "(\($0))" }].compactMap { $0 }.joined(separator: " ")
        return [item.condition?.title(language: language), location.isEmpty ? nil : location,
                item.shippingLine(language: language), item.sellerLine(language: language), item.reservedLine(language: language)]
            .compactMap { $0 }.joined(separator: " · ")
    }
    func itemDetailFacts(language: AppLanguage = .current) -> [ListingFact] {
        guard let item else { return [] }
        let de = language == .german
        var facts: [ListingFact] = []
        if let condition = item.condition?.title(language: language) {
            facts.append(ListingFact(label: de ? "Zustand" : "Condition", value: condition))
        }
        if let shipping = item.shippingLine(language: language) {
            facts.append(ListingFact(label: de ? "Lieferung" : "Delivery", value: shipping))
        }
        if let city { facts.append(ListingFact(label: de ? "Ort" : "Place", value: city)) }
        if let distance = item.distanceLine(language: language) {
            facts.append(ListingFact(label: de ? "Entfernung" : "Distance", value: distance, numeric: true))
        }
        if let seller = item.sellerLine(language: language) {
            facts.append(ListingFact(label: de ? "Verkäufer" : "Seller", value: seller))
        }
        if let reserved = item.reservedLine(language: language) {
            facts.append(ListingFact(label: de ? "Status" : "Status", value: reserved))
        }
        return facts
    }
}
extension Match {
    func overMaxLine(language: AppLanguage = .current) -> String? {
        guard let overMax else { return nil }
        // This sentence follows the contract's suffix currency in both languages.
        let amount = Format.number(overMax, language: language)
        return language == .german ? "VB, \(amount) € über deinem Limit" : "VB, \(amount) € over your limit"
    }
}

struct HuntSummary: Equatable {
    let title: String
    let parts: [String]
    var line: String { ([title] + parts).joined(separator: " · ") }
    init(_ hunt: Hunt, now: Date = .now, calendar: Calendar = .app, language: AppLanguage = .current) {
        let de = language == .german
        switch hunt.search {
        case .flat(let search):
            let flat = SearchSummary(search, now: now, calendar: calendar, language: language)
            title = flat.kinds
            parts = flat.parts
        case .item(let search):
            title = search.query
            var parts: [String] = []
            switch (search.priceMin, search.priceMax) {
            case let (min?, max?): parts.append(Format.moneyRange(min, max, language: language))
            case let (nil, max?): parts.append((de ? "bis " : "up to ") + Format.money(max, language: language))
            case let (min?, nil): parts.append((de ? "ab " : "from ") + Format.money(min, language: language))
            case (nil, nil): break
            }
            switch search.delivery {
            case .pickup: parts.append(de ? "Nur Abholung" : "Pickup only")
            case .shipping: parts.append(de ? "Versand" : "Shipping")
            case .either: parts.append(de ? "Abholung oder Versand" : "Pickup or shipping")
            }
            if search.delivery != .shipping, !search.places.isEmpty {
                parts.append(search.places.map(\.shortName).joined(separator: ", ") + " (\(Format.number(search.radiusKm, language: language)) km)")
            }
            parts.append(contentsOf: search.sources.map(\.name))
            self.parts = parts
        case .unsupported:
            title = de ? "Benötigt eine neuere App" : "Needs a newer app"
            parts = []
        }
    }
}

extension Hunt {
    func displayName(language: AppLanguage = .current) -> String {
        if let name, !name.isEmpty { return name }
        return HuntSummary(self, language: language).title
    }
}
