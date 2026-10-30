import Foundation
import SwiftData

nonisolated enum PaymentNameScope: Sendable { case shop, payment }

nonisolated struct PaymentNameRule: Codable, Equatable, Sendable {
    let merchant: String
    let name: String
}

/// The rename window's starting values, independent of the display setting. Nil in server mode.
nonisolated struct PaymentRenameInfo: Equatable, Sendable {
    let bankName: String
    let merchantKey: String
    /// The payment's own stored name, as stored: also the bank's name kept for this payment (`keepsBankName`).
    let paymentOwnName: String?
    let shopOwnName: String?
    let otherPaymentCount: Int
    /// The own name the payment shows (`PaymentNames.shown`); nil while it shows the bank's name.
    var ownName: String? { PaymentNames.shown(payment: paymentOwnName, shop: shopOwnName, bankName: bankName) }
    var source: PaymentNameSource? {
        guard ownName != nil else { return nil }
        return paymentOwnName != nil ? .payment : .shop
    }
    /// "Use the bank's name" → Only this one (brief 47): this payment shows the bank's name while its shop keeps its name.
    var keepsBankName: Bool { paymentOwnName != nil && ownName == nil }
    var canRename: Bool { true } // Only produced for a stored bank/PayPal payment.
    var canRenameShop: Bool { !merchantKey.isEmpty }
}

nonisolated enum PaymentNames {
    static let maximumLength = 60

    /// Trim, then keep at most 60 extended grapheme clusters. Empty removes the selected scope's name.
    static func normalized(_ typed: String) -> String {
        String(typed.trimmingCharacters(in: .whitespacesAndNewlines).prefix(maximumLength))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The own name a payment shows: its own, else its shop's. A payment's own name equal to its bank's name (as names
    /// are kept, `keptBankName`) is "Use the bank's name" → Only this one (brief 47): the payment shows the bank's name
    /// and counts with it (its key is the bank's), while the shop's name stays on its other payments. Export and restore
    /// carry it as any own name.
    static func shown(payment: String?, shop: String?, bankName: String) -> String? {
        guard let payment else { return shop }
        return payment == keptBankName(bankName) ? nil : payment
    }

    /// What Only this one stores as the payment's own name: the bank's name as a name is kept (trimmed, at most 60
    /// characters). Empty for a bank line without words, where it cannot be kept.
    static func keptBankName(_ bankName: String) -> String { normalized(bankName) }

    /// Prefixes keep a person's name, an engine key and an exact bank line in separate namespaces.
    static func key(ownName: String?, merchant: String, bankName: String) -> String {
        if let ownName {
            return "own:" + ownName.folding(options: [.caseInsensitive, .diacriticInsensitive],
                                           locale: Locale(identifier: "en_US_POSIX")).precomposedStringWithCanonicalMapping
        }
        return merchant.isEmpty ? "bank:" + bankName : "merchant:" + merchant
    }

    /// After the engine has finished counting: names never enter its sorting, receipt matching or cash allocation.
    static func apply(to dashboard: inout Dashboard, payments: [LedgerPayment], paymentKeys: [String],
                      receipts: [LedgerReceipt], receiptKeys: [String], rules: [String: String], enabled: Bool) {
        assert(!Thread.isMainThread)
        let bank = Dictionary(uniqueKeysWithValues: zip(payments, paymentKeys).map { ($0.0.id, ($0.0, $0.1)) })
        let shops = Dictionary(uniqueKeysWithValues: zip(receipts, receiptKeys).map { ($0.0.id, ($0.0, $0.1)) })
        for index in dashboard.transactions.indices {
            var row = dashboard.transactions[index]
            guard row.coveredBy == nil else { continue }
            if let receiptID = row.receiptId, let (receipt, merchant) = shops[receiptID] {
                // A receipt/entry keeps its editable Shop. Its identity joins the shop's bank payments.
                let own = enabled && !merchant.isEmpty ? rules[merchant] : nil
                row.nameKey = key(ownName: own, merchant: merchant, bankName: receipt.shop ?? row.place)
            } else if let (payment, merchant) = bank[row.id] {
                let own = enabled ? shown(payment: payment.ownName, shop: rules[merchant], bankName: payment.place) : nil
                row.place = own ?? payment.place
                row.bankName = row.place == payment.place ? nil : payment.place
                row.isOwnName = own != nil
                row.ownNameSource = own == nil ? nil : payment.ownName == own ? .payment : .shop
                row.nameKey = key(ownName: own, merchant: merchant, bankName: payment.place)
            }
            dashboard.transactions[index] = row
        }
        if var cash = dashboard.cash {
            for index in cash.movements.indices {
                let movement = cash.movements[index]
                guard movement.kind == .withdrawal, let (payment, merchant) = bank[movement.id] else { continue }
                let own = enabled ? shown(payment: payment.ownName, shop: rules[merchant], bankName: payment.place) : nil
                cash.movements[index].place = own ?? payment.place
            }
            dashboard.cash = cash
        }
        let kinds = Dictionary(dashboard.categories.map { ($0.name, $0.kind) }, uniquingKeysWith: { first, _ in first })
        var grouped: [String: [Transaction]] = [:]
        for row in dashboard.transactions {
            // Mirror the engine's overall totals: extra categories never make an excluded payment count.
            guard row.coveredBy == nil, let key = row.nameKey,
                  kinds[row.categoryName] == .spend || !row.incomeBuckets.isEmpty else { continue }
            grouped[key, default: []].append(row)
        }
        let emptyMonths = Dictionary(uniqueKeysWithValues: dashboard.months.map { ($0.key, PaymentNameAmounts()) })
        dashboard.nameGroups = grouped.mapValues { rows in
            var total = PaymentNameAmounts()
            var months = emptyMonths
            // Integer cents match the dashboard's euro precision without accumulating floating point errors.
            var out = 0, incoming = 0
            var monthOut: [String: Int] = [:], monthIn: [String: Int] = [:]
            for row in rows {
                let cents = Int((abs(row.amount) * 100).rounded())
                if row.amount < 0 { out += cents; monthOut[row.month, default: 0] += cents }
                else { incoming += cents; monthIn[row.month, default: 0] += cents }
            }
            total.moneyOut = Double(out) / 100
            total.moneyIn = Double(incoming) / 100
            for month in months.keys {
                months[month] = PaymentNameAmounts(moneyOut: Double(monthOut[month, default: 0]) / 100,
                                                  moneyIn: Double(monthIn[month, default: 0]) / 100)
            }
            // Stable ties preserve the engine's import order on the same day.
            let sorted = rows.enumerated().sorted {
                $0.element.date == $1.element.date ? $0.offset < $1.offset : $0.element.date > $1.element.date
            }.map(\.element)
            return PaymentNameGroup(rows: sorted, amounts: total, months: months)
        }
    }
}

extension PhoneLedger {
    func namedDetail(id: String, engine: AresiumEngine, catalog: CategoryCatalog,
                     language: AppLanguage, enabled: Bool) async throws -> TransactionDetail {
        guard let payment = try payment(id) else { throw LedgerError.notFound }
        let info = try await renameInfo(id: id, engine: engine)
        return try PickerTiming.measure("names.detail") {
            let list = PhoneCategoryList(catalog: catalog, chosen: try chosen(), language: language)
            var detail = PhoneDashboard.detail(payment, account: try account(payment.account), list: list)
            let own = enabled ? info.ownName : nil
            detail.place = own ?? info.bankName
            detail.bankName = detail.place == info.bankName ? nil : info.bankName
            detail.isOwnName = own != nil
            detail.ownNameSource = own == nil ? nil : info.source
            detail.nameKey = PaymentNames.key(ownName: own, merchant: info.merchantKey, bankName: info.bankName)
            return detail
        }
    }

    func paymentNames() throws -> [PaymentNameRule] {
        try modelContext.fetch(FetchDescriptor<StoredPaymentName>(sortBy: [SortDescriptor(\.merchant)]))
            .map { PaymentNameRule(merchant: $0.merchant, name: $0.name) }
    }

    /// Fetching, key construction, counting and the lifetime of the full payment array stay on the ledger worker.
    func renameInfo(id: String, engine: AresiumEngine) async throws -> PaymentRenameInfo {
        assert(!Thread.isMainThread)
        let all = try PickerTiming.measure("names.snapshot") { try payments() }
        guard let payment = all.first(where: { $0.id == id }) else { throw LedgerError.notFound }
        let keys = try await engine.merchantKeys(all.map { $0.sorting(raw: false) })
        let merchant = keys[all.firstIndex(where: { $0.id == id })!]
        let rule = try paymentNames().first { $0.merchant == merchant }?.name
        let count = merchant.isEmpty ? 0 : zip(all, keys).filter { $0.0.id != id && $0.1 == merchant }.count
        return PaymentRenameInfo(bankName: payment.place, merchantKey: merchant, paymentOwnName: payment.ownName,
                                 shopOwnName: rule, otherPaymentCount: count)
    }

    func rename(id: String, name: String, scope: PaymentNameScope, engine: AresiumEngine) async throws {
        assert(!Thread.isMainThread)
        guard let payment = try payment(id) else { throw LedgerError.notFound }
        let normalized = PickerTiming.measure("names.normalize") { PaymentNames.normalized(name) }
        switch scope {
        case .payment:
            let stored = try modelContext.fetch(FetchDescriptor<StoredPayment>(predicate: #Predicate { $0.id == id })).first
            stored?.ownName = normalized.isEmpty ? nil : normalized
        case .shop:
            let merchant = try await engine.merchantKeys([payment.sorting(raw: false)])[0]
            guard !merchant.isEmpty else { throw LedgerError.notFound }
            let stored = try modelContext.fetch(FetchDescriptor<StoredPaymentName>(predicate: #Predicate { $0.merchant == merchant })).first
            if normalized.isEmpty {
                if let stored { modelContext.delete(stored) }
            } else if let stored { stored.name = normalized }
            else { modelContext.insert(StoredPaymentName(merchant: merchant, name: normalized)) }
        }
        try modelContext.save()
    }
}

extension PhoneBackend {
    static let ownNamesKey = "aresium.ownNames"

    func renameInfo(id: String) async throws -> PaymentRenameInfo { try await ledger.renameInfo(id: id, engine: engine) }

    /// Save only; the detail store rebuilds the dashboard as category changes do.
    func rename(id: String, name: String, scope: PaymentNameScope) async throws -> TransactionDetail {
        try await ledger.rename(id: id, name: name, scope: scope, engine: engine)
        try await refresh()
        return try await transactionDetail(id: id, auth: BackendAuth(token: nil))
    }
}

extension DashboardStore {
    var ownNames: Bool { phone?.ownNames ?? true }

    /// Settings must use this call so the dashboard and widget rebuild after the preference changes.
    func setOwnNames(_ enabled: Bool) async {
        guard let phone, phone.ownNames != enabled else { return }
        phone.setOwnNames(enabled)
        await reloadAfterTransactionChange()
    }

    /// O(1) access to the group built with the dashboard; nil for excluded rows and server mode.
    func nameGroup(for transaction: Transaction) -> PaymentNameGroup? {
        transaction.nameKey.flatMap { dashboard?.nameGroups?[$0] }
    }
}
