import Foundation

/// The contract's made-up sample answers (Samples/, copies of Arestemis/docs/samples/), for the tests and for
/// `-sampleData`.
enum ArestemisSamples {
    nonisolated static let files = ["overview", "matches", "match", "rejected", "settings", "places", "hunts", "item-matches",
                                    "ebay-match", "ikea-match", "vinted-match", "immowelt-match", "kinds", "watch-matches",
                                    "price-matches",
                                    "prices-9", "prices-10"]

    static func data(_ name: String) throws -> Data {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try Data(contentsOf: url)
    }

    static func decode<T: Decodable>(_ type: T.Type, from name: String, shift: TimeInterval = 0) throws -> T {
        let data = try data(name)
        return try JSONDecoder().decode(type, from: shift == 0 ? data : shifted(data, by: shift))
    }

    /// Moves every timestamp in a sample by `seconds`, so "found 4 min ago" stays true whenever the sample is opened.
    /// Dates without a time ("2026-12-01") stay as they are.
    static func shifted(_ data: Data, by seconds: TimeInterval) throws -> Data {
        func walk(_ value: Any) -> Any {
            switch value {
            case let dictionary as [String: Any]: return dictionary.mapValues(walk)
            case let array as [Any]: return array.map(walk)
            case let string as String where string.count >= 20 && string.contains("T"):
                guard let date = Timestamp.parse(string) else { return string }
                return iso(date.addingTimeInterval(seconds))
            default: return value
            }
        }
        let json = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        return try JSONSerialization.data(withJSONObject: walk(json), options: [.fragmentsAllowed])
    }

    static func iso(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}

/// What a sample server holds: the contract's files (`contract`, `-sampleData` and the tests) or the tour's own, in the
/// app's language (`TourData`, brief 139).
struct SampleContent {
    var overview: Overview
    var matches: [Match]
    var rejected: [Rejected]
    var settings: Settings
    var kinds: [OfferedKind]
    /// The places the place search knows besides the flat hunt's own.
    var places: [Place]
    /// Each price monitor's history, by hunt id.
    var histories: [Int: [PricePoint]]
    /// An application text for a listing, signed with the name; nil: the samples' German one.
    var application: ((Listing, String) -> String)? = nil

    /// The contract's sample files (copies of the server's `docs/samples`), their timestamps moved so the last scan was
    /// 40 s before `now`.
    static func contract(now: Date = .now) throws -> SampleContent {
        let raw = try ArestemisSamples.decode(Overview.self, from: "overview")
        let lastScan = raw.lastScan.flatMap(Timestamp.parse) ?? now
        let shift = now.addingTimeInterval(-40).timeIntervalSince(lastScan)
        let overview = try ArestemisSamples.decode(Overview.self, from: "overview", shift: shift)
        let page = try ArestemisSamples.decode(MatchPage.self, from: "matches", shift: shift)
        let single = try ArestemisSamples.decode(Match.self, from: "match", shift: shift)
        let matches = page.items + (page.items.contains { $0.id == single.id } ? [] : [single])
            + (try ArestemisSamples.decode(MatchPage.self, from: "item-matches", shift: shift)).items
            // The server's Immowelt listing (brief 141), whose description is only the site's preview.
            + (try ["ebay-match", "ikea-match", "vinted-match", "immowelt-match"].map {
                try ArestemisSamples.decode(Match.self, from: $0, shift: shift)
            })
            + (try ArestemisSamples.decode(MatchPage.self, from: "watch-matches", shift: shift)).items
            + (try ArestemisSamples.decode(MatchPage.self, from: "price-matches", shift: shift)).items
        var histories: [Int: [PricePoint]] = [:]
        for card in overview.hunts where card.hunt.kind == .price {
            if let prices = try? ArestemisSamples.decode(Prices.self, from: "prices-\(card.id)", shift: shift) {
                histories[card.id] = prices.points
            }
        }
        return SampleContent(overview: overview, matches: matches,
                             rejected: try ArestemisSamples.decode(RejectedPage.self, from: "rejected", shift: shift).items,
                             settings: try ArestemisSamples.decode(Settings.self, from: "settings"),
                             kinds: try ArestemisSamples.decode([OfferedKind].self, from: "kinds"),
                             places: try ArestemisSamples.decode([Place].self, from: "places"),
                             histories: histories)
    }
}

/// A sample server in memory: `-sampleData` on the contract's files (DEBUG, screenshots) and the tour on its own data
/// (every build, brief 139). Actions change the in-memory state (states, start/pause, the search, settings);
/// application texts are made up from the listing. Nothing leaves the device.
final class SampleBackend: ArestemisBackend {
    struct Options {
        var noHunt = false          // -sampleNoHunt: no search yet
        var paused = false          // -samplePaused
        var hangs = false           // -sampleLoading: the overview never arrives
        var moreLoading = false     // -sampleMoreLoading: pause the next listings page
        var moreFailure = false     // -sampleMoreFailure: fail the next listings page
        var longDescription = false // -sampleLongDescription: a long description (shown in full)
        var ownMode = false         // -sampleOwnMode: the own text instead of automatic texts
        var noTexts = false         // -sampleNoTexts: no own text, notes or facts about you yet
        var slowed = false          // -sampleSlowed: the thing hunt is read less often
        var newerKind = false       // -sampleNewerKind: a hunt of a kind this build does not know
        var ebayNotReady = false    // -sampleEbayNotReady: eBay without its keys on the server (greyed in the form)
        var watchRead: String?      // -sampleWatchRead <read>: the second watch's page state (screenshots)
        var preview: String?        // -pricePreview reading|refused|failed: how the product's preview answers
    }

    private var base: Overview
    private var huntValues: [Hunt]
    /// Each watch's page as last read, by hunt id.
    private var pages: [Int: PageState]
    /// Each monitor's product as last read, by hunt id.
    private var products: [Int: PriceState]
    /// Each monitor's year of history (its sample file, timestamps moved to now), by hunt id.
    private var histories: [Int: [PricePoint]]
    private var nextHuntID: Int
    private var matches: [Match]
    private var rejectedItems: [Rejected]
    private var settingsValue: Settings
    private var kindsValue: [OfferedKind]
    private let knownPlaces: [Place]
    private let application: ((Listing, String) -> String)?
    private let options: Options

    /// The contract's sample files (`-sampleData`), the last scan 40 s before `now`.
    convenience init(options: Options = Options(), now: Date = .now) throws {
        try self.init(content: .contract(now: now), options: options, now: now)
    }

    init(content: SampleContent, options: Options = Options(), now: Date = .now) throws {
        self.options = options
        base = content.overview
        matches = content.matches
        application = content.application
        if options.longDescription {
            // Extend only the fictional listing description, leaving the contract's fields unchanged.
            matches = try matches.map { match in
                var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(match)) as! [String: Any]
                var listing = object["listing"] as! [String: Any]
                listing["description"] = Array(repeating: match.listing.description, count: 4).joined(separator: "\n\n")
                object["listing"] = listing
                return try JSONDecoder().decode(Match.self, from: JSONSerialization.data(withJSONObject: object))
            }
        }
        rejectedItems = content.rejected
        settingsValue = content.settings
        kindsValue = content.kinds
        if options.ownMode { settingsValue.applicationMode = .own }
        if options.noTexts {
            settingsValue.ownText = ""
            settingsValue.applicationNotes = ""
            settingsValue.aboutMe = ""
        }
        let suggestions = content.places
        let searched = base.hunt?.search.flat?.places ?? []
        knownPlaces = searched + suggestions.filter { place in !searched.contains { $0.id == place.id } }
        huntValues = base.hunts.map(\.hunt)
        pages = Dictionary(uniqueKeysWithValues: base.hunts.compactMap { card in card.page.map { (card.id, $0) } })
        products = Dictionary(uniqueKeysWithValues: base.hunts.compactMap { card in card.price.map { (card.id, $0) } })
        histories = content.histories
        nextHuntID = (huntValues.map(\.id).max() ?? 0) + 1
        if let read = options.watchRead, let id = huntValues.filter({ $0.kind == .watch }).dropFirst().first?.id,
           let page = pages[id] {
            pages[id] = Self.page(page, reading: read, checked: base.lastScan)
        }
        if options.noHunt {
            huntValues = []
            nextHuntID = 1
            matches = []
            rejectedItems = []
        }
        if options.paused { for index in huntValues.indices { huntValues[index].active = false } }
        if options.ebayNotReady {
            // As the server without eBay's keys: eBay not set up, and no hunt reads it.
            kindsValue = kindsValue.map { offered in
                OfferedKind(kind: offered.kind, name: offered.name, sources: offered.sources.map { site in
                    var site = site
                    if site.source == .ebay { site.ready = false }
                    return site
                })
            }
            for index in huntValues.indices {
                guard case .item(var search) = huntValues[index].search else { continue }
                search.sources.removeAll { $0 == .ebay }
                huntValues[index].search = .item(search)
            }
        }
        if options.newerKind {
            let created = ArestemisSamples.iso(now)
            huntValues.append(Hunt(id: nextHuntID, kind: .unknown("car"), name: "Camper van", active: true,
                                   search: .unsupported, created: created, updated: created, activated: created))
            nextHuntID += 1
        }
    }

    func overview() async throws -> Overview {
        if options.hangs { try await Task.sleep(for: .seconds(3600)) }
        var overview = base
        overview.hunt = huntValues.first { $0.kind == .flat }
        overview.sources = base.sources.map { status in
            var status = status
            if !huntValues.contains(where: { hunt in
                hunt.active && Self.sources(hunt.search).contains(status.source)
            }) { status.state = .idle }
            return status
        }
        let visible = matches.filter { $0.state != .dismissed }.sorted { $0.id > $1.id }
        let today = visible.filter { match in
            Timestamp.parse(match.found).map { Calendar.app.isDateInToday($0) } ?? false
        }
        overview.counts = .init(new: visible.count { $0.state == .new }, today: today.count,
                                saved: visible.count { $0.state == .saved }, applied: visible.count { $0.state == .applied })
        overview.hunts = huntValues.map { hunt in
            HuntCard(hunt: hunt, counts: Self.counts(matches.filter { $0.huntID == hunt.id }),
                     sources: hunt.active ? Self.sources(hunt.search) : [],
                     slowed: options.slowed && hunt.active && hunt.kind == .item,
                     page: hunt.kind == .watch ? pages[hunt.id] : nil,
                     price: hunt.kind == .price ? products[hunt.id] : nil)
        }
        overview.latest = Array(visible.prefix(3))
        return overview
    }

    func kinds() async throws -> [OfferedKind] { kindsValue }

    func hunts() async throws -> [Hunt] { huntValues }

    func createHunt(kind: HuntKind, name: String?, search: HuntSearch) async throws -> Hunt {
        guard huntValues.count < 30 else { throw HTTPError.server(409, "This account has 30 hunts. Delete one first.") }
        guard kind == search.kind else { throw HTTPError.server(400, "This hunt needs a newer app.") }
        let name = try Self.name(name)
        if let watch = search.watch { try Self.check(watch) }
        if let monitor = search.price { try Self.check(monitor) }
        let now = ArestemisSamples.iso(.now)
        let created = Hunt(id: nextHuntID, kind: kind, name: name, active: false, search: search,
                           created: now, updated: now, activated: nil)
        if let watch = search.watch { pages[created.id] = Self.waiting(watch) }
        if let monitor = search.price { products[created.id] = Self.waiting(monitor) }
        nextHuntID += 1
        huntValues.append(created)
        return created
    }
    func updateHunt(id: Int, search: HuntSearch, name: String?) async throws -> Hunt {
        let index = try huntIndex(id)
        guard huntValues[index].kind == search.kind else { throw HTTPError.server(400, "The hunt kind cannot change.") }
        if let watch = search.watch {
            try Self.check(watch)
            // A new address or description is read again from the start, as on the server.
            let old = huntValues[index].search.watch
            if old?.url != watch.url || old?.change != watch.change || pages[id]?.read == .blocked {
                pages[id] = Self.waiting(watch)
            }
        }
        if let monitor = search.price {
            try Self.check(monitor)
            // A new link is read again from the start, as on the server; the switches change nothing of the read.
            if huntValues[index].search.price?.url != monitor.url || products[id]?.read == .blocked {
                products[id] = Self.waiting(monitor)
                histories[id] = nil
            }
        }
        huntValues[index].name = try Self.name(name)
        huntValues[index].search = search
        huntValues[index].updated = ArestemisSamples.iso(.now)
        return huntValues[index]
    }
    func renameHunt(id: Int, name: String?) async throws -> Hunt {
        let index = try huntIndex(id)
        huntValues[index].name = try Self.name(name)
        huntValues[index].updated = ArestemisSamples.iso(.now)
        return huntValues[index]
    }
    func setActive(id: Int, active: Bool) async throws -> Hunt {
        let index = try huntIndex(id)
        if active, !huntValues[index].active, huntValues.count(where: { $0.active }) >= 10 {
            throw HTTPError.server(409, "At most 10 hunts can run at once. Pause one first.")
        }
        huntValues[index].active = active
        if active { huntValues[index].activated = ArestemisSamples.iso(.now) }
        return huntValues[index]
    }
    func deleteHunt(id: Int) async throws {
        let index = try huntIndex(id)
        huntValues.remove(at: index)
        matches.removeAll { $0.huntID == id }
        rejectedItems.removeAll { $0.huntID == id }
    }
    private func huntIndex(_ id: Int) throws -> Int {
        guard let index = huntValues.firstIndex(where: { $0.id == id }) else { throw HTTPError.server(404, nil) }
        return index
    }
    private static func name(_ value: String?) throws -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard trimmed.count <= 60 else { throw HTTPError.server(400, "The name must be at most 60 characters.") }
        return trimmed.isEmpty ? nil : trimmed
    }
    private static func sources(_ search: HuntSearch) -> [Source] {
        switch search {
        case .flat(let search): search.sources
        case .item(let search): search.sources
        case .price, .watch, .unsupported: []
        }
    }

    /// The server's refusals of a watch, in its words (English, as the samples), so the form's lines at their fields can
    /// be seen without a server. Only an imitation: the real app never judges an address itself.
    private static func check(_ watch: WatchSearch) throws {
        let hunted = [("kleinanzeigen.de", "Kleinanzeigen"), ("ebay.de", "eBay"), ("vinted.de", "Vinted"),
                      ("wg-gesucht.de", "WG-Gesucht"), ("immowelt.de", "Immowelt"),
                      ("immobilienscout24.de", "ImmoScout24"), ("mydealz.de", "mydealz")]
        guard let host = WatchAddress.host(watch.url), host.contains("."), !host.hasSuffix(".local"),
              host != "localhost" else {
            throw FieldRefusal(field: "search.url", message: "This address can't be watched.")
        }
        if let site = hunted.first(where: { host == $0.0 || host.hasSuffix("." + $0.0) }) {
            throw FieldRefusal(field: "search.url", message: "\(site.1) has its own hunt in Arestemis.")
        }
        if watch.change.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw FieldRefusal(field: "search.change", message: "Describe the change to watch for.")
        }
    }

    /// The server's refusals of a monitor, in its words (English, as the samples): the watch's address rules, the switches'
    /// rule and an alarm without a condition. Only an imitation.
    private static func check(_ monitor: PriceSearch) throws {
        try check(WatchSearch(url: monitor.url, change: "price", every: monitor.every))
        if !monitor.history && monitor.alarm == nil {
            throw FieldRefusal(field: "search.history", message: "Choose the history, the alarm or both.")
        }
        if let alarm = monitor.alarm, !alarm.isComplete {
            throw FieldRefusal(field: "search.alarm", message: "Say when the alarm should ring.")
        }
    }

    /// A monitor saved with a new link: not read yet.
    private static func waiting(_ monitor: PriceSearch) -> PriceState {
        PriceState(host: WatchAddress.host(monitor.url) ?? "", read: .waiting)
    }

    /// A watch saved with a new address or description: not read yet.
    private static func waiting(_ watch: WatchSearch) -> PageState {
        PageState(host: WatchAddress.host(watch.url) ?? "", read: .waiting)
    }

    /// `-sampleWatchRead`: the second watch's page in another state, with the server's kind of note for it.
    private static func page(_ page: PageState, reading read: String, checked: String?) -> PageState {
        var page = page
        page.read = PageState.Read(rawValue: read)
        page.checked = checked
        switch page.read {
        case .waiting: page = PageState(host: page.host, read: .waiting)
        case .ok: page.now = "Cheapest offer 219 €"; page.note = nil
        case .unreadable: page.note = "This page doesn't show it; it may need a browser."
        case .failing: page.note = "The page has not answered since yesterday."
        case .blocked: page.note = "Cloudflare refuses the server."
        case .unknown: page.note = "Read in a new way."
        }
        return page
    }
    private static func counts(_ matches: [Match]) -> Overview.Counts {
        let visible = matches.filter { $0.state != .dismissed }
        return .init(new: visible.count { $0.state == .new },
                     today: visible.count { Timestamp.parse($0.found).map { Calendar.app.isDateInToday($0) } ?? false },
                     saved: visible.count { $0.state == .saved }, applied: visible.count { $0.state == .applied })
    }

    func parse(text: String, kind: HuntKind) async throws -> HuntParseResult {
        switch kind {
        case .flat: return .flat(try await parseFlat(text))
        case .item:
            let search = base.hunts.first { $0.hunt.kind == .item }?.hunt.search.item
            return .item(ParsedItemSearch(search: PartialItemSearch(query: search?.query, priceMax: search?.priceMax,
                                                                   delivery: search?.delivery, places: search?.places), unclear: []))
        case .price, .watch, .unknown: throw HTTPError.server(400, "This hunt needs a newer app.")
        }
    }

    /// An imitation of the server's preview for screenshots: the watch's address refusals, a link without a path is no
    /// single product, and a made-up product (the console on MediaMarkt, else one named after the link's last part).
    /// `-pricePreview reading|refused|failed` makes it wait, refuse or fail.
    func pricePreview(url: String) async throws -> PricePreview {
        switch options.preview {
        case "reading": try await Task.sleep(for: .seconds(3600))
        case "refused": throw FieldRefusal(field: "url", message: "This page shows no single product with a price.")
        case "failed": throw HTTPError.server(503, "The price could not be read right now. Try again in a moment.")
        default: try await Task.sleep(for: .milliseconds(600))
        }
        do { try Self.check(WatchSearch(url: url, change: "price", every: 60)) } catch let refusal as FieldRefusal {
            throw FieldRefusal(field: "url", message: refusal.message)
        }
        let address = url.contains("://") ? url : "https://" + url
        guard let parts = URLComponents(string: address), let host = parts.host,
              let last = parts.path.split(separator: "/").last else {
            throw FieldRefusal(field: "url", message: "This page shows no single product with a price.")
        }
        if host.contains("mediamarkt") {
            return PricePreview(product: "NINTENDO Switch 2", price: 483.99, currency: "EUR", availability: .inStock,
                                source: "shop")
        }
        let words = last.split(whereSeparator: { "-_.".contains($0) }).filter { !$0.allSatisfy(\.isNumber) && $0 != "html" }
        let product = words.prefix(4).map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
        return PricePreview(product: product.isEmpty ? host : product, price: 129.0, currency: "EUR",
                            availability: .inStock, source: "shop")
    }

    /// A monitor's history over the window, from its sample year; the lowest and highest in euros, as the server.
    func prices(hunt id: Int, days: Int) async throws -> Prices {
        let index = try huntIndex(id)
        guard huntValues[index].search.price?.history == true else { throw HTTPError.server(404, nil) }
        let start = Date.now.addingTimeInterval(-Double(days) * 86_400)
        let points = (histories[id] ?? []).filter { (Timestamp.parse($0.at) ?? .distantPast) >= start }
        let euros = points.filter { $0.currency == "EUR" }.map(\.price)
        return Prices(points: points, low: euros.min(), high: euros.max())
    }

    private func parseFlat(_ text: String) async throws -> ParsedSearch {
        try await Task.sleep(for: .milliseconds(600))
        let year = Calendar.app.component(.year, from: .now)
        let munich = knownPlaces.first { $0.name == "München" }
        return ParsedSearch(search: PartialSearch(kinds: [.flat, .wg], people: 2, places: munich.map { [$0] },
                                                  districts: ["Schwabing"], rentWarmMax: 1400,
                                                  moveInFrom: "\(year)-12-01", extra: "möbliert"),
                            unclear: ["No size given, so any size is fine."])
    }

    func places(query: String) async throws -> [Place] {
        let wanted = query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        return Array(knownPlaces.filter {
            $0.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).contains(wanted)
        }.prefix(10))
    }

    func matches(hunt: Int?, state states: [MatchState]?, limit: Int, before: Int?) async throws -> MatchPage {
        if let hunt { _ = try huntIndex(hunt) }
        if before != nil {
            if options.moreLoading { try await Task.sleep(for: .seconds(3600)) }
            if options.moreFailure { throw HTTPError.server(500, String(localized: "Could not load older listings.")) }
        }
        let wanted = matches.filter { match in
            (hunt == nil || match.huntID == hunt) && (states?.contains(match.state) ?? (match.state != .dismissed)) && match.id < (before ?? .max)
        }.sorted { $0.id > $1.id }
        return MatchPage(items: Array(wanted.prefix(limit)), more: wanted.count > limit || (before == nil && (options.moreLoading || options.moreFailure)))
    }

    /// An imitation of the server's search (brief 132) for screenshots, much simpler than the server's: every word must
    /// begin a word of the listing; a title counts most, then the place, then the description and a page's lines; ties
    /// newest first. The real app never ranks: it shows the server's order.
    func findMatches(_ words: String, hunt: Int?, limit: Int) async throws -> MatchPage {
        if let hunt { _ = try huntIndex(hunt) }
        let wanted = Self.folded(words)
        guard !wanted.isEmpty else { return MatchPage(items: [], more: false) }
        let scored: [(match: Match, score: Int)] = matches.compactMap { match in
            guard match.state != .dismissed, hunt == nil || match.huntID == hunt else { return nil }
            let listing = match.listing
            let fields: [(words: [String], weight: Int)] = [
                (Self.folded(listing.title), 3),
                (Self.folded([listing.city, listing.district].compactMap { $0 }.joined(separator: " ")), 2),
                (Self.folded(([listing.description] + (listing.page.map { $0.added + $0.removed } ?? []))
                    .joined(separator: " ")), 1),
            ]
            var score = 0
            for word in Set(wanted) {
                let best = fields.filter { $0.words.contains { $0.hasPrefix(word) } }.map(\.weight).max()
                guard let best else { return nil }
                score += best
            }
            return (match, score)
        }
        let ranked = scored.sorted { a, b in
            if a.score != b.score { return a.score > b.score }
            if a.match.found != b.match.found { return a.match.found > b.match.found }
            return a.match.id > b.match.id
        }.map(\.match)
        return MatchPage(items: Array(ranked.prefix(limit)), more: ranked.count > limit)
    }

    /// Casefolded words without accents, ß as ss, split at anything but letters and digits.
    private static func folded(_ text: String) -> [String] {
        text.replacingOccurrences(of: "ß", with: "ss")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "de_DE"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
    }

    func match(id: Int) async throws -> Match {
        guard let match = matches.first(where: { $0.id == id }) else { throw HTTPError.server(404, "This listing is gone.") }
        return match
    }

    func setState(_ state: MatchState, match id: Int) async throws -> Match {
        guard let index = matches.firstIndex(where: { $0.id == id }) else { throw HTTPError.server(404, nil) }
        matches[index].state = state
        return matches[index]
    }

    func application(match id: Int, regenerate: Bool) async throws -> Application {
        guard let index = matches.firstIndex(where: { $0.id == id }) else { throw HTTPError.server(404, nil) }
        guard matches[index].listing.item == nil else { throw HTTPError.server(400, "Application texts are for flats.") }
        if let cached = matches[index].application, !regenerate { return cached }
        try await Task.sleep(for: .milliseconds(900))
        let mode = settingsValue.applicationMode
        let listing = matches[index].listing
        let text = mode == .own ? settingsValue.ownText
            : application?(listing, base.me.name)
                ?? Self.writtenText(for: listing, notes: settingsValue.applicationNotes, name: base.me.name)
        let written = Application(text: text, mode: mode, created: ArestemisSamples.iso(.now))
        matches[index].application = written
        return written
    }

    func rejected(hunt: Int?, limit: Int) async throws -> RejectedPage {
        if let hunt { _ = try huntIndex(hunt) }
        return RejectedPage(items: Array(rejectedItems.filter { hunt == nil || $0.huntID == hunt }.prefix(limit)))
    }

    func settings() async throws -> Settings { settingsValue }

    func saveSettings(_ settings: Settings) async throws -> Settings {
        settingsValue = settings
        return settings
    }

    /// A made-up automatic text for the sample (German, like the real ones), with the notes as their own paragraph.
    private static func writtenText(for listing: Listing, notes: String, name: String) -> String {
        let moveIn = listing.availableFrom.flatMap { DateOnly.parse($0) }.map {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "de_DE")
            formatter.dateFormat = "d. MMMM"
            return " Der Einzug ab \(formatter.string(from: $0)) passt mir sehr gut."
        } ?? ""
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let notesParagraph = trimmed.isEmpty ? "" : "\n\n" + trimmed
        return """
        Hallo,

        mit großem Interesse habe ich Ihre Anzeige „\(listing.title)“ gelesen.\(moveIn) Ich lebe ruhig und ordentlich, \
        bin Nichtraucher, und die Miete ist gesichert.\(notesParagraph)

        Über einen Besichtigungstermin würde ich mich sehr freuen; ich bin zeitlich flexibel.

        Viele Grüße
        \(name)
        """
    }
}
