import Foundation

/// What fitting listings of a thing search usually ask (brief 256; the Arestemis server's brief 254,
/// `~/Arestemis/docs/API.md` → Thing asking-price records). For each Dinge search the server keeps the **asking prices**
/// of the listings that fit, within the search's own price limits, for 30 days (`GET /hunts/{id}/price-record`), and a
/// match may carry a verdict on its own price (`Match.price_verdict`). These are asking prices, not sale prices, and the
/// server's text says so. Every text comes ready in both languages (`LocalizedText`), whatever `Accept-Language` said;
/// the app picks the one it shows. A server from before them sends neither: the app then shows nothing of it.

/// A text the server sends in both languages at once.
struct LocalizedText: Codable, Equatable, Sendable {
    let en: String
    let de: String

    /// The text in the app's language; the other one if that one is empty.
    func text(_ language: AppLanguage = .current) -> String {
        let chosen = language == .german ? de : en
        return chosen.isEmpty ? (language == .german ? en : de) : chosen
    }

    init(en: String, de: String) {
        self.en = en
        self.de = de
    }

    /// A missing language reads as empty, so the other one is shown.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        en = (try? c.decodeIfPresent(String.self, forKey: .en)) ?? ""
        de = (try? c.decodeIfPresent(String.self, forKey: .de)) ?? ""
    }
}

/// One UTC calendar week's median asking price (weeks with at least 8 offers).
struct ItemPriceWeek: Codable, Equatable, Sendable {
    let weekStart: String
    let count: Int
    let median: Double

    enum CodingKeys: String, CodingKey {
        case count, median
        case weekStart = "week_start"
    }
}

/// How the weekly median moved from the oldest to the newest week shown.
enum ItemPriceTrend: String, Codable, Sendable { case up, down, steady }

/// One site's numbers, or every site's (`source` nil). Below 8 distinct offers the server sends only the count and the
/// cheapest of the last 7 days (median and the middle half are nil), and `display` says only that.
struct ItemPriceStats: Codable, Equatable, Sendable {
    let source: Source?
    let count: Int
    var median: Double? = nil
    var q25: Double? = nil
    var q75: Double? = nil
    var cheapest7d: Double? = nil
    var weeklyMedians: [ItemPriceWeek] = []
    var trend: ItemPriceTrend? = nil
    /// The server's short line: count · usual range · cheapest of the last 7 days · trend, as available.
    let display: LocalizedText

    enum CodingKeys: String, CodingKey {
        case source, count, median, q25, q75, trend, display
        case cheapest7d = "cheapest_7d", weeklyMedians = "weekly_medians"
    }

    init(source: Source?, count: Int, median: Double? = nil, q25: Double? = nil, q75: Double? = nil,
         cheapest7d: Double? = nil, weeklyMedians: [ItemPriceWeek] = [], trend: ItemPriceTrend? = nil,
         display: LocalizedText) {
        self.source = source
        self.count = count
        self.median = median
        self.q25 = q25
        self.q75 = q75
        self.cheapest7d = cheapest7d
        self.weeklyMedians = weeklyMedians
        self.trend = trend
        self.display = display
    }

    /// The count and the line are the contract's core; the numbers around them are read leniently (an unknown trend
    /// is none, missing weeks are none).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        source = try c.decodeIfPresent(Source.self, forKey: .source)
        count = try c.decode(Int.self, forKey: .count)
        median = (try? c.decodeIfPresent(Double.self, forKey: .median)) ?? nil
        q25 = (try? c.decodeIfPresent(Double.self, forKey: .q25)) ?? nil
        q75 = (try? c.decodeIfPresent(Double.self, forKey: .q75)) ?? nil
        cheapest7d = (try? c.decodeIfPresent(Double.self, forKey: .cheapest7d)) ?? nil
        weeklyMedians = (try? c.decodeIfPresent([ItemPriceWeek].self, forKey: .weeklyMedians)) ?? []
        trend = (try? c.decodeIfPresent(ItemPriceTrend.self, forKey: .trend)) ?? nil
        display = try c.decode(LocalizedText.self, forKey: .display)
    }

    /// The middle half of the asking prices ("usually"), once there are enough of them.
    var usual: ClosedRange<Double>? {
        guard let q25, let q75, q25 <= q75 else { return nil }
        return q25...q75
    }
}

/// `GET /hunts/{id}/price-record`: a thing search's asking prices of the last 30 days, overall and per site (the sites
/// with any in that window, in the server's order).
struct ItemPriceSummary: Codable, Equatable, Sendable {
    let huntID: Int
    var currency: String = "EUR"
    var days: Int = 30
    let since: String
    let until: String
    let overall: ItemPriceStats
    var sites: [ItemPriceStats] = []
    /// Shown beside the numbers: asking prices of fitting listings within the search's limits, no fees, not sale prices.
    let note: LocalizedText

    enum CodingKeys: String, CodingKey {
        case currency, days, since, until, overall, sites, note
        case huntID = "hunt_id"
    }

    init(huntID: Int, currency: String = "EUR", days: Int = 30, since: String, until: String, overall: ItemPriceStats,
         sites: [ItemPriceStats] = [], note: LocalizedText) {
        self.huntID = huntID
        self.currency = currency
        self.days = days
        self.since = since
        self.until = until
        self.overall = overall
        self.sites = sites
        self.note = note
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        huntID = try c.decode(Int.self, forKey: .huntID)
        currency = (try? c.decodeIfPresent(String.self, forKey: .currency)) ?? "EUR"
        days = (try? c.decodeIfPresent(Int.self, forKey: .days)) ?? 30
        since = try c.decode(String.self, forKey: .since)
        until = try c.decode(String.self, forKey: .until)
        overall = try c.decode(ItemPriceStats.self, forKey: .overall)
        sites = try c.decodeIfPresent([ItemPriceStats].self, forKey: .sites) ?? []
        note = try c.decode(LocalizedText.self, forKey: .note)
    }
}

/// `Match.price_verdict`: how a listing's asking price compares with at least 8 other fitting offers of its search.
/// Most listings have none (their price lies in the usual range, or there are too few others).
struct ItemPriceVerdict: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case cheap, expensive
        /// Below the usual range's lower fence: often bait, a scam or a mismatch, so it says "check carefully".
        case unusuallyCheap = "unusually_cheap"
    }

    let verdict: Kind
    let price: Double
    var currency: String = "EUR"
    let comparisonCount: Int
    let q25: Double
    let q75: Double
    /// "Cheap" / "Günstig", "Expensive" / "Teuer", "Unusually cheap – check carefully" / "Ungewöhnlich günstig – genau
    /// prüfen".
    let label: LocalizedText
    /// The label with the usual range: "Cheap: usually €23.50–€30.00 asked within your search limits".
    let display: LocalizedText
    let note: LocalizedText

    enum CodingKeys: String, CodingKey {
        case verdict, price, currency, q25, q75, label, display, note
        case comparisonCount = "comparison_count"
    }
}
