import Foundation
import Observation

/// One file's import in phone mode: how many payments were new, already there, sorted, and waiting for a category.
nonisolated struct PhoneImportResult: Equatable, Sendable {
    let name: String
    var added = 0
    var already = 0
    var sorted = 0
    var waiting = 0
    var account: String?
    var error: String?
    /// An unknown CSV: the guessed layout, which the person confirms before the file is read.
    var layout: LayoutGuess?

    var displayMessage: String {
        if let error, !error.isEmpty { return "\(name): \(error)" }
        if layout != nil { return String(localized: "\(name): check its columns") }
        return String(localized: "\(name): \(added) new · \(already) already there")
    }
}

/// The words for imports in phone mode (English here, German in the catalog).
nonisolated enum ImportWording {
    /// The engine's bank-file error codes (aresium/src/engine/readers/table.ts → `BankFileErrorCode`), in plain words.
    static func bankFileProblem(_ code: String, language: AppLanguage = .current) -> String {
        switch code {
        case "zip": language.string("Unzip the file first, then import what is inside.")
        case "empty": language.string("The file is empty.")
        case "noTable": language.string("No table of payments was found in this file.")
        case "headerMismatch": language.string("The columns of this file don't match its saved layout.")
        case "camt": language.string("This XML file is not a bank statement Aresium can read.")
        case "mt940": language.string("This MT940 file could not be read.")
        default: language.string("This file could not be read.")
        }
    }

    /// "12 new · 3 already there · 10 sorted · 2 waiting for a category" (and how many files failed).
    static func summary(_ results: [PhoneImportResult], language: AppLanguage = .current) -> String {
        let added = results.reduce(0) { $0 + $1.added }, already = results.reduce(0) { $0 + $1.already }
        let sorted = results.reduce(0) { $0 + $1.sorted }, waiting = results.reduce(0) { $0 + $1.waiting }
        let failed = results.filter { $0.error?.isEmpty == false }.count
        var line = language.string("\(added) new · \(already) already there · \(sorted) sorted · \(waiting) waiting for a category")
        if failed > 0 { line += " · " + language.string("\(failed) files failed") }
        return line
    }
}

/// Phone mode: the dashboard, a payment's detail, Switch, Add and imports from the phone's own store (`PhoneLedger`)
/// and the shared engine (`AresiumEngine`), nothing over the network. Also the phone-only work the new screens use:
/// categories, the merchant question, layouts, export and restore.
@MainActor @Observable
final class PhoneBackend: AresiumBackend {
    let account: String?
    @ObservationIgnored let ledger: PhoneLedger
    @ObservationIgnored let engine: AresiumEngine
    /// What the store holds, for the first run and Settings; refreshed after every change.
    private(set) var summary = LedgerSummary()
    private(set) var catalog: CategoryCatalog?
    /// Today as `YYYY-MM-DD` for the dashboard (tests pin it).
    @ObservationIgnored var today: () -> String = { LedgerExport.day(.now) }

    init(account: String, ledger: PhoneLedger, engine: AresiumEngine) {
        self.account = account
        self.ledger = ledger
        self.engine = engine
    }

    /// Reads the engine's categories and the store's numbers; call once after opening.
    func load() async throws {
        catalog = try await engine.catalog()
        try await refresh()
    }

    func refresh() async throws { summary = try await ledger.summary() }

    /// The person's categories as the screens and the dashboard name them, in the app's language.
    func categories(language: AppLanguage = .current) async throws -> PhoneCategoryList {
        let catalog = try await catalogValue()
        return PhoneCategoryList(catalog: catalog, chosen: try await ledger.chosen(), language: language)
    }

    var hasChosenCategories: Bool { !summary.chosen.isEmpty }

    // MARK: AresiumBackend

    var mode: AresiumMode { .phone }
    func isReady(_ session: EmpireSession) -> Bool { true }

    func dashboard(auth: BackendAuth) async throws -> Dashboard {
        let list = try await categories()
        let payments = try await ledger.payments()
        let input = PhoneDashboard.input(payments: payments, list: list, today: today())
        return try await engine.dashboard(input)
    }

    func transactionDetail(id: String, auth: BackendAuth) async throws -> TransactionDetail {
        guard let payment = try await ledger.payment(id) else { throw LedgerError.notFound }
        return PhoneDashboard.detail(payment, account: try await ledger.account(payment.account), list: try await categories())
    }

    /// Moves the payment by hand, learns its merchant, and finds the merchant's other payments not set by hand.
    func switchCategory(id: String, to category: String, auth: BackendAuth) async throws -> SwitchResult {
        let list = try await categories()
        guard let target = list.id(named: category) else { throw LedgerError.notFound }
        guard let payment = try await ledger.payment(id) else { throw LedgerError.notFound }
        try await ledger.setCategory(id, category: target, source: .manual)
        let rules = try await engine.learn(payment.sorting(raw: false), categoryID: target)
        try await ledger.remember(rules)
        try await refresh()
        let detail = try await transactionDetail(id: id, auth: auth)
        guard let merchant = rules.keys.first else { return SwitchResult(detail: detail) }
        let others = try await otherPayments(of: merchant, besides: id, target: target)
        guard !others.isEmpty else { return SwitchResult(detail: detail) }
        let followUp = MerchantFollowUp(shop: payment.place, category: category, count: others.count) { [weak self] in
            guard let self else { return }
            try await self.ledger.move(others, to: target, source: .learned)
            try await self.refresh()
        }
        return SwitchResult(detail: detail, followUp: followUp)
    }

    /// Payments of this merchant, other than `id`, not set by hand and not in `target` already.
    private func otherPayments(of merchant: String, besides id: String, target: String) async throws -> [String] {
        let payments = try await ledger.payments()
        let keys = try await engine.merchantKeys(payments.map { $0.sorting(raw: false) })
        return zip(payments, keys).compactMap { payment, key in
            key == merchant && payment.id != id && payment.categorySource != .manual && payment.category != target
                ? payment.id : nil
        }
    }

    func setTags(id: String, categories names: [String], dropCurrent: Bool, auth: BackendAuth) async throws -> TransactionDetail {
        let list = try await categories()
        let ids = try names.map { name in
            guard let id = list.id(named: name) else { throw LedgerError.notFound }
            return id
        }
        guard let payment = try await ledger.payment(id) else { throw LedgerError.notFound }
        if dropCurrent, let first = ids.first {
            try await ledger.setCategory(id, category: first, extras: Array(ids.dropFirst()), source: .manual)
        } else {
            try await ledger.setCategory(id, category: payment.category, extras: ids, source: payment.categorySource)
        }
        try await refresh()
        return try await transactionDetail(id: id, auth: auth)
    }

    var importExtensions: Set<String> { ImportFileReader.phoneExtensions }

    func importPlan(_ files: [ImportFile], maximumBytes: Int) throws -> ImportPlan {
        ImportPlan(batches: files.isEmpty ? [] : [files], refused: [])
    }

    /// Reads each file with the engine (and the layouts the person confirmed), stores the payments that are new, then
    /// sorts: all payments in one `sortPayments` call (the own-transfer rules look across them), applied to the new
    /// ones and to the ones it affects (`PhoneLedger.applySort`).
    func importFiles(_ files: [ImportFile], auth: BackendAuth) async throws -> [ImportFileResult] {
        var results: [PhoneImportResult] = []
        var fresh: [[String]] = []          // per file: its new payment ids
        let layouts = try await ledger.layouts()
        for file in files {
            var result = PhoneImportResult(name: file.name)
            do {
                let read = try await engine.readBankFile(file.data, layouts: layouts)
                if let guess = read.needsLayout {
                    result.layout = guess
                } else {
                    let added = try await ledger.add(read, account: AccountKey.account(for: read))
                    result.added = added.newIDs.count
                    result.already = added.already
                    result.account = added.accountName
                    fresh.append(added.newIDs)
                }
            } catch let error as EngineError {
                result.error = error.localizedDescription
            }
            if fresh.count == results.count { fresh.append([]) }
            results.append(result)
        }
        let newIDs = Set(fresh.joined())
        if !newIDs.isEmpty {
            let sorted = try await sort(fresh: newIDs)
            for index in results.indices {
                let ids = fresh[index]
                results[index].sorted = ids.filter { id in (sorted[id] ?? nil) != nil }.count
                results[index].waiting = ids.count - results[index].sorted
            }
        }
        try await refresh()
        return results.map { .phone($0) }
    }

    func importSummary(_ results: [ImportFileResult]) -> String {
        ImportWording.summary(results.compactMap { if case let .phone(result) = $0 { result } else { nil } })
    }

    // MARK: sorting

    /// Sorts with the engine and applies it: every payment in `fresh`, the unsorted ones, and those whose own-transfer
    /// status changed. Returns the new categories of `fresh`.
    @discardableResult
    func sort(fresh: Set<String> = []) async throws -> [String: String?] {
        let snapshot = try await ledger.sortingSnapshot()
        guard !snapshot.ids.isEmpty else { return [:] }
        let list = PhoneCategoryList(catalog: try await catalogValue(), chosen: try await ledger.chosen())
        let results = try await engine.sortPayments(snapshot.payments, categories: list.sortingIDs, learned: snapshot.learned)
        return try await ledger.applySort(ids: snapshot.ids, results: results, fresh: fresh)
    }

    // MARK: categories (the picker)

    /// Ticks a default category; payments not sorted yet are sorted again with it.
    func choose(_ id: String) async throws {
        try await ledger.choose(id)
        try await sort()
        try await refresh()
    }

    /// Adds one's own category (ticked).
    @discardableResult
    func addCustom(named typed: String) async throws -> String {
        let name = try await categories().checkedName(typed)
        let id = "custom-" + UUID().uuidString.lowercased()
        try await ledger.choose(id, name: name)
        try await refresh()
        return id
    }

    func paymentCount(in id: String) async throws -> Int { try await ledger.paymentCount(in: id) }

    /// Unticks a category; its payments go to `target` (or Not sorted, then sorted again with the rest of the list).
    func unchoose(_ id: String, moveTo target: String?) async throws {
        try await ledger.unchoose(id, moveTo: target)
        try await sort()
        try await refresh()
    }

    // MARK: layouts

    /// The file read with a layout the person is building (the confirmation sheet's preview).
    func preview(_ file: ImportFile, layout: CsvLayout) async throws -> [BankTxn] {
        try await engine.read(file.data, with: layout).transactions
    }

    /// Saves a layout the person confirmed from a guess (never a known bank's: that would freeze it).
    func saveLayout(_ layout: CsvLayout) async throws {
        try await ledger.saveLayout(layout)
        try await refresh()
    }

    // MARK: export and restore

    func export() async throws -> LedgerExport { try await ledger.export() }

    /// Restores an export's file into the empty store (checked first, all or nothing).
    func restore(_ data: Data) async throws {
        let export = try LedgerExport.decode(data)
        try await ledger.restore(export, catalog: try await catalogValue())
        try await refresh()
    }

    private func catalogValue() async throws -> CategoryCatalog {
        if let catalog { return catalog }
        let catalog = try await engine.catalog()
        self.catalog = catalog
        return catalog
    }
}

/// Stored payments → the engine's input, and a payment → its detail. Pure, so tests pin them.
nonisolated enum PhoneDashboard {
    static func input(payments: [LedgerPayment], list: PhoneCategoryList, today: String) -> DashboardSourceInput {
        let named = Dictionary(list.sortingIDs.compactMap { id in list.name(of: id).map { (id, $0) } },
                               uniquingKeysWith: { first, _ in first })
        let transactions = payments.map { payment in
            SourcePayment(id: payment.id, externalId: payment.externalId, date: payment.bookingDate,
                          amount: payment.amountValue, currency: payment.currency,
                          balance: payment.balance.flatMap(Double.init), description: payment.text,
                          counterparty: payment.counterparty, city: nil, raw: payment.raw,
                          category: payment.category.flatMap { named[$0] },
                          tags: payment.extraCategories.compactMap { named[$0] })
        }
        return DashboardSourceInput(transactions: transactions, categories: list.sourceCategories, today: today)
    }

    /// The dashboard's own name and look for payments without a category (the engine's `UNCATEGORISED`).
    static let uncategorised = (name: "Uncategorised", color: "#9ca3af")

    static func detail(_ payment: LedgerPayment, account: LedgerAccount?, list: PhoneCategoryList) -> TransactionDetail {
        let category = payment.category.flatMap { list.name(of: $0) }
        return TransactionDetail(
            id: payment.id, place: payment.place, amount: payment.amountValue, currency: payment.currency,
            bookingDate: payment.bookingDate, valueDate: payment.valueDate, balance: payment.balance.flatMap(Double.init),
            category: category ?? uncategorised.name,
            categoryColor: payment.category.map { list.look(of: $0).color } ?? uncategorised.color,
            tags: payment.extraCategories.compactMap { list.name(of: $0) },
            categorySource: category == nil ? nil : payment.categorySource.rawValue, categorized: category != nil,
            description: payment.text, counterparty: payment.counterparty, account: account?.name, iban: account?.iban,
            source: payment.source, city: nil, country: nil, trip: nil, tripKind: nil, placeType: nil, recurring: false,
            externalId: payment.externalId, raw: payment.raw ?? .null)
    }
}
