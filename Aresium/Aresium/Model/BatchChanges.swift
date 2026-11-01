import Foundation

/// Batch APIs use dashboard row ids, including the engine's receipt/entry ids. A sum expands to its member ids.
nonisolated struct BatchCounts: Equatable, Sendable {
    var bankPayments = 0
    var receipts = 0
    var cashEntries = 0
    var total: Int { bankPayments + receipts + cashEntries }
}

struct PaymentSelectionSummary {
    let counts: BatchCounts
    /// One category month list has one side. Nil for an empty or mixed-side set.
    let side: DashboardSide?
    /// Magnitude, in euros; added in integer cents, as the list's sums are.
    let total: Double
    let currentCategory: String?
    let canSwitch: Bool
    let canRename: Bool
    var count: Int { counts.total }
    var bankPayments: Int { counts.bankPayments }
}

nonisolated enum BatchRenameScope: Sendable { case payments, shops }

nonisolated struct BatchRenameInfo: Equatable, Sendable {
    let bankPaymentCount: Int
    let otherPaymentCount: Int
    /// Distinct nonempty engine identities, not distinct merchant spellings.
    let shopCount: Int
    let skipped: BatchCounts
    var allPaymentCount: Int { bankPaymentCount + otherPaymentCount }
}

nonisolated enum BatchChangeError: LocalizedError, Equatable {
    case unavailable
    case changed
    case invalidSelection

    var errorDescription: String? {
        switch self {
        case .unavailable: String(localized: "This change is no longer available.")
        case .changed: String(localized: "The data changed. Select the payments again.")
        case .invalidSelection: String(localized: "Select payments from one month's list.")
        }
    }
}

nonisolated enum BatchUndoOutcome: Equatable, Sendable {
    case undone, unavailable

    var message: String {
        switch self {
        case .undone: String(localized: "Change undone.")
        case .unavailable: String(localized: "Cannot undo because the data changed.")
        }
    }
}

/// One shared handle: applying the shop question extends this undo to include both changes. Single use.
@MainActor
final class BatchUndo {
    fileprivate var token: BatchLedgerUndo?
    private let phone: PhoneBackend
    fileprivate var afterChange: (@MainActor () async -> Void)?

    fileprivate init(token: BatchLedgerUndo, phone: PhoneBackend) {
        self.token = token
        self.phone = phone
    }

    func perform() async throws -> BatchUndoOutcome {
        guard let token else { return .unavailable }
        self.token = nil
        guard try await phone.ledger.undoBatch(token) else { return .unavailable }
        try await phone.refresh()
        await afterChange?()
        return .undone
    }
}

/// One question for all selected shops, absent when none has eligible other payments. Applying it is single use.
@MainActor
final class BatchMerchantFollowUp {
    let count: Int
    let shopCount: Int
    let shop: String?
    let category: String
    private let plan: BatchFollowUpPlan
    private let phone: PhoneBackend
    private let undo: BatchUndo
    private var applied = false

    fileprivate init(plan: BatchFollowUpPlan, phone: PhoneBackend, undo: BatchUndo) {
        self.plan = plan
        self.phone = phone
        self.undo = undo
        count = plan.ids.count
        shopCount = plan.shopCount
        shop = plan.shop
        category = plan.categoryName
    }

    var added: [String] { plan.addedNames }
    var removed: [String] { plan.removedNames }
    var wording: CategoryQuestionWording {
        CategoryQuestionWording(count: count, selectedCount: plan.selectedCount, shopCount: shopCount, shop: shop,
                                category: category, added: added, removed: removed, selection: true)
    }
    var question: String { wording.question() }

    func apply() async throws -> BatchChangeResult {
        guard !applied, let token = undo.token else { throw BatchChangeError.unavailable }
        applied = true
        let saved = try await phone.ledger.applyBatchFollowUp(plan, undo: token)
        undo.token = saved.undo
        try await phone.refresh()
        await undo.afterChange?()
        return BatchChangeResult(action: plan.changesExtras ? .addCategory : .switchCategory, category: category, changed: saved.changed,
                                 skipped: saved.skipped, undo: undo, followUp: nil)
    }
}

nonisolated enum BatchChangeKind: Sendable { case switchCategory, addCategory, rename }

@MainActor
struct BatchChangeResult {
    let action: BatchChangeKind
    let category: String?
    let changed: BatchCounts
    /// Includes receipts/entries on Add and Rename, and bank rows already carrying the added category.
    let skipped: BatchCounts
    let undo: BatchUndo
    let followUp: BatchMerchantFollowUp?
    var message: String { BatchWording.result(action, count: changed.total, category: category, skipped: skipped) }
}

nonisolated enum BatchWording {
    static func result(_ action: BatchChangeKind, count: Int, category: String?, skipped: BatchCounts,
                       language: AppLanguage = .current) -> String {
        let line: String
        switch action {
        case .switchCategory: line = language.string("\(count) payments moved to \(category ?? "")")
        case .addCategory: line = language.string("\(category ?? "") added to \(count) payments")
        case .rename: line = language.string("Name changed for \(count) payments")
        }
        guard skipped.total > 0 else { return line }
        return line + " · " + language.string("\(skipped.total) skipped")
    }

    static func question(count: Int, shops: Int, shop: String?, language: AppLanguage = .current) -> String {
        if let shop, shops == 1 { return language.string("Also move \(count) other payments from \(shop)?") }
        return language.string("Also move \(count) other payments from \(shops) shops?")
    }
}

/// The selection window prepares once on Save, presents `question` when present, then saves its answer.
/// No payment is changed until the answer. The resulting follow-up and undo are the normal batch handles.
@MainActor
struct BatchAddRequest {
    let question: RemoveCurrentQuestion?
    private let saveAnswer: (Bool) async throws -> BatchChangeResult

    init(question: RemoveCurrentQuestion?, save: @escaping (Bool) async throws -> BatchChangeResult) {
        self.question = question
        saveAnswer = save
    }

    func save(removeCurrent: Bool = false) async throws -> BatchChangeResult { try await saveAnswer(removeCurrent) }
}

extension DashboardStore {
    /// Only category month lists call this; day, name, search and Cash pages do not offer selection.
    func offersSelection(in list: PaymentList) -> Bool { !selectableRows(in: list).isEmpty }

    func offersSelection(category: String, month: String, side: DashboardSide) -> Bool {
        offersSelection(in: paymentList(category: category, month: month, side: side))
    }

    func selectableRows(in list: PaymentList) -> [TransactionRow] {
        guard phone != nil else { return [] }
        return list.rows.filter { $0.transaction.coveredBy == nil }
    }

    func selectionIDs(for entry: PaymentListEntry) -> Set<String> {
        guard phone != nil else { return [] }
        switch entry {
        case let .payment(row, _): return row.transaction.coveredBy == nil ? [row.id] : []
        case let .summed(sum): return Set(sum.rows.filter { $0.transaction.coveredBy == nil }.map(\.id))
        }
    }

    /// Live rows only: stale/deleted ids and covered rows contribute nothing to the summary.
    func selectionRows(_ ids: Set<String>) -> [Transaction] {
        guard phone != nil else { return [] }
        return (dashboard?.transactions ?? []).filter { ids.contains($0.id) && $0.coveredBy == nil }
    }

    func selectionSummary(_ ids: Set<String>) -> PaymentSelectionSummary {
        let rows = selectionRows(ids)
        var counts = BatchCounts()
        let entryIDs = Set((dashboard?.cash?.movements ?? []).filter { $0.kind == .manual || $0.kind == .received }.map(\.id))
        for row in rows {
            if row.receiptId == nil { counts.bankPayments += 1 }
            else if let id = row.receiptId, entryIDs.contains(id) { counts.cashEntries += 1 }
            else { counts.receipts += 1 }
        }
        let sides = Set(rows.map { $0.amount > 0 ? DashboardSide.income : .expenses })
        let categories = Set(rows.map(\.categoryName))
        let cents = rows.reduce(0) { $0 + Int((abs($1.amount) * 100).rounded()) }
        return PaymentSelectionSummary(counts: counts, side: sides.count == 1 ? sides.first : nil,
                                       total: Double(cents) / 100,
                                       currentCategory: categories.count == 1 ? categories.first : nil,
                                       canSwitch: !rows.isEmpty && sides.count == 1,
                                       canRename: counts.bankPayments > 0 && ownNames && sides.count == 1)
    }

    /// The same membership as the single payment's change window; a common primary category is left out.
    func offeredCategories(for ids: Set<String>, mode: RecategorisationMode = .switchCategory) -> [Category] {
        guard let phone, let catalog = phone.catalog else { return [] }
        let summary = selectionSummary(ids)
        guard let side = summary.side else { return [] }
        let list = PhoneCategoryList(catalog: catalog, chosen: phone.summary.chosen)
        let offered = Set(list.offered(for: side == .income ? .in : .out).compactMap { list.name(of: $0) })
        return (dashboard?.recategorisationChoices(amount: side == .income ? 1 : -1) ?? []).filter {
            offered.contains($0.name) && $0.name != summary.currentCategory
                && (mode != .add || list.id(named: $0.name) != CategoryCatalog.ownTransfers)
        }
    }

    func switchCategory(ids: Set<String>, to category: String) async throws -> BatchChangeResult {
        guard let phone else { throw BatchChangeError.unavailable }
        try validateSelection(ids)
        return await publishBatch(try await phone.switchCategory(ids: ids, to: category))
    }

    func addCategory(ids: Set<String>, name: String, removingCurrent: String? = nil) async throws -> BatchChangeResult {
        try await addCategories(ids: ids, names: [name], removingCurrent: removingCurrent)
    }

    func addCategories(ids: Set<String>, names: [String], removing: [String] = [],
                       removingCurrent: String? = nil) async throws -> BatchChangeResult {
        guard let phone else { throw BatchChangeError.unavailable }
        try validateSelection(ids)
        return await publishBatch(try await phone.addCategories(ids: ids, names: names, removing: removing,
                                                                removingCurrent: removingCurrent))
    }

    func prepareAddCategories(ids: Set<String>, names: [String], currentCategory: String,
                              removing: [String] = []) throws -> BatchAddRequest {
        guard phone != nil else { throw BatchChangeError.unavailable }
        try validateSelection(ids)
        let rows = selectionRows(ids)
        let adds = names.filter { name in rows.contains { $0.categoryName != name && !$0.tags.contains(name) } }
        let question: RemoveCurrentQuestion? = currentCategory != CategoryName.uncategorised
            && !names.contains(currentCategory) && !adds.isEmpty && rows.contains { $0.categoryName == currentCategory }
            ? RemoveCurrentQuestion(category: currentCategory, categories: names, selection: true) : nil
        return BatchAddRequest(question: question) { [weak self] remove in
            guard let self else { throw BatchChangeError.unavailable }
            return try await self.addCategories(ids: ids, names: names, removing: removing,
                                               removingCurrent: remove && question != nil ? currentCategory : nil)
        }
    }

    func renameInfo(ids: Set<String>) async throws -> BatchRenameInfo {
        guard let phone else { throw BatchChangeError.unavailable }
        try validateSelection(ids)
        return try await phone.renameInfo(ids: ids)
    }

    func rename(ids: Set<String>, to name: String, scope: BatchRenameScope) async throws -> BatchChangeResult {
        guard let phone else { throw BatchChangeError.unavailable }
        try validateSelection(ids)
        return await publishBatch(try await phone.rename(ids: ids, to: name, scope: scope))
    }

    private func validateSelection(_ ids: Set<String>) throws {
        let rows = selectionRows(ids)
        guard !ids.isEmpty, rows.count == ids.count, Set(rows.map(\.month)).count == 1,
              selectionSummary(ids).side != nil else { throw BatchChangeError.invalidSelection }
    }

    private func publishBatch(_ result: BatchChangeResult) async -> BatchChangeResult {
        result.undo.afterChange = { [weak self] in await self?.reloadAfterTransactionChange() }
        await reloadAfterTransactionChange()
        return result
    }
}

extension PhoneBackend {
    func switchCategory(ids: Set<String>, to category: String) async throws -> BatchChangeResult {
        try await batch(ids: ids, action: .switchCategory(category))
    }

    func addCategory(ids: Set<String>, name: String, removingCurrent: String? = nil) async throws -> BatchChangeResult {
        try await addCategories(ids: ids, names: [name], removingCurrent: removingCurrent)
    }

    func addCategories(ids: Set<String>, names: [String], removing: [String] = [],
                       removingCurrent: String? = nil) async throws -> BatchChangeResult {
        try await batch(ids: ids, action: .editCategories(added: names, removed: removing, dropCurrent: removingCurrent))
    }

    func renameInfo(ids: Set<String>) async throws -> BatchRenameInfo {
        try await ledger.batchRenameInfo(ids: ids, engine: engine)
    }

    func rename(ids: Set<String>, to name: String, scope: BatchRenameScope) async throws -> BatchChangeResult {
        try await batch(ids: ids, action: .rename(name, scope))
    }

    private func batch(ids: Set<String>, action: BatchLedgerAction) async throws -> BatchChangeResult {
        // `load` normally fills this; querying the engine here also supports the tour's in-memory ledger.
        let catalog = try await engine.catalog()
        let saved = try await ledger.changeBatch(ids: ids, action: action, engine: engine, catalog: catalog)
        try await refresh()
        let undo = BatchUndo(token: saved.undo, phone: self)
        let followUp = saved.followUp.map { BatchMerchantFollowUp(plan: $0, phone: self, undo: undo) }
        return BatchChangeResult(action: action.kind, category: action.category, changed: saved.changed,
                                 skipped: saved.skipped, undo: undo, followUp: followUp)
    }
}
