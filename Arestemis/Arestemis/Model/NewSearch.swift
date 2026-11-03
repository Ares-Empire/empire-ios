import Foundation

/// New search (brief 135, Patrik 2026-11-02: the kind menu "is not pretty"): a page of its own instead of iOS's action
/// sheet, one card per kind this build can open, each with what it does in one short line and an example that opens its
/// form filled in (one per kind since brief 142: less to read). Decided here, so the page only lays it out.

/// One kind's card on New search.
struct NewSearchCard: Equatable, Identifiable {
    let kind: SearchKind
    /// `/kinds`' name ("Wohnung"), or this build's while the server has not answered.
    let name: String
    /// What the kind does, in one short line.
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
    /// New search's line for the kind: what it does, in six to eight words (brief 142, Patrik 2026-11-03: "lots of
    /// concentrated reading"); the sites are the form's to show.
    func pitch(language: AppLanguage = .current) -> String {
        switch self {
        case .flat: language.string("New flats and WG rooms, minutes after posting.")
        case .item: language.string("Used and cheap, under your price limit.")
        case .price: language.string("One product: a push when it gets cheaper.")
        case .watch: language.string("Any page: a push when something new appears.")
        }
    }
}

/// An example on New search, one per kind (brief 142; the WG room, the road bike, back in stock, a new job and the
/// canteen menu went with it): a tap opens its kind's form filled in as its words say. Places and addresses stay for the
/// user (a flat's town, a watched page's address); the name stays empty, so the form shows the automatic one. The
/// tour's step 2 names these four (`TourStep.newSearch`).
enum SearchExample: String, CaseIterable, Hashable, Identifiable, Sendable {
    case twoRooms, kallax, priceBelow, newVersion
    var id: String { rawValue }

    var kind: SearchKind {
        switch self {
        case .twoRooms: .flat
        case .kallax: .item
        case .priceBelow: .price
        case .newVersion: .watch
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
        case .kallax: language.string("Kallax up to €40")
        case .priceBelow: language.string("Price under € …")
        case .newVersion: language.string("New version")
        }
    }

    /// A flat example's form: a whole flat with at least 2 rooms up to €1,100 warm.
    var flatDraft: SearchDraft? {
        guard self == .twoRooms else { return nil }
        var draft = SearchDraft()
        draft.type = .flat
        draft.roomsMin = 2
        draft.warmRent.max = 1100
        return draft
    }

    /// A thing example's form: the words and the price.
    func itemDraft(language: AppLanguage = .current) -> ItemSearchDraft? {
        guard self == .kallax else { return nil }
        var draft = ItemSearchDraft()
        draft.query = "Kallax"
        draft.priceMax = "40"
        return draft
    }

    /// A monitor example's form: the alarm on with its price condition (the limit fills in once the product's price is
    /// found, `PriceSearchDraft.prefillLimit`), the history on as in every new monitor; the link is the user's.
    var priceDraft: PriceSearchDraft? {
        guard self == .priceBelow else { return nil }
        var draft = PriceSearchDraft()
        draft.alarm = true
        return draft
    }

    /// A watch example's form: the "Tell me when" sentence; the page's address is the user's.
    func watchDraft(language: AppLanguage = .current) -> WatchSearchDraft? {
        guard self == .newVersion else { return nil }
        var draft = WatchSearchDraft()
        draft.change = language.string("a new version comes out")
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
