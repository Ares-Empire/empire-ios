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
        case .auction: return amount.map { $0 + (language == .german ? " (Gebot)" : " (bid)") }
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
            let amount = Format.cents(shippingCost, language: language)
            return label + (language == .german ? " ab \(amount)" : " from \(amount)")
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
    /// A thing's page, its facts grid: Condition (with the site's own word when it differs), Delivery (Shipping or
    /// Pickup only), Shipping cost, Distance, Seller, Place, Posted, and Status while it is reserved; only the known ones.
    func itemDetailFacts(now: Date = .now, calendar: Calendar = .app, language: AppLanguage = .current) -> [ListingFact] {
        guard let item else { return [] }
        let l = language
        var facts: [ListingFact] = []
        if let condition = item.condition {
            let title = condition.title(language: l)
            let site = item.conditionLabel?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let differs = !site.isEmpty && site.compare(title, options: [.caseInsensitive, .diacriticInsensitive]) != .orderedSame
            facts.append(ListingFact(label: l.string("Condition"), value: differs ? "\(title) (\(site))" : title))
        }
        switch item.shipping {
        case .yes: facts.append(ListingFact(label: l.string("Delivery"), value: l.string("Shipping")))
        case .pickupOnly: facts.append(ListingFact(label: l.string("Delivery"), value: l.string("Pickup only")))
        case nil: break
        }
        if item.shipping == .yes, let cost = item.shippingCost {
            facts.append(ListingFact(label: l.string("Shipping cost"), value: l.string("from \(Format.cents(cost, language: l))")))
        }
        if let distance = item.distanceKm {
            facts.append(ListingFact(label: l.string("Distance"), value: Format.number(distance, language: l), unit: "km",
                                     numeric: true))
        }
        if let seller = item.sellerLine(language: l) { facts.append(ListingFact(label: l.string("Seller"), value: seller)) }
        if let place = district.map({ [city, $0].compactMap { $0 }.joined(separator: ", ") }) ?? city {
            facts.append(ListingFact(label: l.string("Place"), value: place))
        }
        if let posted = Format.relative(posted, now: now, calendar: calendar, language: l) {
            facts.append(ListingFact(label: l.string("Posted"), value: posted))
        }
        if item.reserved == true { facts.append(ListingFact(label: l.string("Status"), value: l.string("Reserved"))) }
        return facts
    }

    /// A thing's row, its one facts line: condition · shipping, or pickup with the distance · place ("Like new ·
    /// Pickup, 5 km · Garching"); "Reserved" last while it is. Unknown parts are left out.
    func itemRowFacts(language: AppLanguage = .current) -> String {
        guard let item else { return "" }
        let l = language
        let distance = item.distanceKm.map { Format.number($0, language: l) + " km" }
        let delivery: String? = switch item.shipping {
        case .yes: l.string("Shipping")
        case .pickupOnly: distance.map { l.string("Pickup, \($0)") } ?? l.string("Pickup")
        case nil: distance
        }
        return [item.condition?.title(language: l), delivery, district ?? city,
                item.reserved == true ? l.string("Reserved") : nil]
            .compactMap { $0 }.joined(separator: " · ")
    }
}

extension Listing {
    /// A filtered-out thing's line (it has no big figure there): "€480 VB · Good · Pickup, 5 km · Garching".
    func itemFactsWithPrice(language: AppLanguage = .current) -> String {
        guard let item else { return "" }
        let facts = itemRowFacts(language: language)
        return [item.priceLine(language: language), facts.isEmpty ? nil : facts].compactMap { $0 }.joined(separator: " · ")
    }
}

/// A thing's price as its row and page show it big: the amount ("€480") and the quiet word beside it ("VB",
/// "VB, €30 over"). Without an amount the word alone is the figure ("Free", "VB", "Price on request").
struct ItemPrice: Equatable {
    let amount: String?
    let label: String?
}

extension Match {
    /// The big figure of a thing's row and page; nil for a flat's match, or a thing without any price.
    func itemPrice(language: AppLanguage = .current) -> ItemPrice? {
        guard let item = listing.item else { return nil }
        let l = language
        let amount = item.price.map { Format.money($0, language: l) }
        switch item.priceKind {
        case .fixed: return amount.map { ItemPrice(amount: $0, label: nil) }
        case .negotiable:
            let over = overMax.map { l.string("VB, \(Format.money($0, language: l)) over") }
            return ItemPrice(amount: amount, label: over ?? "VB")
        case .free: return ItemPrice(amount: nil, label: l.string("Free"))
        case .auction: return ItemPrice(amount: amount, label: l.string("bid"))
        case .onRequest: return ItemPrice(amount: nil, label: l.string("Price on request"))
        case nil: return amount.map { ItemPrice(amount: $0, label: nil) }
        }
    }

    /// A thing's small line: "Kleinanzeigen · 4 min ago", or "Kleinanzeigen · Online at start" for a match the quiet
    /// check found when the hunt started (its time says nothing about when it was listed).
    func itemSourceLine(now: Date = .now, calendar: Calendar = .app, language: AppLanguage = .current) -> String {
        guard atStart else { return sourceLine(now: now, calendar: calendar) }
        return listing.sourceName + " · " + language.string("Online at start")
    }

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
            title = de ? "Braucht eine neuere App-Version" : "Needs a newer app"
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
