import Foundation

// The search (brief 77, Patrik 2026-11-01: "A small search icon. Im thinking search by names which uses own given and
// also original names organized by best match"): a magnifying glass in the start screen's header (phone mode, where
// payments have names) opens a page on the dashboard's stack with a field; the results are brief 76's ranking
// (`DashboardStore.searchNames(_:)`), each opening the name's page. This file decides what the page and its rows say;
// the look is `Screens/SearchScreen.swift`.

extension DashboardStore {
    /// Whether the start screen offers the search: phone mode, where payments have names (server rows have none, so
    /// there the search would never find anything).
    var offersSearch: Bool { phone != nil }

    /// Before anything is typed: the names of the newest payments, newest first (`NameSearch.latest`).
    func latestNames(limit: Int = SearchPage.latestCount) -> [NameSearchResult] {
        NameSearch.latest(in: dashboard?.nameGroups ?? [:], limit: limit)
    }

    /// A category by the name the dashboard gives it, on either side (a result's newest payment may be money in).
    func categoryLook(named name: String) -> Category? {
        category(name, side: .expenses) ?? category(name, side: .income)
    }
}

extension NameSearch {
    /// The names whose newest payment is newest, as results without a match (what the page lists before typing):
    /// newest payment first, then more payments, then the key, so the order never changes between two looks.
    static func latest(in groups: [String: PaymentNameGroup], limit: Int) -> [NameSearchResult] {
        groups.compactMap { key, group -> NameSearchResult? in
            guard let newest = group.rows.first else { return nil }
            return NameSearchResult(key: key, shownName: newest.place, matchedName: nil, count: group.count,
                                    moneyOut: group.moneyOut, moneyIn: group.moneyIn, newestDate: newest.date,
                                    categoryName: newest.categoryName)
        }
        .sorted {
            if $0.newestDate != $1.newestDate { return $0.newestDate > $1.newestDate }
            if $0.count != $1.count { return $0.count > $1.count }
            return $0.key < $1.key
        }
        .prefix(max(0, limit)).map { $0 }
    }
}

/// What the search page says (pure, so tests pin it).
nonisolated enum SearchPage {
    /// How many of the newest names show before anything is typed.
    static let latestCount = 8
    /// A result whose category the dashboard no longer has: its tile in the neutral grey of the category looks.
    static let noCategoryColor = "9AA6B8"

    /// The kind of the other name a result was found by.
    enum MatchKind: Equatable {
        /// A bank line of one of its payments (an older spelling of the shop's name, or the line under an own name).
        case bank
        /// A name of one's own (one shown on another payment, or hidden while Own names is off).
        case own
        /// Anything else, such as the Shop typed on a receipt or a cash entry.
        case other
    }

    /// The field's prompt and the page's line before anything is typed.
    static func prompt(language: AppLanguage = .current) -> String { language.string("Search names") }
    static func hint(language: AppLanguage = .current) -> String {
        language.string("Finds your own names and the bank's.")
    }

    /// The heading over the newest names before anything is typed.
    static func latestHeading(language: AppLanguage = .current) -> String { language.string("Latest") }

    /// Nothing matches what was typed: one quiet line.
    static func noMatch(_ query: String, language: AppLanguage = .current) -> String {
        language.string("No name found for “\(query.trimmingCharacters(in: .whitespacesAndNewlines))”.")
    }

    /// What kind of name `name` is among a group's: a bank payment's own bank line (`bankName` when the row shows
    /// another name, else its shown name), a receipt's or entry's typed Shop, else a name of one's own.
    static func kind(of name: String, in group: PaymentNameGroup?) -> MatchKind {
        guard let group else { return .other }
        if group.rows.contains(where: { $0.receiptId == nil && ($0.bankName ?? $0.place) == name }) { return .bank }
        if group.rows.contains(where: { $0.receiptId != nil && $0.place == name }) { return .other }
        return .own
    }

    /// The row's line under a match on another name: "Bank's name: MGP Vinted - Kleiderkreisel", "Your name: …", or
    /// the name alone (a receipt's Shop).
    static func matchLine(_ name: String, kind: MatchKind, language: AppLanguage = .current) -> String {
        switch kind {
        case .bank: language.string("Bank's name: \(name)")
        case .own: language.string("Your name: \(name)")
        case .other: name
        }
    }

    /// The row's quiet line: the count, the newest payment's day, its category: "12 payments · 14 Oct · Clothes" /
    /// "12 Buchungen · 14. Okt. · Kleidung" (as a mail list dates a thread by its newest message; "zuletzt" made the
    /// German line too long for the category). The year shows when the day is in another year than `now`'s.
    static func line(count: Int, newestDate: String, category: String, now: Date = .now,
                     language: AppLanguage = .current) -> String {
        var parts = [language.string("\(count) payments")]
        if let day = day(newestDate, now: now, language: language) { parts.append(day) }
        let category = CategoryName.shown(category, language: language)
        if !category.isEmpty { parts.append(category) }
        return parts.joined(separator: " · ")
    }

    /// A result's whole set of lines.
    struct Row: Equatable {
        let title: String
        let line: String
        /// The other name it was found by, with what kind it is (nil: found by its shown name).
        let match: String?
        /// The money out ("−84.50") and in ("+20.00"), each only when there is any.
        let moneyOut: String?
        let moneyIn: String?

        init(_ result: NameSearchResult, group: PaymentNameGroup?, now: Date = .now,
             language: AppLanguage = .current) {
            title = result.shownName
            line = SearchPage.line(count: result.count, newestDate: result.newestDate, category: result.categoryName,
                                   now: now, language: language)
            match = result.matchedName.map { SearchPage.matchLine($0, kind: SearchPage.kind(of: $0, in: group),
                                                                   language: language) }
            moneyOut = result.moneyOut > 0 ? Money.transaction(-result.moneyOut, language: language) : nil
            moneyIn = result.moneyIn > 0 ? Money.transaction(result.moneyIn, language: language) : nil
        }

        /// What VoiceOver reads for the row, in one go.
        var spoken: String {
            [title, line, match, moneyOut, moneyIn].compactMap { $0 }.joined(separator: ", ")
        }
    }

    /// "14 Oct" / "14. Okt." (with the year when it is not `now`'s); nil when it is no day.
    private static func day(_ value: String, now: Date, language: AppLanguage) -> String? {
        guard let date = WidgetFormatting.date(String(value.prefix(10))) else { return nil }
        let calendar = WidgetFormatting.calendar
        var style = Date.FormatStyle(date: .omitted, time: .omitted, locale: language.locale, calendar: calendar,
                                     timeZone: calendar.timeZone).day().month(.abbreviated)
        if calendar.component(.year, from: date) != calendar.component(.year, from: now) { style = style.year() }
        return date.formatted(style)
    }
}
