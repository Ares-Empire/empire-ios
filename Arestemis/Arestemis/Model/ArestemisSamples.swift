import Foundation

/// The contract's made-up sample answers (Samples/, copies of Arestemis/docs/samples/), for the tests and for
/// `-sampleData`.
enum ArestemisSamples {
    nonisolated static let files = ["overview", "matches", "match", "rejected", "settings", "places", "hunts", "item-matches"]

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

#if DEBUG
/// `-sampleData`: the samples as a server in memory. Actions change the in-memory state (states, start/pause, the
/// search, settings); application texts are made up from the listing. Nothing leaves the device.
final class SampleBackend: ArestemisBackend {
    struct Options {
        var noHunt = false          // -sampleNoHunt: no search yet
        var paused = false          // -samplePaused
        var hangs = false           // -sampleLoading: the overview never arrives
        var moreLoading = false     // -sampleMoreLoading: pause the next listings page
        var moreFailure = false     // -sampleMoreFailure: fail the next listings page
        var longDescription = false // -sampleLongDescription: a description with More
        var ownMode = false         // -sampleOwnMode: the own text instead of automatic texts
        var noTexts = false         // -sampleNoTexts: no own text, notes or facts about you yet
    }

    private var base: Overview
    private var huntValues: [Hunt]
    private var nextHuntID: Int
    private var matches: [Match]
    private var rejectedItems: [Rejected]
    private var settingsValue: Settings
    private let knownPlaces: [Place]
    private let options: Options

    init(options: Options = Options(), now: Date = .now) throws {
        self.options = options
        // The sample's last scan becomes "40 s ago".
        let raw = try ArestemisSamples.decode(Overview.self, from: "overview")
        let lastScan = raw.lastScan.flatMap(Timestamp.parse) ?? now
        let shift = now.addingTimeInterval(-40).timeIntervalSince(lastScan)
        base = try ArestemisSamples.decode(Overview.self, from: "overview", shift: shift)
        let page = try ArestemisSamples.decode(MatchPage.self, from: "matches", shift: shift)
        let single = try ArestemisSamples.decode(Match.self, from: "match", shift: shift)
        matches = page.items + (page.items.contains { $0.id == single.id } ? [] : [single])
            + (try ArestemisSamples.decode(MatchPage.self, from: "item-matches", shift: shift)).items
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
        rejectedItems = try ArestemisSamples.decode(RejectedPage.self, from: "rejected", shift: shift).items
        settingsValue = try ArestemisSamples.decode(Settings.self, from: "settings")
        if options.ownMode { settingsValue.applicationMode = .own }
        if options.noTexts {
            settingsValue.ownText = ""
            settingsValue.applicationNotes = ""
            settingsValue.aboutMe = ""
        }
        let suggestions = try ArestemisSamples.decode([Place].self, from: "places")
        let searched = base.hunt?.search.flat?.places ?? []
        knownPlaces = searched + suggestions.filter { place in !searched.contains { $0.id == place.id } }
        huntValues = base.hunts.map(\.hunt)
        nextHuntID = (huntValues.map(\.id).max() ?? 0) + 1
        if options.noHunt {
            huntValues = []
            nextHuntID = 1
            matches = []
            rejectedItems = []
        }
        if options.paused { for index in huntValues.indices { huntValues[index].active = false } }
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
                     sources: hunt.active ? Self.sources(hunt.search) : [], slowed: false)
        }
        overview.latest = Array(visible.prefix(3))
        return overview
    }

    func hunts() async throws -> [Hunt] { huntValues }

    func createHunt(kind: HuntKind, name: String?, search: HuntSearch) async throws -> Hunt {
        guard huntValues.count < 30 else { throw HTTPError.server(409, "This account has 30 hunts. Delete one first.") }
        guard kind == search.kind else { throw HTTPError.server(400, "This hunt needs a newer app.") }
        let name = try Self.name(name)
        let now = ArestemisSamples.iso(.now)
        let created = Hunt(id: nextHuntID, kind: kind, name: name, active: false, search: search,
                           created: now, updated: now, activated: nil)
        nextHuntID += 1
        huntValues.append(created)
        return created
    }
    func updateHunt(id: Int, search: HuntSearch, name: String?) async throws -> Hunt {
        let index = try huntIndex(id)
        guard huntValues[index].kind == search.kind else { throw HTTPError.server(400, "The hunt kind cannot change.") }
        huntValues[index].name = try Self.name(name)
        huntValues[index].search = search
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
        switch search { case .flat(let search): search.sources; case .item(let search): search.sources; case .unsupported: [] }
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
        case .unknown: throw HTTPError.server(400, "This hunt needs a newer app.")
        }
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
        let text = mode == .own ? settingsValue.ownText
            : Self.writtenText(for: matches[index].listing, notes: settingsValue.applicationNotes, name: base.me.name)
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
#endif
