import Foundation

/// "How do I get my file?": per bank, the steps to get a file of one's payments out of the bank's website or app, the
/// file to pick and why, the limits and how the file reaches Aresium. The data is `Guide/bank-steps.json` (researched
/// for brief 19 from public sources; how and what is unsure: docs/bank-export-guide/README.md), shown as it is. The
/// screens are `Screens/BankGuideScreens.swift`.
nonisolated struct BankGuide: Decodable, Sendable {
    /// The day the steps were checked.
    let checked: String
    /// The shared ways a file reaches Aresium (Safari's download, a bank app's Share, a computer, …), by key.
    let ways: [Way.Key: Way]
    /// The banks in the guide's order; "Another bank" (`Bank.otherID`) is one of them.
    let banks: [Bank]

    private enum CodingKeys: String, CodingKey { case checked, ways = "toAresium", banks }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        checked = try container.decode(String.self, forKey: .checked)
        banks = try container.decode([Bank].self, forKey: .banks)
        // Keyed by the enum, so a way the app does not know fails here (and in the tests), not on the screen.
        let raw = try container.decode([String: Way].self, forKey: .ways)
        var ways: [Way.Key: Way] = [:]
        for (name, way) in raw {
            guard let key = Way.Key(rawValue: name) else {
                throw DecodingError.dataCorruptedError(forKey: .ways, in: container,
                                                       debugDescription: "Unknown way \(name)")
            }
            ways[key] = way
        }
        self.ways = ways
    }

    /// The guide shipped with the app.
    static func bundled(_ bundle: Bundle = .main) throws -> BankGuide {
        guard let url = bundle.url(forResource: "bank-steps", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder().decode(BankGuide.self, from: Data(contentsOf: url))
    }

    func bank(_ id: String) -> Bank? { banks.first { $0.id == id } }

    /// The banks whose names match what the person typed (`BankSearch`), in the guide's order; "Another bank" always
    /// last, so there is always somewhere to go.
    func search(_ query: String) -> [Bank] {
        let other = banks.filter(\.isOther)
        let named = banks.filter { !$0.isOther }
        let words = BankSearch.words(query)
        guard !words.isEmpty else { return named + other }
        return named.filter { BankSearch.matches(words, names: $0.names + [$0.title.en]) } + other
    }

    /// What the guide's list shows for a search.
    enum Results {
        /// The matching banks (every bank before anything is typed), Another bank last.
        case banks([Bank])
        /// Something was typed and no bank matches: Another bank's steps show in place, with "Tell us about your
        /// bank" (brief 25).
        case unknown(Bank)
    }

    func results(_ query: String) -> Results {
        let found = search(query)
        if !BankSearch.words(query).isEmpty, !found.contains(where: { !$0.isOther }),
           let other = found.first(where: \.isOther) {
            return .unknown(other)
        }
        return .banks(found)
    }
}

// MARK: - the parts

extension BankGuide {
    /// One bank (or "Another bank").
    nonisolated struct Bank: Decodable, Identifiable, Sendable {
        static let otherID = "other"

        let id: String
        /// What people call the bank, for the search.
        let names: [String]
        let website: Place
        let app: Place
        /// The ways this bank's file reaches Aresium, the usual one first.
        let toAresium: [Way.Key]
        let fileType: FileType
        let limits: Localized<String>
        let confidence: Confidence
        /// The bank's name on the screen; "Another bank" has none in the data and is named by the app.
        let title: Localized<String>

        private enum CodingKeys: String, CodingKey {
            case id, names, website, app, toAresium, fileType, limits, confidence, title
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            names = try container.decode([String].self, forKey: .names)
            website = try container.decode(Place.self, forKey: .website)
            app = try container.decode(Place.self, forKey: .app)
            toAresium = try container.decode([Way.Key].self, forKey: .toAresium)
            fileType = try container.decode(FileType.self, forKey: .fileType)
            limits = try container.decode(Localized<String>.self, forKey: .limits)
            confidence = try container.decode(Confidence.self, forKey: .confidence)
            title = try container.decodeIfPresent(Localized<String>.self, forKey: .title)
                ?? Localized(de: AppLanguage.german.string("Another bank"), en: AppLanguage.english.string("Another bank"))
        }

        var isOther: Bool { id == Self.otherID }

        func place(_ kind: PlaceKind) -> Place { kind == .website ? website : app }

        /// The places with steps, website first (the bank page's switch shows only these).
        var placesWithSteps: [PlaceKind] { PlaceKind.allCases.filter { place($0).hasSteps } }

        /// Where the page opens: the usual way first (`toAresium`'s first is a bank app's Share → the app), else the
        /// first place with steps.
        var firstPlace: PlaceKind {
            let usual: PlaceKind = toAresium.first == .share ? .app : .website
            return place(usual).hasSteps ? usual : (placesWithSteps.first ?? .website)
        }

        /// The ways that fit a place: the bank app's Share for the app, the others (Safari, a computer, …) for the
        /// website.
        func ways(for kind: PlaceKind) -> [Way.Key] {
            let fitting = toAresium.filter { ($0 == .share) == (kind == .app) }
            // A bank app without Share in the data still gets the way out of an app.
            return fitting.isEmpty && kind == .app ? [.share] : fitting
        }

        /// A button's label may differ at this bank: the steps are not from the bank's own recent page.
        func mayDiffer(_ kind: PlaceKind) -> Bool { confidence.of(kind) != .high }

        /// When only one place has steps, one line on the other: it has no file export, or no source describes one.
        func otherPlaceLine(_ language: AppLanguage = .current) -> String? {
            guard placesWithSteps.count == 1, let shown = placesWithSteps.first else { return nil }
            let other: PlaceKind = shown == .website ? .app : .website
            let unknown = place(other).status == .unsure
            switch (other, unknown) {
            case (.app, false): return language.string("This doesn't work in the bank's app, only on the website.")
            case (.app, true): return language.string("Aresium knows no way in the bank's app; the website works.")
            case (.website, false): return language.string("This doesn't work on the website, only in the bank's app.")
            case (.website, true): return language.string("Aresium knows no way on the website; the bank's app works.")
            }
        }
    }

    enum PlaceKind: String, CaseIterable, Sendable { case website, app }

    /// The website or the app: whether a file export is there, and its steps.
    nonisolated struct Place: Decodable, Sendable {
        enum Status: String, Decodable, Sendable {
            /// The steps come from a source.
            case found
            /// A part is not confirmed (the bank's notes say which); without steps: no source describes an export.
            case unsure
            /// No file export there.
            case none
        }

        let status: Status
        let de: [String]?
        let en: [String]?

        var hasSteps: Bool { status != .none && !(de ?? []).isEmpty && !(en ?? []).isEmpty }

        func steps(_ language: AppLanguage = .current) -> [String] {
            guard hasSteps else { return [] }
            return (language == .german ? de : en) ?? []
        }
    }

    /// The file to pick (the bank's own label or labels) and, in one line, why.
    nonisolated struct FileType: Decodable, Sendable {
        let pick: Localized<[String]>
        let de: String
        let en: String

        func why(_ language: AppLanguage = .current) -> String { language == .german ? de : en }
    }

    nonisolated struct Confidence: Decodable, Sendable {
        enum Level: String, Decodable, Sendable { case high, medium, low }
        let website: Level
        let app: Level

        func of(_ kind: PlaceKind) -> Level { kind == .website ? website : app }
    }

    /// A way the file reaches Aresium: three short steps and sometimes one "or" line.
    nonisolated struct Way: Decodable, Sendable {
        enum Key: String, Decodable, CaseIterable, Sendable {
            case safari, share, computer, unzip, desktopSite, numbers
        }

        let de: [String]
        let en: [String]
        let alsoDe: String?
        let alsoEn: String?

        func steps(_ language: AppLanguage = .current) -> [String] { language == .german ? de : en }
        func also(_ language: AppLanguage = .current) -> String? { language == .german ? alsoDe : alsoEn }
    }
}

/// A text (or a list) in German and English. In the data either `{"de": …, "en": …}`, or one value for both (a bank's
/// name, a label that is the same in both).
nonisolated struct Localized<Value: Decodable & Sendable>: Decodable, Sendable {
    let de: Value
    let en: Value

    init(de: Value, en: Value) {
        self.de = de
        self.en = en
    }

    private enum CodingKeys: String, CodingKey { case de, en }

    init(from decoder: Decoder) throws {
        if let container = try? decoder.container(keyedBy: CodingKeys.self),
           let de = try? container.decode(Value.self, forKey: .de) {
            self.de = de
            en = try container.decode(Value.self, forKey: .en)
        } else {
            let value = try decoder.singleValueContainer().decode(Value.self)
            de = value
            en = value
        }
    }

    func callAsFunction(_ language: AppLanguage = .current) -> Value { language == .german ? de : en }
}

/// The guide's search: a bank matches when every typed word starts a word of one of its names ("spark", "vr bank",
/// "dkb visa"), or when one of its names is among the typed words ("Kreissparkasse Heilbronn" finds the Sparkasse).
/// Case, accents and ß don't count.
nonisolated enum BankSearch {
    static func words(_ text: String) -> [String] {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "de_DE"))
            .replacingOccurrences(of: "ß", with: "ss")
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
    }

    static func matches(_ query: [String], names: [String]) -> Bool {
        names.contains { name in
            let nameWords = words(name)
            guard !nameWords.isEmpty else { return false }
            let typedStartsName = query.allSatisfy { typed in nameWords.contains { $0.hasPrefix(typed) } }
            let nameInTyped = nameWords.allSatisfy { query.contains($0) }
            return typedStartsName || nameInTyped
        }
    }
}
