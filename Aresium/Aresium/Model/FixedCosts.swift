import Foundation

nonisolated enum FixedCostCadence: String, Codable, CaseIterable, Sendable {
    case monthly, quarterly, halfYearly, yearly

    var months: Int {
        switch self { case .monthly: 1; case .quarterly: 3; case .halfYearly: 6; case .yearly: 12 }
    }
    var days: ClosedRange<Int> {
        switch self { case .monthly: 26...35; case .quarterly: 85...98; case .halfYearly: 175...190; case .yearly: 355...375 }
    }
    var graceDays: Int {
        switch self { case .monthly: 45; case .quarterly: 120; case .halfYearly: 220; case .yearly: 400 }
    }
    var minimumCount: Int { months < 6 ? 3 : 2 }

    func nextDay(after day: String) -> String? {
        guard let date = FixedCosts.date(day),
              let next = FixedCosts.calendar.date(byAdding: .month, value: months, to: date) else { return nil }
        return LedgerExport.day(next, calendar: FixedCosts.calendar)
    }
}

/// The series anchor distinguishes two subscriptions at one shop with the same cadence. It is a payment id,
/// never an amount (a price rise must preserve a correction). A stored anchor also survives an older import.
nonisolated struct FixedCostMark: Codable, Equatable, Hashable, Sendable {
    /// The anchor payment's original merchant key, or exact bank line, independent of display names.
    let key: String
    let side: DashboardSide
    let cadence: FixedCostCadence
    let anchor: String
    var id: String { [key, side.rawValue, cadence.rawValue, anchor].joined(separator: "\u{1F}") }
}

nonisolated struct FixedCostEntry: Identifiable, Sendable {
    let mark: FixedCostMark
    let newest: Transaction
    let category: Category
    let cents: Int
    let monthlyCents: Int
    let count: Int
    let first: String
    let last: String
    let nextDue: String
    let running: Bool
    let notFixed: Bool
    /// Dashboard row ids, newest first (later dashboard order breaks same-day ties).
    let ids: [String]
    var id: String { mark.id }
    var name: String { newest.place }
    var side: DashboardSide { mark.side }
    var cadence: FixedCostCadence { mark.cadence }
    var amount: Double { Double(cents) / 100 }
    var monthlyEquivalent: Double { Double(monthlyCents) / 100 }
}

nonisolated struct FixedCostList: Sendable {
    let running: [FixedCostEntry]
    let ended: [FixedCostEntry]
    let takenOut: [FixedCostEntry]
    var monthlyCents: Int { running.reduce(0) { $0 + $1.monthlyCents } }
    var monthlyTotal: Double { Double(monthlyCents) / 100 }
}

nonisolated enum FixedCosts {
    /// UTC Gregorian arithmetic makes detection independent of time zones and daylight saving.
    static var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(secondsFromGMT: 0)!
        return result
    }
    static func date(_ day: String) -> Date? {
        guard LedgerExport.isDay(day) else { return nil }
        let parts = day.split(separator: "-").compactMap { Int($0) }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
    }

    static func entries(in dashboard: Dashboard, marks: [FixedCostMark] = []) -> [FixedCostEntry] {
        // The reference is the whole ledger's newest bank payment, including transfers and withdrawals.
        let bank = dashboard.transactions.filter { $0.receiptId == nil && $0.coveredBy == nil }
        guard let reference = bank.map(\.date).max().flatMap(date) else { return [] }
        let categories = Dictionary((dashboard.categories + dashboard.incomeBuckets).map { ($0.name, $0) },
                                    uniquingKeysWith: { first, _ in first })
        let candidates = bank.enumerated().filter { _, row in
            row.nameKey != nil && row.cashWithdrawal != true && row.countedAmount != 0
                && categories[row.categoryName]?.kind != .transfer
                && !(row.categoriesIn + row.incomeBuckets).isEmpty
        }.sorted {
            $0.element.date == $1.element.date ? $0.offset < $1.offset : $0.element.date < $1.element.date
        }
        var groups: [String: [[Transaction]]] = [:]
        for (_, row) in candidates {
            let side: DashboardSide = row.amount < 0 ? .expenses : .income
            let key = row.nameKey! + "\u{1F}" + side.rawValue
            var series = groups[key, default: []]
            let cents = Int((abs(row.countedAmount) * 100).rounded())
            // Closest open amount wins an ambiguous match; series order makes ties deterministic.
            let match = series.indices.filter {
                let previous = Int((abs(series[$0].last!.countedAmount) * 100).rounded())
                return abs(previous - cents) <= max(300, Int((Double(cents) * 0.1).rounded()))
            }.min {
                abs(abs(series[$0].last!.countedAmount) - abs(row.countedAmount))
                    < abs(abs(series[$1].last!.countedAmount) - abs(row.countedAmount))
            }
            if let match { series[match].append(row) } else { series.append([row]) }
            groups[key] = series
        }
        return groups.keys.sorted().flatMap { key in
            groups[key]!.compactMap { rows -> FixedCostEntry? in
                let dates = rows.compactMap { date($0.date) }
                guard dates.count == rows.count, rows.count >= 2 else { return nil }
                let gaps = zip(dates, dates.dropFirst()).map { calendar.dateComponents([.day], from: $0, to: $1).day! }
                let cadence = FixedCostCadence.allCases.first { cadence in
                    let twice = cadence.days.lowerBound * 2...cadence.days.upperBound * 2
                    let normalized = gaps.map { twice.contains($0) ? Double($0) / 2 : Double($0) }.sorted()
                    let middle = normalized.count / 2
                    let median = normalized.count.isMultiple(of: 2)
                        ? (normalized[middle - 1] + normalized[middle]) / 2 : normalized[middle]
                    return rows.count >= cadence.minimumCount && gaps.contains(where: cadence.days.contains)
                        && median >= Double(cadence.days.lowerBound) && median <= Double(cadence.days.upperBound)
                        && gaps.allSatisfy { Double($0) >= median / 2 }
                        && gaps.filter { cadence.days.contains($0) || twice.contains($0) }.count * 4 >= gaps.count * 3
                }
                guard let cadence else { return nil }
                let newest = rows.last!, side: DashboardSide = newest.amount < 0 ? .expenses : .income
                let names = side == .expenses ? newest.categoriesIn : newest.incomeBuckets
                let name = names.contains(newest.categoryName) ? newest.categoryName : names.first
                guard let name, let category = categories[name], let next = cadence.nextDay(after: newest.date) else { return nil }
                let stored = marks.first { mark in
                    mark.side == side && mark.cadence == cadence
                        && rows.contains { $0.id == mark.anchor }
                }
                let anchor = rows.min {
                    let left = $0.ledgerSequence ?? Int.max, right = $1.ledgerSequence ?? Int.max
                    return left < right
                } ?? rows[0]
                let identity = stored ?? FixedCostMark(key: anchor.fixedCostKey ?? anchor.nameKey!, side: side, cadence: cadence, anchor: anchor.id)
                let cents = Int((abs(newest.countedAmount) * 100).rounded())
                let age = calendar.dateComponents([.day], from: dates.last!, to: reference).day!
                return FixedCostEntry(mark: identity, newest: newest, category: category, cents: cents,
                    monthlyCents: Int((Double(cents) / Double(cadence.months)).rounded()), count: rows.count,
                    first: rows[0].date, last: newest.date, nextDue: next, running: age <= cadence.graceDays,
                    notFixed: stored != nil, ids: rows.reversed().map(\.id))
            }
        }
    }

    static func list(_ entries: [FixedCostEntry], side: DashboardSide) -> FixedCostList {
        let rows = entries.filter { $0.side == side }
        func ranked(_ a: FixedCostEntry, _ b: FixedCostEntry) -> Bool {
            if a.monthlyCents != b.monthlyCents { return a.monthlyCents > b.monthlyCents }
            return a.name == b.name ? a.id < b.id : a.name < b.name
        }
        return FixedCostList(running: rows.filter { $0.running && !$0.notFixed }.sorted(by: ranked),
            ended: rows.filter { !$0.running && !$0.notFixed }.sorted { $0.last == $1.last ? $0.id < $1.id : $0.last > $1.last },
            takenOut: rows.filter(\.notFixed).sorted(by: ranked))
    }
}

nonisolated struct FixedCostsCache: Sendable {
    var revision = -1
    var entries: [FixedCostEntry] = []
    static func build(_ dashboard: Dashboard, marks: [FixedCostMark]) async -> [FixedCostEntry] {
        await Task.detached(priority: .userInitiated) { FixedCosts.entries(in: dashboard, marks: marks) }.value
    }
}

extension DashboardStore {
    func fixedCosts(side: DashboardSide) -> FixedCostList? {
        guard phone != nil, dashboard != nil, builtFixedCosts.revision == revision else { return nil }
        return FixedCosts.list(builtFixedCosts.entries, side: side)
    }
    /// An entry id from any of the three lists; nil when detection no longer finds it.
    func fixedCost(id: String) -> FixedCostEntry? {
        guard phone != nil, builtFixedCosts.revision == revision, dashboard != nil else { return nil }
        return builtFixedCosts.entries.first { $0.id == id }
    }
    func setNotFixed(_ entry: FixedCostEntry, _ notFixed: Bool) async throws -> BatchUndo {
        guard let phone, let live = fixedCost(id: entry.id), live.ids == entry.ids else { throw BatchChangeError.unavailable }
        let undo = try await phone.setNotFixed(live, notFixed)
        undo.afterChange = { [weak self] in await self?.reloadAfterTransactionChange() }
        await reloadAfterTransactionChange()
        return undo
    }
}

nonisolated enum FixedCostWording {
    static func cadence(_ cadence: FixedCostCadence, language: AppLanguage = .current) -> String {
        switch cadence {
        case .monthly: language.string("monthly")
        case .quarterly: language.string("quarterly")
        case .halfYearly: language.string("every 6 months")
        case .yearly: language.string("yearly")
        }
    }
    /// `referenceDay` is explicit so the year and both languages are testable without a wall clock.
    static func nextDue(_ day: String, referenceDay: String = ReceiptDay.day(.now), language: AppLanguage = .current) -> String {
        guard let formatted = shortDay(day, referenceDay: referenceDay, language: language) else { return day }
        return language.string("next \(formatted)")
    }
    /// An ended entry's newest payment (brief 209): "last 3 Aug" / "zuletzt am 3. Aug.", the year as in `nextDue`.
    static func last(_ day: String, referenceDay: String = ReceiptDay.day(.now), language: AppLanguage = .current) -> String {
        guard let formatted = shortDay(day, referenceDay: referenceDay, language: language) else { return day }
        return language.string("last \(formatted)")
    }
    /// "3 Dec" / "3. Dez.", with the year only when it is not the reference day's.
    private static func shortDay(_ day: String, referenceDay: String, language: AppLanguage) -> String? {
        guard let date = FixedCosts.date(day) else { return nil }
        var style = Date.FormatStyle(date: .omitted, time: .omitted, locale: language.locale,
                                     calendar: FixedCosts.calendar, timeZone: FixedCosts.calendar.timeZone).day().month(.abbreviated)
        if day.prefix(4) != referenceDay.prefix(4) { style = style.year() }
        return date.formatted(style)
    }
}
