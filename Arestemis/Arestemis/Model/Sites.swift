import Foundation

/// The sites Arestemis reads (brief 119). The server decides about them: it names every site (`SourceStatus.name`,
/// `Listing.source_name`, `GET /kinds`), says which kind of search can use which site, whether a site is set up there
/// (`ready`) and whether it has auctions. The app keeps every site the server names, shows it by the server's name and
/// offers what `/kinds` offers, so a new site needs no app update.

/// One site, by the id the server uses ("wg_gesucht", "ebay"). An open value: a site this build has never heard of is
/// kept wherever the contract has one, never dropped. The known ones are constants for the code that needs them (the
/// lists a form shows before the server answered, Kleinanzeigen as a new thing search's site).
nonisolated struct Source: RawRepresentable, Codable, Hashable, Identifiable, Sendable {
    let rawValue: String

    init(rawValue: String) { self.rawValue = rawValue }
    init(_ rawValue: String) { self.rawValue = rawValue }

    var id: String { rawValue }

    init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    static let wgGesucht = Source("wg_gesucht")
    static let kleinanzeigen = Source("kleinanzeigen")
    static let immowelt = Source("immowelt")
    static let immoscout24 = Source("immoscout24")
    static let ebay = Source("ebay")

    /// The flat portals the app knew before `/kinds`: the flat form's list until the server answered, and every one of
    /// them is on in a new flat search.
    static let flatPortals: [Source] = [.wgGesucht, .kleinanzeigen, .immowelt, .immoscout24]

    /// The server's own order of the sites it has today.
    private static let known: [Source] = [.wgGesucht, .kleinanzeigen, .immowelt, .immoscout24, .ebay]

    /// The chosen sites as a search sends them: the known ones in the server's order, any other after them by id. One
    /// order however they were chosen, so a search the server sends back equals the one the form sent.
    static func ordered(_ sources: Set<Source>) -> [Source] {
        known.filter(sources.contains) + sources.subtracting(known).sorted { $0.rawValue < $1.rawValue }
    }

    /// The names the four sites of before brief 119 had in the app, for a list shown before any answer named them.
    fileprivate var earlierName: String? {
        switch self {
        case .wgGesucht: "WG-Gesucht"
        case .kleinanzeigen: "Kleinanzeigen"
        case .immowelt: "Immowelt"
        case .immoscout24: "ImmoScout24"
        default: nil
        }
    }
}

/// `GET /kinds`: one site a kind of search can use.
struct KindSource: Codable, Equatable, Identifiable, Sendable {
    let source: Source
    let name: String               // "eBay"
    var ready: Bool                // false: not set up on the server yet; shown greyed, cannot be chosen
    var auctions: Bool             // the site has auctions: the thing form offers "Include auctions"

    var id: Source { source }

    init(source: Source, name: String, ready: Bool = true, auctions: Bool = false) {
        self.source = source
        self.name = name
        self.ready = ready
        self.auctions = auctions
    }

    /// `ready` and `auctions` came after the site and its name: a server without them means set up, no auctions.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        source = try c.decode(Source.self, forKey: .source)
        name = try c.decode(String.self, forKey: .name)
        ready = try c.decodeIfPresent(Bool.self, forKey: .ready) ?? true
        auctions = try c.decodeIfPresent(Bool.self, forKey: .auctions) ?? false
    }
}

/// `GET /kinds`: a kind of search and its sites, in the server's order. A kind this build does not know is kept as
/// `HuntKind.unknown` and offered nowhere.
struct OfferedKind: Codable, Equatable, Sendable {
    let kind: HuntKind
    let name: String               // "Something to buy"
    let sources: [KindSource]
}

/// The sites' names from the server's answers: the overview's sites (`SourceStatus.name`) and `/kinds`. A site no
/// answer named yet (offline at launch) shows the name it had in the app before, if it is one of those four, else its
/// id; the app makes up no name.
struct SiteNames: Equatable, Sendable {
    private var names: [Source: String] = [:]

    init(statuses: [SourceStatus] = [], kinds: [OfferedKind]? = nil) {
        for kind in kinds ?? [] {
            for site in kind.sources { names[site.source] = site.name }
        }
        for status in statuses { names[status.source] = status.name }
    }

    func name(_ source: Source) -> String {
        names[source] ?? source.earlierName ?? source.rawValue
    }
}

/// What a search form shows under Portals: the sites `/kinds` offers for its kind, in the server's order, or the lists
/// of before while there is no answer (offline, a server from before `/kinds`); then any site the search has chosen that
/// the list leaves out, so it can be switched off. A site that is not set up shows greyed and cannot be switched on (one
/// that is on can still be switched off); one line under the sites says why. The thing form's auction switch shows
/// while a chosen site has auctions.
struct SiteChoices: Equatable {
    let sites: [KindSource]

    init(kind: SearchKind, kinds: [OfferedKind]?, chosen: Set<Source>, names: SiteNames) {
        let offered = kinds?.first { $0.kind == kind.huntKind }?.sources
            ?? Self.fallback(kind).map { KindSource(source: $0, name: names.name($0)) }
        let listed = Set(offered.map(\.source))
        let others = Source.ordered(chosen.subtracting(listed)).map { KindSource(source: $0, name: names.name($0)) }
        sites = offered + others
    }

    /// The lists of before `/kinds`: the four flat portals, and Kleinanzeigen for things.
    static func fallback(_ kind: SearchKind) -> [Source] {
        switch kind {
        case .flat: Source.flatPortals
        case .item: [.kleinanzeigen]
        }
    }

    /// A site that is not set up cannot be switched on; one that is on can always be switched off.
    func canSwitch(_ site: KindSource, chosen: Set<Source>) -> Bool {
        site.ready || chosen.contains(site.source)
    }

    /// The thing form's "Include auctions" shows while a chosen site has auctions.
    func showsAuctions(chosen: Set<Source>) -> Bool {
        sites.contains { $0.auctions && chosen.contains($0.source) }
    }

    /// The line under the sites while some are not set up: "eBay is not set up yet.", "eBay and Example are not set up
    /// yet." Nil while every site is.
    func notReadyLine(language: AppLanguage = .current) -> String? {
        let names = sites.filter { !$0.ready }.map(\.name)
        guard !names.isEmpty else { return nil }
        let list = names.formatted(.list(type: .and).locale(language.locale))
        return names.count == 1 ? language.string("\(list) is not set up yet.") : language.string("\(list) are not set up yet.")
    }
}
