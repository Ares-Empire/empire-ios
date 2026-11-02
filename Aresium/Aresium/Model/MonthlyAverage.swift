import Foundation

/// Finished months only. Totals already include the engine's payback accounting, on either backend.
nonisolated struct MonthlyAverage: Equatable, Sendable {
    let cents: Int
    let count: Int
    let first: String
    let last: String
    var amount: Double { Double(cents) / 100 }

    static func calculate(in dashboard: Dashboard, side: DashboardSide) -> MonthlyAverage? {
        let earliest = dashboard.transactions.map(\.date).min()
        let lateFirst = earliest.flatMap { Int($0.suffix(2)) }.map { $0 > 7 } ?? false
        let months = dashboard.months.filter {
            !$0.partial && !(lateFirst && $0.key == earliest.map { String($0.prefix(7)) })
        }.sorted { $0.key < $1.key }
        guard months.count >= 2 else { return nil }
        let cents = months.reduce(0) { total, month in
            let data = dashboard.byMonth[month.key]
            let amount = side == .expenses ? data?.expense : data?.income
            return total + Int(((amount ?? 0) * 100).rounded())
        }
        return MonthlyAverage(cents: Int((Double(cents) / Double(months.count)).rounded()), count: months.count,
                              first: months[0].key, last: months[months.count - 1].key)
    }
}

extension DashboardStore {
    func monthlyAverage(side: DashboardSide) -> MonthlyAverage? {
        dashboard.flatMap { MonthlyAverage.calculate(in: $0, side: side) }
    }
}
