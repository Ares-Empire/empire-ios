import Foundation
import SwiftData
import os

/// Observes every save on this ledger context, including existing single-row changes and imports. No model schema
/// or export change is needed. The lock also makes the notification callback safe under strict concurrency.
nonisolated final class BatchSaveObserver: @unchecked Sendable {
    let id = UUID()
    private let revision = OSAllocatedUnfairLock<UInt64>(initialState: 0)
    // Set only in init and removed in deinit; callbacks touch only the locked revision.
    private var observation: NSObjectProtocol?

    init(context: ModelContext) {
        let identity = ObjectIdentifier(context)
        let token = NotificationCenter.default.addObserver(forName: ModelContext.didSave, object: nil, queue: nil) { [weak self] note in
            guard let object = note.object as? ModelContext, ObjectIdentifier(object) == identity else { return }
            self?.revision.withLock { $0 &+= 1 }
        }
        observation = token
    }

    deinit {
        if let observation { NotificationCenter.default.removeObserver(observation) }
    }

    var value: UInt64 { revision.withLock { $0 } }
}

nonisolated enum BatchLedgerAction: Sendable {
    case switchCategory(String), addCategory(String), rename(String, BatchRenameScope)
    case editCategories(added: [String], removed: [String], dropCurrent: String?)
    var kind: BatchChangeKind {
        switch self {
        case .switchCategory: .switchCategory
        case .addCategory, .editCategories: .addCategory
        case .rename: .rename
        }
    }
    var category: String? {
        switch self {
        case let .switchCategory(name), let .addCategory(name): name
        case let .editCategories(added, _, _): added.first
        case .rename: nil
        }
    }
}

/// Private value token never leaves memory. Snapshot equality supplements the ledger context's save revision.
/// Undo restores category/source/extras, own names, links and rules that this action changed.
nonisolated struct BatchLedgerUndo: Sendable {
    let ledger: UUID
    let revision: UInt64
    let before: LedgerExport
    let after: LedgerExport
}

nonisolated struct BatchFollowUpPlan: Sendable {
    let ids: Set<String>
    let keys: [String]
    let target: String
    let categoryName: String
    let shopCount: Int
    let shop: String?
    var added: [String] = []
    var removed: [String] = []
    var addedNames: [String] = []
    var removedNames: [String] = []
    var selectedCount = 1
    var changesExtras: Bool { !added.isEmpty || !removed.isEmpty }
}

nonisolated struct BatchLedgerResult: Sendable {
    let changed: BatchCounts
    let skipped: BatchCounts
    let undo: BatchLedgerUndo
    var followUp: BatchFollowUpPlan? = nil
}

extension PhoneLedger {
    func batchObserver() -> BatchSaveObserver {
        if let batchSaveObserver { return batchSaveObserver }
        let observer = BatchSaveObserver(context: modelContext)
        batchSaveObserver = observer
        return observer
    }

    func batchSnapshot() throws -> LedgerExport { try export(on: Date(timeIntervalSince1970: 0)) }

    /// One actor operation for all rows. Awaited engine work precedes every mutation; a save revision check catches
    /// reentrant changes during those awaits. All fetching, planning, applying and snapshot lifetimes stay off main.
    func changeBatch(ids: Set<String>, action: BatchLedgerAction, engine: AresiumEngine, catalog: CategoryCatalog,
                     language: AppLanguage = .current, span: BatchSpan = .oneMonth) async throws -> BatchLedgerResult {
        assert(!Thread.isMainThread)
        let timing = PickerTiming.begin("batch.change")
        defer { timing.end() }
        configurePaybacks(catalog: catalog)
        let observer = batchObserver(), revision = observer.value
        let before = try batchSnapshot()
        let selected = try batchSelected(ids, from: before, span: span)
        let list = PhoneCategoryList(catalog: catalog, chosen: before.categories, language: language)
        let target: String?
        if let name = action.category {
            guard let id = list.id(named: name) else { throw LedgerError.notFound }
            target = id
        } else { target = nil }

        // Add may switch just the rows in the list's current category, plus any unsorted rows.
        let edit: (added: [String], removed: [String], drop: String?)?
        switch action {
        case let .addCategory(name): edit = ([name], [], nil)
        case let .editCategories(added, removed, drop): edit = (added, removed, drop)
        default: edit = nil
        }
        func categoryIDs(_ names: [String]) throws -> [String] {
            try names.map {
                guard let id = list.id(named: $0), id != CategoryCatalog.ownTransfers else { throw LedgerError.notFound }
                return id
            }
        }
        let added = try categoryIDs(edit?.added ?? []), removed = try categoryIDs(edit?.removed ?? [])
        let drop: String?
        if let name = edit?.drop {
            guard let id = list.id(named: name) else { throw LedgerError.notFound }
            drop = id
        } else { drop = nil }
        let switchingPayments: [LedgerPayment]
        let switchingReceipts: [LedgerReceipt]
        if case .switchCategory = action {
            switchingPayments = selected.payments
            switchingReceipts = selected.receipts
        } else if edit != nil, let target {
            switchingPayments = selected.payments.filter {
                $0.category != target && ($0.category == nil || (drop != nil && $0.category == drop))
            }
            switchingReceipts = selected.receipts.filter {
                $0.category != target && ($0.category == nil || (drop != nil && $0.category == drop))
            }
        } else { switchingPayments = []; switchingReceipts = [] }
        let switching = Set(switchingPayments.map(\.id) + switchingReceipts.map(\.id))
        var learned: [String: String] = [:]
        var snapshot: ShopSnapshot?
        if !switching.isEmpty {
            var corrections = switchingPayments.map { $0.sorting(raw: false) }
            corrections += switchingReceipts.filter { $0.kind == .receipt && $0.category != target }.compactMap { receipt in
                guard let shop = receipt.shop, !shop.isEmpty else { return nil }
                return SortingPayment(counterparty: shop, description: shop, source: "bank", account: "receipt",
                                      amount: -receipt.totalValue, currency: receipt.currency, date: receipt.date)
            }
            learned = try await engine.learn(corrections, categoryID: target!)
            snapshot = try await shopSnapshot(engine: engine)
        } else {
            switch action {
            case .rename(_, .shops), .addCategory, .editCategories: snapshot = try await shopSnapshot(engine: engine)
            default: break
            }
        }
        // Do not apply an answer computed from rows changed while the engine was working.
        guard observer.value == revision else { throw BatchChangeError.changed }
        let payments = try modelContext.fetch(FetchDescriptor<StoredPayment>())
        let receipts = try modelContext.fetch(FetchDescriptor<StoredReceipt>())
        let byID = Dictionary(uniqueKeysWithValues: payments.map { ($0.id, $0) })
        var changed = BatchCounts(), skipped = BatchCounts()
        var followUp: BatchFollowUpPlan?
        do {
            // Both Switch and Add/Remove use this same mutation, learning and shop-follow-up path.
            for payment in payments where switching.contains(payment.id) {
                payment.category = target
                payment.categorySource = CategorySource.manual.rawValue
                payment.extraCategories.removeAll { $0 == target }
                changed.bankPayments += 1
            }
            for receipt in receipts where switching.contains(receipt.id) {
                receipt.category = target
                receipt.categorySource = CategorySource.manual.rawValue
                if receipt.kind == ReceiptKind.manual.rawValue { changed.cashEntries += 1 }
                else { changed.receipts += 1 }
                if let paymentID = receipt.paymentID, let payment = byID[paymentID],
                   payment.categorySource == CategorySource.receipt.rawValue {
                    payment.category = target
                    payment.extraCategories.removeAll { $0 == target }
                }
            }
            try batchRemember(learned)
            if !switching.isEmpty, let snapshot, let target {
                followUp = batchFollowUp(snapshot, learnedKeys: Set(learned.keys), excluding: ids,
                                         target: target, name: action.category ?? "")
            }
            switch action {
            case .switchCategory: break
            case .addCategory, .editCategories:
                for receipt in selected.receipts where !switching.contains(receipt.id) {
                    if receipt.kind == .manual { skipped.cashEntries += 1 } else { skipped.receipts += 1 }
                }
                for payment in payments where ids.contains(payment.id) {
                    let old = payment.extraCategories
                    payment.extraCategories.removeAll { removed.contains($0) || $0 == payment.category }
                    for category in added where category != payment.category && !payment.extraCategories.contains(category) {
                        payment.extraCategories.append(category)
                    }
                    if !switching.contains(payment.id) {
                        if payment.extraCategories == old { skipped.bankPayments += 1 }
                        else { changed.bankPayments += 1 }
                    }
                }
                if switching.isEmpty, let snapshot, let edit {
                    let adding = zip(added, edit.added).filter { category, _ in
                        selected.payments.contains { $0.category != category && !$0.extraCategories.contains(category) }
                    }
                    let removing = zip(removed, edit.removed).filter { category, _ in
                        selected.payments.contains { $0.extraCategories.contains(category) }
                    }
                    followUp = extrasFollowUp(snapshot, selected: ids, added: adding.map(\.0), removed: removing.map(\.0),
                                              addedNames: adding.map(\.1), removedNames: removing.map(\.1))
                }
            case let .rename(name, scope):
                skipped = BatchCounts(receipts: selected.receipts.filter { $0.kind == .receipt }.count,
                                      cashEntries: selected.receipts.filter { $0.kind == .manual }.count)
                let normalized = PaymentNames.normalized(name)
                let own = normalized.isEmpty ? nil : normalized
                var merchants: [String: String] = [:] // identity -> one selected exact key, deterministic ledger order
                if let snapshot {
                    for (payment, key) in zip(snapshot.payments, snapshot.paymentKeys)
                        where ids.contains(payment.id) && !key.isEmpty {
                        merchants[snapshot.shops.identity(key)] = key
                    }
                    let rules = try modelContext.fetch(FetchDescriptor<StoredPaymentName>())
                    for rule in rules where merchants[snapshot.shops.identity(rule.merchant)] != nil {
                        modelContext.delete(rule)
                    }
                    if let own {
                        for key in merchants.values { modelContext.insert(StoredPaymentName(merchant: key, name: own)) }
                    }
                }
                let keys = snapshot.map { Dictionary(uniqueKeysWithValues: zip($0.payments.map(\.id), $0.paymentKeys)) } ?? [:]
                for payment in payments where ids.contains(payment.id) {
                    // Shop scope clears the selected override; keyless payments still get their own name.
                    payment.ownName = scope == .shops && !(keys[payment.id] ?? "").isEmpty ? nil : own
                    changed.bankPayments += 1
                }
            }
            try removeTransferPaybacks()
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
        let after = try batchSnapshot()
        return BatchLedgerResult(changed: changed, skipped: skipped,
                                 undo: BatchLedgerUndo(ledger: observer.id, revision: observer.value, before: before, after: after),
                                 followUp: followUp)
    }

    /// One direction always; one month unless `span` allows every month (brief 99's group of one name).
    private func batchSelected(_ ids: Set<String>, from snapshot: LedgerExport, span: BatchSpan = .oneMonth) throws
        -> (payments: [LedgerPayment], receipts: [LedgerReceipt]) {
        let payments = snapshot.payments.filter { ids.contains($0.id) }
        let receipts = snapshot.receipts.filter { ids.contains($0.id) }
        guard !ids.isEmpty, payments.count + receipts.count == ids.count else { throw BatchChangeError.invalidSelection }
        let directions = Set(payments.map { $0.amountValue > 0 ? "in" : "out" }
            + receipts.map { $0.direction.rawValue })
        let months = Set(payments.map { String($0.bookingDate.prefix(7)) } + receipts.map { String($0.date.prefix(7)) })
        guard directions.count == 1, span == .allMonths || months.count == 1 else { throw BatchChangeError.invalidSelection }
        return (payments, receipts)
    }

    private func batchRemember(_ learned: [String: String]) throws {
        let rules = Dictionary(uniqueKeysWithValues: try modelContext.fetch(FetchDescriptor<StoredRule>()).map { ($0.merchant, $0) })
        for (key, category) in learned where !key.isEmpty {
            if let rule = rules[key] { rule.category = category }
            else { modelContext.insert(StoredRule(merchant: key, category: category)) }
        }
    }

    private func batchFollowUp(_ snapshot: ShopSnapshot, learnedKeys: Set<String>, excluding selected: Set<String>,
                               target: String, name: String) -> BatchFollowUpPlan? {
        let identities = Set(learnedKeys.map(snapshot.shops.identity).filter { !$0.isEmpty })
        var ids = Set<String>(), shops = Set<String>(), titles: [String: String] = [:]
        for (payment, key) in zip(snapshot.payments, snapshot.paymentKeys) {
            let identity = snapshot.shops.identity(key)
            guard !key.isEmpty, identities.contains(identity) else { continue }
            titles[identity] = payment.place
            guard !selected.contains(payment.id), !CategorySource.keeps(payment.categorySource.rawValue),
                  payment.categorySource != .structural, payment.category != CategoryCatalog.ownTransfers,
                  payment.category != target else { continue }
            ids.insert(payment.id)
            shops.insert(identity)
        }
        guard !ids.isEmpty else { return nil }
        let keys = snapshot.shops.byKey.keys.filter { !$0.isEmpty && shops.contains(snapshot.shops.identity($0)) }.sorted()
        return BatchFollowUpPlan(ids: ids, keys: keys, target: target, categoryName: name, shopCount: shops.count,
                                 shop: shops.count == 1 ? shops.first.flatMap { titles[$0] } : nil)
    }

    /// Extras may change manual and receipt-set bank rows too; they never change the primary or learn rules.
    private func extrasFollowUp(_ snapshot: ShopSnapshot, selected: Set<String>, added: [String], removed: [String],
                                addedNames: [String], removedNames: [String]) -> BatchFollowUpPlan? {
        let identities = Set(zip(snapshot.payments, snapshot.paymentKeys).compactMap { payment, key in
            selected.contains(payment.id) && !key.isEmpty ? snapshot.shops.identity(key) : nil
        }.filter { !$0.isEmpty })
        var ids = Set<String>(), shops = Set<String>(), titles: [String: String] = [:]
        for (payment, key) in zip(snapshot.payments, snapshot.paymentKeys) {
            let identity = snapshot.shops.identity(key)
            guard !key.isEmpty, identities.contains(identity) else { continue }
            titles[identity] = payment.place
            guard !selected.contains(payment.id), payment.category != CategoryCatalog.ownTransfers,
                  payment.categorySource != .structural else { continue }
            if added.contains(where: { $0 != payment.category && !payment.extraCategories.contains($0) })
                || removed.contains(where: { payment.extraCategories.contains($0) }) {
                ids.insert(payment.id)
                shops.insert(identity)
            }
        }
        guard !ids.isEmpty else { return nil }
        return BatchFollowUpPlan(ids: ids, keys: [], target: "", categoryName: addedNames.first ?? removedNames.first ?? "",
                                 shopCount: shops.count, shop: shops.count == 1 ? shops.first.flatMap { titles[$0] } : nil,
                                 added: added, removed: removed, addedNames: addedNames, removedNames: removedNames,
                                 selectedCount: snapshot.payments.filter { selected.contains($0.id) }.count)
    }

    func batchRenameInfo(ids: Set<String>, engine: AresiumEngine) async throws -> BatchRenameInfo {
        let observer = batchObserver(), revision = observer.value
        let before = try batchSnapshot()
        let selected = try batchSelected(ids, from: before)
        let snapshot = try await shopSnapshot(engine: engine)
        guard observer.value == revision else { throw BatchChangeError.changed }
        let identities = Set(zip(snapshot.payments, snapshot.paymentKeys).compactMap { payment, key in
            ids.contains(payment.id) && !key.isEmpty ? snapshot.shops.identity(key) : nil
        }.filter { !$0.isEmpty })
        let other = zip(snapshot.payments, snapshot.paymentKeys).filter { payment, key in
            !ids.contains(payment.id) && !key.isEmpty && identities.contains(snapshot.shops.identity(key))
        }.count
        return BatchRenameInfo(bankPaymentCount: selected.payments.count, otherPaymentCount: other, shopCount: identities.count,
                               skipped: BatchCounts(receipts: selected.receipts.filter { $0.kind == .receipt }.count,
                                                    cashEntries: selected.receipts.filter { $0.kind == .manual }.count))
    }

    private func canUndoBatch(_ token: BatchLedgerUndo) throws -> Bool {
        let observer = batchObserver()
        guard token.ledger == observer.id, token.revision == observer.value else { return false }
        return try batchSnapshot() == token.after
    }

    func applyBatchFollowUp(_ plan: BatchFollowUpPlan, undo token: BatchLedgerUndo) throws -> BatchLedgerResult {
        assert(!Thread.isMainThread)
        guard try canUndoBatch(token) else { throw BatchChangeError.changed }
        do {
            for payment in try modelContext.fetch(FetchDescriptor<StoredPayment>()) where plan.ids.contains(payment.id) {
                if plan.changesExtras {
                    payment.extraCategories.removeAll { plan.removed.contains($0) }
                    for category in plan.added where category != payment.category && !payment.extraCategories.contains(category) {
                        payment.extraCategories.append(category)
                    }
                } else {
                    payment.category = plan.target
                    payment.categorySource = CategorySource.learned.rawValue
                    payment.extraCategories.removeAll { $0 == plan.target }
                }
            }
            if !plan.changesExtras {
                try batchRemember(Dictionary(uniqueKeysWithValues: plan.keys.map { ($0, plan.target) }))
            }
            try removeTransferPaybacks()
            try modelContext.save()
        } catch { modelContext.rollback(); throw error }
        let observer = batchObserver()
        return BatchLedgerResult(changed: BatchCounts(bankPayments: plan.ids.count), skipped: BatchCounts(),
                                 undo: BatchLedgerUndo(ledger: observer.id, revision: observer.value,
                                                       before: token.before, after: try batchSnapshot()))
    }

    /// Validate the entire token before touching any row or rule. Refusal performs no writes, including no partial
    /// restoration of a selection whose other payments still match. A change-and-change-back also invalidates it.
    func undoBatch(_ token: BatchLedgerUndo) throws -> Bool {
        assert(!Thread.isMainThread)
        guard try canUndoBatch(token) else { return false }
        let before = token.before, after = token.after
        let oldPayments = Dictionary(uniqueKeysWithValues: before.payments.map { ($0.id, $0) })
        let newPayments = Dictionary(uniqueKeysWithValues: after.payments.map { ($0.id, $0) })
        let oldReceipts = Dictionary(uniqueKeysWithValues: before.receipts.map { ($0.id, $0) })
        let newReceipts = Dictionary(uniqueKeysWithValues: after.receipts.map { ($0.id, $0) })
        do {
            for payment in try modelContext.fetch(FetchDescriptor<StoredPayment>()) {
                guard let old = oldPayments[payment.id], let new = newPayments[payment.id], old != new else { continue }
                payment.category = old.category
                payment.categorySource = old.categorySource.rawValue
                payment.extraCategories = old.extraCategories
                payment.ownName = old.ownName
                payment.paysBack = old.paysBack
            }
            for receipt in try modelContext.fetch(FetchDescriptor<StoredReceipt>()) {
                guard let old = oldReceipts[receipt.id], old != newReceipts[receipt.id] else { continue }
                receipt.category = old.category
                receipt.categorySource = old.categorySource.rawValue
            }
            // Category removal's undo restores its list entry as well as its payments and learned rules.
            let currentCategories = Set(try chosen().map(\.id))
            for category in before.categories where !currentCategories.contains(category.id) {
                modelContext.insert(StoredChosen(id: category.id, customName: category.name, order: category.order,
                                                 look: category.look, side: category.side, otherSide: category.otherSide))
            }
            let oldRules = Dictionary(uniqueKeysWithValues: before.learned.map { ($0.merchant, $0.category) })
            let newRules = Dictionary(uniqueKeysWithValues: after.learned.map { ($0.merchant, $0.category) })
            let changedKeys = Set(oldRules.keys).union(newRules.keys).filter { oldRules[$0] != newRules[$0] }
            let storedRules = try modelContext.fetch(FetchDescriptor<StoredRule>())
            for rule in storedRules where changedKeys.contains(rule.merchant) { modelContext.delete(rule) }
            for key in changedKeys {
                if let category = oldRules[key] { modelContext.insert(StoredRule(merchant: key, category: category)) }
            }
            let oldNames = Dictionary(uniqueKeysWithValues: before.nameRules.map { ($0.merchant, $0.name) })
            let newNames = Dictionary(uniqueKeysWithValues: after.nameRules.map { ($0.merchant, $0.name) })
            let changedNames = Set(oldNames.keys).union(newNames.keys).filter { oldNames[$0] != newNames[$0] }
            for rule in try modelContext.fetch(FetchDescriptor<StoredPaymentName>()) where changedNames.contains(rule.merchant) {
                modelContext.delete(rule)
            }
            for key in changedNames {
                if let name = oldNames[key] { modelContext.insert(StoredPaymentName(merchant: key, name: name)) }
            }
            if before.fixedCostMarks != after.fixedCostMarks {
                for mark in try modelContext.fetch(FetchDescriptor<StoredFixedCostExclusion>()) { modelContext.delete(mark) }
                for mark in before.fixedCostMarks { modelContext.insert(StoredFixedCostExclusion(mark)) }
            }
            try modelContext.save()
        } catch { modelContext.rollback(); throw error }
        return true
    }
}
