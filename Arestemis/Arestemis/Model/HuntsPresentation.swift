import Foundation

/// What the Hunts and Listings tabs show of the account's hunts, decided here so the screens only lay it out: the kinds
/// this build can make (the New search dialog), a hunt's lines on its card and page, which actions its page offers, the
/// Listings tab's hunt chips and the word for the "applied" state, the rename field's rule and the radius steps.

/// The kinds of search this build can make and edit. A hunt of another kind (from a newer server) shows its name and
/// "Needs a newer app", nothing else.
enum SearchKind: String, CaseIterable, Hashable, Identifiable, Sendable {
    case flat, item
    var id: String { rawValue }

    init?(_ kind: HuntKind) {
        switch kind {
        case .flat: self = .flat
        case .item: self = .item
        case .unknown: return nil
        }
    }

    var huntKind: HuntKind { self == .flat ? .flat : .item }

    /// New search's dialog, in this order: "Flat or room", "Something to buy".
    static let choices: [SearchKind] = [.flat, .item]

    /// The dialog's button for this kind.
    func choiceTitle(language: AppLanguage = .current) -> String {
        switch self {
        case .flat: language.string("Flat or room")
        case .item: language.string("Something to buy")
        }
    }

    /// The small mark on a hunt's card and chip (SF Symbols): a house for a flat, a tag for a thing.
    var symbol: String { self == .flat ? "house" : "tag" }

    /// The "applied" state's word: flats are applied for, a thing's seller is asked.
    func appliedWord(language: AppLanguage = .current) -> String {
        self == .flat ? language.string("Applied") : language.string("Asked")
    }
}

/// A hunt's lines on its card and its page.
struct HuntText: Equatable {
    /// nil: a kind (or a search) this build cannot show.
    let kind: SearchKind?
    /// The hunt's own name, else what it looks for ("Flat or WG room", "Herman Miller Aeron").
    let title: String
    /// Places, price, dates …; with an own name, what it looks for first. Lines break only between parts.
    let details: String?
    /// Instead of the details, for a hunt this build cannot show: "Needs a newer app".
    let newerApp: String?

    /// `sites`: the server's names for a thing hunt's sites (`ArestemisStore.siteNames`).
    init(_ hunt: Hunt, sites: SiteNames = SiteNames(), now: Date = .now, calendar: Calendar = .app,
         language: AppLanguage = .current) {
        let ownName = hunt.name.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 }
        guard let kind = SearchKind(hunt.kind), hunt.search != .unsupported else {
            self.kind = nil
            title = ownName ?? language.string("Search")
            details = nil
            newerApp = language.string("Needs a newer app")
            return
        }
        let summary = HuntSummary(hunt, sites: sites, now: now, calendar: calendar, language: language)
        let parts = (ownName == nil ? [] : [summary.title]) + summary.parts
        self.kind = kind
        title = ownName ?? summary.title
        details = parts.isEmpty ? nil : parts.map(SearchSummary.unbreakable).joined(separator: " · ")
        newerApp = nil
    }
}

/// What a hunt's page offers. A hunt this build cannot show can still be listed, renamed and deleted, but not
/// started, paused or edited.
struct HuntPageActions: Equatable {
    let startPause: Bool
    let editSearch: Bool
    let listings = true
    let rename = true
    let delete = true

    init(_ hunt: Hunt) {
        let known = SearchKind(hunt.kind) != nil && hunt.search != .unsupported
        startPause = known
        editSearch = known
    }

    /// The figures under the hunt's card: New, Today, and Applied (flats) or Asked (things).
    static func figureLabels(_ kind: SearchKind?, language: AppLanguage = .current) -> [String] {
        [language.string("New"), language.string("Today"), (kind ?? .flat).appliedWord(language: language)]
    }
}

/// One chip over the Listings tab: All, or one hunt.
struct HuntChip: Equatable, Identifiable {
    /// nil = All.
    let huntID: Int?
    let title: String
    /// The hunt's kind mark; none for All and for a kind this build does not know.
    let symbol: String?
    var id: String { huntID.map(String.init) ?? "all" }
}

enum HuntChips {
    /// "All" and one chip per hunt, oldest first; none while there is only one hunt (All would be the same list).
    static func chips(_ hunts: [HuntCard], language: AppLanguage = .current) -> [HuntChip] {
        guard hunts.count > 1 else { return [] }
        return [HuntChip(huntID: nil, title: language.string("All"), symbol: nil)]
            + hunts.map { card in
                HuntChip(huntID: card.id, title: HuntText(card.hunt, language: language).title,
                         symbol: SearchKind(card.hunt.kind)?.symbol)
            }
    }

    /// True while only things are shown: the chosen hunt is a thing hunt, or with All, every hunt is one. The picker
    /// then says "Asked" for the applied state.
    static func showsOnlyThings(_ hunts: [HuntCard], selected: Int?) -> Bool {
        if let selected { return hunts.first { $0.id == selected }?.hunt.kind == .item }
        return !hunts.isEmpty && hunts.allSatisfy { $0.hunt.kind == .item }
    }
}

/// A hunt's own name (Rename): 1 to 60 characters; empty clears it, so the hunt is named after its search again.
enum HuntName {
    static let maxLength = 60

    /// What the rename field keeps while typing.
    static func limited(_ text: String) -> String { String(text.prefix(maxLength)) }

    /// What is sent: trimmed, nil when empty.
    static func cleaned(_ text: String) -> String? {
        let trimmed = limited(text).trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// The thing form's radius around each place, in steps (km).
enum RadiusSteps {
    static let steps: [Double] = [5, 10, 20, 50, 100, 200]

    /// The next step above (a value between two steps goes to the upper one); the largest stays.
    static func up(from value: Double) -> Double {
        steps.first { $0 > value } ?? steps[steps.count - 1]
    }

    /// The next step below (a value between two steps goes to the lower one); the smallest stays.
    static func down(from value: Double) -> Double {
        steps.last { $0 < value } ?? steps[0]
    }
}

extension MatchState {
    /// The word a row shows for a state that is not obvious from the list it is in; a thing's seller is "Asked".
    func word(thing: Bool = false, language: AppLanguage = .current) -> String? {
        switch self {
        case .saved: language.string("Saved")
        case .applied: (thing ? SearchKind.item : .flat).appliedWord(language: language)
        case .new, .dismissed: nil
        }
    }
}

extension Match {
    /// A thing for sale (its listing has the item details): no application, "Asked" for the applied state.
    var isThing: Bool { listing.item != nil }
}
