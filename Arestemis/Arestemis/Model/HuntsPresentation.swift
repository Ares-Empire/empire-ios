import Foundation

/// What the Hunts and Listings tabs show of the account's hunts, decided here so the screens only lay it out: the kinds
/// this build can make (New search, `NewSearch.swift`), a hunt's lines on its card and page, which actions its page and
/// its card's long press offer, the word for the "applied" state, the name's rule and the radius steps. The Listings
/// tab's own parts: `ListingsPresentation.swift`.

/// The kinds of search this build can make and edit: a flat, a thing for sale, a product's price (brief 137) and a page
/// to watch (brief 131). A hunt of another kind (from a newer server) shows its name and "Needs a newer app", nothing
/// else.
enum SearchKind: String, CaseIterable, Hashable, Identifiable, Sendable {
    case flat, item, price, watch
    var id: String { rawValue }

    init?(_ kind: HuntKind) {
        switch kind {
        case .flat: self = .flat
        case .item: self = .item
        case .price: self = .price
        case .watch: self = .watch
        case .unknown: return nil
        }
    }

    var huntKind: HuntKind {
        switch self {
        case .flat: .flat
        case .item: .item
        case .price: .price
        case .watch: .watch
        }
    }

    /// Every kind this build can make, in the order of the server's `/kinds`: Flat, Things, Price monitor, Watch a
    /// website.
    static let all: [SearchKind] = [.flat, .item, .price, .watch]

    /// New search's cards: the kinds the server offers (`GET /kinds`) that this build can make, in the server's order (a
    /// kind this build cannot open, such as one from a newer server, is left out); all of them while there is no answer
    /// (offline, a server from before `/kinds`), or when the answer names none of them, so the page is never empty. The
    /// server still refuses a kind it does not know.
    static func choices(offered kinds: [OfferedKind]?) -> [SearchKind] {
        guard let kinds else { return all }
        var choices: [SearchKind] = []
        for offered in kinds {
            if let kind = SearchKind(offered.kind), !choices.contains(kind) { choices.append(kind) }
        }
        return choices.isEmpty ? all : choices
    }

    /// The kind's name while the server has not named it (`/kinds` names it as the server's texts say, brief 134):
    /// "Flat" / "Wohnung", "Things" / "Dinge", "Price monitor" / "Preismonitor", "Watch a website" / "Webseite
    /// beobachten".
    func choiceTitle(language: AppLanguage = .current) -> String {
        switch self {
        case .flat: language.string("Flat")
        case .item: language.string("Things")
        case .price: language.string("Price monitor")
        case .watch: language.string("Watch a website")
        }
    }

    /// The small mark on a hunt's card and row (SF Symbols): a house for a flat, a tag for a thing, a falling line for a
    /// price, an eye for a page.
    var symbol: String {
        switch self {
        case .flat: "house"
        case .item: "tag"
        case .price: "chart.line.downtrend.xyaxis"
        case .watch: "eye"
        }
    }

    /// The "applied" state's word: flats are applied for, a thing's seller is asked. A watch's change and a price alarm
    /// are neither (their pages offer only Save and Dismiss).
    func appliedWord(language: AppLanguage = .current) -> String {
        self == .item ? language.string("Asked") : language.string("Applied")
    }

    /// Whether its listings can be applied for (a flat) or asked about (a thing); a watch's changes and a monitor's
    /// alarms are only saved or dismissed.
    var appliesOrAsks: Bool { self == .flat || self == .item }
}

/// The words for a hunt that name what it is: a search (a flat or a thing), a price monitor ("Preismonitor") or a watch
/// ("Beobachtung"). A hunt of a kind this build does not know (`nil`) is a search. A monitor and a watch both watch: their
/// status reads "Watching" ("Beobachtung läuft"), as the sketch's monitor card does.
struct HuntWords: Equatable {
    let kind: SearchKind?
    let language: AppLanguage

    init(_ kind: SearchKind?, language: AppLanguage = .current) {
        self.kind = kind
        self.language = language
    }

    private func pick(_ search: LocalizedStringResource, _ watch: LocalizedStringResource,
                      price: LocalizedStringResource? = nil) -> String {
        switch kind {
        case .watch: language.string(watch)
        case .price: language.string(price ?? watch)
        case .flat, .item, nil: language.string(search)
        }
    }

    /// The status beside the pulse: "Hunting" / "Watching", or "Paused"; a watch or a monitor whose page refuses the
    /// server reads "Stopped" (the server reads it no more until it is edited), without the pulse.
    func status(active: Bool, stopped: Bool = false) -> String {
        if active && stopped { return language.string("Stopped") }
        return active ? pick("Hunting", "Watching") : language.string("Paused")
    }
    /// The one primary button of a paused hunt.
    var start: String { pick("Start hunting", "Start watching") }
    /// A form's title in the bar.
    var newTitle: String { pick("New search", "New watch", price: "New price monitor") }
    var editTitle: String { pick("Edit search", "Edit watch", price: "Edit price monitor") }
    /// The hunt's page's button to its form, beside Listings at half the width: "Beobachtung bearbeiten" did not fit.
    var editButton: String { pick("Edit search", "Edit") }
    /// The form's main button.
    var create: String { pick("Create search", "Create watch", price: "Create price monitor") }
    var save: String { pick("Save search", "Save watch", price: "Save price monitor") }
    /// Under a new form's main button.
    var startsPaused: String {
        pick("The search starts paused.", "The watch starts paused.", price: "The price monitor starts paused.")
    }
    /// The hunt's page, its card's long press and its form: delete, and its question.
    var delete: String { pick("Delete search", "Delete watch", price: "Delete price monitor") }
    var deleteQuestion: String { pick("Delete the search?", "Delete the watch?", price: "Delete the price monitor?") }
    var deleteMessage: String {
        pick("The hunt stops and its listings are deleted.", "The watch stops and the changes it found are deleted.",
             price: "The price monitor stops and its history and alarms are deleted.")
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

    /// `page`: a watch's page as last read (`HuntCard.page`), for its title and host; `price`: a monitor's product as
    /// last read (`HuntCard.price`). `sites`: the server's names for a thing hunt's sites (`ArestemisStore.siteNames`).
    /// `allWords`: a thing hunt's page lists every search word first in the details (brief 149), where the cards name
    /// only the first and how many more ("Hermès tie + 2").
    init(_ hunt: Hunt, page: PageState? = nil, price: PriceState? = nil, sites: SiteNames = SiteNames(),
         allWords: Bool = false, now: Date = .now, calendar: Calendar = .app, language: AppLanguage = .current) {
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
            title = ownName ?? Self.automaticTitle(hunt.search, page: page) ?? search.url
            details = host == title ? nil : host
            newerApp = nil
            return
        }
        if case .price(let search) = hunt.search {
            // A monitor is named by its own name, else the product once read, else the host; then the product (under an
            // own name), the host, and what it does: "Alarm under €450", or "History only".
            let product = Self.text(price?.product)
            let host = Self.text(price?.host) ?? WatchAddress.host(search.url)
            let title = ownName ?? Self.automaticTitle(hunt.search, price: price) ?? search.url
            let parts = [product, host].compactMap { $0 }.filter { $0 != title }
                + [PriceWords.mode(search, language: language)]
            self.kind = kind
            self.title = title
            details = parts.joined(separator: " · ")
            newerApp = nil
            return
        }
        let summary = HuntSummary(hunt.search, sites: sites, now: now, calendar: calendar, language: language)
        // What it looks for leads the details under an own name; on the page every word when there are several.
        let lead = (allWords ? summary.wordList : nil) ?? (ownName == nil ? nil : SearchSummary.unbreakable(summary.title))
        let parts = [lead].compactMap { $0 } + summary.parts.map(SearchSummary.unbreakable)
        self.kind = kind
        title = ownName ?? summary.title
        details = parts.isEmpty ? nil : parts.joined(separator: " · ")
        newerApp = nil
    }

    /// A card's lines: its hunt, with the page or the product the server last read for it.
    init(_ card: HuntCard, sites: SiteNames = SiteNames(), allWords: Bool = false, now: Date = .now,
         calendar: Calendar = .app, language: AppLanguage = .current) {
        self.init(card.hunt, page: card.page, price: card.price, sites: sites, allWords: allWords, now: now,
                  calendar: calendar, language: language)
    }

    /// The title a search has without a name of its own (brief 135: the name fields' grey placeholder): what it looks
    /// for (a flat's kinds, a thing's words), a watch's page title once read, else its host, a monitor's product once
    /// read, else its host; nil while there is nothing yet (a thing without words, a watch without an address) and for a
    /// search this build cannot read.
    static func automaticTitle(_ search: HuntSearch, page: PageState? = nil, price: PriceState? = nil,
                               language: AppLanguage = .current) -> String? {
        switch search {
        case .watch(let watch):
            text(page?.pageTitle) ?? text(page?.host) ?? WatchAddress.host(watch.url)
        case .price(let monitor):
            text(price?.product) ?? text(price?.host) ?? WatchAddress.host(monitor.url)
        case .flat, .item:
            text(HuntSummary(search, language: language).title)
        case .unsupported:
            nil
        }
    }

    /// A text with something in it, trimmed; nil for nil, empty or only spaces.
    static func text(_ value: String?) -> String? {
        value.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 }
    }
}

/// What a hunt's page and its card's long press offer. A hunt this build cannot show can still be listed and deleted,
/// but not started, paused, edited or renamed (its page shows no name to edit in place).
struct HuntPageActions: Equatable {
    let startPause: Bool
    let editSearch: Bool
    let listings = true
    let rename: Bool
    let delete = true

    init(_ hunt: Hunt) {
        let known = SearchKind(hunt.kind) != nil && hunt.search != .unsupported
        startPause = known
        editSearch = known
        rename = known
    }

    /// The figures under the hunt's card, each opening those listings: New, Today, and Applied (flats) or Asked
    /// (things); a watch's changes and a monitor's alarms are never applied for, so their third figure is Saved.
    static func figures(_ kind: SearchKind?, counts: Overview.Counts, language: AppLanguage = .current) -> [HuntFigure] {
        let third = kind == .watch || kind == .price
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

/// A hunt's own name (the forms' Name field, renaming in place): 1 to 60 characters; empty clears it, so the hunt is
/// named after its search again (`HuntText.automaticTitle`).
enum HuntName {
    static let maxLength = 60

    /// What a name field keeps while typing.
    static func limited(_ text: String) -> String { String(text.prefix(maxLength)) }

    /// What is sent: trimmed, nil when empty.
    static func cleaned(_ text: String) -> String? {
        let trimmed = limited(text).trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// A name field's grey placeholder: the name the search gets while the field stays empty, else "Optional" (nothing
    /// to name it after yet).
    static func placeholder(_ automatic: String?, language: AppLanguage = .current) -> String {
        automatic ?? language.string("Optional")
    }
}

/// Renaming a search where its name stands (brief 135, the search's page): the field opens with the own name (empty
/// while the search has none, so the automatic name shows grey in its place), keeps at most 60 characters, and only a
/// changed name is sent: Return, Save or a tap elsewhere saves it (empty: the automatic name again), Cancel or Escape
/// leaves the name as it was.
struct NameEdit: Equatable {
    let hunt: Int
    /// The own name when the field opened; nil while the search had none.
    let original: String?
    var text: String {
        didSet { if text.count > HuntName.maxLength { text = HuntName.limited(text) } }
    }

    init(_ hunt: Hunt) {
        self.hunt = hunt.id
        original = HuntName.cleaned(hunt.name ?? "")
        text = original ?? ""
    }

    /// The name to send: trimmed, nil when empty.
    var name: String? { HuntName.cleaned(text) }
    /// Whether saving would change the name (spaces around it change nothing).
    var hasChanges: Bool { name != original }
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
    /// The word a row shows for a state that is not obvious from the list it is in; a thing's seller is "Asked". New
    /// only where every state shows (the search over listings).
    func word(thing: Bool = false, includingNew: Bool = false, language: AppLanguage = .current) -> String? {
        switch self {
        case .new: includingNew ? language.string("New") : nil
        case .saved: language.string("Saved")
        case .applied: (thing ? SearchKind.item : .flat).appliedWord(language: language)
        case .dismissed: nil
        }
    }
}

extension Match {
    /// A thing for sale (its listing has the item details): no application, "Asked" for the applied state.
    var isThing: Bool { listing.item != nil }
    /// An alarm of a price monitor (its listing has the price change): no application, no applied state.
    var isPriceChange: Bool { listing.priceChange != nil }
    /// A change found on a watched page (its listing has the page's change, or comes from `"page"` without a price
    /// change, which a monitor's alarms also come from): no application, no applied state.
    var isPageChange: Bool { !isPriceChange && (listing.page != nil || listing.source == .page) }
}
