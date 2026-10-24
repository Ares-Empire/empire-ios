import Foundation

/// The Arestemis API, version 1 (Arestemis/docs/API.md). The server decides and calculates; the app only displays and
/// sends what the user changed. Field names on the wire are the contract's (snake_case, in the CodingKeys); timestamps
/// and dates stay the contract's ISO 8601 strings and are read with `Timestamp` / `DateOnly` where shown.

enum Kind: String, Codable, CaseIterable, Identifiable, Sendable {
    case flat, wgRoom = "wg_room", wgEmpty = "wg_empty"
    var id: String { rawValue }
    var isWG: Bool { self != .flat }
}

enum Source: String, Codable, CaseIterable, Identifiable, Sendable {
    case wgGesucht = "wg_gesucht", kleinanzeigen, immowelt
    var id: String { rawValue }
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

struct RentTier: Codable, Equatable, Hashable, Sendable {
    var sqmMin: Double
    var rentMaxWarm: Double
    enum CodingKeys: String, CodingKey { case sqmMin = "sqm_min", rentMaxWarm = "rent_max_warm" }
}

enum Sublet: String, Codable, CaseIterable, Sendable { case exclude, include, only }
enum Furnished: String, Codable, CaseIterable, Sendable { case any, yes, no }

struct Search: Codable, Equatable, Sendable {
    var kinds: [Kind]
    var places: [Place]
    var districts: [String]
    var rentMaxWarm: Double?
    var rentTiers: [RentTier]
    var sqmMin: Double?
    var roomsMin: Double?          // own flat only
    var flatmatesMax: Int?         // WG kinds only
    var moveInFrom: String?        // "2026-12-01"
    var moveInUntil: String?
    var sublet: Sublet
    var furnished: Furnished
    var extra: String
    var sources: [Source]

    enum CodingKeys: String, CodingKey {
        case kinds, places, districts, sublet, furnished, extra, sources
        case rentMaxWarm = "rent_max_warm", rentTiers = "rent_tiers", sqmMin = "sqm_min", roomsMin = "rooms_min"
        case flatmatesMax = "flatmates_max", moveInFrom = "move_in_from", moveInUntil = "move_in_until"
    }

    /// Every field is sent, unknown values as `null` (the contract's `number | null`), so a cleared field clears.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kinds, forKey: .kinds)
        try container.encode(places, forKey: .places)
        try container.encode(districts, forKey: .districts)
        try container.encode(rentMaxWarm, forKey: .rentMaxWarm)
        try container.encode(rentTiers, forKey: .rentTiers)
        try container.encode(sqmMin, forKey: .sqmMin)
        try container.encode(roomsMin, forKey: .roomsMin)
        try container.encode(flatmatesMax, forKey: .flatmatesMax)
        try container.encode(moveInFrom, forKey: .moveInFrom)
        try container.encode(moveInUntil, forKey: .moveInUntil)
        try container.encode(sublet, forKey: .sublet)
        try container.encode(furnished, forKey: .furnished)
        try container.encode(extra, forKey: .extra)
        try container.encode(sources, forKey: .sources)
    }
}

/// `Partial<Search>` from `POST /search/parse`: only what the sentence said. A `null` counts as "not said".
struct PartialSearch: Codable, Equatable, Sendable {
    var kinds: [Kind]?
    var places: [Place]?
    var districts: [String]?
    var rentMaxWarm: Double?
    var rentTiers: [RentTier]?
    var sqmMin: Double?
    var roomsMin: Double?
    var flatmatesMax: Int?
    var moveInFrom: String?
    var moveInUntil: String?
    var sublet: Sublet?
    var furnished: Furnished?
    var extra: String?
    var sources: [Source]?

    enum CodingKeys: String, CodingKey {
        case kinds, places, districts, sublet, furnished, extra, sources
        case rentMaxWarm = "rent_max_warm", rentTiers = "rent_tiers", sqmMin = "sqm_min", roomsMin = "rooms_min"
        case flatmatesMax = "flatmates_max", moveInFrom = "move_in_from", moveInUntil = "move_in_until"
    }
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
    let note: String?              // "Only München"
    var id: Source { source }
}

struct Listing: Codable, Equatable, Sendable {
    let source: Source
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
    var applicationMode: ApplicationMode
    var ownText: String
    var aboutMe: String
    var notify: Notify

    struct Notify: Codable, Equatable, Sendable {
        var push: Bool
        var timeSensitive: Bool
        enum CodingKeys: String, CodingKey { case push, timeSensitive = "time_sensitive" }
    }

    enum CodingKeys: String, CodingKey {
        case notify
        case applicationMode = "application_mode", ownText = "own_text", aboutMe = "about_me"
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
