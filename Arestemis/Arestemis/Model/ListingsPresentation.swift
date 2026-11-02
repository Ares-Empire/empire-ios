import Foundation

/// What the Listings tab shows (brief 133, Patrik's choice of 2026-11-02: "New | Searches"), decided here so the screens
/// only lay it out: New's groups and their order, the rows of Searches, and the words of the search over listings.

/// One search's new listings in New.
struct NewGroup: Equatable, Identifiable {
    let huntID: Int
    /// Newest first.
    let matches: [Match]
    var id: Int { huntID }
}

enum NewListings {
    /// New's groups: every new listing under its search, the search with the newest finding first, newest first within
    /// it. Newest by when it was found, then by id (the server's order), so the order never depends on how the matches
    /// arrived.
    static func groups(_ matches: [Match]) -> [NewGroup] {
        let new = matches.filter { $0.state == .new }.sorted(by: newer)
        var order: [Int] = []
        var byHunt: [Int: [Match]] = [:]
        for match in new {
            if byHunt[match.huntID] == nil { order.append(match.huntID) }
            byHunt[match.huntID, default: []].append(match)
        }
        return order.map { NewGroup(huntID: $0, matches: byHunt[$0] ?? []) }
    }

    /// Found later, or found at the same moment with the higher id.
    static func newer(_ a: Match, _ b: Match) -> Bool {
        let foundA = Timestamp.parse(a.found) ?? .distantPast
        let foundB = Timestamp.parse(b.found) ?? .distantPast
        return foundA != foundB ? foundA > foundB : a.id > b.id
    }

    /// A heading over each search's group, unless the account has one search (whose listings every one would be).
    static func showsHeadings(searches: Int) -> Bool { searches > 1 }
}

/// One row of Searches: the search's kind and name, its new count, and what was kept from it in a quiet line ("2 saved ·
/// 1 applied"; a thing's seller is asked; a watch's changes are only saved; "Paused" first while it is paused). A search
/// of a kind this build does not know shows its name only.
struct SearchRow: Equatable, Identifiable {
    let huntID: Int
    let text: HuntText
    /// nil for a kind this build does not know.
    let newCount: Int?
    let line: String?
    var id: Int { huntID }

    init(_ card: HuntCard, sites: SiteNames = SiteNames(), language: AppLanguage = .current) {
        huntID = card.id
        text = HuntText(card.hunt, page: card.page, sites: sites, language: language)
        guard let kind = text.kind else {
            newCount = nil
            line = nil
            return
        }
        newCount = card.counts.new
        var parts: [String] = []
        if !card.hunt.active { parts.append(language.string("Paused")) }
        parts.append(language.string("\(card.counts.saved) saved"))
        switch kind {
        case .flat: parts.append(language.string("\(card.counts.applied) applied"))
        case .item: parts.append(language.string("\(card.counts.applied) asked"))
        case .watch: break
        }
        line = parts.joined(separator: " · ")
    }

    /// VoiceOver reads the row as one: "Herman Miller Aeron, 4 new, 0 saved · 0 asked".
    func spoken(language: AppLanguage = .current) -> String {
        [text.title, newCount.map { language.string("\($0) new") }, line].compactMap { $0 }.joined(separator: ", ")
    }
}

/// The words of the search over listings.
enum ListingSearchWords {
    /// The field's prompt.
    static func prompt(language: AppLanguage = .current) -> String { language.string("Search by name or place") }

    /// Under the field before two letters are typed.
    static func hint(language: AppLanguage = .current) -> String {
        language.string("Type at least two letters. The best matches come first.")
    }

    /// The page's title: the search it is limited to, or every search.
    static func title(hunt: HuntText?, language: AppLanguage = .current) -> String {
        hunt?.title ?? language.string("All searches")
    }

    /// "Nothing found for “Kallax”."
    static func nothingFound(_ words: String, language: AppLanguage = .current) -> String {
        language.string("Nothing found for “\(words)”.")
    }

    /// Under the results when the server has more than it sent.
    static func more(language: AppLanguage = .current) -> String {
        language.string("More listings match. Another word narrows it down.")
    }
}
