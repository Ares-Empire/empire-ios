import Foundation
import Observation
import os

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
    /// An unknown CSV: the engine's ways of reading it, best first, for "Does this look right?" (empty: the column
    /// check).
    var readings: [FileReading] = []
    /// A file read with a layout the person confirmed (an unknown bank), when that layout may be sent to us: the result
    /// offers to send it (`BankOutbox`).
    var format: BankFormat?
    /// The payments this file added, so its sorted and not sorted can be counted again later (`PhoneBackend.recount`).
    var newIDs: [String] = []
    /// Waiting card receipts that joined one of this file's payments.
    var receiptsJoined = 0

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

    /// "12 new · 3 already there · 10 sorted · 2 not sorted" (and how many files failed); "not sorted" is the name the
    /// dashboard shows for payments without a category (`CategoryName`).
    static func summary(_ results: [PhoneImportResult], language: AppLanguage = .current) -> String {
        let added = results.reduce(0) { $0 + $1.added }, already = results.reduce(0) { $0 + $1.already }
        let sorted = results.reduce(0) { $0 + $1.sorted }, waiting = results.reduce(0) { $0 + $1.waiting }
        let failed = results.filter { $0.error?.isEmpty == false }.count
        var line = language.string("\(added) new · \(already) already there · \(sorted) sorted · \(waiting) not sorted")
        let joined = results.reduce(0) { $0 + $1.receiptsJoined }
        if joined > 0 { line += " · " + language.string("\(joined) receipts joined") }
        if failed > 0 { line += " · " + language.string("\(failed) files failed") }
        return line
    }
}

/// Phone mode: the dashboard, a payment's detail, Switch, Add and imports from the phone's own store (`PhoneLedger`)
/// and the shared engine (`AresiumEngine`), nothing over the network. Also the phone-only work the new screens use:
/// categories, the merchant question, layouts, export and restore.
@MainActor @Observable
final class PhoneBackend: AresiumBackend {
    @ObservationIgnored let ledger: PhoneLedger
    @ObservationIgnored let engine: AresiumEngine
    /// What the store holds, for the first screen and Settings; refreshed after every change.
    private(set) var summary = LedgerSummary()
    private(set) var catalog: CategoryCatalog?
    /// Today as `YYYY-MM-DD` for the dashboard (tests pin it).
    @ObservationIgnored var today: () -> String = { LedgerExport.day(.now) }
    /// "Is this the same payment?" for waiting card receipts, found after a bank import (`matchWaitingReceipts`): asked
    /// once each, after the category picker when both are due (ContentView presents them).
    var receiptQuestions: [ReceiptQuestion] = []

    init(ledger: PhoneLedger, engine: AresiumEngine) {
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
        let input = PhoneDashboard.input(payments: payments, list: list, today: today(), receipts: try await ledger.receipts())
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
            key == merchant && payment.id != id && !CategorySource.keeps(payment.categorySource.rawValue)
                && payment.category != target
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
        let confirmed = Set(layouts.map(PhoneLedger.layoutID))
        for file in files {
            var result = PhoneImportResult(name: file.name)
            do {
                let read = try await engine.readBankFile(file.data, layouts: layouts)
                if let guess = read.needsLayout {
                    result.layout = guess
                    result.readings = await readings(of: file, layouts: layouts)
                } else {
                    let added = try await ledger.add(read, account: AccountKey.account(for: read))
                    result.added = added.newIDs.count
                    result.newIDs = added.newIDs
                    result.already = added.already
                    result.account = added.accountName
                    fresh.append(added.newIDs)
                    // An unknown bank's file, read with the layout the person confirmed: its format may go to us.
                    if read.format == "csv", read.bank == nil, let layout = read.layout,
                       confirmed.contains(PhoneLedger.layoutID(layout)) {
                        result.format = await bankFormat(of: layout, read: read)
                    }
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
            // Receipts waiting for these payments: an exact match joins now (counted with the file its payment came
            // from), the others are asked after the import.
            let round = try await matchWaitingReceipts()
            for payment in round.joined.values {
                let index = fresh.firstIndex { $0.contains(payment) } ?? 0
                if results.indices.contains(index) { results[index].receiptsJoined += 1 }
            }
        }
        try await refresh()
        return results.map { .phone($0) }
    }

    func importSummary(_ results: [ImportFileResult]) -> String {
        ImportWording.summary(results.compactMap { if case let .phone(result) = $0 { result } else { nil } })
    }

    /// No category chosen yet: what an import adds waits as Not sorted, so the category picker follows it.
    var waitsForCategories: Bool { !hasChosenCategories }

    /// Each file's new payments counted as sorted or not as the store holds them now.
    func recount(_ results: [ImportFileResult]) async throws -> [ImportFileResult] {
        let sorted = Set(try await ledger.payments().filter { $0.category != nil }.map(\.id))
        return results.map { result in
            guard case var .phone(file) = result else { return result }
            file.sorted = file.newIDs.filter(sorted.contains).count
            file.waiting = file.newIDs.count - file.sorted
            return .phone(file)
        }
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

    /// The picker's numbers, category id → payments (no entry for none): a ticked category, or one's own, the payments in
    /// it now; a default category not ticked, how many of the payments waiting as Not sorted the engine would sort into
    /// it if it were ticked. That is one dry run of the sorting with every default category besides the chosen ones;
    /// nothing is stored. An estimate: ticked alone, a category can get a few more (a learned shop whose own category
    /// stays unticked then falls back to the shop list).
    func categoryCounts() async throws -> [String: Int] {
        var counts = try await ledger.paymentCounts()
        let list = PhoneCategoryList(catalog: try await catalogValue(), chosen: try await ledger.chosen())
        let unticked = list.catalog.defaults.map(\.id).filter { !list.isChosen($0) }
        let waiting = try await ledger.sortingSnapshot(waitingOnly: true)
        if !unticked.isEmpty, !waiting.ids.isEmpty {
            let results = try await engine.sortPayments(waiting.payments, categories: list.sortingIDs + unticked,
                                                        learned: waiting.learned)
            let estimated = Set(unticked)
            for case let id? in results.map(\.categoryId) where estimated.contains(id) { counts[id, default: 0] += 1 }
        }
        return counts.filter { $0.value > 0 }
    }

    /// Unticks a category; its payments go to `target` (or Not sorted, then sorted again with the rest of the list).
    func unchoose(_ id: String, moveTo target: String?) async throws {
        try await ledger.unchoose(id, moveTo: target)
        try await sort()
        try await refresh()
    }

    // MARK: layouts

    /// The file read with a layout the person is building (the column check's preview).
    func preview(_ file: ImportFile, layout: CsvLayout) async throws -> [BankTxn] {
        try await engine.read(file.data, with: layout).transactions
    }

    /// The engine's readings of an unknown CSV; none when the engine could not offer any (the column check then).
    private func readings(of file: ImportFile, layouts: [CsvLayout]) async -> [FileReading] {
        do { return try await engine.readings(file.data, layouts: layouts) }
        catch {
            Self.log.error("no readings for an unknown file: \(String(describing: error), privacy: .public)")
            return []
        }
    }

    /// A confirmed layout as it may be sent to us (`shareableLayout`), or nil when it may not: then the result offers
    /// nothing, and only the engine's reason is logged (never a value from the file).
    private func bankFormat(of layout: CsvLayout, read: BankFile) async -> BankFormat? {
        do {
            switch try await engine.shareableLayout(layout) {
            case let .shareable(shared):
                return BankFormat(layout: shared, key: BankFormat.key(of: layout), suggestion: read.bank?.name ?? layout.name)
            case let .notShareable(reason):
                Self.log.notice("a confirmed layout is not offered for sending: \(reason, privacy: .public)")
                return nil
            }
        } catch {
            Self.log.error("shareableLayout failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }

    private static let log = Logger(subsystem: "de.ares-empire.aresium", category: "formats")

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
    static func input(payments: [LedgerPayment], list: PhoneCategoryList, today: String,
                      receipts: [LedgerReceipt] = []) -> DashboardSourceInput {
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
        return DashboardSourceInput(transactions: transactions, categories: list.sourceCategories, today: today,
                                    receipts: receipts.isEmpty ? nil : receipts.map { source($0, named: named) })
    }

    /// A receipt as the engine counts it: in euros (a cash receipt in another currency with the euro amount typed for
    /// it); a card receipt in another currency keeps its currency, and the engine leaves it out until it is joined.
    static func source(_ receipt: LedgerReceipt, named: [String: String]) -> SourceReceipt {
        let euros = receipt.euros
        return SourceReceipt(id: receipt.id, date: receipt.date, total: euros ?? receipt.totalValue,
                             currency: euros == nil ? receipt.currency : ReceiptAmount.euro, method: receipt.method,
                             category: receipt.category.flatMap { named[$0] }, shop: receipt.shop,
                             paymentId: receipt.paymentID)
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
