import Foundation

/// Price monitors (brief 134 on the server, 137 here): a hunt of kind `price` reads one product page in one shop every
/// so often. It records the price and the availability as a history, raises an alarm when the price falls under a limit
/// or the product is back in stock, or both; at least one of the two is on. The server reads the shop's page (its
/// product data first, the AI only where it has none) and decides; the app shows what it read and never parses a page.

/// `PriceSearch`: a monitor watches one shop's product page (`page`, brief 137: the page's address) or one product on
/// every site that sells it (`everywhere`, brief 157 here, 154 on the server: the product in words, optional details,
/// the product the preview found and the sites switched off); then the history and the alarm switches, how often.
struct PriceSearch: Codable, Equatable, Sendable {
    /// Ein Shop (a link) or Überall (a product in words). A mode this build does not know makes the monitor one it
    /// cannot read (`HuntSearch.unsupported`: "Needs a newer app"), never a page monitor without a page.
    enum Mode: String, Codable, Equatable, Sendable {
        case page, everywhere
    }

    var mode: Mode
    /// `page`: the product page's address. Nil for `everywhere` (sent as null).
    var url: String?
    /// `everywhere`: the product in words as the user typed it, 2–100 characters ("AirPods Max 2").
    var product: String?
    /// `everywhere`: optional words for the variant ("Mitternacht oder Blau"), at most 300 characters; "" for none.
    var details: String
    /// `everywhere`: the product the preview found, which saving confirms.
    var identity: ProductIdentity?
    /// `everywhere`: the ids of the sites the user switched off (`PriceSite.id`).
    var sourcesOff: [String]
    /// Separate ordinary used listings; previews, shop totals and history remain new goods.
    var includeUsed = false
    var delivery: Delivery = .shipping
    var places: [Place] = []
    var radiusKm: Double = 20
    /// Records the price and the availability at every read, for the curve (`everywhere`: the cheapest offer's).
    var history: Bool
    /// The alarm and its conditions; nil while the alarm is off.
    var alarm: Alarm?
    /// Minutes between reads: one of `WatchSearch.everyChoices`; `everywhere` at least hourly (`everyChoices(for:)`).
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

    /// A monitor of one shop's page (`page`).
    init(url: String, history: Bool, alarm: Alarm?, every: Int = WatchSearch.defaultEvery) {
        mode = .page
        self.url = url
        product = nil
        details = ""
        identity = nil
        sourcesOff = []
        self.history = history
        self.alarm = alarm
        self.every = every
    }

    /// A monitor of one product on every site that sells it (`everywhere`).
    init(product: String, details: String = "", identity: ProductIdentity?, sourcesOff: [String] = [], history: Bool,
         alarm: Alarm?, every: Int = WatchSearch.defaultEvery, delivery: Delivery = .shipping,
         places: [Place] = [], radiusKm: Double = 20, includeUsed: Bool = false) {
        mode = .everywhere
        url = nil
        self.product = product
        self.details = details
        self.identity = identity
        self.sourcesOff = sourcesOff
        self.includeUsed = includeUsed
        self.delivery = delivery
        self.places = places
        self.radiusKm = radiusKm
        self.history = history
        self.alarm = alarm
        self.every = every
    }

    /// Lenient as the server's defaults: no mode is a page (every monitor from before brief 154), no history, no alarm,
    /// every hour, no details, no site switched off. A page monitor without an address, or a mode this build does not
    /// know, cannot be read (the hunt then shows "Needs a newer app").
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let rawMode = try c.decodeIfPresent(String.self, forKey: .mode) ?? Mode.page.rawValue
        guard let mode = Mode(rawValue: rawMode) else {
            throw DecodingError.dataCorruptedError(forKey: .mode, in: c, debugDescription: "Unknown mode \(rawMode)")
        }
        self.mode = mode
        url = try c.decodeIfPresent(String.self, forKey: .url)
        if mode == .page && url == nil {
            throw DecodingError.keyNotFound(CodingKeys.url, .init(codingPath: c.codingPath,
                                                                   debugDescription: "A page monitor needs its url"))
        }
        product = try c.decodeIfPresent(String.self, forKey: .product)
        details = try c.decodeIfPresent(String.self, forKey: .details) ?? ""
        identity = try c.decodeIfPresent(ProductIdentity.self, forKey: .identity)
        sourcesOff = try c.decodeIfPresent([String].self, forKey: .sourcesOff) ?? []
        includeUsed = mode == .everywhere ? try c.decodeIfPresent(Bool.self, forKey: .includeUsed) ?? false : false
        let rawDelivery = try c.decodeIfPresent(String.self, forKey: .delivery) ?? Delivery.shipping.rawValue
        guard let delivery = Delivery(rawValue: rawDelivery) else {
            throw DecodingError.dataCorruptedError(forKey: .delivery, in: c,
                                                   debugDescription: "Unknown delivery \(rawDelivery)")
        }
        self.delivery = delivery
        places = try c.decodeIfPresent([Place].self, forKey: .places) ?? []
        radiusKm = try c.decodeIfPresent(Double.self, forKey: .radiusKm) ?? 20
        history = try c.decodeIfPresent(Bool.self, forKey: .history) ?? false
        alarm = try c.decodeIfPresent(Alarm.self, forKey: .alarm)
        every = try c.decodeIfPresent(Int.self, forKey: .every) ?? WatchSearch.defaultEvery
    }

    /// The whole search, `alarm: null` included, as `PUT` replaces it. A page monitor is sent as before brief 154 (its
    /// four fields; the server reads no mode as a page); an everywhere monitor with every field, `url: null`.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if mode == .everywhere {
            try c.encode(mode, forKey: .mode)
            try c.encode(url, forKey: .url)
            try c.encode(product, forKey: .product)
            try c.encode(details, forKey: .details)
            try c.encode(identity, forKey: .identity)
            try c.encode(sourcesOff, forKey: .sourcesOff)
            try c.encode(includeUsed, forKey: .includeUsed)
            try c.encode(delivery, forKey: .delivery)
            try c.encode(places, forKey: .places)
            try c.encode(radiusKm, forKey: .radiusKm)
        } else {
            try c.encode(url ?? "", forKey: .url)
        }
        try c.encode(history, forKey: .history)
        try c.encode(alarm, forKey: .alarm)
        try c.encode(every, forKey: .every)
    }

    enum CodingKeys: String, CodingKey {
        case mode, url, product, details, identity, history, alarm, every
        case delivery, places
        case radiusKm = "radius_km"
        case sourcesOff = "sources_off"
        case includeUsed = "include_used"
    }

    /// The server's rule: the history, the alarm or both; an alarm says when it rings.
    var isComplete: Bool { (history || alarm != nil) && (alarm?.isComplete ?? true) }

    /// The product's page to open in the browser ("Open in shop"): the link as saved, read as https without a scheme, as
    /// the server reads it; nil for anything but a web address, and for an everywhere monitor (it opens its cheapest
    /// offer, `PriceOffers`).
    var shopURL: URL? {
        guard mode == .page, let url else { return nil }
        return WebLink.url(url)
    }

    /// The fewest minutes between reads of an everywhere monitor (the server's "Check everywhere at most once an hour.").
    static let everywhereEvery = 60

    /// How often a monitor of this mode may read: every server interval for a page, hourly or slower everywhere.
    static func everyChoices(for mode: Mode) -> [Int] {
        mode == .everywhere ? WatchSearch.everyChoices.filter { $0 >= everywhereEvery } : WatchSearch.everyChoices
    }
}

/// `ProductIdentity`: the product an everywhere monitor watches, as the preview found it ("Apple AirPods Max (2.
/// Generation)"), with the EAN/GTIN numbers of the variants that fit the details (none when no site gives one).
struct ProductIdentity: Codable, Equatable, Hashable, Sendable {
    var name: String
    var eans: [String]
    var imageURL: String?

    init(name: String, eans: [String] = [], imageURL: String? = nil) {
        self.name = name
        self.eans = eans
        self.imageURL = imageURL
    }

    enum CodingKeys: String, CodingKey {
        case name, eans
        case imageURL = "image_url"
    }

    /// Lenient: no numbers and no picture when missing.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        eans = try c.decodeIfPresent([String].self, forKey: .eans) ?? []
        imageURL = try c.decodeIfPresent(String.self, forKey: .imageURL)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(eans, forKey: .eans)
        try c.encode(imageURL, forKey: .imageURL)
    }
}

/// A web address to open: as typed, read as https without a scheme; nil for anything but http(s) with a host.
enum WebLink {
    static func url(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed.contains("://") ? trimmed : "https://" + trimmed),
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

/// `PriceState.product_state` (the server's brief 179, 180 here): an everywhere monitor saved without a confirmed
/// product is `finding` it in the background, and once the search is complete has `found` it or `notFound` it (then
/// it reads nothing more until its words are edited). Missing (older monitors, page monitors) and a value this build
/// does not know read as found, so such a card shows what it showed before.
enum ProductState: String, Equatable, Sendable {
    case finding, found
    case notFound = "not_found"

    init(serverValue: String?) {
        self = serverValue.flatMap(Self.init(rawValue:)) ?? .found
    }
}

/// `PriceState.refusal` (the server's brief 179): why no product fits an everywhere monitor's words, in the body a
/// refused preview gives (`FieldRefusal`, brief 163): the server's sentence in the app's language, up to four concrete
/// names to choose from and the words for a Dinge search.
struct ProductRefusal: Codable, Equatable, Sendable {
    var error: String
    var suggestions: [String]
    var itemSearch: ProductItemSearch?

    init(error: String, suggestions: [String] = [], itemSearch: ProductItemSearch? = nil) {
        self.error = error
        self.suggestions = suggestions
        self.itemSearch = itemSearch
    }

    enum CodingKeys: String, CodingKey {
        case error, suggestions, field
        case itemSearch = "item_search"
    }

    /// Lenient as `FieldRefusal`: the optional choices never hide the sentence.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        error = try c.decode(String.self, forKey: .error)
        suggestions = (try? c.decodeIfPresent([String].self, forKey: .suggestions)) ?? []
        itemSearch = (try? c.decodeIfPresent(ProductItemSearch.self, forKey: .itemSearch)) ?? nil
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(error, forKey: .error)
        try c.encode("product", forKey: .field)
        try c.encode(suggestions, forKey: .suggestions)
        try c.encodeIfPresent(itemSearch, forKey: .itemSearch)
    }

    /// What the form and the monitor's page offer under the sentence ("Did you mean…" and the Dinge route); nil when the
    /// server named neither.
    var choices: ProductSuggestions? {
        suggestions.isEmpty && itemSearch == nil ? nil : ProductSuggestions(names: suggestions, itemSearch: itemSearch)
    }
}

/// `HuntCard.price`: what the server last read of a monitor's product page. A failed read keeps the last good product
/// and price; `read` and `note` say how the page reads now. For an everywhere monitor (brief 154) the price,
/// currency, availability and host are the cheapest offer's (the host is its shop's name, "Amazon"), the product is
/// the identity's name, and `offers` counts the sites with an offer now. An everywhere monitor saved without a confirmed
/// product (brief 179) is `finding` it first, its product the words as typed; `notFound` carries the server's refusal.
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
    /// An everywhere monitor's sites with an offer now; nil for a page monitor.
    var offers: Int?
    /// The everywhere price excludes shipping because its cost is unknown.
    var shippingUnknown: Bool
    /// An everywhere monitor's product: being found, found, or none fits its words (brief 179).
    var productState: ProductState
    /// Why none fits, while `productState` is `notFound`.
    var refusal: ProductRefusal?

    enum CodingKeys: String, CodingKey {
        case reader, product, host, price, currency, availability, source, read, checked, note, since, offers, refusal
        case low30d = "low_30d", high30d = "high_30d"
        case shippingUnknown = "shipping_unknown"
        case productState = "product_state"
    }

    init(reader: PageReader = .plain, product: String? = nil, host: String, price: Double? = nil,
         currency: String? = nil, availability: Availability = .unknown, source: String? = nil,
         read: PageState.Read, checked: String? = nil, note: String? = nil, low30d: Double? = nil,
         high30d: Double? = nil, since: String? = nil, offers: Int? = nil, shippingUnknown: Bool = false,
         productState: ProductState = .found, refusal: ProductRefusal? = nil) {
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
        self.offers = offers
        self.shippingUnknown = shippingUnknown
        self.productState = productState
        self.refusal = refusal
    }

    /// Lenient, as `PageState`: a missing host is empty, a missing `read` is waiting, a missing reader plain; a missing or
    /// unknown product state is found, a refusal that cannot be read is none.
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
        offers = try c.decodeIfPresent(Int.self, forKey: .offers)
        shippingUnknown = try c.decodeIfPresent(Bool.self, forKey: .shippingUnknown) ?? false
        productState = ProductState(serverValue: (try? c.decodeIfPresent(String.self, forKey: .productState)) ?? nil)
        refusal = (try? c.decodeIfPresent(ProductRefusal.self, forKey: .refusal)) ?? nil
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(productState.rawValue, forKey: .productState)
        try c.encodeIfPresent(refusal, forKey: .refusal)
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
        try c.encodeIfPresent(offers, forKey: .offers)
        try c.encode(shippingUnknown, forKey: .shippingUnknown)
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
    var shippingUnknown: Bool

    init(old: Double?, new: Double, currency: String = "EUR", availability: Availability = .inStock, kind: Kind,
         shippingUnknown: Bool = false) {
        self.old = old
        self.new = new
        self.currency = currency
        self.availability = availability
        self.kind = kind
        self.shippingUnknown = shippingUnknown
    }

    /// Lenient: a missing currency is euros, an unknown availability or kind reads as unknown.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        old = try c.decodeIfPresent(Double.self, forKey: .old)
        new = try c.decode(Double.self, forKey: .new)
        currency = try c.decodeIfPresent(String.self, forKey: .currency) ?? "EUR"
        availability = try c.decodeIfPresent(Availability.self, forKey: .availability) ?? .unknown
        kind = try c.decodeIfPresent(Kind.self, forKey: .kind) ?? .unknown
        shippingUnknown = try c.decodeIfPresent(Bool.self, forKey: .shippingUnknown) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(old, forKey: .old)
        try c.encode(new, forKey: .new)
        try c.encode(currency, forKey: .currency)
        try c.encode(availability, forKey: .availability)
        try c.encode(kind, forKey: .kind)
        try c.encode(shippingUnknown, forKey: .shippingUnknown)
    }

    private enum CodingKeys: String, CodingKey {
        case old, new, currency, availability, kind
        case shippingUnknown = "shipping_unknown"
    }
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

// MARK: - everywhere (brief 154 on the server)

/// `Offer`: one offer of an everywhere monitor's product, as a site showed it: the site read (`source`, its name
/// `sourceName`), who sells it (`shop`: the site itself, or the shop a comparison site lists, "Amazon"), where to buy it
/// (or the comparison site's offer link), the price, the shipping when known and the availability.
struct Offer: Codable, Equatable, Identifiable, Sendable {
    var source: String
    var sourceName: String
    var shop: String
    var url: String
    var price: Double?
    var currency: String?
    /// Shipping in euros, when the site says.
    var shipping: Double?
    var availability: Availability
    /// The last successful read of this offer.
    var checked: String?

    var fulfillment: Fulfillment = .shipping
    var pickupMethod: PickupMethod?
    var pickupFee: Double?
    var store: OfferStore?
    /// The server's eligible selected total. Missing on older payloads means unknown, never product price alone.
    var total: Double?
    /// The server's comparison amount: known total, or item price with unknown shipping. Never a local sum.
    var totalFrom: Double?

    var id: String { source + "|" + shop + "|" + url + "|" + fulfillment.rawValue + "|" + (pickupMethod?.rawValue ?? "") + "|" + (store?.id ?? "") }

    init(source: String, sourceName: String, shop: String, url: String, price: Double?, currency: String? = "EUR",
         shipping: Double? = nil, availability: Availability = .inStock, checked: String? = nil,
         fulfillment: Fulfillment = .shipping, pickupMethod: PickupMethod? = nil, pickupFee: Double? = nil,
         store: OfferStore? = nil, total: Double? = nil, totalFrom: Double? = nil) {
        self.source = source
        self.sourceName = sourceName
        self.shop = shop
        self.url = url
        self.price = price
        self.currency = currency
        self.shipping = shipping
        self.availability = availability
        self.checked = checked
        self.fulfillment = fulfillment
        self.pickupMethod = pickupMethod
        self.pickupFee = pickupFee
        self.store = store
        self.total = total
        self.totalFrom = totalFrom
    }

    enum CodingKeys: String, CodingKey {
        case fulfillment, store, total
        case totalFrom = "total_from"
        case pickupMethod = "pickup_method", pickupFee = "pickup_fee"
        case source, shop, url, price, currency, shipping, availability, checked
        case sourceName = "source_name"
    }

    /// Lenient: a missing shop is the site itself, a missing name the site's id, an unknown availability unknown.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        source = try c.decode(String.self, forKey: .source)
        sourceName = try c.decodeIfPresent(String.self, forKey: .sourceName) ?? source
        shop = try c.decodeIfPresent(String.self, forKey: .shop) ?? sourceName
        url = try c.decode(String.self, forKey: .url)
        price = try c.decodeIfPresent(Double.self, forKey: .price)
        currency = try c.decodeIfPresent(String.self, forKey: .currency)
        shipping = try c.decodeIfPresent(Double.self, forKey: .shipping)
        availability = try c.decodeIfPresent(Availability.self, forKey: .availability) ?? .unknown
        checked = try c.decodeIfPresent(String.self, forKey: .checked)
        fulfillment = (try c.decodeIfPresent(String.self, forKey: .fulfillment)).map {
            Fulfillment(rawValue: $0) ?? .unknown
        } ?? .shipping
        pickupMethod = (try c.decodeIfPresent(String.self, forKey: .pickupMethod)).map {
            PickupMethod(rawValue: $0) ?? .unknown
        }
        pickupFee = try c.decodeIfPresent(Double.self, forKey: .pickupFee)
        store = try c.decodeIfPresent(OfferStore.self, forKey: .store)
        total = try c.decodeIfPresent(Double.self, forKey: .total)
        totalFrom = try c.decodeIfPresent(Double.self, forKey: .totalFrom)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(source, forKey: .source)
        try c.encode(sourceName, forKey: .sourceName)
        try c.encode(shop, forKey: .shop)
        try c.encode(url, forKey: .url)
        try c.encode(price, forKey: .price)
        try c.encode(currency, forKey: .currency)
        try c.encode(shipping, forKey: .shipping)
        try c.encode(availability, forKey: .availability)
        try c.encode(checked, forKey: .checked)
        try c.encode(fulfillment, forKey: .fulfillment)
        try c.encode(pickupMethod, forKey: .pickupMethod)
        try c.encode(pickupFee, forKey: .pickupFee)
        try c.encode(store, forKey: .store)
        try c.encode(total, forKey: .total)
        try c.encode(totalFrom, forKey: .totalFrom)
    }

    /// Where a tap on the offer goes; nil for anything but a web address.
    var link: URL? { WebLink.url(url) }
}

/// `PriceSite`: one site an everywhere monitor checks for its product: a shop, a price comparison site or a
/// marketplace, whether it has the product, and whether the user left it on. A kind or a state this build does not know
/// is kept (shown by name, without a state word).
struct PriceSite: Codable, Equatable, Identifiable, Sendable {
    enum Kind: Hashable, Sendable {
        case shop, comparison, marketplace
        case unknown(String)

        init(rawValue: String) {
            switch rawValue {
            case "shop": self = .shop
            case "comparison": self = .comparison
            case "marketplace": self = .marketplace
            default: self = .unknown(rawValue)
            }
        }

        var rawValue: String {
            switch self {
            case .shop: "shop"
            case .comparison: "comparison"
            case .marketplace: "marketplace"
            case .unknown(let value): value
            }
        }
    }

    enum State: Hashable, Sendable {
        /// Not known yet: the finder has not looked, or a shop answered without a clear yes.
        case checking
        case hasIt
        case notFound
        /// The site could not be read just now.
        case unreadable
        case unknown(String)

        init(rawValue: String) {
            switch rawValue {
            case "checking": self = .checking
            case "has_it": self = .hasIt
            case "not_found": self = .notFound
            case "unreadable": self = .unreadable
            default: self = .unknown(rawValue)
            }
        }

        var rawValue: String {
            switch self {
            case .checking: "checking"
            case .hasIt: "has_it"
            case .notFound: "not_found"
            case .unreadable: "unreadable"
            case .unknown(let value): value
            }
        }
    }

    let id: String
    var name: String
    var kind: Kind
    var state: State
    /// False while the monitor's `sources_off` names it (a preview's sites are all on).
    var on: Bool
    /// Absent or future capabilities leave the site available, as in Things.
    var delivery: Delivery?

    var isComparison: Bool { kind == .comparison }

    init(id: String, name: String, kind: Kind = .shop, state: State = .checking, on: Bool = true, delivery: Delivery? = nil) {
        self.id = id
        self.name = name
        self.kind = kind
        self.state = state
        self.on = on
        self.delivery = delivery
    }

    enum CodingKeys: String, CodingKey { case id, name, kind, state, on, delivery }

    /// Lenient as the server's defaults: checking and on; a missing name is the id.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? id
        kind = Kind(rawValue: try c.decodeIfPresent(String.self, forKey: .kind) ?? "")
        state = try c.decodeIfPresent(String.self, forKey: .state).map(State.init(rawValue:)) ?? .checking
        on = try c.decodeIfPresent(Bool.self, forKey: .on) ?? true
        delivery = (try c.decodeIfPresent(String.self, forKey: .delivery)).flatMap(Delivery.init(rawValue:))
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(kind.rawValue, forKey: .kind)
        try c.encode(state.rawValue, forKey: .state)
        try c.encode(on, forKey: .on)
        try c.encodeIfPresent(delivery, forKey: .delivery)
    }
}

/// `GET /hunts/{id}/offers`: an everywhere monitor's offers now (cheapest first) and every site it checks.
struct PriceOffers: Codable, Equatable, Sendable {
    var offers: [Offer]
    var sites: [PriceSite]

    init(offers: [Offer] = [], sites: [PriceSite] = []) {
        self.offers = offers
        self.sites = sites
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        offers = try c.decodeIfPresent([Offer].self, forKey: .offers) ?? []
        sites = try c.decodeIfPresent([PriceSite].self, forKey: .sites) ?? []
    }
}

/// `POST /price/preview` with `{product, details}`: the product the server found for the words, what its first look
/// found (cheapest first) and every site it would check. Nothing is saved.
struct ProductPreview: Codable, Equatable, Sendable {
    var identity: ProductIdentity
    var offers: [Offer]
    var sites: [PriceSite]

    init(identity: ProductIdentity, offers: [Offer] = [], sites: [PriceSite] = []) {
        self.identity = identity
        self.offers = offers
        self.sites = sites
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        identity = try c.decode(ProductIdentity.self, forKey: .identity)
        offers = try c.decodeIfPresent([Offer].self, forKey: .offers) ?? []
        sites = try c.decodeIfPresent([PriceSite].self, forKey: .sites) ?? []
    }
}
