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
    /// not know, such as the Preismonitor before brief 137, is left out); this build's three while there is no answer.
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
        case .watch:
            language.string("A page you know: a new version, a new job, tickets, the canteen menu.")
        }
    }
}

/// An example on New search: a tap opens its kind's form filled in as its words say. Places and addresses stay for the
/// user (a flat's town, a watched page's address); the name stays empty, so the form shows the automatic one.
enum SearchExample: String, CaseIterable, Hashable, Identifiable, Sendable {
    case twoRooms, wgRoom, kallax, roadBike, newVersion, newJob, canteenMenu
    var id: String { rawValue }

    var kind: SearchKind {
        switch self {
        case .twoRooms, .wgRoom: .flat
        case .kallax, .roadBike: .item
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
