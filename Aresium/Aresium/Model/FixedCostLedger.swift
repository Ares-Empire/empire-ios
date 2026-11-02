import Foundation
import SwiftData

extension PhoneLedger {
    func fixedCostMarks() throws -> [FixedCostMark] {
        try modelContext.fetch(FetchDescriptor<StoredFixedCostExclusion>(sortBy: [SortDescriptor(\.id)])).compactMap {
            guard let side = DashboardSide(rawValue: $0.side), let cadence = FixedCostCadence(rawValue: $0.cadence) else { return nil }
            return FixedCostMark(key: $0.key, side: side, cadence: cadence, anchor: $0.anchor)
        }
    }

    /// Same longest whole-word prefix move as name rules. Own names and exact bank lines are not engine keys.
    /// Called inside the engine-revision rebuild, before its single save.
    func moveFixedCostMarks(current: Set<String>) throws {
        let candidates = current.sorted { $0.count == $1.count ? $0 < $1 : $0.count > $1.count }
        let stored = try fixedCostMarks()
        var occupied = Set(stored.map(\.id))
        let models = try modelContext.fetch(FetchDescriptor<StoredFixedCostExclusion>())
        for mark in stored where mark.key.hasPrefix("merchant:") {
            let old = String(mark.key.dropFirst("merchant:".count))
            guard !current.contains(old), let key = candidates.first(where: { old.hasPrefix($0 + " ") }) else { continue }
            let moved = FixedCostMark(key: "merchant:" + key, side: mark.side, cadence: mark.cadence, anchor: mark.anchor)
            if occupied.insert(moved.id).inserted { modelContext.insert(StoredFixedCostExclusion(moved)) }
            if let model = models.first(where: { $0.id == mark.id }) { modelContext.delete(model) }
        }
    }

    func changeNotFixed(_ entry: FixedCostEntry, _ notFixed: Bool, engine: AresiumEngine,
                        catalog: CategoryCatalog, today: String, ownNames: Bool) async throws -> BatchLedgerUndo {
        let observer = batchObserver(), revision = observer.value
        let before = try batchSnapshot()
        let dashboard = try await dashboard(engine: engine, catalog: catalog, language: .current, today: today, ownNames: ownNames)
        guard observer.value == revision else { throw BatchChangeError.changed }
        // Refuse a stale screen before any write, including an import that changed membership or cadence.
        guard let live = FixedCosts.entries(in: dashboard, marks: before.fixedCostMarks).first(where: { $0.id == entry.id }),
              live.ids == entry.ids else { throw BatchChangeError.changed }
        do {
            let models = try modelContext.fetch(FetchDescriptor<StoredFixedCostExclusion>())
            if notFixed {
                if !models.contains(where: { $0.id == live.id }) { modelContext.insert(StoredFixedCostExclusion(live.mark)) }
            } else {
                // Both price segments may have been excluded before detection joined them. Count again
                // clears every matching mark in this one save; the existing snapshot undo restores them.
                for model in models where model.id == live.id || live.exclusionIDs.contains(model.id) {
                    modelContext.delete(model)
                }
            }
            try modelContext.save()
        } catch { modelContext.rollback(); throw error }
        return BatchLedgerUndo(ledger: observer.id, revision: observer.value, before: before, after: try batchSnapshot())
    }
}

extension PhoneBackend {
    func setNotFixed(_ entry: FixedCostEntry, _ notFixed: Bool) async throws -> BatchUndo {
        let token = try await ledger.changeNotFixed(entry, notFixed, engine: engine, catalog: engine.catalog(),
                                                    today: today(), ownNames: ownNames)
        try await refresh()
        return BatchUndo(token: token, phone: self)
    }
}
