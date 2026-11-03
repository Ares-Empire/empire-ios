import Foundation

/// The engine's finished-month average, including its payback accounting on either backend.
nonisolated struct MonthlyAverage: Codable, Equatable, Sendable {
    let cents: Int
    let count: Int
    let first: String
    let last: String
    var amount: Double { Double(cents) / 100 }
}

extension DashboardStore {
    func monthlyAverage(side: DashboardSide) -> MonthlyAverage? {
        guard dashboard != nil, builtFixedCosts.revision == revision else { return nil }
        return builtFixedCosts.analysis?.averages[side.rawValue]
    }
}
