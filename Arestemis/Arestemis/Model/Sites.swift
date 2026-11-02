import Foundation

/// The sites Arestemis reads (brief 119). The server decides about them: it names every site (`SourceStatus.name`,
/// `Listing.source_name`, `GET /kinds`), says which kind of search can use which site, whether a site is set up there
/// (`ready`), whether it has auctions and how its listings change hands (`delivery`, brief 129). The app keeps every site
/// the server names, shows it by the server's name and offers what `/kinds` offers, so a new site needs no app update.

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

/// How a site's listings change hands (`KindSource.delivery`, brief 129): IKEA Preowned's are only picked up, Vinted's
/// and mydealz's only shipped, the others' either way. The server says it; the app never decides it for a site.
enum SiteDelivery: String, Codable, Sendable {
    case both, pickup, shipping

    /// Whether a thing search with this delivery choice can use such a site. A pickup-only site cannot serve a
    /// shipping-only search, a shipping-only site not a pickup-only one; "either" can use every site.
    func serves(_ delivery: Delivery) -> Bool {
        switch (self, delivery) {
        case (.pickup, .shipping), (.shipping, .pickup): false
        default: true
        }
    }
}

/// `GET /kinds`: one site a kind of search can use.
struct KindSource: Codable, Equatable, Identifiable, Sendable {
    let source: Source
    let name: String               // "eBay"
    var ready: Bool                // false: not set up on the server yet; shown greyed, cannot be chosen
    var auctions: Bool             // the site has auctions: the thing form offers "Include auctions"
    var delivery: SiteDelivery     // pickup or shipping only: greyed in a thing search it cannot serve

    var id: Source { source }

    init(source: Source, name: String, ready: Bool = true, auctions: Bool = false, delivery: SiteDelivery = .both) {
        self.source = source
        self.name = name
        self.ready = ready
        self.auctions = auctions
        self.delivery = delivery
    }

    /// `ready`, `auctions` and `delivery` came after the site and its name: a server without them means set up, no
    /// auctions, both ways. A delivery this build does not know counts as both too: the server still refuses what the
    /// site cannot serve, and the app greys only what it was told.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        source = try c.decode(Source.self, forKey: .source)
        name = try c.decode(String.self, forKey: .name)
        ready = try c.decodeIfPresent(Bool.self, forKey: .ready) ?? true
        auctions = try c.decodeIfPresent(Bool.self, forKey: .auctions) ?? false
        delivery = try c.decodeIfPresent(SiteDelivery.self, forKey: .delivery) ?? .both
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
/// the list leaves out, so it can be switched off. A site that is not set up, or (in the thing form) cannot serve the
/// chosen delivery, shows greyed and cannot be switched on (one that is on can still be switched off); one line under the
/// sites says why. The thing form's auction switch shows while a chosen site has auctions.
struct SiteChoices: Equatable {
    let sites: [KindSource]
    /// The thing form's delivery choice; nil in the flat form, where every site serves.
    let delivery: Delivery?

    init(kind: SearchKind, kinds: [OfferedKind]?, chosen: Set<Source>, names: SiteNames, delivery: Delivery? = nil) {
        let offered = kinds?.first { $0.kind == kind.huntKind }?.sources
            ?? Self.fallback(kind).map { KindSource(source: $0, name: names.name($0)) }
        let listed = Set(offered.map(\.source))
        let others = Source.ordered(chosen.subtracting(listed)).map { KindSource(source: $0, name: names.name($0)) }
        sites = offered + others
        self.delivery = delivery
    }

    /// The lists of before `/kinds`: the four flat portals, and Kleinanzeigen for things.
    static func fallback(_ kind: SearchKind) -> [Source] {
        switch kind {
        case .flat: Source.flatPortals
        case .item: [.kleinanzeigen]
        }
    }

    /// Whether the site can serve the chosen delivery (always, in the flat form and for a site the server gave no
    /// delivery).
    func serves(_ site: KindSource) -> Bool {
        delivery.map(site.delivery.serves) ?? true
    }

    /// Set up and able to serve the delivery: shown in ink, and it can be switched on.
    func isOpen(_ site: KindSource) -> Bool {
        site.ready && serves(site)
    }

    /// A site that is not open cannot be switched on; one that is on can always be switched off.
    func canSwitch(_ site: KindSource, chosen: Set<Source>) -> Bool {
        isOpen(site) || chosen.contains(site.source)
    }

    /// The thing form's "Include auctions" shows while a chosen site has auctions.
    func showsAuctions(chosen: Set<Source>) -> Bool {
        sites.contains { $0.auctions && chosen.contains($0.source) }
    }

    /// The line under the sites while some are greyed: why, each site named once. First the sites that are not set up
    /// ("eBay is not set up yet."), then those the delivery rules out, in the server's words ("IKEA Preowned is pickup
    /// only.", "mydealz and Vinted only ship."). A site ruled out by the delivery is named there only, since that holds
    /// even once it is set up. Nil while every site is open.
    func line(language: AppLanguage = .current) -> String? {
        let sentences = [notReadyLine(language: language), deliveryLine(language: language)].compactMap { $0 }
        return sentences.isEmpty ? nil : sentences.joined(separator: " ")
    }

    /// "eBay is not set up yet.", "eBay and Example are not set up yet." for the sites that could serve the delivery but
    /// are not set up; nil while there are none.
    func notReadyLine(language: AppLanguage = .current) -> String? {
        let names = sites.filter { !$0.ready && serves($0) }.map(\.name)
        guard !names.isEmpty else { return nil }
        let list = names.formatted(.list(type: .and).locale(language.locale))
        return names.count == 1 ? language.string("\(list) is not set up yet.") : language.string("\(list) are not set up yet.")
    }

    /// The sites the delivery rules out, as the server says it: "IKEA Preowned is pickup only." under Shipping, "Vinted
    /// only ships." / "mydealz and Vinted only ship." under Pickup (German "… gibt es nur zur Abholung." / "… gibt es
    /// nur mit Versand."); nil under Either and in the flat form.
    func deliveryLine(language: AppLanguage = .current) -> String? {
        let ruledOut = sites.filter { !serves($0) }
        guard let delivery, !ruledOut.isEmpty else { return nil }
        let list = ruledOut.map(\.name).formatted(.list(type: .and).locale(language.locale))
        let one = ruledOut.count == 1
        switch delivery {
        case .shipping: return one ? language.string("\(list) is pickup only.") : language.string("\(list) are pickup only.")
        case .pickup: return one ? language.string("\(list) only ships.") : language.string("\(list) only ship.")
        case .either: return nil
        }
    }
}
