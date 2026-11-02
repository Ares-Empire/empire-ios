import Foundation

/// Price monitors (brief 134 on the server, 137 here): a hunt of kind `price` reads one product page in one shop every
/// so often. It records the price and the availability as a history, raises an alarm when the price falls under a limit
/// or the product is back in stock, or both; at least one of the two is on. The server reads the shop's page (its
/// product data first, the AI only where it has none) and decides; the app shows what it read and never parses a page.

/// `PriceSearch`: the product page's address (the watch's rules), the history and the alarm switches, how often.
struct PriceSearch: Codable, Equatable, Sendable {
    var url: String
    /// Records the price and the availability at every read, for the curve.
    var history: Bool
    /// The alarm and its conditions; nil while the alarm is off.
    var alarm: Alarm?
    /// Minutes between reads: one of `WatchSearch.everyChoices`.
    var every: Int

    struct Alarm: Codable, Equatable, Sendable {
        /// A limit in euros: the alarm rings when the price falls to or under it. Nil: no price condition.
        var below: Double?
        /// The alarm rings when the product is back in stock (or can be preordered again).
        var backInStock: Bool

        enum CodingKeys: String, CodingKey {
            case below
            case backInStock = "back_in_stock"
        }

        /// `below: null` is sent, not left out.
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(below, forKey: .below)
            try c.encode(backInStock, forKey: .backInStock)
        }

        /// Lenient: a missing condition is off.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            below = try c.decodeIfPresent(Double.self, forKey: .below)
            backInStock = try c.decodeIfPresent(Bool.self, forKey: .backInStock) ?? false
        }

        init(below: Double? = nil, backInStock: Bool = false) {
            self.below = below
            self.backInStock = backInStock
        }

        /// What the server accepts: a positive limit, or back in stock.
        var isComplete: Bool { (below.map { $0 > 0 && $0.isFinite } ?? false) || backInStock }
    }

    init(url: String, history: Bool, alarm: Alarm?, every: Int = WatchSearch.defaultEvery) {
        self.url = url
        self.history = history
        self.alarm = alarm
        self.every = every
    }

    /// Lenient as the server's defaults: no history, no alarm, every hour.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        url = try c.decode(String.self, forKey: .url)
        history = try c.decodeIfPresent(Bool.self, forKey: .history) ?? false
        alarm = try c.decodeIfPresent(Alarm.self, forKey: .alarm)
        every = try c.decodeIfPresent(Int.self, forKey: .every) ?? WatchSearch.defaultEvery
    }

    /// The whole search, `alarm: null` included, as `PUT` replaces it.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(url, forKey: .url)
        try c.encode(history, forKey: .history)
        try c.encode(alarm, forKey: .alarm)
        try c.encode(every, forKey: .every)
    }

    enum CodingKeys: String, CodingKey { case url, history, alarm, every }

    /// The server's rule: the history, the alarm or both; an alarm says when it rings.
    var isComplete: Bool { (history || alarm != nil) && (alarm?.isComplete ?? true) }

    /// The product's page to open in the browser ("Open in shop"): the link as saved, read as https without a scheme, as
    /// the server reads it; nil for anything but a web address.
    var shopURL: URL? {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed.contains("://") ? trimmed : "https://" + trimmed),
              let scheme = url.scheme?.lowercased(), ["https", "http"].contains(scheme), url.host() != nil else { return nil }
        return url
    }
}

/// Whether a product can be bought now. A value this build does not know reads as unknown.
enum Availability: String, Codable, Equatable, Sendable {
    case inStock = "in_stock"
    case outOfStock = "out_of_stock"
    case preorder
    case unknown

    init(from decoder: Decoder) throws {
        let value = try? decoder.singleValueContainer().decode(String.self)
        self = value.flatMap(Availability.init(rawValue:)) ?? .unknown
    }
}

/// How the server reads a watched page or a product page (brief 136): plainly, with a browser, or with a browser
/// through an exit. It climbs by itself; the server's note says so. A value this build does not know is kept.
enum PageReader: Equatable, Sendable {
    case plain, browser, browserExit
    case unknown(String)

    init(rawValue: String) {
        switch rawValue {
        case "plain": self = .plain
        case "browser": self = .browser
        case "browser_exit": self = .browserExit
        default: self = .unknown(rawValue)
        }
    }

    var rawValue: String {
        switch self {
        case .plain: "plain"
        case .browser: "browser"
        case .browserExit: "browser_exit"
        case .unknown(let value): value
        }
    }
}

/// `HuntCard.price`: what the server last read of a monitor's product page. A failed read keeps the last good product
/// and price; `read` and `note` say how the page reads now.
struct PriceState: Codable, Equatable, Sendable {
    var reader: PageReader
    var product: String?
    var host: String
    var price: Double?
    var currency: String?
    var availability: Availability
    /// Where the price came from: the shop's own product data or the AI; nil before the first read.
    var source: String?
    /// The watch's read states (`PageState.Read`).
    var read: PageState.Read
    var checked: String?
    var note: String?
    /// The lowest and highest price in euros over the last 30 days; nil while the history is off.
    var low30d: Double?
    var high30d: Double?
    var since: String?

    enum CodingKeys: String, CodingKey {
        case reader, product, host, price, currency, availability, source, read, checked, note, since
        case low30d = "low_30d", high30d = "high_30d"
    }

    init(reader: PageReader = .plain, product: String? = nil, host: String, price: Double? = nil,
         currency: String? = nil, availability: Availability = .unknown, source: String? = nil,
         read: PageState.Read, checked: String? = nil, note: String? = nil, low30d: Double? = nil,
         high30d: Double? = nil, since: String? = nil) {
        self.reader = reader
        self.product = product
        self.host = host
        self.price = price
        self.currency = currency
        self.availability = availability
        self.source = source
        self.read = read
        self.checked = checked
        self.note = note
        self.low30d = low30d
        self.high30d = high30d
        self.since = since
    }

    /// Lenient, as `PageState`: a missing host is empty, a missing `read` is waiting, a missing reader plain.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        reader = try c.decodeIfPresent(String.self, forKey: .reader).map(PageReader.init(rawValue:)) ?? .plain
        product = try c.decodeIfPresent(String.self, forKey: .product)
        host = try c.decodeIfPresent(String.self, forKey: .host) ?? ""
        price = try c.decodeIfPresent(Double.self, forKey: .price)
        currency = try c.decodeIfPresent(String.self, forKey: .currency)
        availability = try c.decodeIfPresent(Availability.self, forKey: .availability) ?? .unknown
        source = try c.decodeIfPresent(String.self, forKey: .source)
        read = try c.decodeIfPresent(String.self, forKey: .read).map(PageState.Read.init(rawValue:)) ?? .waiting
        checked = try c.decodeIfPresent(String.self, forKey: .checked)
        note = try c.decodeIfPresent(String.self, forKey: .note)
        low30d = try c.decodeIfPresent(Double.self, forKey: .low30d)
        high30d = try c.decodeIfPresent(Double.self, forKey: .high30d)
        since = try c.decodeIfPresent(String.self, forKey: .since)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(reader.rawValue, forKey: .reader)
        try c.encode(product, forKey: .product)
        try c.encode(host, forKey: .host)
        try c.encode(price, forKey: .price)
        try c.encode(currency, forKey: .currency)
        try c.encode(availability, forKey: .availability)
        try c.encode(source, forKey: .source)
        try c.encode(read.rawValue, forKey: .read)
        try c.encode(checked, forKey: .checked)
        try c.encode(note, forKey: .note)
        try c.encode(low30d, forKey: .low30d)
        try c.encode(high30d, forKey: .high30d)
        try c.encode(since, forKey: .since)
    }
}

/// `Listing.price_change`: an alarm of a monitor (its match): the price before and now, and why it rang.
struct PriceChange: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Equatable, Sendable {
        /// The price fell to or under the limit.
        case below
        /// A new lowest price while it stays under the limit.
        case lower
        /// Back in stock.
        case back
        case unknown

        init(from decoder: Decoder) throws {
            let value = try? decoder.singleValueContainer().decode(String.self)
            self = value.flatMap(Kind.init(rawValue:)) ?? .unknown
        }
    }

    var old: Double?
    var new: Double
    var currency: String
    var availability: Availability
    var kind: Kind

    init(old: Double?, new: Double, currency: String = "EUR", availability: Availability = .inStock, kind: Kind) {
        self.old = old
        self.new = new
        self.currency = currency
        self.availability = availability
        self.kind = kind
    }

    /// Lenient: a missing currency is euros, an unknown availability or kind reads as unknown.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        old = try c.decodeIfPresent(Double.self, forKey: .old)
        new = try c.decode(Double.self, forKey: .new)
        currency = try c.decodeIfPresent(String.self, forKey: .currency) ?? "EUR"
        availability = try c.decodeIfPresent(Availability.self, forKey: .availability) ?? .unknown
        kind = try c.decodeIfPresent(Kind.self, forKey: .kind) ?? .unknown
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(old, forKey: .old)
        try c.encode(new, forKey: .new)
        try c.encode(currency, forKey: .currency)
        try c.encode(availability, forKey: .availability)
        try c.encode(kind, forKey: .kind)
    }

    private enum CodingKeys: String, CodingKey { case old, new, currency, availability, kind }
}

/// `POST /price/preview`: what the server read on the product page just now (nothing is saved).
struct PricePreview: Codable, Equatable, Sendable {
    var product: String
    var price: Double
    var currency: String
    var availability: Availability
    var source: String?
}

/// One read of a monitor's history.
struct PricePoint: Codable, Equatable, Sendable {
    var at: String
    var price: Double
    var currency: String
    var availability: Availability

    init(at: String, price: Double, currency: String = "EUR", availability: Availability = .inStock) {
        self.at = at
        self.price = price
        self.currency = currency
        self.availability = availability
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        at = try c.decode(String.self, forKey: .at)
        price = try c.decode(Double.self, forKey: .price)
        currency = try c.decodeIfPresent(String.self, forKey: .currency) ?? "EUR"
        availability = try c.decodeIfPresent(Availability.self, forKey: .availability) ?? .unknown
    }

    private enum CodingKeys: String, CodingKey { case at, price, currency, availability }
}

/// `GET /hunts/{id}/prices?days=`: the history over 30, 90 or 365 days, oldest first; the lowest and highest price in
/// euros over that time (nil without points in euros).
struct Prices: Codable, Equatable, Sendable {
    var points: [PricePoint]
    var low: Double?
    var high: Double?

    /// The windows the server offers, in days.
    static let windows = [30, 90, 365]
}
