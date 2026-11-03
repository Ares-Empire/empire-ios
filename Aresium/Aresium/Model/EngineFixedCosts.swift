import Foundation

nonisolated enum FixedCostCadence: String, Codable, CaseIterable, Sendable {
    case monthly, quarterly, halfYearly, yearly
}

/// The stored Swift mark format is identical to the engine: no schema or ID migration is needed.
nonisolated struct FixedCostMark: Codable, Equatable, Hashable, Sendable {
    /// The anchor payment's original merchant key, or exact bank line, independent of display names.
    let key: String
    let side: DashboardSide
    let cadence: FixedCostCadence
    let anchor: String
    var id: String { [key, side.rawValue, cadence.rawValue, anchor].joined(separator: "\u{1F}") }
}

nonisolated struct FixedCostEntry: Codable, Identifiable, Sendable {
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
    let id: String
    let name: String
    let side: DashboardSide
    let cadence: FixedCostCadence
    let amount: Double
    let monthlyEquivalent: Double
}

nonisolated struct FixedCostList: Codable, Sendable {
    let running: [FixedCostEntry]
    let ended: [FixedCostEntry]
    let takenOut: [FixedCostEntry]
    let monthlyCents: Int
    let monthlyTotal: Double
    let yearlyTotal: Double
}

/// Results of the shared engine after the phone has applied its display names and stable grouping keys.
nonisolated struct FixedCostAnalysis: Decodable, Sendable {
    let entries: [FixedCostEntry]
    let lists: [String: FixedCostList]
    let averages: [String: MonthlyAverage]
}

nonisolated struct FixedCostsCache: Sendable {
    var revision = -1
    var analysis: FixedCostAnalysis? = nil
    var entries: [FixedCostEntry] { analysis?.entries ?? [] }

    static func build(_ dashboard: Dashboard, marks: [FixedCostMark], engine: AresiumEngine,
                      includeFixedCosts: Bool = true) async throws -> FixedCostAnalysis {
        try await engine.fixedCostAnalysis(in: dashboard, marks: marks, includeFixedCosts: includeFixedCosts)
    }
}

extension DashboardStore {
    func fixedCosts(side: DashboardSide) -> FixedCostList? {
        guard phone != nil, dashboard != nil, builtFixedCosts.revision == revision else { return nil }
        return builtFixedCosts.analysis?.lists[side.rawValue]
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

