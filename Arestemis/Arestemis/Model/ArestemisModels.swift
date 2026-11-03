import Foundation

/// The Arestemis API, version 2 (Arestemis/docs/API.md). The server decides and calculates; the app only displays and
/// sends what the user changed. Field names on the wire are the contract's (snake_case, in the CodingKeys); timestamps
/// and dates stay the contract's ISO 8601 strings and are read with `Timestamp` / `DateOnly` where shown.

/// A whole flat, or a room in a shared flat (WG).
enum Kind: String, Codable, CaseIterable, Identifiable, Sendable {
    case flat, wg
    var id: String { rawValue }
    var isWG: Bool { self == .wg }
}

struct Place: Codable, Equatable, Hashable, Identifiable, Sendable {
    let id: String                 // stable server id, "wg:90"
    let name: String               // "München"
    let region: String?            // "Bayern"
    let sources: [Source]          // sites that can search this place (any the server names, `Sites.swift`)

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(region, forKey: .region)          // null, not left out
        try container.encode(sources, forKey: .sources)
    }
}

/// Temporary offers (Zwischenmiete): none, also, or only those.
enum Sublet: String, Codable, CaseIterable, Sendable { case exclude, include, only }

/// Every filter is optional on its own (`nil` = any) except places and sources; each min/max pair is a range.
struct Search: Codable, Equatable, Sendable {
    var kinds: [Kind]              // [.flat], [.wg] or both (= either)
    var people: Int                // moving in together, 1–6
    var flatmatesMax: Int?         // WG offers: people already living there
    var places: [Place]
    var districts: [String]
    var sqmMin: Double?            // the flat (flat offers)
    var sqmMax: Double?
    var roomSqmMin: Double?        // the room (WG offers)
    var roomSqmMax: Double?
    var roomsMin: Double?          // flat offers only
    var rentColdMin: Double?
    var rentColdMax: Double?
    var rentWarmMin: Double?
    var rentWarmMax: Double?
    var moveInFrom: String?        // "2026-12-01"
    var moveInUntil: String?
    var sublet: Sublet
    var extra: String
    var sources: [Source]

    enum CodingKeys: String, CodingKey {
        case kinds, people, places, districts, sublet, extra, sources
        case flatmatesMax = "flatmates_max", sqmMin = "sqm_min", sqmMax = "sqm_max"
        case roomSqmMin = "room_sqm_min", roomSqmMax = "room_sqm_max", roomsMin = "rooms_min"
        case rentColdMin = "rent_cold_min", rentColdMax = "rent_cold_max"
        case rentWarmMin = "rent_warm_min", rentWarmMax = "rent_warm_max"
        case moveInFrom = "move_in_from", moveInUntil = "move_in_until"
    }

    /// Every field is sent, unknown values as `null` (the contract's `number | null`), so a cleared field clears.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kinds, forKey: .kinds)
        try container.encode(people, forKey: .people)
        try container.encode(flatmatesMax, forKey: .flatmatesMax)
        try container.encode(places, forKey: .places)
        try container.encode(districts, forKey: .districts)
        try container.encode(sqmMin, forKey: .sqmMin)
        try container.encode(sqmMax, forKey: .sqmMax)
        try container.encode(roomSqmMin, forKey: .roomSqmMin)
        try container.encode(roomSqmMax, forKey: .roomSqmMax)
        try container.encode(roomsMin, forKey: .roomsMin)
        try container.encode(rentColdMin, forKey: .rentColdMin)
        try container.encode(rentColdMax, forKey: .rentColdMax)
        try container.encode(rentWarmMin, forKey: .rentWarmMin)
        try container.encode(rentWarmMax, forKey: .rentWarmMax)
        try container.encode(moveInFrom, forKey: .moveInFrom)
        try container.encode(moveInUntil, forKey: .moveInUntil)
        try container.encode(sublet, forKey: .sublet)
        try container.encode(extra, forKey: .extra)
        try container.encode(sources, forKey: .sources)
    }
}

/// `Partial<Search>` from `POST /search/parse`: only what the sentence said. A `null` counts as "not said".
struct PartialSearch: Codable, Equatable, Sendable {
    var kinds: [Kind]?
    var people: Int?
    var flatmatesMax: Int?
    var places: [Place]?
    var districts: [String]?
    var sqmMin: Double?
    var sqmMax: Double?
    var roomSqmMin: Double?
    var roomSqmMax: Double?
    var roomsMin: Double?
    var rentColdMin: Double?
    var rentColdMax: Double?
    var rentWarmMin: Double?
    var rentWarmMax: Double?
    var moveInFrom: String?
    var moveInUntil: String?
    var sublet: Sublet?
    var extra: String?
    var sources: [Source]?

    typealias CodingKeys = Search.CodingKeys
}

struct ParsedSearch: Codable, Equatable, Sendable {
    let search: PartialSearch
    let unclear: [String]
}

enum HuntKind: Equatable, Hashable, Codable, Sendable {
    case flat, item, price, watch, unknown(String)

    var rawValue: String {
        switch self {
        case .flat: "flat"
        case .item: "item"
        case .price: "price"
        case .watch: "watch"
        case .unknown(let value): value
        }
    }
    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        switch value {
        case "flat": self = .flat
        case "item": self = .item
        case "price": self = .price
        case "watch": self = .watch
        default: self = .unknown(value)
        }
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

enum HuntSearch: Equatable, Encodable, Sendable {
    case flat(Search), item(ItemSearch), price(PriceSearch), watch(WatchSearch), unsupported

    var flat: Search? { if case .flat(let value) = self { value } else { nil } }
    var item: ItemSearch? { if case .item(let value) = self { value } else { nil } }
    var price: PriceSearch? { if case .price(let value) = self { value } else { nil } }
    var watch: WatchSearch? { if case .watch(let value) = self { value } else { nil } }
    var kind: HuntKind? {
        switch self {
        case .flat: .flat
        case .item: .item
        case .price: .price
        case .watch: .watch
        case .unsupported: nil
        }
    }
    func encode(to encoder: Encoder) throws {
        switch self {
        case .flat(let search): try search.encode(to: encoder)
        case .item(let search): try search.encode(to: encoder)
        case .price(let search): try search.encode(to: encoder)
        case .watch(let search): try search.encode(to: encoder)
        case .unsupported:
            throw EncodingError.invalidValue(self, .init(codingPath: encoder.codingPath,
                                                        debugDescription: "Unsupported hunt search"))
        }
    }
}

struct Hunt: Codable, Equatable, Identifiable, Sendable {
    let id: Int
    let kind: HuntKind
    var name: String? = nil
    var active: Bool
    var search: HuntSearch
    let created: String
    var updated: String
    var activated: String?
    var lastScan: String? = nil

    enum CodingKeys: String, CodingKey {
        case id, kind, name, active, search, created, updated, activated
        case lastScan = "last_scan"
    }
}

struct HuntCard: Codable, Equatable, Identifiable, Sendable {
    var hunt: Hunt
    var counts: Overview.Counts
    var sources: [Source]
    var slowed: Bool
    /// A watch's page as last read (brief 130); nil for the other kinds, and for a watch before its first overview.
    var page: PageState? = nil
    /// A price monitor's product as last read (brief 134); nil for the other kinds, and for a monitor before its first
    /// overview.
    var price: PriceState? = nil
    var id: Int { hunt.id }

    /// A watch or a monitor whose page refuses the server: read no more until it is saved again.
    var isStopped: Bool { page?.read == .blocked || price?.read == .blocked }
}

struct SourceStatus: Codable, Equatable, Identifiable, Sendable {
    enum State: String, Codable, Sendable { case ok, blocked, error, idle }
    let source: Source
    let name: String               // "WG-Gesucht"
    var state: State
    let checked: String?
    let note: String?              // e.g. "Blocked since 14:02"
    var id: Source { source }
}

struct Listing: Codable, Equatable, Sendable {
    let source: Source             // any site the server names, known to this build or not
    let sourceName: String         // the server's name for it ("eBay")
    let url: String
    let title: String
    let kind: Kind?
    let rentWarm: Double?
    let rentCold: Double?
    let sqm: Double?
    let rooms: Double?
    let flatmates: Int?
    let city: String?
    let district: String?
    let address: String?
    let availableFrom: String?
    let availableUntil: String?    // sublet end
    let furnished: Bool?
    let posted: String?
    let imageURL: String?
    let description: String
    /// The description is only the site's preview (a list card's snippet), so the whole text is on the site (server
    /// brief 141). A server from before it sends nothing: read as the whole text.
    var descriptionPartial = false
    var item: ItemDetails? = nil
    /// A watch's match: the lines that changed on the page and what it says now (brief 130); nil for the other kinds.
    var page: PageChange? = nil
    /// A price monitor's alarm: the price before and now, and why it rang (brief 134); nil for the other kinds.
    var priceChange: PriceChange? = nil

    enum CodingKeys: String, CodingKey {
        case source, url, title, kind, sqm, rooms, flatmates, city, district, address, furnished, posted, description, item
        case page
        case priceChange = "price_change"
        case sourceName = "source_name", rentWarm = "rent_warm", rentCold = "rent_cold"
        case availableFrom = "available_from", availableUntil = "available_until", imageURL = "image_url"
        case descriptionPartial = "description_partial"
    }
}

enum MatchState: String, Codable, CaseIterable, Sendable { case new, saved, applied, dismissed }

struct Application: Codable, Equatable, Sendable {
    let text: String
    let mode: ApplicationMode
    let created: String
}

enum ApplicationMode: String, Codable, CaseIterable, Sendable { case own, ai }

struct Match: Codable, Equatable, Identifiable, Sendable {
    let id: Int
    let huntID: Int
    var state: MatchState
    let found: String
    let listing: Listing
    let reason: String
    let warnings: [String]
    var application: Application?
    var atStart: Bool = false
    var overMax: Double? = nil

    enum CodingKeys: String, CodingKey {
        case id, state, found, listing, reason, warnings, application
        case huntID = "hunt_id", atStart = "at_start", overMax = "over_max"
    }
}

struct Rejected: Codable, Equatable, Identifiable, Sendable {
    let id: Int
    let huntID: Int
    let found: String
    let listing: Listing
    let reason: String

    enum CodingKeys: String, CodingKey {
        case id, found, listing, reason
        case huntID = "hunt_id"
    }
}

struct Settings: Codable, Equatable, Sendable {
    var applicationMode: ApplicationMode   // own: the own text; ai: written for each listing
    var ownText: String                    // used as it is in own mode; kept while ai is on
    var applicationNotes: String           // points every automatic text includes (brief 62); "" = none
    var aboutMe: String                    // the facts about the person, for the check and the automatic texts
    var notify: Notify

    struct Notify: Codable, Equatable, Sendable {
        var push: Bool
        var timeSensitive: Bool
        enum CodingKeys: String, CodingKey { case push, timeSensitive = "time_sensitive" }
    }

    enum CodingKeys: String, CodingKey {
        case notify
        case applicationMode = "application_mode", ownText = "own_text", applicationNotes = "application_notes"
        case aboutMe = "about_me"
    }
}

extension Settings {
    /// A server from before brief 62 sends no `application_notes`: read as none. Encoding always sends them.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        applicationMode = try container.decode(ApplicationMode.self, forKey: .applicationMode)
        ownText = try container.decode(String.self, forKey: .ownText)
        applicationNotes = try container.decodeIfPresent(String.self, forKey: .applicationNotes) ?? ""
        aboutMe = try container.decode(String.self, forKey: .aboutMe)
        notify = try container.decode(Notify.self, forKey: .notify)
    }
}

struct Overview: Codable, Equatable, Sendable {
    let version: Int
    let me: Me
    var hunt: Hunt?
    var hunts: [HuntCard] = []
    var sources: [SourceStatus]
    let lastScan: String?
    var counts: Counts
    var latest: [Match]

    struct Me: Codable, Equatable, Sendable {
        let id: String
        let name: String
    }

    struct Counts: Codable, Equatable, Sendable {
        var new: Int
        var today: Int
        var saved: Int
        var applied: Int
    }

    enum CodingKeys: String, CodingKey {
        case version, me, hunt, hunts, sources, counts, latest
        case lastScan = "last_scan"
    }
}

/// `GET /matches`
struct MatchPage: Codable, Equatable, Sendable {
    let items: [Match]
    let more: Bool
}

/// `GET /rejected`
struct RejectedPage: Codable, Equatable, Sendable {
    let items: [Rejected]
}

extension Overview {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        me = try c.decode(Me.self, forKey: .me)
        hunt = try c.decodeIfPresent(Hunt.self, forKey: .hunt)
        sources = try c.decode([SourceStatus].self, forKey: .sources)
        lastScan = try c.decodeIfPresent(String.self, forKey: .lastScan)
        counts = try c.decode(Counts.self, forKey: .counts)
        latest = try c.decode([Match].self, forKey: .latest)
        hunts = try c.decodeIfPresent([HuntCard].self, forKey: .hunts)
            ?? hunt.map { [HuntCard(hunt: $0, counts: counts,
                                   sources: $0.active ? sources.filter { $0.state != .idle }.map(\.source) : [],
                                   slowed: false)] } ?? []
    }
}

extension HuntCard {
    /// A watch's page state or a monitor's product state that cannot be read is left out (the card then reads as not
    /// read yet), never the overview.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hunt = try c.decode(Hunt.self, forKey: .hunt)
        counts = try c.decode(Overview.Counts.self, forKey: .counts)
        sources = try c.decode([Source].self, forKey: .sources)
        slowed = try c.decode(Bool.self, forKey: .slowed)
        page = (try? c.decodeIfPresent(PageState.self, forKey: .page)) ?? nil
        price = (try? c.decodeIfPresent(PriceState.self, forKey: .price)) ?? nil
    }
}

extension Hunt {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        kind = try c.decode(HuntKind.self, forKey: .kind)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        active = try c.decode(Bool.self, forKey: .active)
        switch kind {
        case .flat: search = (try? c.decode(Search.self, forKey: .search)).map(HuntSearch.flat) ?? .unsupported
        case .item: search = (try? c.decode(ItemSearch.self, forKey: .search)).map(HuntSearch.item) ?? .unsupported
        case .price: search = (try? c.decode(PriceSearch.self, forKey: .search)).map(HuntSearch.price) ?? .unsupported
        case .watch: search = (try? c.decode(WatchSearch.self, forKey: .search)).map(HuntSearch.watch) ?? .unsupported
        case .unknown: search = .unsupported
        }
        created = try c.decode(String.self, forKey: .created)
        updated = try c.decode(String.self, forKey: .updated)
        activated = try c.decodeIfPresent(String.self, forKey: .activated)
        lastScan = try c.decodeIfPresent(String.self, forKey: .lastScan)
    }
}

extension Listing {
    /// Read as the contract says; `description_partial` leniently: absent, null or not a boolean is the whole text
    /// (a server from before brief 141).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        source = try c.decode(Source.self, forKey: .source)
        sourceName = try c.decode(String.self, forKey: .sourceName)
        url = try c.decode(String.self, forKey: .url)
        title = try c.decode(String.self, forKey: .title)
        kind = try c.decodeIfPresent(Kind.self, forKey: .kind)
        rentWarm = try c.decodeIfPresent(Double.self, forKey: .rentWarm)
        rentCold = try c.decodeIfPresent(Double.self, forKey: .rentCold)
        sqm = try c.decodeIfPresent(Double.self, forKey: .sqm)
        rooms = try c.decodeIfPresent(Double.self, forKey: .rooms)
        flatmates = try c.decodeIfPresent(Int.self, forKey: .flatmates)
        city = try c.decodeIfPresent(String.self, forKey: .city)
        district = try c.decodeIfPresent(String.self, forKey: .district)
        address = try c.decodeIfPresent(String.self, forKey: .address)
        availableFrom = try c.decodeIfPresent(String.self, forKey: .availableFrom)
        availableUntil = try c.decodeIfPresent(String.self, forKey: .availableUntil)
        furnished = try c.decodeIfPresent(Bool.self, forKey: .furnished)
        posted = try c.decodeIfPresent(String.self, forKey: .posted)
        imageURL = try c.decodeIfPresent(String.self, forKey: .imageURL)
        description = try c.decode(String.self, forKey: .description)
        descriptionPartial = ((try? c.decodeIfPresent(Bool.self, forKey: .descriptionPartial)) ?? nil) ?? false
        item = try c.decodeIfPresent(ItemDetails.self, forKey: .item)
        page = try c.decodeIfPresent(PageChange.self, forKey: .page)
        priceChange = try c.decodeIfPresent(PriceChange.self, forKey: .priceChange)
    }
}

extension Match {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        huntID = try c.decode(Int.self, forKey: .huntID)
        state = try c.decode(MatchState.self, forKey: .state)
        found = try c.decode(String.self, forKey: .found)
        listing = try c.decode(Listing.self, forKey: .listing)
        reason = try c.decode(String.self, forKey: .reason)
        warnings = try c.decode([String].self, forKey: .warnings)
        application = try c.decodeIfPresent(Application.self, forKey: .application)
        atStart = try c.decodeIfPresent(Bool.self, forKey: .atStart) ?? false
        overMax = try c.decodeIfPresent(Double.self, forKey: .overMax)
    }
}
