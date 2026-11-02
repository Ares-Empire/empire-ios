import Foundation

/// New search (brief 135, Patrik 2026-11-02: the kind menu "is not pretty"): a page of its own instead of iOS's action
/// sheet, one card per kind this build can open, each with what it does in one sentence and examples that open its form
/// filled in. Decided here, so the page only lays it out.

/// One kind's card on New search.
struct NewSearchCard: Equatable, Identifiable {
    let kind: SearchKind
    /// `/kinds`' name ("Wohnung"), or this build's while the server has not answered.
    let name: String
    /// What the kind does, in one sentence.
    let line: String
    let examples: [SearchExample]
    var id: SearchKind { kind }

    /// The cards for the kinds `/kinds` offers that this build can open, in the server's order (a kind this build does
    /// not know is left out); this build's four while there is no answer.
    static func cards(offered kinds: [OfferedKind]?, language: AppLanguage = .current) -> [NewSearchCard] {
        SearchKind.choices(offered: kinds).map { kind in
            let offered = kinds?.first { $0.kind == kind.huntKind }?.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = offered.flatMap { $0.isEmpty ? nil : $0 } ?? kind.choiceTitle(language: language)
            return NewSearchCard(kind: kind, name: name, line: kind.pitch(language: language),
                                 examples: SearchExample.examples(for: kind))
        }
    }
}

extension SearchKind {
    /// New search's sentence for the kind: what it finds, and where.
    func pitch(language: AppLanguage = .current) -> String {
        switch self {
        case .flat:
            language.string("New listings from WG-Gesucht, Kleinanzeigen, Immowelt and ImmoScout24, minutes after they go online.")
        case .item:
            language.string("Used and cheap: Kleinanzeigen, eBay, Vinted, IKEA Preowned and more, with a price limit and pickup nearby.")
        case .price:
            language.string("One product in one shop: its price history, and a word when it gets cheaper or is back in stock.")
        case .watch:
            language.string("A page you know: a new version, a new job, tickets, the canteen menu.")
        }
    }
}

/// An example on New search: a tap opens its kind's form filled in as its words say. Places and addresses stay for the
/// user (a flat's town, a watched page's address); the name stays empty, so the form shows the automatic one.
enum SearchExample: String, CaseIterable, Hashable, Identifiable, Sendable {
    case twoRooms, wgRoom, kallax, roadBike, priceBelow, backInStock, newVersion, newJob, canteenMenu
    var id: String { rawValue }

    var kind: SearchKind {
        switch self {
        case .twoRooms, .wgRoom: .flat
        case .kallax, .roadBike: .item
        case .priceBelow, .backInStock: .price
        case .newVersion, .newJob, .canteenMenu: .watch
        }
    }

    /// The kind's examples, in the card's order.
    static func examples(for kind: SearchKind) -> [SearchExample] {
        allCases.filter { $0.kind == kind }
    }

    /// The chip's words.
    func title(language: AppLanguage = .current) -> String {
        switch self {
        case .twoRooms: language.string("2 rooms up to €1,100 warm")
        case .wgRoom: language.string("WG room")
        case .kallax: language.string("Kallax up to €40")
        case .roadBike: language.string("Road bike size 56")
        case .priceBelow: language.string("Price under € …")
        case .backInStock: language.string("Back in stock")
        case .newVersion: language.string("New version")
        case .newJob: language.string("New job")
        case .canteenMenu: language.string("Canteen menu")
        }
    }

    /// A flat example's form: a whole flat with at least 2 rooms up to €1,100 warm, or a WG room.
    var flatDraft: SearchDraft? {
        var draft = SearchDraft()
        switch self {
        case .twoRooms:
            draft.type = .flat
            draft.roomsMin = 2
            draft.warmRent.max = 1100
        case .wgRoom:
            draft.type = .wg
        default:
            return nil
        }
        return draft
    }

    /// A thing example's form: the words and the price; the size goes where the form asks for it (Extras).
    func itemDraft(language: AppLanguage = .current) -> ItemSearchDraft? {
        var draft = ItemSearchDraft()
        switch self {
        case .kallax:
            draft.query = "Kallax"
            draft.priceMax = "40"
        case .roadBike:
            draft.query = language.string("Road bike")
            draft.extra = language.string("Frame size 56")
        default:
            return nil
        }
        return draft
    }

    /// A monitor example's form: the alarm on with its one condition (the price's limit fills in once the product's price
    /// is found, `PriceSearchDraft.prefillLimit`), the history on as in every new monitor; the link is the user's.
    var priceDraft: PriceSearchDraft? {
        var draft = PriceSearchDraft()
        switch self {
        case .priceBelow: draft.alarm = true
        case .backInStock:
            draft.alarm = true
            draft.backInStock = true
        default: return nil
        }
        return draft
    }

    /// A watch example's form: the "Tell me when" sentence; the page's address is the user's.
    func watchDraft(language: AppLanguage = .current) -> WatchSearchDraft? {
        var draft = WatchSearchDraft()
        switch self {
        case .newVersion: draft.change = language.string("a new version comes out")
        case .newJob: draft.change = language.string("a new job is posted")
        case .canteenMenu: draft.change = language.string("the new menu is out")
        default: return nil
        }
        return draft
    }
}

/// The watch form's examples over "Tell me when" (brief 137, the sketch's third mockup): a tap fills the sentence for the
/// user to sharpen; "own description" empties a sentence that is still an example's, for the user's own words.
enum WatchChange: String, CaseIterable, Identifiable, Sendable {
    case newVersion, newEntry, dateChanges, own
    var id: String { rawValue }

    /// The chip's words; for the examples also the sentence it fills in.
    func title(language: AppLanguage = .current) -> String {
        switch self {
        case .newVersion: language.string("a new version comes out")
        case .newEntry: language.string("a new entry appears")
        case .dateChanges: language.string("a date changes")
        case .own: language.string("own description")
        }
    }

    /// The sentence an example fills in; nil for "own description".
    func sentence(language: AppLanguage = .current) -> String? {
        self == .own ? nil : title(language: language)
    }

    /// The field after a tap: an example's sentence; for "own description" the field emptied while it still holds an
    /// example's sentence, else kept (the user's own words stay).
    func apply(to text: String, language: AppLanguage = .current) -> String {
        if let sentence = sentence(language: language) { return sentence }
        return Self.example(in: text, language: language) == nil ? text : ""
    }

    /// The example whose sentence the field holds as it is (spaces around it aside); nil for any other words.
    static func example(in text: String, language: AppLanguage = .current) -> WatchChange? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return allCases.first { $0.sentence(language: language) == trimmed }
    }
}
