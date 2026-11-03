import Foundation

/// What a Preismonitor "Überall" shows (brief 157; the server's brief 154, `~/Arestemis/docs/API.md` → Price monitors
/// everywhere): one product watched on every site that sells it. Decided here, so the screens only lay it out: the
/// preview's line, the quiet line about the sites it looks in, the sites in their order with a word for each state, the
/// switches' rule, the offers cheapest first with their quiet line, and the start of a "Shop vorschlagen" message.

/// The words of an everywhere monitor.
enum EverywhereWords {
    /// The form's two modes, as the segmented switch says them: "One shop" | "Everywhere" ("Ein Shop" | "Überall").
    static func mode(_ mode: PriceSearch.Mode, language: AppLanguage = .current) -> String {
        switch mode {
        case .page: language.string("One shop")
        case .everywhere: language.string("Everywhere")
        }
    }

    /// "11 shops" / "11 Shops".
    static func shops(_ count: Int, language: AppLanguage = .current) -> String {
        language.string("\(count) shops")
    }

    /// The lines under the product once the server found it, as the sketch's two: "Found: Apple AirPods Max (2nd gen.)"
    /// over "in 2 shops, from €215.00" ("Gefunden: …", "in 2 Shops, ab 215,00 €"), or "no offer yet" when its first look
    /// found none. The shops are the sellers among its offers (a comparison site lists several), counted once each.
    static func found(_ preview: ProductPreview, language: AppLanguage = .current) -> FoundLines {
        let name = WatchText.keepingAmounts(preview.identity.name.trimmingCharacters(in: .whitespacesAndNewlines))
        let priced = OfferList.sorted(preview.offers).filter { $0.price != nil }
        let found = language.string("Found: \(name)")
        guard let cheapest = priced.first, let price = cheapest.price else {
            return FoundLines(title: found, detail: language.string("no offer yet"))
        }
        let sellers = Set(priced.map { $0.shop.trimmingCharacters(in: .whitespaces).lowercased() }).count
        let from = PriceWords.money(price, currency: cheapest.currency, language: language)
        return FoundLines(title: found, detail: language.string("in \(sellers) shops, from \(from)"))
    }

    /// The preview's two lines; `text` both in one ("Found: … · in 2 shops, from €215.00"), as VoiceOver reads them.
    struct FoundLines: Equatable {
        let title: String
        let detail: String
        var text: String { title + " · " + detail }
    }

    /// The cheapest price the preview found in euros, for the alarm's limit.
    static func cheapest(_ preview: ProductPreview) -> (price: Double, currency: String?)? {
        OfferList.sorted(preview.offers).first { $0.price != nil }.flatMap { offer in offer.price.map { ($0, offer.currency) } }
    }

    /// The quiet line under the product's preview and on the monitor's page: "Looks in 9 shops" / "Sucht in 9 Shops";
    /// the sites switched on, which include price comparison sites and marketplaces (Patrik's sketch counts them as
    /// shops).
    static func looksIn(_ count: Int, language: AppLanguage = .current) -> String {
        language.string("Looks in \(count) shops")
    }

    /// The card's word for the cheapest offer's shop, beside its price: "at Amazon" / "bei Amazon".
    static func at(_ shop: String, language: AppLanguage = .current) -> String {
        language.string("at \(shop)")
    }

    /// A site's state on "Where it looks": "has it", "checking", "doesn't have it", "can't be read now"; nil for a state
    /// this build does not know.
    static func state(_ state: PriceSite.State, language: AppLanguage = .current) -> String? {
        switch state {
        case .hasIt: language.string("has it")
        case .checking: language.string("checking")
        case .notFound: language.string("doesn't have it")
        case .unreadable: language.string("can't be read now")
        case .unknown: nil
        }
    }

    /// The line over the sites: "Every site Arestemis checks for “Apple AirPods Max”. Switch off any you would never
    /// buy from." / "Jede Seite, die Arestemis für „…“ prüft. Schalte aus, wo du nie kaufen würdest."
    static func sitesIntro(product: String?, language: AppLanguage = .current) -> String {
        guard let product = HuntText.text(product) else {
            return language.string("Every site Arestemis checks. Switch off any you would never buy from.")
        }
        return language.string("Every site Arestemis checks for “\(product)”. Switch off any you would never buy from.")
    }
}

/// An everywhere monitor's sites, as "Where it looks" shows them and the switches change them.
enum PriceSites {
    /// The ones that have the product first, then those still being checked, those that cannot be read now (or are in a
    /// state this build does not know), and those that don't have it; the server's order within each.
    static func ordered(_ sites: [PriceSite]) -> [PriceSite] {
        func rank(_ state: PriceSite.State) -> Int {
            switch state {
            case .hasIt: 0
            case .checking: 1
            case .unreadable, .unknown: 2
            case .notFound: 3
            }
        }
        return sites.enumerated().sorted { a, b in
            rank(a.element.state) == rank(b.element.state) ? a.offset < b.offset
                : rank(a.element.state) < rank(b.element.state)
        }.map(\.element)
    }

    /// How many of the sites are switched on.
    static func onCount(_ sites: [PriceSite], off: [String]) -> Int {
        sites.count { !off.contains($0.id) }
    }

    /// A site switched on or off: the new `sources_off` (in the sites' order, ids no longer listed kept), or nil when it
    /// would switch off the last site that is on (a monitor that looks nowhere finds nothing).
    static func switched(_ site: String, on: Bool, off: [String], sites: [PriceSite]) -> [String]? {
        var off = off
        if on {
            off.removeAll { $0 == site }
            return off
        }
        guard !off.contains(site) else { return off }
        guard onCount(sites, off: off) > 1 || !sites.contains(where: { $0.id == site }) else { return nil }
        off.append(site)
        let order = sites.map(\.id)
        return off.sorted { (order.firstIndex(of: $0) ?? .max) < (order.firstIndex(of: $1) ?? .max) }
    }

    /// The line when the last site is not let go.
    static func lastSiteLine(language: AppLanguage = .current) -> String {
        language.string("At least one site stays on.")
    }

    /// "Suggest a shop": Settings' Contact & support form, opened as an idea or wish with its text started, so the
    /// person types the shop's name.
    static func suggestion(language: AppLanguage = .current) -> (kind: SupportKind, text: String) {
        (.idea, language.string("Suggest a shop: "))
    }
}

/// An everywhere monitor's offers, as its page lists them.
enum OfferList {
    /// Cheapest first, as the server sorts them: euros before other currencies, priced before unpriced, then by price,
    /// shop and site.
    static func sorted(_ offers: [Offer]) -> [Offer] {
        offers.sorted { a, b in
            let aKey = (a.currency?.uppercased() ?? "EUR") != "EUR", bKey = (b.currency?.uppercased() ?? "EUR") != "EUR"
            if aKey != bKey { return !aKey }
            if (a.price == nil) != (b.price == nil) { return a.price != nil }
            if let ap = a.price, let bp = b.price, ap != bp { return ap < bp }
            if a.shop != b.shop { return a.shop.localizedStandardCompare(b.shop) == .orderedAscending }
            return a.source < b.source
        }
    }

    /// What the page lists: the offers of the sites switched on, cheapest first, one per shop (its cheapest: a shop that
    /// two comparison sites list shows once, as the sketch's list of shops).
    static func shown(_ offers: [Offer], off: [String]) -> [Offer] {
        var seen: Set<String> = []
        return sorted(offers.filter { !off.contains($0.source) }).filter { offer in
            seen.insert(offer.shop.trimmingCharacters(in: .whitespaces).lowercased()).inserted
        }
    }

    /// How many rows show before "+ N more shops".
    static let firstRows = 5

    /// An offer's quiet line: its availability, the shipping when known, and the comparison site it was found on when
    /// the shop is another ("in stock · shipping €4.99 · via billiger.de" / "lieferbar · Versand 4,99 € · über
    /// billiger.de").
    static func line(_ offer: Offer, language: AppLanguage = .current) -> String? {
        var parts: [String] = []
        if let word = PriceWords.availability(offer.availability, language: language) { parts.append(word) }
        if let shipping = offer.shipping, shipping >= 0, shipping.isFinite {
            parts.append(language.string("shipping \(PriceWords.limit(shipping, language: language))"))
        }
        let site = offer.sourceName.trimmingCharacters(in: .whitespaces)
        if !site.isEmpty, site.lowercased() != offer.shop.trimmingCharacters(in: .whitespaces).lowercased() {
            parts.append(language.string("via \(site)"))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// "+ 6 more shops" / "+ 6 weitere Shops".
    static func more(_ count: Int, language: AppLanguage = .current) -> String {
        language.string("+ \(count) more shops")
    }
}
