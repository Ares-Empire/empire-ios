import Foundation

/// Keep both the work and the lifetime of large payment arrays on the ledger's worker. Merely awaiting a snapshot
/// from the main actor still destroys its payments and raw JSON there after the engine returns.
extension PhoneLedger {
    func sort(engine: AresiumEngine, catalog: CategoryCatalog, fresh: Set<String>) async throws -> [String: String?] {
        let snapshot = try sortingSnapshot()
        guard !snapshot.ids.isEmpty else { return [:] }
        let list = PhoneCategoryList(catalog: catalog, chosen: try chosen())
        let ids = PickerTiming.measure("sort.list") { list.sortingIDs }
        let results = try await engine.sortPayments(snapshot.payments, categories: ids, learned: snapshot.learned)
        return try applySort(ids: snapshot.ids, results: results, fresh: fresh)
    }

    func categoryCounts(engine: AresiumEngine, catalog: CategoryCatalog) async throws -> [String: Int] {
        var counts = try paymentCounts()
        let list = PhoneCategoryList(catalog: catalog, chosen: try chosen())
        let unticked = list.catalog.defaults.map(\.id).filter { !list.isChosen($0) }
        let waiting = try sortingSnapshot(waitingOnly: true)
        if !unticked.isEmpty, !waiting.ids.isEmpty {
            let results = try await engine.sortPayments(waiting.payments, categories: list.sortingIDs + unticked,
                                                        learned: waiting.learned)
            let estimated = Set(unticked)
            PickerTiming.measure("counts.reduce") {
                for case let id? in results.map(\.categoryId) where estimated.contains(id) { counts[id, default: 0] += 1 }
            }
        }
        return counts.filter { $0.value > 0 }
    }

    func dashboard(engine: AresiumEngine, catalog: CategoryCatalog, language: AppLanguage, today: String) async throws -> Dashboard {
        let list = PhoneCategoryList(catalog: catalog, chosen: try chosen(), language: language)
        let payments = try payments()
        let receipts = try receipts()
        let input = PickerTiming.measure("dashboard.input") {
            PhoneDashboard.input(payments: payments, list: list, today: today, receipts: receipts)
        }
        return try await engine.dashboard(input)
    }
}
