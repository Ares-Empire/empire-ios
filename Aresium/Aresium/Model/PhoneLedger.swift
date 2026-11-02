import Foundation
import SwiftData

/// Who set a payment's category.
nonisolated enum CategorySource: String, Codable, Sendable, CaseIterable {
    /// The engine's structural rules: own transfers (PayPal's bank lines, pairs between two accounts).
    case structural
    /// A merchant the person sorted before (a Switch, `learn`).
    case learned
    /// The shop rules shipped with the engine.
    case starter
    /// The person, by hand (Switch, Add, or answering where an unticked category's payments go).
    case manual
    /// The receipt joined to it (brief 31): a payment not sorted takes its receipt's category.
    case receipt
    /// Nothing yet: not sorted.
    case none

    /// A category the person gave (by hand, or through the receipt they checked): sorting and the "also the others"
    /// answer never change it.
    static func keeps(_ source: String) -> Bool { source == manual.rawValue || source == receipt.rawValue }
}

nonisolated struct LedgerAccount: Codable, Equatable, Sendable {
    let id: String
    var name: String
    var iban: String?
    var bank: String?
    var currency: String?
}

/// A stored payment as a value (also its shape in an export, schema version 1).
nonisolated struct LedgerPayment: Codable, Equatable, Sendable {
    let id: String
    let account: String
    let source: String
    let externalId: String
    let bookingDate: String
    var valueDate: String?
    let amount: String
    let currency: String
    let text: String
    var counterparty: String?
    var counterpartyIban: String?
    var balance: String?
    var raw: JSONValue?
    var category: String?
    var categorySource: CategorySource
    var extraCategories: [String]
    var sequence: Int
    /// Schema 4 export: this payment alone, before any shop rule. Never used for sorting.
    var ownName: String? = nil
    /// Schema 7: links carried by money in, with decimal euros as stored money.
    var paysBack: [LedgerPayback]? = nil

    /// What makes a payment unique: the same booking imported again (from the same export or an overlapping one) has
    /// the same key.
    static func key(account: String, source: String, externalId: String) -> String {
        [account, source, externalId].joined(separator: "\u{1F}")
    }

    var key: String { Self.key(account: account, source: source, externalId: externalId) }
    var amountValue: Double { Double(amount) ?? 0 }
    /// Where it was spent or who paid: the counterparty, else the text (as the dashboard's `place`).
    var place: String { counterparty.flatMap { $0.isEmpty ? nil : $0 } ?? text }

    /// The payment as the sorting rules see it. `accountIban`: its account's IBAN; `raw`: false for the merchant key
    /// alone, which reads only the texts.
    func sorting(accountIban: String? = nil, raw: Bool = true) -> SortingPayment {
        SortingPayment(counterparty: counterparty, description: text, source: source, account: account,
                       accountIban: accountIban, counterpartyIban: counterpartyIban, amount: amountValue,
                       currency: currency, date: bookingDate, raw: raw ? self.raw : nil, externalId: externalId)
    }
}

/// A category on the person's list: a default one (by id), or their own (`custom-…`, with its name and look).
nonisolated struct ChosenCategory: Codable, Equatable, Sendable {
    let id: String
    /// The personal name: required for own categories, optional override for defaults.
    var name: String?
    var order: Int
    /// Only for one's own categories: the icon and colour chosen when it was made (`OwnCategoryLook`, brief 36), kept so
    /// it never changes. An export carries it; one without it (made before) gets a look when restored.
    var look: CategoryLook? = nil

    /// Own categories only: "spend" or "income". Defaults use the catalog.
    var side: String? = nil
    /// Also offered for the opposite payment direction; totals still follow the home side.
    var otherSide: Bool = false

    private enum CodingKeys: String, CodingKey { case id, name, order, look, side, otherSide }

    init(id: String, name: String? = nil, order: Int, look: CategoryLook? = nil,
         side: String? = nil, otherSide: Bool = false) {
        self.id = id
        self.name = name
        self.order = order
        self.look = look
        self.side = side
        self.otherSide = otherSide
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        name = try values.decodeIfPresent(String.self, forKey: .name)
        order = try values.decode(Int.self, forKey: .order)
        look = try values.decodeIfPresent(CategoryLook.self, forKey: .look)
        side = try values.decodeIfPresent(String.self, forKey: .side)
        otherSide = try values.decodeIfPresent(Bool.self, forKey: .otherSide) ?? false
    }

    static func isCustom(_ id: String) -> Bool { id.hasPrefix("custom-") }
}

nonisolated struct LearnedRule: Codable, Equatable, Sendable {
    let merchant: String
    let category: String
}

/// What the phone store holds, in numbers, for the screens (the first screen, Settings).
nonisolated struct LedgerSummary: Equatable, Sendable {
    var payments = 0
    var unsorted = 0
    var accounts = 0
    var learned = 0
    var layouts = 0
    var receipts = 0
    var nameRules = 0
    var chosen: [ChosenCategory] = []

    /// Nothing imported, kept or learned yet (chosen categories may exist): an export can be restored into it.
    var isEmpty: Bool { payments == 0 && accounts == 0 && learned == 0 && layouts == 0 && receipts == 0 && nameRules == 0 }
}

/// The payments added from one file.
nonisolated struct AddedPayments: Equatable, Sendable {
    var newIDs: [String] = []
    /// Already in the store (the same booking from an earlier import, or twice in this one).
    var already = 0
    var accountName: String
}

/// All payments in the order the sorting rules get them, with what else sorting needs.
nonisolated struct SortingSnapshot: Sendable {
    let ids: [String]
    let payments: [SortingPayment]
    let chosen: [String]
    let learned: [String: String]
}

nonisolated enum LedgerError: LocalizedError, Equatable {
    case notFound
    case notEmpty
    case invalidExport(String)
    case nameTaken
    case emptyName
    case receiptNotFound

    var errorDescription: String? {
        switch self {
        case .notFound: String(localized: "This payment is no longer on this iPhone.")
        case .notEmpty: String(localized: "An export can only be restored while Aresium has no data on this iPhone.")
        case .invalidExport: String(localized: "This file is not an Aresium export, or it is damaged. Nothing was restored.")
        case .nameTaken: String(localized: "There is already a category with this name.")
        case .emptyName: String(localized: "Type a name for the category.")
        case .receiptNotFound: String(localized: "This receipt is no longer on this iPhone.")
        }
    }
}

/// Phone mode's storage work: the person's accounts and payments, chosen categories, learned rules and saved layouts,
/// export and restore. Values in, values out; the models never leave the actor. The engine is not used here
/// (`PhoneBackend` brings the two together).
actor PhoneLedger: ModelActor {
    /// Created on the ledger executor when batch work first needs a save revision.
    var batchSaveObserver: BatchSaveObserver?
    var cachedDashboard: PhoneDashboardCache?
    var transferCategoryIDs: Set<String> = [CategoryCatalog.ownTransfers]
    nonisolated let modelContainer: ModelContainer
    private nonisolated let executor: PhoneLedgerExecutor
    nonisolated var modelExecutor: any ModelExecutor { executor }
    nonisolated var unownedExecutor: UnownedSerialExecutor { executor.asUnownedSerialExecutor() }

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        executor = PhoneLedgerExecutor(container: modelContainer)
    }

    // MARK: summary

    func summary() throws -> LedgerSummary {
        try PickerTiming.measure("ledger.summary") {
            LedgerSummary(payments: try modelContext.fetchCount(FetchDescriptor<StoredPayment>()),
                          unsorted: try modelContext.fetchCount(FetchDescriptor<StoredPayment>(predicate: #Predicate { $0.category == nil })),
                          accounts: try modelContext.fetchCount(FetchDescriptor<StoredAccount>()),
                          learned: try modelContext.fetchCount(FetchDescriptor<StoredRule>()),
                          layouts: try modelContext.fetchCount(FetchDescriptor<StoredLayout>()),
                          receipts: try modelContext.fetchCount(FetchDescriptor<StoredReceipt>()),
                          nameRules: try modelContext.fetchCount(FetchDescriptor<StoredPaymentName>()),
                          chosen: try chosen())
        }
    }

    // MARK: categories

    func chosen() throws -> [ChosenCategory] {
        try modelContext.fetch(FetchDescriptor<StoredChosen>(sortBy: [SortDescriptor(\.order), SortDescriptor(\.id)]))
            .map { ChosenCategory(id: $0.id, name: $0.customName, order: $0.order, look: Self.look(of: $0),
                                  side: $0.side, otherSide: $0.otherSide) }
    }

    /// Ticks a default category (or adds one's own, with `name`, and gives it its look beside the other own ones,
    /// `OwnCategoryLook`). Ticking one that is on the list changes nothing.
    func choose(_ id: String, name: String? = nil, side: String? = nil) throws {
        try PickerTiming.measure("ledger.choose") {
            let all = try modelContext.fetch(FetchDescriptor<StoredChosen>())
            guard !all.contains(where: { $0.id == id }) else { return }
            var look: CategoryLook?
            if ChosenCategory.isCustom(id) {
                let others = all.filter { ChosenCategory.isCustom($0.id) }.compactMap(Self.look)
                look = OwnCategoryLook.look(for: name ?? "", besides: others)
            }
            modelContext.insert(StoredChosen(id: id, customName: name, order: (all.map(\.order).max() ?? -1) + 1, look: look,
                                             side: ChosenCategory.isCustom(id) ? (side ?? "spend") : nil,
                                             otherSide: id == "friends"))
            try modelContext.save()
        }
    }

    /// One's own categories without a look (made before brief 36, or restored from an older export) get theirs, in the
    /// order they were made, as if added one after the other (`OwnCategoryLook.fill`), and the context is saved. Run
    /// when the store is opened (`PhoneStorage.open`) and in a restore; nothing happens when every one has its look.
    nonisolated static func giveOwnCategoriesLooks(in context: ModelContext) throws {
        let own = try context.fetch(FetchDescriptor<StoredChosen>(sortBy: [SortDescriptor(\.order), SortDescriptor(\.id)]))
            .filter { ChosenCategory.isCustom($0.id) }
        guard own.contains(where: { look(of: $0) == nil }) else { return }
        let looks = OwnCategoryLook.fill(own.map { (name: $0.customName ?? "", look: look(of: $0)) })
        for (category, look) in zip(own, looks) where Self.look(of: category) == nil {
            category.icon = look.icon
            category.color = look.color
        }
        try context.save()
    }

    /// Once per old chosen category, before the store is exposed or after an older export's payments are restored.
    /// The engine computes the old net from primary categories exactly as it did before explicit sides.
    nonisolated static func giveCategoriesSides(in context: ModelContext) throws {
        let all = try context.fetch(FetchDescriptor<StoredChosen>())
        let pending = all.filter { !$0.sidesAssigned }
        guard !pending.isEmpty else { return }
        let payments = try context.fetch(FetchDescriptor<StoredPayment>()).map(Self.value)
        let receipts = try context.fetch(FetchDescriptor<StoredReceipt>()).map(Self.value)
        var list: PhoneCategoryList?
        let kinds = try AresiumEngine.legacyCategoryKinds { catalog in
            let old = PhoneCategoryList(catalog: catalog, chosen: all.map {
                ChosenCategory(id: $0.id, name: $0.customName, order: $0.order)
            }, language: .english)
            list = old
            let input = PhoneDashboard.input(payments: payments, list: old, today: LedgerExport.day(.now), receipts: receipts)
            // Classification is all-time. The date only selects the current dashboard month.
            let categories = input.categories.map {
                SourceCategory(name: $0.name, icon: $0.icon, color: $0.color, excludeFromTotals: $0.excludeFromTotals)
            }
            return DashboardSourceInput(transactions: input.transactions, categories: categories,
                                        today: input.today, receipts: input.receipts)
        }
        guard let list else { return }
        for category in pending {
            let wasIncome = list.name(of: category.id).flatMap { kinds[$0] } == "income"
            if ChosenCategory.isCustom(category.id), category.side == nil {
                category.side = wasIncome ? "income" : "spend"
            } else if list.side(of: category.id) == .spend, wasIncome {
                category.otherSide = true
            }
            category.sidesAssigned = true
        }
        try context.save()
    }

    /// Returns which directions have primary payments, including receipts/entries as the engine receives them.
    func hasPayments(in id: String, direction: ReceiptDirection) throws -> Bool {
        let payments = try payments()
        if payments.contains(where: { $0.category == id && ($0.amountValue > 0 ? .in : ReceiptDirection.out) == direction }) {
            return true
        }
        let paymentIDs = Set(payments.map(\.id))
        return try receipts().contains { receipt in
            guard receipt.category == id,
                  receipt.kind == .manual || receipt.paymentID.map({ !paymentIDs.contains($0) }) ?? true,
                  receipt.euros != nil else { return false }
            return (receipt.method == .card ? ReceiptDirection.out : receipt.direction) == direction
        }
    }

    func setSide(_ side: CategorySide, of id: String) throws {
        guard ChosenCategory.isCustom(id),
              let category = try modelContext.fetch(FetchDescriptor<StoredChosen>(predicate: #Predicate { $0.id == id })).first
        else { throw LedgerError.notFound }
        if let old = category.side.flatMap(CategorySide.init(rawValue:)), old != side,
           try hasPayments(in: id, direction: old.direction) {
            category.otherSide = true
        }
        category.side = side.rawValue
        category.sidesAssigned = true
        try modelContext.save()
    }

    func setOtherSide(_ on: Bool, for id: String) throws {
        guard let category = try modelContext.fetch(FetchDescriptor<StoredChosen>(predicate: #Predicate { $0.id == id })).first
        else { throw LedgerError.notFound }
        category.otherSide = on
        category.sidesAssigned = true
        try modelContext.save()
    }

    /// Only the name changes; every reference, look and choice stays on the stable id.
    func rename(_ id: String, to name: String?) throws {
        guard let category = try modelContext.fetch(FetchDescriptor<StoredChosen>(predicate: #Predicate { $0.id == id })).first
        else { throw LedgerError.notFound }
        category.customName = name
        try modelContext.save()
    }

    /// A stored category's own look: both parts, or none.
    private nonisolated static func look(of category: StoredChosen) -> CategoryLook? {
        guard let icon = category.icon, let color = category.color else { return nil }
        return CategoryLook(icon: icon, color: color)
    }

    /// How many payments are in a category (as their category; extra "Add" categories not counted).
    func paymentCount(in category: String) throws -> Int {
        try modelContext.fetchCount(FetchDescriptor<StoredPayment>(predicate: #Predicate { $0.category == category }))
    }

    /// `paymentCount(in:)` for every category that has payments, by id.
    func paymentCounts() throws -> [String: Int] {
        try PickerTiming.measure("ledger.paymentCounts") {
            var counts: [String: Int] = [:]
            for payment in try modelContext.fetch(FetchDescriptor<StoredPayment>()) {
                if let category = payment.category { counts[category, default: 0] += 1 }
            }
            return counts
        }
    }

    /// Unticks a category. Its payments move to `target` (set by hand) or, with nil, to Not sorted; it is taken off
    /// every payment's extra categories. Learned rules into one's own category go with it; rules into a default one
    /// stay (the engine ignores them while it is not on the list, and they work again when it is ticked again).
    func unchoose(_ id: String, moveTo target: String?) throws {
        try PickerTiming.measure("ledger.unchoose") {
            for payment in try modelContext.fetch(FetchDescriptor<StoredPayment>(predicate: #Predicate { $0.category == id })) {
                payment.category = target
                payment.categorySource = (target == nil ? CategorySource.none : .manual).rawValue
                payment.extraCategories.removeAll { $0 == id || $0 == target }
            }
            for payment in try modelContext.fetch(FetchDescriptor<StoredPayment>()) where payment.extraCategories.contains(id) {
                payment.extraCategories.removeAll { $0 == id }
            }
            for receipt in try modelContext.fetch(FetchDescriptor<StoredReceipt>(predicate: #Predicate { $0.category == id })) {
                receipt.category = target
                receipt.categorySource = (target == nil ? CategorySource.none : .manual).rawValue
            }
            if ChosenCategory.isCustom(id) {
                try modelContext.fetch(FetchDescriptor<StoredRule>(predicate: #Predicate { $0.category == id }))
                    .forEach(modelContext.delete)
            }
            try modelContext.fetch(FetchDescriptor<StoredChosen>(predicate: #Predicate { $0.id == id })).forEach(modelContext.delete)
            try removeTransferPaybacks()
            try modelContext.save()
        }
    }

    // MARK: learned rules and layouts

    func learned() throws -> [String: String] {
        Dictionary(try modelContext.fetch(FetchDescriptor<StoredRule>()).map { ($0.merchant, $0.category) },
                   uniquingKeysWith: { _, last in last })
    }

    func remember(_ rules: [String: String]) throws {
        let existing = Dictionary(try modelContext.fetch(FetchDescriptor<StoredRule>()).map { ($0.merchant, $0) },
                                  uniquingKeysWith: { first, _ in first })
        for (merchant, category) in rules where !merchant.isEmpty {
            if let rule = existing[merchant] { rule.category = category }
            else { modelContext.insert(StoredRule(merchant: merchant, category: category)) }
        }
        try modelContext.save()
    }

    func layouts() throws -> [CsvLayout] {
        try modelContext.fetch(FetchDescriptor<StoredLayout>(sortBy: [SortDescriptor(\.savedAt, order: .reverse)]))
            .compactMap { try? JSONDecoder().decode(CsvLayout.self, from: $0.layout) }
    }

    /// Saves a layout the person confirmed; one confirmed before for the same table is replaced.
    func saveLayout(_ layout: CsvLayout, at date: Date = .now) throws {
        let id = Self.layoutID(layout)
        let data = try JSONEncoder().encode(layout)
        if let saved = try modelContext.fetch(FetchDescriptor<StoredLayout>(predicate: #Predicate { $0.id == id })).first {
            saved.layout = data
            saved.savedAt = date
        } else {
            modelContext.insert(StoredLayout(id: id, layout: data, savedAt: date))
        }
        try modelContext.save()
    }

    static func layoutID(_ layout: CsvLayout) -> String {
        ([layout.separator] + layout.header).joined(separator: "\u{1F}")
    }

    // MARK: payments

    /// Adds a read file's payments to its account, counting those already stored by key or bank booking group.
    /// Not sorted yet: `applySort` follows.
    func add(_ file: BankFile, account: LedgerAccount) throws -> AddedPayments {
        let accountID = account.id
        if let stored = try modelContext.fetch(FetchDescriptor<StoredAccount>(predicate: #Predicate { $0.id == accountID })).first {
            if stored.iban == nil { stored.iban = account.iban }
            if stored.bank == nil { stored.bank = account.bank }
        } else {
            modelContext.insert(StoredAccount(id: account.id, name: account.name, iban: account.iban, bank: account.bank,
                                              currency: account.currency))
        }
        let storedPayments = try modelContext.fetch(FetchDescriptor<StoredPayment>(predicate: #Predicate { $0.account == accountID }))
        var keys = Set(storedPayments.map(\.key))
        var unmatched: [BankBookingGroup: Int] = [:]
        if file.source == "bank" {
            // Bank formats do not share ids. Exports cover every booking of each day, so the remaining bookings
            // of this account can answer one new row each by day, cents and currency. Reserve every key match in
            // the whole file first, even when it comes after a new row; PayPal keeps its transaction-code matching.
            let fileKeys = Set(file.transactions.map {
                LedgerPayment.key(account: accountID, source: file.source, externalId: $0.externalId)
            })
            for stored in storedPayments where stored.source == "bank" && !fileKeys.contains(stored.key) {
                if let group = BankBookingGroup(day: stored.bookingDate, amount: stored.amount, currency: stored.currency) {
                    unmatched[group, default: 0] += 1
                }
            }
        }
        var last = try lastSequence()
        var added = AddedPayments(accountName: account.name)
        for txn in file.transactions {
            let key = LedgerPayment.key(account: account.id, source: file.source, externalId: txn.externalId)
            guard keys.insert(key).inserted else { added.already += 1; continue }
            if file.source == "bank",
               let group = BankBookingGroup(day: txn.day, amount: txn.amount, currency: txn.currency),
               let count = unmatched[group], count > 0 {
                unmatched[group] = count - 1
                added.already += 1
                continue
            }
            last += 1
            let payment = LedgerPayment(id: UUID().uuidString, account: account.id, source: file.source,
                                        externalId: txn.externalId, bookingDate: txn.day,
                                        valueDate: txn.valueDate.map { String($0.prefix(10)) }, amount: txn.amount,
                                        currency: txn.currency, text: txn.description, counterparty: txn.counterparty,
                                        counterpartyIban: txn.counterpartyIban, balance: txn.balance, raw: txn.raw,
                                        category: nil, categorySource: .none,
                                        extraCategories: [], sequence: last)
            modelContext.insert(StoredPayment(payment))
            added.newIDs.append(payment.id)
        }
        try modelContext.save()
        return added
    }

    /// The account is already fixed by the import's fetch; decimal cents avoid differences in amount formatting.
    nonisolated private struct BankBookingGroup: Hashable {
        let day: String
        let cents: Decimal
        let currency: String

        init?(day: String, amount: String, currency: String) {
            guard let value = Decimal(string: amount, locale: Locale(identifier: "en_US_POSIX")) else { return nil }
            var scaled = value * 100
            var rounded = Decimal()
            NSDecimalRound(&rounded, &scaled, 0, .plain)
            self.day = String(day.prefix(10))
            self.cents = rounded
            self.currency = currency
        }
    }

    private func lastSequence() throws -> Int {
        var last = FetchDescriptor<StoredPayment>(sortBy: [SortDescriptor(\.sequence, order: .reverse)])
        last.fetchLimit = 1
        return try modelContext.fetch(last).first?.sequence ?? 0
    }

    /// Every payment in booking order (then the order they were added in): the order the sorting rules and the
    /// dashboard get them in.
    func payments() throws -> [LedgerPayment] {
        try PickerTiming.measure("ledger.payments") {
            try storedPayments().map(Self.value)
        }
    }

    func payment(_ id: String) throws -> LedgerPayment? {
        try modelContext.fetch(FetchDescriptor<StoredPayment>(predicate: #Predicate { $0.id == id })).first.map(Self.value)
    }

    func accounts() throws -> [LedgerAccount] {
        try modelContext.fetch(FetchDescriptor<StoredAccount>(sortBy: [SortDescriptor(\.id)])).map(Self.value)
    }

    func account(_ id: String) throws -> LedgerAccount? {
        try modelContext.fetch(FetchDescriptor<StoredAccount>(predicate: #Predicate { $0.id == id })).first.map(Self.value)
    }

    /// - Parameter waitingOnly: only the payments without a category (Not sorted), for the picker's estimate.
    func sortingSnapshot(waitingOnly: Bool = false) throws -> SortingSnapshot {
        try PickerTiming.measure("ledger.sortingSnapshot") {
            let payments = try storedPayments().filter { !waitingOnly || $0.category == nil }
            let ibans = Dictionary(try accounts().map { ($0.id, $0.iban) }, uniquingKeysWith: { first, _ in first })
            return SortingSnapshot(ids: payments.map(\.id),
                                   payments: payments.map { Self.value($0).sorting(accountIban: ibans[$0.account] ?? nil) },
                                   chosen: try chosen().map(\.id), learned: try learned())
        }
    }

    /// Applies `sortPayments`'s results (one per id of `snapshot`, in order) to the payments they concern: every
    /// payment in `fresh` (new from an import); of the others, those without a category, and those whose structural
    /// status changed (a new PayPal export makes the bank's PayPal lines own transfers; a new account's payment pairs
    /// with an older one). A category set by hand never changes, and neither does one sorted before by a shop rule or
    /// a learned merchant (the "also N others?" answer stays as given).
    /// - Returns: the new category of each payment in `fresh` (nil: not sorted).
    @discardableResult
    func applySort(ids: [String], results: [SortResult], fresh: Set<String>) throws -> [String: String?] {
        try PickerTiming.measure("ledger.applySort") {
            guard ids.count == results.count else { throw EngineError.invalidAnswer("sort results do not match") }
            let byID = Dictionary(try modelContext.fetch(FetchDescriptor<StoredPayment>()).map { ($0.id, $0) },
                                  uniquingKeysWith: { first, _ in first })
            var sortedFresh: [String: String?] = [:]
            for (id, result) in zip(ids, results) {
                guard let payment = byID[id], !CategorySource.keeps(payment.categorySource) else { continue }
                let source = result.categoryId == nil ? CategorySource.none : CategorySource(rawValue: result.source ?? "") ?? .none
                let wasStructural = payment.categorySource == CategorySource.structural.rawValue
                let applies = fresh.contains(id) || payment.category == nil || wasStructural != (source == .structural)
                guard applies else { continue }
                if payment.category != result.categoryId { payment.category = result.categoryId }
                if payment.categorySource != source.rawValue { payment.categorySource = source.rawValue }
                if let category = result.categoryId { payment.extraCategories.removeAll { $0 == category } }
                if fresh.contains(id) { sortedFresh[id] = result.categoryId }
            }
            try removeTransferPaybacks()
            if modelContext.hasChanges { try modelContext.save() }
            return sortedFresh
        }
    }

    /// Moves one payment to a category (or Not sorted) and its extra categories (Switch and Add).
    func setCategory(_ id: String, category: String?, extras: [String]? = nil, source: CategorySource) throws {
        guard let payment = try modelContext.fetch(FetchDescriptor<StoredPayment>(predicate: #Predicate { $0.id == id })).first
        else { throw LedgerError.notFound }
        payment.category = category
        payment.categorySource = (category == nil ? CategorySource.none : source).rawValue
        var kept: [String] = []
        for extra in extras ?? payment.extraCategories where extra != category && !kept.contains(extra) { kept.append(extra) }
        payment.extraCategories = kept
        try removeTransferPaybacks()
        if modelContext.hasChanges { try modelContext.save() }
    }

    /// Moves several payments to one category (the "also the N others" answer).
    func move(_ ids: [String], to category: String, source: CategorySource) throws {
        let wanted = Set(ids)
        for payment in try modelContext.fetch(FetchDescriptor<StoredPayment>()) where wanted.contains(payment.id) {
            guard !CategorySource.keeps(payment.categorySource),
                  payment.categorySource != CategorySource.structural.rawValue else { continue }
            payment.category = category
            payment.categorySource = source.rawValue
            payment.extraCategories.removeAll { $0 == category }
        }
        try removeTransferPaybacks()
        if modelContext.hasChanges { try modelContext.save() }
    }

    // MARK: receipts

    /// Every receipt, newest purchase first (then the newest kept).
    func receipts() throws -> [LedgerReceipt] {
        try modelContext.fetch(FetchDescriptor<StoredReceipt>(sortBy: [SortDescriptor(\.date, order: .reverse),
                                                                       SortDescriptor(\.created, order: .reverse)]))
            .map(Self.value)
    }

    func receipt(_ id: String) throws -> LedgerReceipt? {
        try storedReceipt(id).map(Self.value)
    }

    /// The receipt joined to this payment, if one is.
    func receipt(joinedTo paymentID: String) throws -> LedgerReceipt? {
        try modelContext.fetch(FetchDescriptor<StoredReceipt>(predicate: #Predicate { $0.paymentID == paymentID }))
            .first.map(Self.value)
    }

    func addReceipt(_ receipt: LedgerReceipt) throws {
        modelContext.insert(StoredReceipt(receipt))
        try modelContext.save()
    }

    /// The payments other receipts are joined to (a payment takes one receipt).
    func takenPayments(besides receiptID: String?) throws -> Set<String> {
        Set(try modelContext.fetch(FetchDescriptor<StoredReceipt>()).compactMap { $0.id == receiptID ? nil : $0.paymentID })
    }

    /// Joins a receipt to its bank payment. A payment not sorted takes the receipt's category (source `receipt`).
    /// - Returns: whether the payment took the receipt's category.
    @discardableResult
    func join(_ receiptID: String, to paymentID: String) throws -> Bool {
        guard let receipt = try storedReceipt(receiptID) else { throw LedgerError.receiptNotFound }
        guard let payment = try storedPayment(paymentID) else { throw LedgerError.notFound }
        receipt.paymentID = paymentID
        receipt.declined.removeAll { $0 == paymentID }
        var gave = false
        if payment.category == nil, let category = receipt.category {
            payment.category = category
            payment.categorySource = CategorySource.receipt.rawValue
            payment.extraCategories.removeAll { $0 == category }
            gave = true
        }
        try removeTransferPaybacks()
        try modelContext.save()
        return gave
    }

    /// Unjoins a receipt: it waits for its bank payment again, and a category the payment took from it goes (the
    /// payment is sorted again with the others not sorted).
    func unjoin(_ receiptID: String) throws {
        guard let receipt = try storedReceipt(receiptID) else { throw LedgerError.receiptNotFound }
        if let paymentID = receipt.paymentID {
            takeBackCategory(of: paymentID)
            receipt.declined.removeAll { $0 == paymentID }
        }
        receipt.paymentID = nil
        try modelContext.save()
    }

    /// "None of these": the person said these payments are not the receipt's.
    func decline(_ paymentIDs: [String], for receiptID: String) throws {
        guard let receipt = try storedReceipt(receiptID) else { throw LedgerError.receiptNotFound }
        for id in paymentIDs where !receipt.declined.contains(id) { receipt.declined.append(id) }
        try modelContext.save()
    }

    /// Deletes a receipt or cash entry: its payment, if joined, loses a category it took from it; the cash it covered is
    /// uncovered (the dashboard counts again without it); what was paid from it (cash received) goes back to automatic.
    func deleteReceipt(_ receiptID: String) throws {
        guard let receipt = try storedReceipt(receiptID) else { throw LedgerError.receiptNotFound }
        if let paymentID = receipt.paymentID { takeBackCategory(of: paymentID) }
        try forgetPaidFrom(receiptID, saving: false)
        modelContext.delete(receipt)
        try modelContext.save()
    }

    /// The receipts and entries paid from `sourceID` go back to automatic (it is gone, or no source any more).
    func forgetPaidFrom(_ sourceID: String, saving: Bool = true) throws {
        let paid = try modelContext.fetch(FetchDescriptor<StoredReceipt>(predicate: #Predicate { $0.paidFrom == sourceID }))
        for receipt in paid { receipt.paidFrom = nil }
        if saving { try modelContext.save() }
    }

    /// The receipt's category, set by the person (or nil: not sorted).
    func setReceiptCategory(_ receiptID: String, category: String?, source: CategorySource) throws {
        guard let receipt = try storedReceipt(receiptID) else { throw LedgerError.receiptNotFound }
        receipt.category = category
        receipt.categorySource = (category == nil ? CategorySource.none : source).rawValue
        followCategory(of: receipt)
        try removeTransferPaybacks()
        try modelContext.save()
    }

    /// A receipt corrected after saving (brief 33): its values as the person confirmed them now. When it leaves the
    /// payment it was joined to (`value.paymentID` differs), that payment loses a category it took from the receipt
    /// (sorted again with the others not sorted); while it stays joined, such a payment follows the receipt's new
    /// category.
    func updateReceipt(_ value: LedgerReceipt) throws {
        guard let receipt = try storedReceipt(value.id) else { throw LedgerError.receiptNotFound }
        if let joined = receipt.paymentID, joined != value.paymentID { takeBackCategory(of: joined) }
        receipt.date = value.date
        receipt.time = value.time
        receipt.shop = value.shop
        receipt.total = value.total
        receipt.currency = value.currency
        receipt.euroAmount = value.euroAmount
        receipt.method = value.method.rawValue
        receipt.category = value.category
        receipt.categorySource = (value.category == nil ? CategorySource.none : value.categorySource).rawValue
        receipt.paymentID = value.paymentID
        receipt.declined = value.declined
        receipt.direction = value.direction.rawValue
        receipt.kind = value.kind.rawValue
        receipt.paidFrom = value.paidFrom
        receipt.shopAsRead = value.shopAsRead
        followCategory(of: receipt)
        try removeTransferPaybacks()
        try modelContext.save()
    }

    /// A joined payment that took its category from this receipt keeps taking it: the receipt's category now, or Not
    /// sorted (then sorted again with the others).
    private func followCategory(of receipt: StoredReceipt) {
        guard let paymentID = receipt.paymentID, let payment = try? storedPayment(paymentID),
              payment.categorySource == CategorySource.receipt.rawValue else { return }
        payment.category = receipt.category
        payment.categorySource = (receipt.category == nil ? CategorySource.none : .receipt).rawValue
        if let category = receipt.category { payment.extraCategories.removeAll { $0 == category } }
    }

    // MARK: shop names the person corrected

    /// The name the person gave the shop read as `read` (normalised, `ShopNames.key`), if they corrected it before.
    func shopName(read: String) throws -> String? {
        try modelContext.fetch(FetchDescriptor<StoredShopName>(predicate: #Predicate { $0.read == read })).first?.name
    }

    /// Remembers (or replaces) a corrected shop name, or drops one (`ShopNames.Change`).
    func apply(_ change: ShopNames.Change, at date: Date = .now) throws {
        switch change {
        case let .remember(correction):
            let read = correction.read
            if let stored = try modelContext.fetch(FetchDescriptor<StoredShopName>(predicate: #Predicate { $0.read == read })).first {
                stored.name = correction.name
                stored.saved = date
            } else {
                modelContext.insert(StoredShopName(read: correction.read, name: correction.name, saved: date))
            }
        case let .forget(read):
            try modelContext.fetch(FetchDescriptor<StoredShopName>(predicate: #Predicate { $0.read == read }))
                .forEach(modelContext.delete)
        }
        try modelContext.save()
    }

    /// Every corrected shop name, by the shop as read.
    func shopNames() throws -> [ShopNameCorrection] {
        try modelContext.fetch(FetchDescriptor<StoredShopName>(sortBy: [SortDescriptor(\.read)]))
            .map { ShopNameCorrection(read: $0.read, name: $0.name) }
    }

    private func takeBackCategory(of paymentID: String) {
        guard let payment = try? storedPayment(paymentID),
              payment.categorySource == CategorySource.receipt.rawValue else { return }
        payment.category = nil
        payment.categorySource = CategorySource.none.rawValue
    }

    private func storedReceipt(_ id: String) throws -> StoredReceipt? {
        try modelContext.fetch(FetchDescriptor<StoredReceipt>(predicate: #Predicate { $0.id == id })).first
    }

    private func storedPayment(_ id: String) throws -> StoredPayment? {
        try modelContext.fetch(FetchDescriptor<StoredPayment>(predicate: #Predicate { $0.id == id })).first
    }

    // MARK: export and restore

    func export(on date: Date = .now) throws -> LedgerExport {
        LedgerExport(exported: LedgerExport.day(date), accounts: try accounts(), payments: try payments(),
                     categories: try chosen(),
                     learned: try modelContext.fetch(FetchDescriptor<StoredRule>(sortBy: [SortDescriptor(\.merchant)]))
                        .map { LearnedRule(merchant: $0.merchant, category: $0.category) },
                     layouts: try modelContext.fetch(FetchDescriptor<StoredLayout>(sortBy: [SortDescriptor(\.savedAt)]))
                        .compactMap { try? JSONDecoder().decode(CsvLayout.self, from: $0.layout) },
                     receipts: try receipts().reversed(), shopNames: try shopNames(), nameRules: try paymentNames())
    }

    /// Restores an export: only into a store without data (chosen categories and corrected shop names are replaced:
    /// neither counts as data), checked first, all or nothing.
    func restore(_ export: LedgerExport, catalog: CategoryCatalog) throws {
        guard try summary().isEmpty else { throw LedgerError.notEmpty }
        try export.validate(catalog: catalog)
        guard export.schema >= 7 || !export.payments.contains(where: { !($0.paysBack ?? []).isEmpty })
        else { throw LedgerError.invalidExport("paybacks before schema 7") }
        configurePaybacks(catalog: catalog)
        do {
            try modelContext.fetch(FetchDescriptor<StoredChosen>()).forEach(modelContext.delete)
            try modelContext.fetch(FetchDescriptor<StoredShopName>()).forEach(modelContext.delete)
            for account in export.accounts {
                modelContext.insert(StoredAccount(id: account.id, name: account.name, iban: account.iban,
                                                  bank: account.bank, currency: account.currency))
            }
            for payment in export.payments { modelContext.insert(StoredPayment(payment)) }
            for category in export.categories {
                // Only one's own keep a look, and only one the app can draw; the others get theirs below.
                let look = category.look.flatMap {
                    ChosenCategory.isCustom(category.id) && OwnCategoryLook.isUsable($0) ? $0 : nil
                }
                modelContext.insert(StoredChosen(id: category.id, customName: category.name, order: category.order,
                                                 look: look,
                                                 side: export.schema >= 5 ? category.side : nil,
                                                 otherSide: export.schema >= 5 && category.otherSide,
                                                 sidesAssigned: export.schema >= 5))
            }
            for rule in export.learned { modelContext.insert(StoredRule(merchant: rule.merchant, category: rule.category)) }
            for (index, layout) in export.layouts.enumerated() {
                modelContext.insert(StoredLayout(id: Self.layoutID(layout), layout: try JSONEncoder().encode(layout),
                                                 savedAt: Date(timeIntervalSince1970: TimeInterval(index))))
            }
            for receipt in export.receipts { modelContext.insert(StoredReceipt(receipt)) }
            for rule in export.nameRules { modelContext.insert(StoredPaymentName(merchant: rule.merchant, name: rule.name)) }
            for (index, correction) in export.shopNames.enumerated() {
                modelContext.insert(StoredShopName(read: correction.read, name: correction.name,
                                                   saved: Date(timeIntervalSince1970: TimeInterval(index))))
            }
            try Self.giveOwnCategoriesLooks(in: modelContext)
            try Self.giveCategoriesSides(in: modelContext)
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    // MARK: values

    private func storedPayments() throws -> [StoredPayment] {
        try modelContext.fetch(FetchDescriptor<StoredPayment>(sortBy: [SortDescriptor(\.bookingDate), SortDescriptor(\.sequence)]))
    }

    private nonisolated static func value(_ payment: StoredPayment) -> LedgerPayment {
        LedgerPayment(id: payment.id, account: payment.account, source: payment.source, externalId: payment.externalId,
                      bookingDate: payment.bookingDate, valueDate: payment.valueDate, amount: payment.amount,
                      currency: payment.currency, text: payment.text, counterparty: payment.counterparty,
                      counterpartyIban: payment.counterpartyIban, balance: payment.balance,
                      raw: try? JSONDecoder().decode(JSONValue.self, from: payment.raw),
                      category: payment.category,
                      categorySource: CategorySource(rawValue: payment.categorySource) ?? .none,
                      extraCategories: payment.extraCategories, sequence: payment.sequence, ownName: payment.ownName,
                      paysBack: payment.paysBack)
    }

    private nonisolated static func value(_ receipt: StoredReceipt) -> LedgerReceipt {
        LedgerReceipt(id: receipt.id, date: receipt.date, time: receipt.time, shop: receipt.shop, total: receipt.total,
                      currency: receipt.currency, euroAmount: receipt.euroAmount,
                      method: ReceiptMethod(rawValue: receipt.method) ?? .card, category: receipt.category,
                      categorySource: CategorySource(rawValue: receipt.categorySource) ?? .none, rows: receipt.rows,
                      from: receipt.from, paymentID: receipt.paymentID, declined: receipt.declined,
                      created: receipt.created, direction: ReceiptDirection(rawValue: receipt.direction) ?? .out,
                      kind: ReceiptKind(rawValue: receipt.kind) ?? .receipt, paidFrom: receipt.paidFrom,
                      shopAsRead: receipt.shopAsRead)
    }

    private static func value(_ account: StoredAccount) -> LedgerAccount {
        LedgerAccount(id: account.id, name: account.name, iban: account.iban, bank: account.bank, currency: account.currency)
    }
}
