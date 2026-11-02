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
    /// All stored exclusions matched by this entry, including both sides of a merged price step.
    let exclusionIDs: Set<String>
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
    /// A booking may pay both a subscription and an extra. Keep the bank row intact for navigation and marks,
    /// and use integer cents for each portion so detecting the extra cannot count the subscription twice.
    private struct Payment {
        let row: Transaction
        let cents: Int
        let order: Int
        let date: Date

        init(row: Transaction, cents: Int, order: Int) {
            self.row = row
            self.cents = cents
            self.order = order
            self.date = FixedCosts.date(row.date)!
        }
    }

    private struct Series {
        let payments: [Payment]
        let anchors: [Payment]
        let cadence: FixedCostCadence?
    }

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
        var groups: [String: [Payment]] = [:]
        for (order, row) in candidates where date(row.date) != nil {
            let side: DashboardSide = row.amount < 0 ? .expenses : .income
            let key = row.nameKey! + "\u{1F}" + side.rawValue
            let cents = Int((abs(row.countedAmount) * 100).rounded())
            groups[key, default: []].append(Payment(row: row, cents: cents, order: order))
        }
        return groups.keys.sorted().flatMap { key in
            let series = splitCombinedPayments(groups[key]!)
            return series.indices.compactMap { index -> FixedCostEntry? in
                let payments = series[index].payments, rows = payments.map(\.row)
                guard let cadence = series[index].cadence else { return nil }
                // Only the long series' own span must be clean. Check portions, since a combined booking's
                // subscription can be regular while its extra is an unrelated one-off (or vice versa).
                if cadence.months >= 6 && series.contains(where: { other in
                    other.cadence == nil && other.payments.contains {
                        $0.row.date >= rows.first!.date && $0.row.date <= rows.last!.date
                    }
                }) { return nil }
                let newest = rows.last!, side: DashboardSide = newest.amount < 0 ? .expenses : .income
                let names = side == .expenses ? newest.categoriesIn : newest.incomeBuckets
                let name = names.contains(newest.categoryName) ? newest.categoryName : names.first
                guard let name, let category = categories[name], let next = cadence.nextDay(after: newest.date) else { return nil }
                // A carried row can also anchor an extra of the same cadence. Only the series' own amount
                // rows may claim that mark, so taking out the extra never takes out the membership as well.
                // A merged price step accepts anchors from either segment; the first stored mark wins if
                // both were taken out. Without a mark, keep the earliest import sequence as before.
                let stored = marks.filter { mark in
                    mark.side == side && mark.cadence == cadence
                        && series[index].anchors.contains { $0.row.id == mark.anchor }
                }
                let anchor = series[index].anchors.min {
                    let left = $0.row.ledgerSequence ?? Int.max, right = $1.row.ledgerSequence ?? Int.max
                    return left < right
                }!.row
                let identity = stored.first ?? FixedCostMark(key: anchor.fixedCostKey ?? anchor.nameKey!, side: side, cadence: cadence, anchor: anchor.id)
                let cents = payments.last!.cents
                let age = calendar.dateComponents([.day], from: payments.last!.date, to: reference).day!
                return FixedCostEntry(mark: identity, newest: newest, category: category, cents: cents,
                    monthlyCents: Int((Double(cents) / Double(cadence.months)).rounded()), count: rows.count,
                    first: rows[0].date, last: newest.date, nextDue: next, running: age <= cadence.graceDays,
                    notFixed: !stored.isEmpty, exclusionIDs: Set(stored.map(\.id)), ids: rows.reversed().map(\.id))
            }
        }
    }

    private static func amountSeries(_ payments: [Payment]) -> [[Payment]] {
        var series: [[Payment]] = []
        for payment in payments {
            // Closest open amount wins an ambiguous match; series order makes ties deterministic.
            let match = series.indices.filter {
                abs(series[$0].last!.cents - payment.cents) <= max(300, Int((Double(payment.cents) * 0.1).rounded()))
            }.min { abs(series[$0].last!.cents - payment.cents) < abs(series[$1].last!.cents - payment.cents) }
            if let match { series[match].append(payment) } else { series.append([payment]) }
        }
        return series
    }

    private static func chronological(_ a: Payment, _ b: Payment) -> Bool {
        a.row.date == b.row.date ? a.order < b.order : a.row.date < b.row.date
    }

    /// A price change can exceed the amount tolerance. Join adjacent, nonoverlapping segments before any
    /// booking is split, including a two-payment segment that is too short to be an entry on its own.
    private static func mergingPriceSteps(_ amounts: [[Payment]]) -> [[Payment]] {
        var result = amounts.sorted { chronological($0[0], $1[0]) }
        var changed = true
        while changed {
            changed = false
            for older in result.indices {
                let previous = result[older], dates = previous.map(\.date)
                guard let cadence = cadence(for: dates, allowingShortSegment: true), hasSteadyDay(dates) else { continue }
                let usual = usualDay(dates).day
                guard let newer = result.indices.first(where: { index in
                    let next = result[index], nextDates = next.map(\.date)
                    return index != older && previous.last!.date < next[0].date
                        && self.cadence(for: nextDates, allowingShortSegment: true) == cadence
                        && hasSteadyDay(nextDates) && dayDistance(usualDay(nextDates).day, usual) <= 5
                        && period(next[0].date, usual: usual) - period(previous.last!.date, usual: usual) == cadence.months
                        && self.cadence(for: dates + nextDates) == cadence
                }) else { continue }
                result[older] += result[newer]
                result.remove(at: newer)
                changed = true
                break
            }
        }
        return result
    }

    private static func splitCombinedPayments(_ payments: [Payment]) -> [Series] {
        var remaining = payments, result: [Series] = []
        while true {
            // Allocate smaller subscriptions first. Every allocation removes its cents from the booking;
            // the remainder goes through the same amount grouping and cadence rules as an ordinary payment.
            let seeds = mergingPriceSteps(amountSeries(remaining)).sorted { $0.last!.cents < $1.last!.cents }
            let regular = seeds.compactMap { seed -> Series? in
                guard let cadence = cadence(for: seed.map(\.date)) else { return nil }
                return Series(payments: seed, anchors: seed, cadence: cadence)
            }
            var found: Series?
            for seed in seeds where seed.count >= 2 {
                let ownDates = seed.map(\.date)
                guard hasSteadyDay(ownDates) else { continue }
                let originalCadence = cadence(for: ownDates)
                // A yearly supermarket pair must not become a monthly subscription by borrowing its other
                // visits. Preserve an established cadence; a series with combined gaps still needs a short
                // interval of its own before larger bookings can complete it.
                if let originalCadence, originalCadence.months >= 6 { continue }
                let gaps = zip(ownDates, ownDates.dropFirst()).map {
                    calendar.dateComponents([.day], from: $0, to: $1).day!
                }
                let ownIDs = Set(seed.map { $0.row.id })
                let usual = usualDay(ownDates).day
                let phase = period(seed[0].date, usual: usual)
                for cadence in [FixedCostCadence.monthly, .quarterly] {
                    let twice = cadence.days.lowerBound * 2...cadence.days.upperBound * 2
                    guard originalCadence == nil || originalCadence == cadence,
                          gaps.contains(where: { cadence.days.contains($0) || twice.contains($0) }) else { continue }
                    let ownSlots = Set(ownDates.map { period($0, usual: usual) })
                    func carriedCents(_ payment: Payment) -> Int {
                        seed.last { $0.row.date <= payment.row.date }?.cents ?? seed[0].cents
                    }
                    func canCarry(_ payment: Payment) -> Bool {
                        let slot = period(payment.date, usual: usual)
                        return (slot - phase).isMultiple(of: cadence.months) && !ownSlots.contains(slot)
                            && dayDistance(calendar.component(.day, from: payment.date), usual) <= 5
                            && payment.cents > carriedCents(payment)
                    }
                    // A regular subscription owns its payments. The sparse combined-fee case is the only
                    // exception: all of a longer series' bookings must fill empty base periods, and their
                    // differences must themselves form one regular fee. Never split just part of a series.
                    let reserved = Set(regular.flatMap { $0.payments.map { $0.row.id } })
                    var occupied = ownSlots
                    var augmented = seed
                    for owner in regular {
                        if owner.cadence!.months >= 6 && owner.cadence!.months > cadence.months,
                           owner.payments.allSatisfy({ canCarry($0) && !occupied.contains(period($0.date, usual: usual)) }) {
                            let extras = owner.payments.map {
                                Payment(row: $0.row, cents: $0.cents - carriedCents($0), order: $0.order)
                            }
                            if mergingPriceSteps(amountSeries(extras)).contains(where: {
                                $0.count == extras.count && self.cadence(for: $0.map(\.date)) == owner.cadence
                            }) {
                                for payment in owner.payments {
                                    occupied.insert(period(payment.date, usual: usual))
                                    augmented.append(Payment(row: payment.row, cents: carriedCents(payment), order: payment.order))
                                }
                            }
                        }
                    }
                    for payment in remaining where !ownIDs.contains(payment.row.id) && !reserved.contains(payment.row.id) {
                        let slot = period(payment.date, usual: usual)
                        guard canCarry(payment), !occupied.contains(slot) else { continue }
                        let cents = carriedCents(payment)
                        occupied.insert(slot)
                        augmented.append(Payment(row: payment.row, cents: cents, order: payment.order))
                    }
                    augmented.sort(by: chronological)
                    guard self.cadence(for: augmented.map(\.date)) == cadence else { continue }
                    found = Series(payments: augmented, anchors: seed, cadence: cadence)
                    break
                }
                if found != nil { break }
            }
            guard let found else { break }
            result.append(found)
            let allocated = Dictionary(uniqueKeysWithValues: found.payments.map { ($0.row.id, $0.cents) })
            remaining = remaining.compactMap { payment in
                let cents = payment.cents - allocated[payment.row.id, default: 0]
                return cents > 0 ? Payment(row: payment.row, cents: cents, order: payment.order) : nil
            }
        }
        return result + mergingPriceSteps(amountSeries(remaining)).map {
            Series(payments: $0, anchors: $0, cadence: cadence(for: $0.map(\.date)))
        }
    }

    /// Assign to the nearest usual day, allowing a booking on the 31st to pay the 1st of the following month.
    /// Quarterly slots must also have the same month phase as the original series.
    private static func period(_ date: Date, usual: Int) -> Int {
        let month = calendar.dateInterval(of: .month, for: date)!.start
        let nearest = (-1...1).map { offset -> Date in
            let start = calendar.date(byAdding: .month, value: offset, to: month)!
            let day = min(usual, calendar.range(of: .day, in: .month, for: start)!.count)
            return calendar.date(byAdding: .day, value: day - 1, to: start)!
        }.min { abs($0.timeIntervalSince(date)) < abs($1.timeIntervalSince(date)) }!
        return calendar.component(.year, from: nearest) * 12 + calendar.component(.month, from: nearest) - 1
    }

    private static func cadence(for dates: [Date], allowingShortSegment: Bool = false) -> FixedCostCadence? {
        guard dates.count >= 2 else { return nil }
        let gaps = zip(dates, dates.dropFirst()).map { calendar.dateComponents([.day], from: $0, to: $1).day! }
        return FixedCostCadence.allCases.first { cadence in
            guard allowingShortSegment || dates.count >= cadence.minimumCount else { return false }
            let twice = cadence.days.lowerBound * 2...cadence.days.upperBound * 2
            let normalized = gaps.map { twice.contains($0) ? Double($0) / 2 : Double($0) }.sorted()
            let middle = normalized.count / 2
            let median = normalized.count.isMultiple(of: 2)
                ? (normalized[middle - 1] + normalized[middle]) / 2 : normalized[middle]
            return gaps.contains(where: cadence.days.contains)
                && median >= Double(cadence.days.lowerBound) && median <= Double(cadence.days.upperBound)
                && gaps.allSatisfy { Double($0) >= median / 2 }
                && gaps.filter { cadence.days.contains($0) || twice.contains($0) }.count * 4 >= gaps.count * 3
                && (cadence.months >= 6 || hasSteadyDay(dates))
        }
    }

    /// The usual day is the circular median: the day that minimizes total distance on a 31-day month. Wrapping
    /// keeps the 30th, 31st and 1st close, including February's clamped month end. A tie favors the larger cluster.
    private static func hasSteadyDay(_ dates: [Date]) -> Bool {
        usualDay(dates).close * 4 >= dates.count * 3
    }

    private static func dayDistance(_ day: Int, _ usual: Int) -> Int {
        let distance = abs(day - usual)
        return min(distance, 31 - distance)
    }

    private static func usualDay(_ dates: [Date]) -> (day: Int, total: Int, close: Int) {
        let days = dates.map { calendar.component(.day, from: $0) }
        let choices = (1...31).map { usual in
            let distances = days.map { dayDistance($0, usual) }
            return (day: usual, total: distances.reduce(0, +), close: distances.filter { $0 <= 5 }.count)
        }
        return choices.min {
            if $0.total != $1.total { return $0.total < $1.total }
            return $0.close == $1.close ? $0.day < $1.day : $0.close > $1.close
        }!
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
