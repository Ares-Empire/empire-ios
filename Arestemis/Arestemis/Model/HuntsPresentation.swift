import Foundation

/// What the Hunts and Listings tabs show of the account's hunts, decided here so the screens only lay it out: the kinds
/// this build can make (the New search dialog), a hunt's lines on its card and page, which actions its page offers, the
/// Listings tab's hunt chips and the word for the "applied" state, the rename field's rule and the radius steps.

/// The kinds of search this build can make and edit: a flat, a thing for sale, and a page to watch (brief 131). A hunt
/// of another kind (from a newer server) shows its name and "Needs a newer app", nothing else.
enum SearchKind: String, CaseIterable, Hashable, Identifiable, Sendable {
    case flat, item, watch
    var id: String { rawValue }

    init?(_ kind: HuntKind) {
        switch kind {
        case .flat: self = .flat
        case .item: self = .item
        case .watch: self = .watch
        case .unknown: return nil
        }
    }

    var huntKind: HuntKind {
        switch self {
        case .flat: .flat
        case .item: .item
        case .watch: .watch
        }
    }

    /// Every kind this build can make, in New search's order: "Flat or room", "Something to buy", "Watch a page".
    static let all: [SearchKind] = [.flat, .item, .watch]

    /// New search's dialog: the kinds the server offers (`GET /kinds`) that this build can make, in this build's order;
    /// all of them while there is no answer (offline, a server from before `/kinds`), or when the answer names none of
    /// them, so the dialog is never empty. The server still refuses a kind it does not know.
    static func choices(offered kinds: [OfferedKind]?) -> [SearchKind] {
        guard let kinds else { return all }
        let offered = Set(kinds.map(\.kind))
        let choices = all.filter { offered.contains($0.huntKind) }
        return choices.isEmpty ? all : choices
    }

    /// The dialog's button for this kind.
    func choiceTitle(language: AppLanguage = .current) -> String {
        switch self {
        case .flat: language.string("Flat or room")
        case .item: language.string("Something to buy")
        case .watch: language.string("Watch a page")
        }
    }

    /// The small mark on a hunt's card and chip (SF Symbols): a house for a flat, a tag for a thing, an eye for a page.
    var symbol: String {
        switch self {
        case .flat: "house"
        case .item: "tag"
        case .watch: "eye"
        }
    }

    /// The "applied" state's word: flats are applied for, a thing's seller is asked. A watch's change is neither (its
    /// page offers only Save and Dismiss).
    func appliedWord(language: AppLanguage = .current) -> String {
        self == .item ? language.string("Asked") : language.string("Applied")
    }
}

/// The words for a hunt that name what it is: a search (a flat or a thing) or a watch ("Beobachtung"). A hunt of a kind
/// this build does not know (`nil`) is a search.
struct HuntWords: Equatable {
    let kind: SearchKind?
    let language: AppLanguage

    init(_ kind: SearchKind?, language: AppLanguage = .current) {
        self.kind = kind
        self.language = language
    }

    private var watch: Bool { kind == .watch }
    private func pick(_ search: LocalizedStringResource, _ watch: LocalizedStringResource) -> String {
        self.watch ? language.string(watch) : language.string(search)
    }

    /// The status beside the pulse: "Hunting" / "Watching", or "Paused".
    func status(active: Bool) -> String {
        active ? pick("Hunting", "Watching") : language.string("Paused")
    }
    /// The one primary button of a paused hunt.
    var start: String { pick("Start hunting", "Start watching") }
    /// A form's title in the bar.
    var newTitle: String { pick("New search", "New watch") }
    var editTitle: String { pick("Edit search", "Edit watch") }
    /// The hunt's page's button to its form, beside Listings at half the width: "Beobachtung bearbeiten" did not fit.
    var editButton: String { pick("Edit search", "Edit") }
    /// The form's main button.
    var create: String { pick("Create search", "Create watch") }
    var save: String { pick("Save search", "Save watch") }
    /// Under a new form's main button.
    var startsPaused: String { pick("The search starts paused.", "The watch starts paused.") }
    /// The hunt's page and its form: delete, and its question.
    var delete: String { pick("Delete search", "Delete watch") }
    var deleteQuestion: String { pick("Delete the search?", "Delete the watch?") }
    var deleteMessage: String {
        pick("The hunt stops and its listings are deleted.", "The watch stops and the changes it found are deleted.")
    }
    /// The hunt's page: rename, and the line under the name's field.
    var rename: String { pick("Rename search", "Rename watch") }
    var renameMessage: String {
        pick("Leave it empty to name it after what it looks for.", "Leave it empty to name it after the page.")
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

    /// `page`: a watch's page as last read (`HuntCard.page`), for its title and host. `sites`: the server's names for a
    /// thing hunt's sites (`ArestemisStore.siteNames`).
    init(_ hunt: Hunt, page: PageState? = nil, sites: SiteNames = SiteNames(), now: Date = .now,
         calendar: Calendar = .app, language: AppLanguage = .current) {
        let ownName = Self.text(hunt.name)
        guard let kind = SearchKind(hunt.kind), hunt.search != .unsupported else {
            self.kind = nil
            title = ownName ?? language.string("Search")
            details = nil
            newerApp = language.string("Needs a newer app")
            return
        }
        if case .watch(let search) = hunt.search {
            // A watch is named by its own name, else the page's title once read, else the host; the host follows
            // under any other name.
            let host = Self.text(page?.host) ?? WatchAddress.host(search.url)
            self.kind = kind
            title = ownName ?? Self.text(page?.pageTitle) ?? host ?? search.url
            details = host == title ? nil : host
            newerApp = nil
            return
        }
        let summary = HuntSummary(hunt, sites: sites, now: now, calendar: calendar, language: language)
        let parts = (ownName == nil ? [] : [summary.title]) + summary.parts
        self.kind = kind
        title = ownName ?? summary.title
        details = parts.isEmpty ? nil : parts.map(SearchSummary.unbreakable).joined(separator: " · ")
        newerApp = nil
    }

    /// A text with something in it, trimmed; nil for nil, empty or only spaces.
    private static func text(_ value: String?) -> String? {
        value.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 }
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

    /// The figures under the hunt's card, each opening those listings: New, Today, and Applied (flats) or Asked
    /// (things); a watch's changes are never applied for, so its third figure is Saved.
    static func figures(_ kind: SearchKind?, counts: Overview.Counts, language: AppLanguage = .current) -> [HuntFigure] {
        let third = kind == .watch
            ? HuntFigure(label: language.string("Saved"), value: counts.saved, filter: .saved)
            : HuntFigure(label: (kind ?? .flat).appliedWord(language: language), value: counts.applied, filter: .applied)
        return [HuntFigure(label: language.string("New"), value: counts.new, filter: .new),
                HuntFigure(label: language.string("Today"), value: counts.today, filter: .all),
                third]
    }

    /// The figures' words alone.
    static func figureLabels(_ kind: SearchKind?, language: AppLanguage = .current) -> [String] {
        figures(kind, counts: .init(new: 0, today: 0, saved: 0, applied: 0), language: language).map(\.label)
    }
}

/// One figure under a hunt's card: its word, its number, and the listings it opens.
struct HuntFigure: Equatable, Identifiable {
    let label: String
    let value: Int
    let filter: MatchFilter
    var id: MatchFilter { filter }
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
                HuntChip(huntID: card.id, title: HuntText(card.hunt, page: card.page, language: language).title,
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
    /// A change found on a watched page (its listing has the page's change, or comes from `"page"`): no application,
    /// no applied state.
    var isPageChange: Bool { listing.page != nil || listing.source == .page }
}
