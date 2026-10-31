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

/// The portals the app knows. A newer server may name one the app does not know yet (as "immoscout24" did before brief
/// 63): every list of portals leaves it out and a listing from it still shows (below), so it never breaks the app.
enum Source: String, Codable, CaseIterable, Identifiable, Sendable {
    case wgGesucht = "wg_gesucht", kleinanzeigen, immowelt, immoscout24
    var id: String { rawValue }
}

// Portals the app does not know yet, wherever the contract has them (brief 61). These overloads are picked by every
// synthesized `init(from:)` in this module, so `Place.sources`, `Search.sources`, `PartialSearch.sources`,
// `Overview.sources` and `Listing.source` all follow the same rule; `DecodingTests` pins each.
extension KeyedDecodingContainer {
    /// A list of portals without the ones the app does not know.
    func decode(_ type: [Source].Type, forKey key: Key) throws -> [Source] {
        try decode([KnownSource].self, forKey: key).compactMap(\.source)
    }

    func decodeIfPresent(_ type: [Source].Type, forKey key: Key) throws -> [Source]? {
        try decodeIfPresent([KnownSource].self, forKey: key)?.compactMap(\.source)
    }

    /// The portals' states without the ones the app does not know (anything else wrong in an entry still fails).
    func decode(_ type: [SourceStatus].Type, forKey key: Key) throws -> [SourceStatus] {
        try decode([KnownStatus].self, forKey: key).compactMap(\.status)
    }

    /// One portal, nil when the app does not know it (a listing then shows the server's `source_name`).
    func decodeIfPresent(_ type: Source.Type, forKey key: Key) throws -> Source? {
        try decodeIfPresent(String.self, forKey: key).flatMap(Source.init(rawValue:))
    }
}

/// One entry of a list of portals: nil for a portal the app does not know.
private struct KnownSource: Decodable {
    let source: Source?

    init(from decoder: Decoder) throws {
        source = Source(rawValue: try decoder.singleValueContainer().decode(String.self))
    }
}

/// One portal's state: nil for a portal the app does not know.
private struct KnownStatus: Decodable {
    let status: SourceStatus?

    private enum Keys: String, CodingKey { case source }

    init(from decoder: Decoder) throws {
        let source = try decoder.container(keyedBy: Keys.self).decode(String.self, forKey: .source)
        status = Source(rawValue: source) == nil ? nil : try SourceStatus(from: decoder)
    }
}

struct Place: Codable, Equatable, Hashable, Identifiable, Sendable {
    let id: String                 // stable server id, "wg:90"
    let name: String               // "München"
    let region: String?            // "Bayern"
    let sources: [Source]          // portals that can search this place

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

struct Hunt: Codable, Equatable, Identifiable, Sendable {
    let id: Int
    let kind: String               // "flat", the only hunt type today
    var active: Bool
    var search: Search
    let created: String
    let updated: String
    let activated: String?
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
    let source: Source?            // nil: a portal the app does not know yet; `sourceName` still names it
    let sourceName: String
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

    enum CodingKeys: String, CodingKey {
        case source, url, title, kind, sqm, rooms, flatmates, city, district, address, furnished, posted, description
        case sourceName = "source_name", rentWarm = "rent_warm", rentCold = "rent_cold"
        case availableFrom = "available_from", availableUntil = "available_until", imageURL = "image_url"
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

    enum CodingKeys: String, CodingKey {
        case id, state, found, listing, reason, warnings, application
        case huntID = "hunt_id"
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
        case version, me, hunt, sources, counts, latest
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
