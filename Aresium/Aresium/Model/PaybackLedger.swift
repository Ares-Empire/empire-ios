import Foundation
import SwiftData

extension PhoneLedger {
    func configurePaybacks(catalog: CategoryCatalog) {
        transferCategoryIDs = Set((catalog.defaults + catalog.builtIns).filter { $0.kind == "transfer" }.map(\.id))
    }

    /// `names`: the search's spellings (the shops' name rules, which take the engine's shop identities). Eligibility,
    /// rests and the suggestions need none of them, so a payment's page and the suggestions skip that work (brief 203:
    /// measured on the simulator at 5,000 payments, the state took 489 ms with the names).
    func paybackCandidates(engine: AresiumEngine, catalog: CategoryCatalog, today: String, ownNames: Bool,
                           names: Bool = true) async throws -> [PaybackCandidate] {
        configurePaybacks(catalog: catalog)
        let dashboard = try await dashboard(engine: engine, catalog: catalog, language: .current, today: today, ownNames: ownNames)
        guard names else {
            return Paybacks.candidates(dashboard: dashboard, payments: try payments(), transferIDs: transferCategoryIDs)
        }
        let snapshot = try await shopSnapshot(engine: engine)
        let rules = snapshot.shops.rules(snapshot.names)
        let shopNames = Dictionary(uniqueKeysWithValues: zip(snapshot.payments, snapshot.paymentKeys).compactMap { payment, key in
            rules[key].map { (payment.id, $0) }
        })
        return Paybacks.candidates(dashboard: dashboard, payments: snapshot.payments, transferIDs: transferCategoryIDs,
                                  shopNames: shopNames)
    }

    /// No awaited work after the revision check: validation and one save are an atomic ledger operation.
    func changePayback(from: String, to: String, amount: Double?, engine: AresiumEngine, catalog: CategoryCatalog,
                       today: String, ownNames: Bool) async throws -> BatchLedgerUndo {
        let observer = batchObserver(), revision = observer.value
        let before = try batchSnapshot()
        guard let payer = before.payments.first(where: { $0.id == from }) else { throw PaybackError.invalidPayment }
        var links = payer.paysBack ?? []
        let previous = links.first(where: { $0.payment == to }).flatMap { Double($0.amount) } ?? 0
        if let amount {
            guard let requested = Paybacks.cents(amount), requested > 0 else { throw PaybackError.invalidAmount }
            let candidates = try await paybackCandidates(engine: engine, catalog: catalog, today: today, ownNames: ownNames,
                                                         names: false)
            guard observer.value == revision else { throw BatchChangeError.changed }
            guard from != to, let incoming = candidates.first(where: { $0.transaction.id == from }),
                  let expense = candidates.first(where: { $0.transaction.id == to }),
                  incoming.state.direction == .moneyIn, expense.state.direction == .moneyOut else { throw PaybackError.invalidPayment }
            let old = Paybacks.cents(previous) ?? 0
            guard requested <= Paybacks.cents(incoming.state.rest)! + old else { throw PaybackError.payerLimit }
            guard requested <= Paybacks.cents(expense.state.rest)! + old else { throw PaybackError.expenseLimit }
            let link = LedgerPayback(payment: to, amount: Paybacks.stored(requested))
            if let index = links.firstIndex(where: { $0.payment == to }) { links[index] = link }
            else { links.append(link) }
        } else {
            guard links.contains(where: { $0.payment == to }) else { throw PaybackError.missingLink }
            links.removeAll { $0.payment == to }
        }
        guard let payment = try modelContext.fetch(FetchDescriptor<StoredPayment>(predicate: #Predicate { $0.id == from })).first
        else { throw PaybackError.invalidPayment }
        do {
            payment.paysBack = links.isEmpty ? nil : links
            try modelContext.save()
        } catch { modelContext.rollback(); throw error }
        return BatchLedgerUndo(ledger: observer.id, revision: observer.value, before: before, after: try batchSnapshot())
    }

    /// Run inside category mutations, before their save. Incoming links are kept on their owners, so both ends are
    /// removed together and included in the operation's normal snapshot undo.
    func removeTransferPaybacks() throws {
        let payments = try modelContext.fetch(FetchDescriptor<StoredPayment>())
        let transfers = Set(payments.filter { $0.category.map(transferCategoryIDs.contains) ?? false }.map(\.id))
        guard !transfers.isEmpty else { return }
        for payment in payments where payment.paysBack != nil {
            let links = transfers.contains(payment.id) ? [] : (payment.paysBack ?? []).filter { !transfers.contains($0.payment) }
            if links != payment.paysBack { payment.paysBack = links.isEmpty ? nil : links }
        }
    }

    func unchooseWithUndo(_ id: String, moveTo target: String?, sorting: Bool,
                          engine: AresiumEngine, catalog: CategoryCatalog) async throws -> BatchLedgerUndo {
        let observer = batchObserver(), revision = observer.value
        let before = try batchSnapshot()
        let list = PhoneCategoryList(catalog: catalog, chosen: before.categories.filter { $0.id != id })
        let ibans = Dictionary(uniqueKeysWithValues: before.accounts.map { ($0.id, $0.iban) })
        let learned = Dictionary(uniqueKeysWithValues: before.learned.filter {
            !ChosenCategory.isCustom(id) || $0.category != id
        }.map { ($0.merchant, $0.category) })
        let results: [SortResult]?
        if sorting && !before.payments.isEmpty {
            results = try await engine.sortPayments(before.payments.map { $0.sorting(accountIban: ibans[$0.account] ?? nil) },
                categories: list.sortingIDs, learned: learned, localPlaces: true)
        } else { results = nil }
        guard observer.value == revision else { throw BatchChangeError.changed }
        try unchoose(id, moveTo: target)
        if let results { try applySort(ids: before.payments.map(\.id), results: results, fresh: []) }
        return BatchLedgerUndo(ledger: observer.id, revision: observer.value, before: before, after: try batchSnapshot())
    }
}

nonisolated struct PaybackLedgerResult: Sendable {
    let plan: PaybackPlan
    let undo: BatchLedgerUndo
}

extension PhoneLedger {
    func paybackGroup(ids: Set<String>, engine: AresiumEngine, catalog: CategoryCatalog,
                      today: String, ownNames: Bool) async throws -> PaybackGroup? {
        let observer = batchObserver(), revision = observer.value
        configurePaybacks(catalog: catalog)
        let dashboard = try await dashboard(engine: engine, catalog: catalog, language: .current,
                                            today: today, ownNames: ownNames)
        guard observer.value == revision else { throw BatchChangeError.changed }
        return Paybacks.group(ids: ids, dashboard: dashboard, payments: try payments(), transferIDs: transferCategoryIDs,
                              revision: PaybackRevision(ledger: observer.id, value: revision))
    }

    private func checkPaybackRevision(_ group: PaybackGroup) throws {
        let observer = batchObserver()
        guard let revision = group.revision, revision.ledger == observer.id, revision.value == observer.value
        else { throw BatchChangeError.changed }
    }

    /// Both preview and save resolve current candidates on the ledger executor. Never trust rests from the screen.
    func planPaybacks(group: PaybackGroup, others: Set<String>, engine: AresiumEngine, catalog: CategoryCatalog,
                      today: String, ownNames: Bool) async throws -> PaybackPlan {
        try checkPaybackRevision(group)
        let candidates = try await paybackCandidates(engine: engine, catalog: catalog, today: today,
                                                     ownNames: ownNames, names: false)
        try checkPaybackRevision(group)
        let selected = candidates.filter { group.ids.contains($0.transaction.id) && $0.state.rest > 0 }
        let picked = candidates.filter { others.contains($0.transaction.id) && $0.state.rest > 0 }
        guard selected.count == group.ids.count, picked.count == others.count,
              selected.allSatisfy({ $0.state.direction == group.direction }) else { throw PaybackError.invalidPayment }
        let current = PaybackGroup(direction: group.direction, payments: selected, skipped: group.skipped,
                                   totalRest: group.totalRest, revision: group.revision)
        return try PaybackPlan(group: current, others: picked)
    }

    /// One save and one snapshot undo for every new or raised pair. No suspension between the last revision check
    /// and save, so an import, category change or another link cannot interleave with applying this plan.
    func changePaybacks(group: PaybackGroup, others: Set<String>, engine: AresiumEngine, catalog: CategoryCatalog,
                        today: String, ownNames: Bool) async throws -> PaybackLedgerResult {
        let plan = try await planPaybacks(group: group, others: others, engine: engine, catalog: catalog,
                                          today: today, ownNames: ownNames)
        try checkPaybackRevision(group)
        guard plan.hasLinks else { throw PaybackError.invalidPayment }
        let observer = batchObserver(), before = try batchSnapshot()
        let stored = Dictionary(uniqueKeysWithValues: try modelContext.fetch(FetchDescriptor<StoredPayment>()).map { ($0.id, $0) })
        do {
            for link in plan.links {
                guard let payer = stored[link.from], let cents = Paybacks.cents(link.totalAmount)
                else { throw PaybackError.invalidPayment }
                var links = payer.paysBack ?? []
                let value = LedgerPayback(payment: link.to, amount: Paybacks.stored(cents))
                if let index = links.firstIndex(where: { $0.payment == link.to }) { links[index] = value }
                else { links.append(value) }
                payer.paysBack = links
            }
            try modelContext.save()
        } catch { modelContext.rollback(); throw error }
        return PaybackLedgerResult(plan: plan, undo: BatchLedgerUndo(ledger: observer.id, revision: observer.value,
                                                                    before: before, after: try batchSnapshot()))
    }
}
