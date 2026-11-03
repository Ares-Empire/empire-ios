import Foundation

/// What a price monitor's card, its page, its chart and its alarms show (brief 137), decided here so the screens only
/// lay it out: the money to the cent in the shop's currency, the availability's word, what the monitor does ("Alarm
/// under €450", "History only"), the card's lines per read state, an alarm's sentence, the preview's line, the limit an
/// alarm starts with, and the chart's stretches.

/// The words of a monitor and its alarms.
enum PriceWords {
    /// A price to the cent in its currency: "€449.00" / "449,00 €"; another currency as the app's locale writes it
    /// ("US$12.99" / "12,99 $").
    static func money(_ amount: Double, currency: String? = "EUR", language: AppLanguage = .current) -> String {
        let code = currency.map { $0.trimmingCharacters(in: .whitespaces).uppercased() }.flatMap { $0.isEmpty ? nil : $0 }
            ?? "EUR"
        if code == "EUR" { return Format.cents(amount, language: language) }
        return amount.formatted(.currency(code: code).precision(.fractionLength(2)).locale(language.locale))
    }

    /// An alarm's limit: whole euros when it is whole ("€450" / "450 €"), else to the cent.
    static func limit(_ euros: Double, language: AppLanguage = .current) -> String {
        euros.rounded() == euros ? Format.money(euros, language: language) : Format.cents(euros, language: language)
    }

    /// A window of the chart: "30 days" / "30 Tage".
    static func window(_ days: Int, language: AppLanguage = .current) -> String {
        language.string("\(days) days")
    }

    /// "in stock" / "lieferbar", "out of stock" / "nicht lieferbar", "preorder" / "vorbestellbar"; nil when unknown.
    static func availability(_ availability: Availability, language: AppLanguage = .current) -> String? {
        switch availability {
        case .inStock: language.string("in stock")
        case .outOfStock: language.string("out of stock")
        case .preorder: language.string("preorder")
        case .unknown: nil
        }
    }

    /// What the monitor does, the quiet line's end: "Alarm under €450", "Alarm when back in stock", "Alarm under €450 or
    /// back in stock"; without an alarm "History only".
    static func mode(_ search: PriceSearch, language: AppLanguage = .current) -> String {
        guard let alarm = search.alarm else { return language.string("History only") }
        let below = alarm.below.flatMap { $0 > 0 ? limit($0, language: language) : nil }
        switch (below, alarm.backInStock) {
        case let (below?, true): return language.string("Alarm under \(below) or back in stock")
        case let (below?, false): return language.string("Alarm under \(below)")
        case (nil, true): return language.string("Alarm when back in stock")
        case (nil, false): return language.string("Alarm")
        }
    }

    /// A price alarm's sentence (its row and the push say it): "Nintendo Switch 2: €449.00 (was €483.99)" /
    /// "Nintendo Switch 2: 449,00 € (vorher 483,99 €)", or "Nintendo Switch 2 is back in stock" / "… ist wieder
    /// lieferbar". An everywhere monitor's names the shop of the cheapest offer (`shop`, brief 157): "AirPods Max:
    /// €449.00 at MediaMarkt (was €483.99)" / "… 449,00 € bei MediaMarkt (vorher …)", "… is back in stock at
    /// MediaMarkt" / "… ist bei MediaMarkt wieder lieferbar".
    static func alarm(product: String, change: PriceChange, shop: String? = nil,
                      language: AppLanguage = .current) -> String {
        let product = product.trimmingCharacters(in: .whitespacesAndNewlines)
        let shop = HuntText.text(shop)
        if change.kind == .back {
            guard let shop else { return language.string("\(product) is back in stock") }
            return language.string("\(product) is back in stock at \(shop)")
        }
        let new = money(change.new, currency: change.currency, language: language)
        let old = change.old.map { money($0, currency: change.currency, language: language) }
        switch (shop, old) {
        case let (shop?, old?): return language.string("\(product): \(new) at \(shop) (was \(old))")
        case let (shop?, nil): return language.string("\(product): \(new) at \(shop)")
        case let (nil, old?): return language.string("\(product): \(new) (was \(old))")
        case (nil, nil): return "\(product): \(new)"
        }
    }

    /// Beside an alarm's new price on its page: "was €483.99" / "vorher 483,99 €", or "back in stock" / "wieder
    /// lieferbar" for a product that came back.
    static func alarmLabel(_ change: PriceChange, language: AppLanguage = .current) -> String {
        if change.kind == .back { return language.string("back in stock") }
        guard let old = change.old else { return availability(change.availability, language: language) ?? "" }
        return language.string("was \(money(old, currency: change.currency, language: language))")
    }

    /// The line under the product's link once the server read it: "Found: NINTENDO Switch 2 · €483.99 · in stock".
    static func found(_ preview: PricePreview, language: AppLanguage = .current) -> String {
        let parts = [money(preview.price, currency: preview.currency, language: language),
                     availability(preview.availability, language: language)].compactMap { $0 }
        let product = WatchText.keepingAmounts(preview.product.trimmingCharacters(in: .whitespacesAndNewlines))
        return ([language.string("Found: \(product)")] + parts).joined(separator: " · ")
    }
}

/// The limit an alarm starts with: a little under the price found (about 5 % under, rounded down to a round step), so
/// "€483.99" offers "€450". Nil without a price, for a price in another currency, and when nothing round is left under it.
enum PriceLimit {
    static func suggested(under price: Double?, currency: String? = "EUR") -> Double? {
        guard let price, price > 0, price.isFinite, (currency ?? "EUR").uppercased() == "EUR" else { return nil }
        let step: Double = price < 20 ? 1 : price < 100 ? 5 : price < 1000 ? 10 : 50
        let limit = (price * 0.95 / step).rounded(.down) * step
        return limit > 0 && limit < price ? limit : nil
    }
}

/// A monitor's lines on its card and its page (under its name and the quiet line): the price large and the
/// availability's word while the page reads well; else one quiet line, as a watch's (reading, or the server's note on
/// why it cannot be read), never an alarm colour; then when it was last checked. An everywhere monitor's (brief 157):
/// the cheapest price with its shop beside it ("€215.00  at Amazon · in stock"), its own words while it looks or
/// cannot read the sites, and "No shop offers it right now." when none does.
struct PriceCardText: Equatable {
    /// "€449.00", while the page reads well.
    let price: String?
    /// "at Amazon", beside the price: the shop of an everywhere monitor's cheapest offer.
    let shop: String?
    /// "in stock", beside the price.
    let availability: String?
    /// A quiet line instead of the price: "Reading the page…", or the server's note (a blocked page adds that saving
    /// tries again). On the page also the server's note while the page reads well (how it is read: "Read with a
    /// browser, every 30 minutes.").
    let note: String?
    /// "Checked 4 min ago"; nil before the first read.
    let checked: String?

    /// `state`: the card's product state; nil for a monitor the overview has not sent yet (just made), read as waiting.
    /// `compact`: the Hunts list's card, which leaves out a note while the page reads well. `everywhere`: the monitor
    /// looks for its product on every site (its price is the cheapest offer's, its host that offer's shop).
    init(_ state: PriceState?, compact: Bool, everywhere: Bool = false, now: Date = .now, calendar: Calendar = .app,
         language: AppLanguage = .current) {
        let l = language
        let note = HuntText.text(state?.note)
        let cannotRead = everywhere ? l.string("The shops can't be read right now.")
            : l.string("The page can't be read right now.")
        var shop: String?
        switch state?.read ?? .waiting {
        case .waiting:
            price = nil
            availability = nil
            self.note = everywhere ? l.string("Looking in the shops…") : l.string("Reading the page…")
        case .ok:
            price = state?.price.map { PriceWords.money($0, currency: state?.currency, language: l) }
            availability = state.flatMap { PriceWords.availability($0.availability, language: l) }
            if everywhere, price != nil { shop = HuntText.text(state?.host).map { EverywhereWords.at($0, language: l) } }
            if everywhere, price == nil {
                self.note = l.string("No shop offers it right now.")
            } else {
                self.note = compact ? nil : note
            }
        case .unreadable:
            price = nil
            availability = nil
            self.note = note ?? (everywhere ? cannotRead : l.string("This page shows no single product with a price."))
        case .failing:
            price = nil
            availability = nil
            self.note = note ?? cannotRead
        case .blocked:
            price = nil
            availability = nil
            self.note = (note ?? cannotRead) + " " + l.string("Saving it again tries again.")
        case .unknown:
            price = nil
            availability = nil
            self.note = note
        }
        self.shop = shop
        checked = Format.relative(state?.checked, now: now, calendar: calendar, language: l).map { l.string("Checked \($0)") }
    }
}

/// A monitor's history as the chart draws it: the points of one currency (the newest point's), oldest first, as steps (a
/// price holds until the next read changes it), in stretches of the same availability, so the stretches out of stock can
/// be drawn dashed; the price range to show, with room for the alarm's limit; the lowest and highest price named under
/// it (the server's, in euros).
struct PriceChart: Equatable {
    struct Point: Equatable, Identifiable {
        let id: Int
        let date: Date
        let price: Double
        let availability: Availability
        var outOfStock: Bool { availability == .outOfStock }
    }

    /// Points in a row with one availability (out of stock or not), ending where the next stretch begins, so the steps
    /// join.
    struct Stretch: Equatable, Identifiable {
        let id: Int
        let outOfStock: Bool
        let points: [Point]
    }

    let points: [Point]
    let stretches: [Stretch]
    let currency: String
    /// The alarm's limit, while it is in the chart's currency (euros).
    let limit: Double?
    /// The prices the plot spans: the points' and the limit, with a little room above and below.
    let range: ClosedRange<Double>
    /// The time the plot spans: the window's start (or the first point) to the newest point.
    let span: ClosedRange<Date>
    let low: Double?
    let high: Double?

    var newest: Point? { points.last }
    var isEmpty: Bool { points.isEmpty }
    var hasOutOfStock: Bool { points.contains(where: \.outOfStock) }

    /// `limit`: the alarm's limit in euros. `days`: the window asked for (the plot starts there when the points reach
    /// back so far; a monitor younger than that starts at its first point).
    init(_ prices: Prices, limit: Double? = nil, days: Int? = nil, now: Date = .now) {
        let currency = prices.points.last?.currency ?? "EUR"
        var points: [Point] = []
        for point in prices.points where point.currency == currency {
            guard let date = Timestamp.parse(point.at), point.price.isFinite else { continue }
            points.append(Point(id: points.count, date: date, price: point.price, availability: point.availability))
        }
        points.sort { $0.date == $1.date ? $0.id < $1.id : $0.date < $1.date }
        self.points = points
        self.currency = currency
        self.limit = currency == "EUR" ? limit.flatMap { $0 > 0 ? $0 : nil } : nil
        low = prices.low
        high = prices.high

        var stretches: [Stretch] = []
        var start = 0
        for index in points.indices where index == points.count - 1 || points[index + 1].outOfStock != points[start].outOfStock {
            // This stretch runs to the next one's first point (its price holds until then), so the steps join.
            let end = min(index + 1, points.count - 1)
            stretches.append(Stretch(id: stretches.count, outOfStock: points[start].outOfStock,
                                     points: Array(points[start...end])))
            start = index + 1
        }
        self.stretches = stretches

        let prices = points.map(\.price) + [self.limit].compactMap { $0 }
        let lowest = prices.min() ?? 0, highest = prices.max() ?? 1
        let room = max((highest - lowest) * 0.12, highest * 0.02, 1)
        range = max(0, lowest - room)...(highest + room)

        let last = points.last?.date ?? now
        let windowStart = days.map { last.addingTimeInterval(-Double($0) * 86_400) }
        let first = points.first?.date ?? last
        let from = min(windowStart.map { max($0, first) } ?? first, last.addingTimeInterval(-3600))
        span = from...last
    }

    /// "Lowest €449.00 · Highest €529.00"; nil while the server names neither (no points in euros).
    func extremes(language: AppLanguage = .current) -> String? {
        let parts = [low.map { language.string("Lowest \(PriceWords.money($0, language: language))") },
                     high.map { language.string("Highest \(PriceWords.money($0, language: language))") }]
            .compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// The time axis's label: the day within 90 days ("4 Oct" / "4. Okt."), the month alone over a year ("Nov").
    static func dayLabel(_ date: Date, days: Int, calendar: Calendar = .app, language: AppLanguage = .current) -> String {
        let style = Date.FormatStyle(date: .omitted, time: .omitted, locale: language.locale, calendar: calendar,
                                     timeZone: calendar.timeZone)
        return days > 120 ? date.formatted(style.month(.abbreviated)) : date.formatted(style.day().month(.abbreviated))
    }

    /// The price axis's label, whole: "€450" / "450 €".
    static func axisPrice(_ value: Double, currency: String, language: AppLanguage = .current) -> String {
        currency == "EUR" ? Format.money(value, language: language)
            : value.formatted(.currency(code: currency).precision(.fractionLength(0)).locale(language.locale))
    }

    /// What VoiceOver says of a point: "€449.00, in stock".
    func spoken(_ point: Point, language: AppLanguage = .current) -> String {
        ([PriceWords.money(point.price, currency: currency, language: language)]
            + [PriceWords.availability(point.availability, language: language)].compactMap { $0 })
            .joined(separator: ", ")
    }
}

extension Match {
    /// A price alarm's sentence, from its change (the server's own sentence, `reason`, only when there is none).
    /// `shop`: the shop an everywhere monitor's alarm names (`ArestemisStore.alarmShop(of:)`).
    func priceTitle(shop: String? = nil, language: AppLanguage = .current) -> String {
        guard let change = listing.priceChange else { return WatchText.keepingAmounts(reason) }
        return PriceWords.alarm(product: listing.title, change: change, shop: shop, language: language)
    }

    /// An alarm's small line: "www.mediamarkt.de · 4 min ago".
    func priceSourceLine(now: Date = .now, calendar: Calendar = .app, language: AppLanguage = .current) -> String {
        [listing.sourceName, Format.relative(found, now: now, calendar: calendar, language: language)]
            .compactMap { $0 }.joined(separator: " · ")
    }
}
