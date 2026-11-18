import Foundation

/// What the note beside a total says (brief 314): the euros of money paid back in that total, and whether they came off.
nonisolated struct PaybackNote: Equatable, Sendable {
    let linked: Double
    let subtracted: Bool

    /// "Excludes €64.00 paid back" / "Ohne 64,00 € Rückzahlungen"; "Includes …" / "Mit …" while they count as booked.
    func text(language: AppLanguage = .current) -> String {
        let euros = Money.precise(linked, language: language)
        return subtracted ? language.string("Excludes \(euros) paid back") : language.string("Includes \(euros) paid back")
    }
}

/// The euros linked as paid back, per side and month, and per category within them. A payment counts once in its month's
/// headline and under each category it is listed in, as its amount does.
nonisolated struct PaybackTotals: Sendable {
    private var months: [DashboardSide: [String: Int]] = [:]
    private var categories: [DashboardSide: [String: [String: Int]]] = [:]
    /// Read from the dashboard itself, so the note always agrees with the numbers beside it.
    private(set) var subtracted = true

    init(dashboard: Dashboard) {
        for row in dashboard.transactions where row.receiptId == nil && row.coveredBy == nil {
            let linked = Paybacks.linked(row)
            guard linked > 0 else { continue }
            let side: DashboardSide = row.amount < 0 ? .expenses : .income
            months[side, default: [:]][row.month, default: 0] += linked
            for name in side == .expenses ? row.categoriesIn : row.incomeBuckets {
                categories[side, default: [:]][name, default: [:]][row.month, default: 0] += linked
            }
            if row.counted == nil { subtracted = false }
        }
    }

    /// `month` nil: every month. `category` nil: the side's headline.
    func linked(side: DashboardSide, month: String?, category: String? = nil) -> Double {
        let values = category.map { categories[side]?[$0] ?? [:] } ?? months[side] ?? [:]
        return Double(month.map { values[$0] ?? 0 } ?? values.values.reduce(0, +)) / 100
    }
}

extension DashboardStore {
    /// The note beside a scope's total, or a category's. Nil where no link touches it, and in server mode.
    func paybackNote(side: DashboardSide, scope: DashboardScope, category: String? = nil) -> PaybackNote? {
        guard phone != nil, let dashboard else { return nil }
        if builtPaybackTotals?.revision != revision {
            builtPaybackTotals = (revision, PaybackTotals(dashboard: dashboard))
        }
        guard let totals = builtPaybackTotals?.totals else { return nil }
        let month = scope.isMonth ? monthKey(scope) : nil
        if scope.isMonth && month == nil { return nil }
        let linked = totals.linked(side: side, month: month, category: category)
        return linked > 0 ? PaybackNote(linked: linked, subtracted: totals.subtracted) : nil
    }
}
