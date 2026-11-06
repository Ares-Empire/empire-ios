import Foundation

/// What the Listings tab shows (brief 133, Patrik's choice of 2026-11-02: "New | Searches"), decided here so the screens
/// only lay it out: New's groups and their order, the rows of Searches, the quiet rows at a list's end (Recently viewed,
/// Filtered out and Not checked in time), and the words of the search over listings, of Recently viewed and of Not
/// checked in time.

/// One search's new listings in New.
struct NewGroup: Equatable, Identifiable {
    let huntID: Int
    /// Newest first: the unread ones (brief 182: an opened one leaves New for Recently viewed), and one read on its page
    /// that is still open (`ArestemisStore.heldInNew`).
    let matches: [Match]
    var id: Int { huntID }
    /// The heading's "● 2 NEW": the listings not opened yet.
    var unread: Int { matches.count { !$0.seen } }
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

/// One row of Searches: the search's kind and name, its new (unread) count, and what was kept from it in a quiet line
/// ("2 favorites · 1 applied"; a thing's seller is asked; a watch's changes are only kept as favorites; "Paused" first
/// while it is paused). Counts of zero are left out, so a search with nothing kept has no line (eight cards of "0 saved ·
/// 0 asked" said nothing).
/// A search of a kind this build does not know shows its name only.
struct SearchRow: Equatable, Identifiable {
    let huntID: Int
    let text: HuntText
    /// nil for a kind this build does not know.
    let newCount: Int?
    let line: String?
    var id: Int { huntID }

    init(_ card: HuntCard, sites: SiteNames = SiteNames(), language: AppLanguage = .current) {
        huntID = card.id
        text = HuntText(card, sites: sites, language: language)
        guard let kind = text.kind else {
            newCount = nil
            line = nil
            return
        }
        newCount = card.counts.new
        var parts: [String] = []
        if !card.hunt.active { parts.append(language.string("Paused")) }
        if card.counts.saved > 0 { parts.append(language.string("\(card.counts.saved) favorites")) }
        if card.counts.applied > 0 {
            switch kind {
            case .flat: parts.append(language.string("\(card.counts.applied) applied"))
            case .item: parts.append(language.string("\(card.counts.applied) asked"))
            case .price, .watch: break
            }
        }
        line = parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// VoiceOver reads the row as one: "Herman Miller Aeron, 4 new, 1 favorite".
    func spoken(language: AppLanguage = .current) -> String {
        [text.title, newCount.map { language.string("\($0) new") }, line].compactMap { $0 }.joined(separator: ", ")
    }
}

/// A quiet outlined row at the end of a list that opens more listings of the same searches (brief 182): Recently viewed,
/// Filtered out and Not checked in time (brief 187), each with its symbol, its words and its count, in one look
/// (`QuietLinkRow`). There is none while it would open an empty list.
struct QuietLink: Equatable {
    enum Kind: Equatable {
        case recentlyViewed, filteredOut, notChecked
    }

    let kind: Kind
    let count: Int
    /// The server has more than it sent (Recently viewed has one page): the count reads "200+".
    let more: Bool

    init?(_ kind: Kind, count: Int, more: Bool = false) {
        guard count > 0 else { return nil }
        self.kind = kind
        self.count = count
        self.more = more
    }

    /// A clock going back for what was opened, the filter's lines for what the check took out, an hourglass for what it
    /// had no time for (time ran out; not a warning).
    var symbol: String {
        switch kind {
        case .recentlyViewed: "clock.arrow.circlepath"
        case .filteredOut: "line.3.horizontal.decrease"
        case .notChecked: "hourglass"
        }
    }

    func title(language: AppLanguage = .current) -> String {
        switch kind {
        case .recentlyViewed: RecentlyViewedWords.title(language: language)
        case .filteredOut: language.string("Filtered out")
        case .notChecked: NotCheckedWords.title(language: language)
        }
    }

    /// "12", or "200+" when the server has more.
    var countText: String { more ? "\(count)+" : "\(count)" }

    /// VoiceOver reads the row as one: "Recently viewed, 3 listings".
    func spoken(language: AppLanguage = .current) -> String {
        language.string("\(title(language: language)), \(count) listings")
    }
}

/// The words of Recently viewed (brief 182): the listings opened in the last 7 days that are still new.
enum RecentlyViewedWords {
    /// The row's words and the page's title: "Recently viewed" / "Zuletzt angesehen".
    static func title(language: AppLanguage = .current) -> String { language.string("Recently viewed") }

    /// The quiet line at the top of the page: what it holds, and how to keep one.
    static func line(language: AppLanguage = .current) -> String {
        language.string("Listings you opened in the last 7 days. To keep one, make it a favorite.")
    }

    /// The page once nothing is left (each one made a favorite, applied or dismissed while it was open).
    static func empty(language: AppLanguage = .current) -> String {
        language.string("No listings here right now.")
    }
}

/// The words of Not checked in time (brief 187): the listings the server could not check in time, kept 7 days for the
/// person to look at. Never a list of misfits, so nothing here says they do not fit.
enum NotCheckedWords {
    /// The row's words and the page's title: "Not checked in time" / "Nicht rechtzeitig geprüft".
    static func title(language: AppLanguage = .current) -> String { language.string("Not checked in time") }

    /// The quiet line at the top of the page: what these are, what to do, how long they stay.
    static func line(language: AppLanguage = .current) -> String {
        language.string("These listings couldn't be checked in time. Have a look yourself; they stay here for 7 days.")
    }

    /// The page with nothing (left) in it: Recently viewed's words.
    static func empty(language: AppLanguage = .current) -> String { RecentlyViewedWords.empty(language: language) }

    /// A listing whose title the site did not give.
    static func untitled(language: AppLanguage = .current) -> String { language.string("Untitled") }
}

extension NotChecked {
    /// The title, or "Untitled" when the site gave none (`hasTitle` false).
    func shownTitle(language: AppLanguage = .current) -> String {
        hasTitle ? (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines) : NotCheckedWords.untitled(language: language)
    }

    var hasTitle: Bool { !(title ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// The listing on its site, only a web address; nil when the server has none, so the row opens nothing.
    var link: URL? { url.flatMap(WebLink.url) }

    /// The quiet line under the title: the price when known, the site, and when its search first saw it ("€420 ·
    /// Kleinanzeigen · yesterday 10:12").
    func line(now: Date = .now, calendar: Calendar = .app, language: AppLanguage = .current) -> String {
        let arrived = Format.relative(firstSeen, now: now, calendar: calendar, language: language)
            ?? Format.relative(found, now: now, calendar: calendar, language: language)
        return [price.map { Format.money($0, language: language) }, sourceName, arrived].compactMap { $0 }
            .joined(separator: " · ")
    }

    /// VoiceOver reads the row as one: "Herman Miller Aeron, size C, €420, Kleinanzeigen, yesterday 10:12".
    func spoken(now: Date = .now, calendar: Calendar = .app, language: AppLanguage = .current) -> String {
        [shownTitle(language: language), line(now: now, calendar: calendar, language: language)
            .replacingOccurrences(of: " · ", with: ", ")].joined(separator: ", ")
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
