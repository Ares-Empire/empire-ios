import Foundation
import os

/// The person's choices in Settings that change what the dashboard says.
nonisolated struct DashboardPreferences: Equatable, Sendable {
    var ownNames = true
    /// Linked money paid back comes off spending and income; off, both payments count as the bank booked them.
    var subtractPaybacks = true
}

/// Keep both the work and the lifetime of large payment arrays on the ledger's worker. Merely awaiting a snapshot
/// from the main actor still destroys its payments and raw JSON there after the engine returns.
/// Share one engine result between a payment detail and the dashboard reload following the same change.
/// Every ledger save invalidates it, including a value changed and changed back. Display preferences and the day
/// are part of the key; no saved state or network is involved.
nonisolated struct PhoneDashboardCache {
    let revision: UInt64
    let today: String
    let language: AppLanguage
    let preferences: DashboardPreferences
    let engine: ObjectIdentifier
    let dashboard: Dashboard
}

extension PhoneLedger {
    func sort(engine: AresiumEngine, catalog: CategoryCatalog, fresh: Set<String>) async throws -> [String: String?] {
        configurePaybacks(catalog: catalog)
        let snapshot = try sortingSnapshot()
        guard !snapshot.ids.isEmpty else { return [:] }
        let list = PhoneCategoryList(catalog: catalog, chosen: try chosen())
        let ids = PickerTiming.measure("sort.list") { list.sortingIDs }
        let results = try await engine.sortPayments(snapshot.payments, categories: ids, learned: snapshot.learned, localPlaces: true)
        return try applySort(ids: snapshot.ids, results: results, fresh: fresh)
    }

    func categoryCounts(engine: AresiumEngine, catalog: CategoryCatalog) async throws -> [String: Int] {
        var counts = try paymentCounts()
        let list = PhoneCategoryList(catalog: catalog, chosen: try chosen())
        let unticked = list.catalog.defaults.map(\.id).filter { !list.isChosen($0) }
        let waiting = try sortingSnapshot(waitingOnly: true)
        if !unticked.isEmpty, !waiting.ids.isEmpty {
            let results = try await engine.sortPayments(waiting.payments, categories: list.sortingIDs + unticked,
                                                        learned: waiting.learned, localPlaces: true)
            let estimated = Set(unticked)
            PickerTiming.measure("counts.reduce") {
                for case let id? in results.map(\.categoryId) where estimated.contains(id) { counts[id, default: 0] += 1 }
            }
        }
        return counts.filter { $0.value > 0 }
    }

    func dashboard(engine: AresiumEngine, catalog: CategoryCatalog, language: AppLanguage, today: String,
                   preferences: DashboardPreferences = DashboardPreferences()) async throws -> Dashboard {
        let observer = batchObserver(), revision = observer.value
        if let cached = cachedDashboard, cached.revision == revision, cached.today == today,
           cached.language == language, cached.preferences == preferences, cached.engine == ObjectIdentifier(engine) {
            return cached.dashboard
        }
        let list = PhoneCategoryList(catalog: catalog, chosen: try chosen(), language: language)
        let snapshot = try await shopSnapshot(engine: engine)
        let payments = snapshot.payments
        let receipts = snapshot.receipts
        let input = PickerTiming.measure("dashboard.input") {
            PhoneDashboard.input(payments: payments, list: list, today: today, receipts: receipts,
                                 subtractPaybacks: preferences.subtractPaybacks)
        }
        var dashboard = try await engine.dashboard(input)
        #if DEBUG
        for ignored in dashboard.paybacksIgnored ?? [] {
            Logger(subsystem: "de.ares-empire.aresium", category: "paybacks")
                .debug("Engine ignored a payback: \(ignored.reason, privacy: .public)")
        }
        #endif
        PickerTiming.measure("names.groups") {
            PaymentNames.apply(to: &dashboard, payments: payments, paymentKeys: snapshot.paymentKeys,
                               bankLineIdentities: snapshot.bankLineIdentities, receipts: receipts,
                               receiptKeys: snapshot.receiptKeys, rules: snapshot.shops.rules(snapshot.names),
                               identities: snapshot.shops, enabled: preferences.ownNames)
            PhoneDashboard.addPurposes(to: &dashboard, payments: payments)
        }
        if observer.value == revision {
            cachedDashboard = PhoneDashboardCache(revision: revision, today: today, language: language,
                                                   preferences: preferences, engine: ObjectIdentifier(engine), dashboard: dashboard)
        }
        return dashboard
    }
}
