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

    /// "16 shops" / "16 Shops": sellers with an offer (the card's count, `PriceState.offers`).
    static func shops(_ count: Int, language: AppLanguage = .current) -> String {
        language.string("\(count) shops")
    }

    /// The lines under the product once the server found it, as the sketch's two: "Found: Apple AirPods Max (2nd gen.)"
    /// over "in 2 shops, from €215.00" ("Gefunden: …", "in 2 Shops, ab 215,00 €"), or "no offer yet" when its first look
    /// found none. The shops are the sellers among its offers (a comparison site lists several), counted once each.
    static func found(_ preview: ProductPreview, off: [String] = [], language: AppLanguage = .current) -> FoundLines {
        let name = WatchText.keepingAmounts(preview.identity.name.trimmingCharacters(in: .whitespacesAndNewlines))
        let offers = preview.offers.filter { !off.contains($0.source) }
        let priced = offers.filter { $0.selectedTotal != nil }
        let found = language.string("Found: \(name)")
        guard let cheapest = priced.first, let price = cheapest.selectedTotal else {
            return FoundLines(title: found, detail: offers.isEmpty ? language.string("no offer yet")
                : language.string("Total unknown"))
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
    static func cheapest(_ preview: ProductPreview, off: [String] = []) -> (price: Double, currency: String?)? {
        cheapest(preview.offers, off: off)
    }

    static func cheapest(_ offers: [Offer], off: [String]) -> (price: Double, currency: String?)? {
        offers.first { !off.contains($0.source) && $0.selectedTotal != nil }
            .flatMap { offer in offer.selectedTotal.map { ($0, offer.currency) } }
    }

    /// The quiet line under the product's preview: "Looks on 9 sites" / "Sucht auf 9 Seiten", the sites switched on
    /// (shops, price comparison sites and marketplaces). "Shops" always means sellers with an offer (the preview's
    /// "in 16 Shops", the card, the offers list); the places it looks are sites, as "Where it looks" calls them.
    static func looksIn(_ count: Int, includeUsed: Bool = false, language: AppLanguage = .current) -> String {
        includeUsed ? language.string("New goods · \(count) sites") : language.string("Looks on \(count) sites")
    }

    /// "9 sites" / "9 Seiten": how many sites it looks on, beside "Where it looks" on the monitor's page.
    static func sites(_ count: Int, includeUsed: Bool = false, language: AppLanguage = .current) -> String {
        includeUsed ? language.string("New goods · \(count) sites") : language.string("\(count) sites")
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
    static func onCount(_ sites: [PriceSite], off: [String], delivery: Delivery = .shipping) -> Int {
        sites.count { !off.contains($0.id) && $0.serves(delivery) }
    }

    /// A site switched on or off: the new `sources_off` (in the sites' order, ids no longer listed kept), or nil when it
    /// would switch off the last site that is on (a monitor that looks nowhere finds nothing).
    static func switched(_ site: String, on: Bool, off: [String], sites: [PriceSite],
                         delivery: Delivery = .shipping) -> [String]? {
        guard sites.first(where: { $0.id == site })?.serves(delivery) != false else { return nil }
        var off = off
        if on {
            off.removeAll { $0 == site }
            return off
        }
        guard !off.contains(site) else { return off }
        guard onCount(sites, off: off, delivery: delivery) > 1 || !sites.contains(where: { $0.id == site }) else { return nil }
        off.append(site)
        let order = sites.map(\.id)
        return off.sorted { (order.firstIndex(of: $0) ?? .max) < (order.firstIndex(of: $1) ?? .max) }
    }

    static func detail(_ site: PriceSite, delivery: Delivery, language: AppLanguage = .current) -> String? {
        let state: String?
        if site.serves(delivery) {
            state = EverywhereWords.state(site.state, language: language)
        } else if site.delivery == .pickup {
            state = language.string("Pickup only")
        } else {
            state = language.string("Shipping only")
        }
        let parts = [site.isComparison ? language.string("Price comparison") : nil, state].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
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
    /// Keep the listing grouping, with distinct pickup stores and handovers visible for the same seller.
    static func shown(_ offers: [Offer], off: [String]) -> [Offer] {
        var seen: Set<String> = []
        return offers.filter { !off.contains($0.source) }.filter { offer in
            let key = offer.shop.trimmingCharacters(in: .whitespaces).lowercased()
                + "|" + offer.fulfillment.rawValue + "|" + (offer.pickupMethod?.rawValue ?? "") + "|" + (offer.store?.id ?? "")
            return seen.insert(key).inserted
        }
    }

    /// Find the quote supplying PriceState, without independently choosing a cheapest price or another URL.
    static func selected(_ offers: [Offer], state: PriceState?, off: [String]) -> Offer? {
        guard let state, let price = state.price else { return nil }
        return shown(offers, off: off).first {
            $0.selectedTotal == price && $0.currency == state.currency
                && ($0.shop == state.host || $0.store?.name == state.host || title($0) == state.host)
        }
    }

    static func title(_ offer: Offer) -> String {
        guard offer.fulfillment == .pickup, let store = offer.store else { return offer.shop }
        return [store.name, HuntText.text(store.city)].compactMap { $0 }.joined(separator: ", ")
    }

    static func handover(_ offer: Offer, language: AppLanguage = .current) -> String? {
        switch offer.fulfillment {
        case .shipping: language.string("Shipping")
        case .pickup: language.string("Pickup")
        case .unknown: nil
        }
    }

    static func amount(_ offer: Offer, language: AppLanguage = .current) -> String {
        offer.selectedTotal.map { PriceWords.money($0, currency: offer.currency, language: language) }
            ?? language.string("Total unknown")
    }

    /// How many rows show before "+ N more shops".
    static let firstRows = 5

    /// An offer's quiet line: its availability, the shipping when known, and the comparison site it was found on when
    /// the shop is another ("in stock · shipping €4.99 · via billiger.de" / "lieferbar · Versand 4,99 € · über
    /// billiger.de").
    static func line(_ offer: Offer, language: AppLanguage = .current) -> String? {
        var parts: [String] = []
        if let price = offer.price, price.isFinite {
            parts.append(PriceWords.money(price, currency: offer.currency, language: language))
        }
        switch offer.fulfillment {
        case .shipping:
            if let shipping = offer.shipping, shipping >= 0, shipping.isFinite {
                parts.append(language.string("shipping \(PriceWords.limit(shipping, language: language))"))
            } else {
                parts.append(language.string("Shipping unknown"))
            }
        case .pickup:
            switch offer.pickupMethod {
            case .inStore?: parts.append(language.string("In store"))
            case .clickCollect?: parts.append(language.string("Click & Collect"))
            default: parts.append(language.string("Pickup"))
            }
            if let fee = offer.pickupFee, fee >= 0, fee.isFinite {
                parts.append(language.string("fee \(PriceWords.limit(fee, language: language))"))
            } else {
                parts.append(language.string("Fee unknown"))
            }
            if let distance = offer.store?.distanceKm, distance.isFinite, distance >= 0 {
                parts.append(Format.number(distance, language: language) + " km")
            }
        case .unknown: break
        }
        if let word = availability(offer.availability, fulfillment: offer.fulfillment, language: language) { parts.append(word) }
        let site = offer.sourceName.trimmingCharacters(in: .whitespaces)
        if !site.isEmpty, site.lowercased() != offer.shop.trimmingCharacters(in: .whitespaces).lowercased() {
            parts.append(language.string("via \(site)"))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// Pickup stock uses a separate translation from shipping availability.
    static func availability(_ value: Availability, fulfillment: Fulfillment?, language: AppLanguage = .current) -> String? {
        if fulfillment == .pickup && value == .inStock { return language.string(LocalizedStringResource("pickup.in_stock", defaultValue: "in stock")) }
        return PriceWords.availability(value, language: language)
    }

    /// An unreadable source may retain its last successful quote. Only that quote's real timestamp belongs here.
    static func lastConfirmed(_ offer: Offer, sites: [PriceSite], timeZone: TimeZone = .current, language: AppLanguage = .current) -> String? {
        guard sites.contains(where: { $0.id == offer.source && $0.state == .unreadable }) else { return nil }
        guard let checked = offer.checked.flatMap(Timestamp.parse) else { return language.string("Last confirmed") }
        let style = Date.FormatStyle(date: .abbreviated, time: .shortened, locale: language.locale, timeZone: timeZone)
        let time = checked.formatted(style)
        return language.string("Last confirmed · \(time)")
    }

    /// "+ 6 more shops" / "+ 6 weitere Shops".
    static func more(_ count: Int, language: AppLanguage = .current) -> String {
        language.string("+ \(count) more shops")
    }
}
