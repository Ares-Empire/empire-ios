import Foundation

// Quick sort (brief 99, Patrik 2026-11-01, after seeing that most of what stays Not sorted on day one is personal and no
// rule can know it: "a way to see the top not sorted factors and going through them"). What is Not sorted is gone
// through name by name, the biggest first: one card per name and direction, and a tap on a category sorts all of that
// name's payments at once and teaches Aresium the name (brief 81's switch with its learning, never a copy of it). Here:
// the groups (a pure function of the dashboard, built off the main thread with each dashboard, `DashboardStore`), when
// the offer after an import shows, and the words. The flow is `QuickSortFlow.swift`, the look
// `Screens/QuickSortScreens.swift`.

/// One card: one name's Not sorted payments in one direction, over every month. A name's money in and money out are two
/// cards (a parent's transfers to you and your payment to them are different questions).
nonisolated struct QuickSortGroup: Identifiable, Equatable, Sendable {
    /// The name's group key (`Transaction.nameKey`) with the direction.
    let id: String
    let nameKey: String
    let side: CategorySide
    /// The newest payment: its shown name is the card's title.
    let newest: Transaction
    let count: Int
    /// The payments' money, positive, in integer cents (as the lists add up).
    let cents: Int
    /// The first and the last payment's day (`YYYY-MM-DD`).
    let first: String
    let last: String
    /// Up to three of the payments' texts (Verwendungszweck), newest first: none repeated, none that only repeats the
    /// name.
    let examples: [String]
    let ids: Set<String>

    var name: String { newest.place }
    /// Positive euros.
    var total: Double { Double(cents) / 100 }
    /// As a payment shows its amount: −312.40 out, +150.00 in.
    var signedTotal: Double { side == .income ? total : -total }

    static func == (lhs: QuickSortGroup, rhs: QuickSortGroup) -> Bool {
        lhs.id == rhs.id && lhs.ids == rhs.ids && lhs.cents == rhs.cents && lhs.examples == rhs.examples
            && lhs.name == rhs.name
    }
}

nonisolated enum QuickSort {
    /// Every Not sorted payment (no category; a withdrawal's covered row is no payment of its own), across all months,
    /// grouped by name as the name groups group them (`Transaction.nameKey`: the shop's identity, an own name, or the
    /// exact bank line for an empty merchant key; a person paying or paid by transfer is a name too), split by direction
    /// and ranked by the number of payments, then the money (then the newest payment and the key, so the order never
    /// changes by itself). Groups of one payment come last by that order. Server rows carry no name key: none.
    static func groups(in dashboard: Dashboard) -> [QuickSortGroup] {
        var grouped: [String: [(offset: Int, row: Transaction)]] = [:]
        for (offset, row) in dashboard.transactions.enumerated()
            where row.categoryName == CategoryName.uncategorised && row.coveredBy == nil {
            guard let key = row.nameKey else { continue }
            grouped[id(nameKey: key, side: CategorySide(amount: row.amount)), default: []].append((offset, row))
        }
        return grouped.map { id, entries in
            // Newest first; on one day the dashboard's later row first, as a name's page lists them.
            let rows = entries.sorted { $0.row.date == $1.row.date ? $0.offset > $1.offset : $0.row.date > $1.row.date }
                .map(\.row)
            let newest = rows[0]
            let cents = rows.reduce(0) { $0 + Int((abs($1.amount) * 100).rounded()) }
            return QuickSortGroup(id: id, nameKey: newest.nameKey ?? "", side: CategorySide(amount: newest.amount),
                                  newest: newest, count: rows.count, cents: cents, first: rows[rows.count - 1].date,
                                  last: newest.date, examples: examples(rows, name: newest.place),
                                  ids: Set(rows.map(\.id)))
        }
        .sorted(by: ranked)
    }

    /// Biggest first: more payments, then more money, then the newer last payment, then the key.
    static func ranked(_ first: QuickSortGroup, _ second: QuickSortGroup) -> Bool {
        if first.count != second.count { return first.count > second.count }
        if first.cents != second.cents { return first.cents > second.cents }
        if first.last != second.last { return first.last > second.last }
        return first.id < second.id
    }

    static func id(nameKey: String, side: CategorySide) -> String { nameKey + "\u{1F}" + side.rawValue }

    /// The payments' texts as example lines: spaces tidied, newest first, at most `limit`, each once (ignoring case and
    /// accents), and none that only repeats the shown name or the bank's (a text that repeats it says nothing new, as
    /// on the payment's page).
    static func examples(_ rows: [Transaction], name: String, limit: Int = 3) -> [String] {
        var seen: Set<String> = [fold(name)]
        var lines: [String] = []
        for row in rows {
            guard let text = row.purpose.map(tidy), !text.isEmpty else { continue }
            let folded = fold(text)
            guard folded != fold(row.bankName ?? ""), seen.insert(folded).inserted else { continue }
            lines.append(text)
            if lines.count == limit { break }
        }
        return lines
    }

    /// Brief 81's question about the shops' other payments, answered All without asking only when every payment it
    /// would move is this name's in this direction and Not sorted. By construction the group holds all of them, so it
    /// covers payments that came in while the flow was open (a file shared into Aresium meanwhile). It is not asked
    /// otherwise: the shop's payments in the other direction are a card of their own, as are its payments under an own
    /// name, and the quick sort changes no payment that is sorted already.
    static func takesFollowUp(_ ids: Set<String>, of group: QuickSortGroup, in dashboard: Dashboard?) -> Bool {
        guard !ids.isEmpty, let dashboard else { return false }
        let same = Set(dashboard.transactions.filter {
            $0.nameKey == group.nameKey && CategorySide(amount: $0.amount) == group.side
                && $0.categoryName == CategoryName.uncategorised && $0.coveredBy == nil
        }.map(\.id))
        return ids.isSubset(of: same)
    }

    /// What is still Not sorted of a group in this dashboard (a payment sorted meanwhile is left out).
    static func live(_ group: QuickSortGroup, in dashboard: Dashboard?) -> Set<String> {
        guard let dashboard else { return [] }
        return Set(dashboard.transactions.filter {
            group.ids.contains($0.id) && $0.categoryName == CategoryName.uncategorised && $0.coveredBy == nil
        }.map(\.id))
    }

    private static func tidy(_ text: String) -> String {
        text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private static func fold(_ text: String) -> String {
        tidy(text).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
}

/// How much is Not sorted: the offer's and the card's numbers.
nonisolated struct QuickSortTally: Equatable, Sendable {
    /// Cards: names, each direction counted on its own.
    let names: Int
    let payments: Int
    /// Some name has two or more payments: the card on Not sorted's list shows (single payments alone are as quick to
    /// sort in the list).
    let hasRepeats: Bool

    init(_ groups: [QuickSortGroup]) {
        names = groups.count
        payments = groups.reduce(0) { $0 + $1.count }
        hasRepeats = groups.contains { $0.count >= 2 }
    }
}

extension DashboardStore {
    /// Brief 99: the quick sort's groups for the dashboard shown now, biggest first, built with it off the main thread
    /// (`reload`); none in server mode or before a dashboard.
    var quickSortGroups: [QuickSortGroup] {
        builtQuickSort.revision == revision && dashboard != nil ? builtQuickSort.groups : []
    }

    var quickSortTally: QuickSortTally { QuickSortTally(quickSortGroups) }

    /// The card at the top of Not sorted's month list (Current and Overview): phone mode, while some name has two or
    /// more payments Not sorted.
    func offersQuickSort(on route: DashboardRoute) -> Bool {
        guard phone != nil, route.isCategoryList, route.category == CategoryName.uncategorised else { return false }
        return quickSortTally.hasRepeats
    }
}

/// The groups built for one dashboard (`DashboardStore.revision`).
nonisolated struct QuickSortCache: Sendable {
    var revision = -1
    var groups: [QuickSortGroup] = []

    /// Off the main thread: the dashboard's rows are only read.
    static func build(_ dashboard: Dashboard) async -> [QuickSortGroup] {
        await Task.detached(priority: .userInitiated) { QuickSort.groups(in: dashboard) }.value
    }
}

// MARK: - the offer after an import

/// "34 payments not sorted, from 12 names. Go through them?" after an import (brief 99): in the import result's place,
/// as the messages' offer (brief 46), once the import's work, the category picker after an import and the result are
/// done, never on top of another window, in the tour or behind the lock. It goes first; the messages' offer waits for
/// it. Answered (Go through, Later, a swipe down, or the flow opened from Not sorted's list) it shows no more until the
/// next import.
nonisolated enum QuickSortOffer {
    nonisolated struct Moment: Equatable {
        /// An import in phone mode added payments and its offer was not answered (`ImportStore.offersQuickSort`).
        var pending = false
        /// What is Not sorted now.
        var tally = QuickSortTally([])
        var tour = false
        var locked = false
        /// Files are read, imported or waiting (`ImportStore.isBusy`).
        var importing = false
        /// The category picker after an import (`ImportStore.asksForCategories`).
        var picker = false
        /// The import's result (or another line of the app's) shows in the offer's place.
        var result = false
        /// Another window of the app is open, the quick sort's own flow included.
        var window = false
    }

    static func shows(_ moment: Moment) -> Bool {
        moment.pending && moment.tally.payments > 0 && !moment.tour && !moment.locked && !moment.importing
            && !moment.picker && !moment.result && !moment.window
    }

    /// The import left nothing Not sorted (or it was sorted since): the offer is over, so it never shows later for
    /// payments a later change left Not sorted without an import.
    static func expires(_ moment: Moment, dashboardShown: Bool) -> Bool {
        moment.pending && dashboardShown && moment.tally.payments == 0 && !moment.importing && !moment.picker
    }
}

extension QuickSortOffer.Moment {
    /// The moment as the app's state has it; the screen adds the tour, the lock and its other windows.
    @MainActor init(imports: ImportStore, store: DashboardStore, tour: Bool, locked: Bool, window: Bool) {
        self.init(pending: imports.offersQuickSort, tally: store.quickSortTally, tour: tour, locked: locked,
                  importing: imports.isBusy, picker: imports.asksForCategories, result: imports.banner != nil,
                  window: window)
    }
}

// MARK: - words

/// The quick sort's words in the app's language (English here, German in the catalog). The app calls whoever a payment
/// is with its name (the name's page, Search names), so the cards are names, not payees: a payee is only who you pay.
nonisolated enum QuickSortWording {
    /// The offer's question: "34 payments not sorted".
    static func offerTitle(_ tally: QuickSortTally, language: AppLanguage = .current) -> String {
        language.string("\(tally.payments) payments not sorted")
    }

    /// The offer's line: "From 12 names. One tap sorts all payments of a name."
    static func offerLine(_ tally: QuickSortTally, language: AppLanguage = .current) -> String {
        from(tally.names, language: language) + ". " + language.string("One tap sorts all payments of a name.")
    }

    /// "From 12 names".
    static func from(_ names: Int, language: AppLanguage = .current) -> String {
        language.string("From \(names) names")
    }

    static func goThrough(language: AppLanguage = .current) -> String { language.string("Go through") }
    static func later(language: AppLanguage = .current) -> String { language.string("Later") }

    /// The card on Not sorted's list: "Sort name by name".
    static func cardTitle(language: AppLanguage = .current) -> String { language.string("Sort name by name") }

    /// Its line: "12 names · 150 payments · all months".
    static func cardLine(_ tally: QuickSortTally, language: AppLanguage = .current) -> String {
        [names(tally.names, language: language), SelectionWording.payments(tally.payments, language: language),
         language.string("all months")].joined(separator: " · ")
    }

    static func names(_ count: Int, language: AppLanguage = .current) -> String {
        language.string("\(count) names")
    }

    /// The flow's progress under its title: "3 of 12 · 41 sorted".
    static func progress(card: Int, of count: Int, sorted: Int, language: AppLanguage = .current) -> String {
        let place = language.string("\(card) of \(count)")
        guard sorted > 0 else { return place }
        return place + " · " + language.string("\(sorted) sorted")
    }

    /// The card's direction: "Money out" / "Money in".
    static func side(_ side: CategorySide, language: AppLanguage = .current) -> String {
        side == .income ? language.string("Money in") : language.string("Money out")
    }

    /// The card's line under the money: "18 payments · Jan–Oct 2026".
    static func line(_ group: QuickSortGroup, language: AppLanguage = .current) -> String {
        SelectionWording.payments(group.count, language: language) + " · "
            + range(first: group.first, last: group.last, language: language)
    }

    /// The line over the tiles: what one tap does.
    static func tapLine(_ count: Int, language: AppLanguage = .current) -> String {
        language.string("A tap sorts all \(count) and Aresium remembers the name.")
    }

    /// The months a card's payments fall in, as Foundation writes a range in the language (the summed rows' days do
    /// the same): "Oct 2026", "Jan – Oct 2026", "Nov 2025 – Oct 2026"; German "Okt. 2026", "Jan.–Okt. 2026".
    static func range(first: String, last: String, language: AppLanguage = .current) -> String {
        guard let start = ReceiptDay.date(first), let end = ReceiptDay.date(last) else { return first }
        let calendar = ReceiptDay.calendar
        if first.prefix(7) == last.prefix(7) || end < start {
            return end.formatted(Date.FormatStyle(date: .omitted, time: .omitted, locale: language.locale,
                                                  calendar: calendar, timeZone: calendar.timeZone)
                .month(.abbreviated).year())
        }
        return (start..<end).formatted(Date.IntervalFormatStyle(locale: language.locale, calendar: calendar,
                                                                timeZone: calendar.timeZone).month(.abbreviated).year())
    }

    /// VoiceOver reads a card as one: the name, the direction, how many, the money, the months and the example lines.
    static func spoken(_ group: QuickSortGroup, title: String, language: AppLanguage = .current) -> String {
        ([title, side(group.side, language: language), SelectionWording.payments(group.count, language: language),
          Money.transaction(group.signedTotal, language: language),
          range(first: group.first, last: group.last, language: language)] + group.examples).joined(separator: ", ")
    }

    static func skip(language: AppLanguage = .current) -> String { language.string("Skip") }

    /// The end's title: "84 payments sorted", or "Nothing sorted".
    static func summaryTitle(sorted payments: Int, language: AppLanguage = .current) -> String {
        payments == 0 ? language.string("Nothing sorted") : language.string("\(payments) payments sorted")
    }

    /// The end's line: "From 9 names · 3 skipped"; "Everything is sorted." once nothing is left.
    static func summaryLine(names: Int, skipped: Int, left: Int, language: AppLanguage = .current) -> String {
        var parts: [String] = []
        if names > 0 { parts.append(from(names, language: language)) }
        if skipped > 0 { parts.append(language.string("\(skipped) skipped")) }
        var line = parts.joined(separator: " · ")
        if left == 0 { line += (line.isEmpty ? "" : ". ") + language.string("Everything is sorted.") }
        return line
    }
}
