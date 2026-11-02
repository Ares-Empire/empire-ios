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
    /// Newest non-card bank line that itself names the shop; nil when none qualifies. Independent of Own names.
    var shopBankName: String? = nil
    var bankDisplayName: String { shopBankName ?? bankName }
    var shopIdentity: String = ""
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

    /// Prefixes keep a person's name, an engine shop identity and an exact bank line in separate namespaces.
    static func key(ownName: String?, merchant: String, bankName: String) -> String {
        if let ownName {
            return "own:" + ownName.folding(options: [.caseInsensitive, .diacriticInsensitive],
                                           locale: Locale(identifier: "en_US_POSIX")).precomposedStringWithCanonicalMapping
        }
        return merchant.isEmpty ? "bank:" + bankName : "merchant:" + merchant
    }

    /// Newest qualifying booking date, then later store order. A line must itself name this shop according to the
    /// engine and not be a card statement, so neither a payment service nor a payment-specific card line names the shop.
    static func bankNames(payments: [LedgerPayment], keys: [String], bankLineIdentities: [String],
                          identities: ShopIdentities) -> [String: String] {
        assert(payments.count == keys.count && keys.count == bankLineIdentities.count)
        var newest: [String: LedgerPayment] = [:]
        for ((payment, key), lineIdentity) in zip(zip(payments, keys), bankLineIdentities) where !key.isEmpty {
            let identity = identities.identity(key)
            guard !identity.isEmpty, lineIdentity == identity else { continue }
            if newest[identity].map({ $0.bookingDate <= payment.bookingDate }) ?? true { newest[identity] = payment }
        }
        return newest.mapValues(\.place)
    }

    /// After the engine has finished counting: names never enter its sorting, receipt matching or cash allocation.
    static func apply(to dashboard: inout Dashboard, payments: [LedgerPayment], paymentKeys: [String], bankLineIdentities: [String],
                      receipts: [LedgerReceipt], receiptKeys: [String], rules: [String: String], identities: ShopIdentities, enabled: Bool) {
        assert(!Thread.isMainThread)
        let bank = Dictionary(uniqueKeysWithValues: zip(payments, paymentKeys).map { ($0.0.id, ($0.0, $0.1)) })
        let bankNames = bankNames(payments: payments, keys: paymentKeys, bankLineIdentities: bankLineIdentities, identities: identities)
        let shops = Dictionary(uniqueKeysWithValues: zip(receipts, receiptKeys).map { ($0.0.id, ($0.0, $0.1)) })
        for index in dashboard.transactions.indices {
            var row = dashboard.transactions[index]
            guard row.coveredBy == nil else { continue }
            if let receiptID = row.receiptId, let (receipt, merchant) = shops[receiptID] {
                // A receipt/entry keeps its editable Shop. Its identity joins the shop's bank payments.
                let own = enabled && !merchant.isEmpty ? rules[merchant] : nil
                row.nameKey = key(ownName: own, merchant: identities.identity(merchant), bankName: receipt.shop ?? row.place)
            } else if let (payment, merchant) = bank[row.id] {
                row.ledgerSequence = payment.sequence
                row.fixedCostKey = key(ownName: nil, merchant: merchant, bankName: payment.place)
                let own = enabled ? shown(payment: payment.ownName, shop: rules[merchant], bankName: payment.place) : nil
                row.place = own ?? (merchant.isEmpty ? nil : bankNames[identities.identity(merchant)]) ?? payment.place
                row.bankName = row.place == payment.place ? nil : payment.place
                row.isOwnName = own != nil
                row.ownNameSource = own == nil ? nil : payment.ownName == own ? .payment : .shop
                row.nameKey = key(ownName: own, merchant: identities.identity(merchant), bankName: payment.place)
            }
            dashboard.transactions[index] = row
        }
        if var cash = dashboard.cash {
            for index in cash.movements.indices {
                let movement = cash.movements[index]
                guard movement.kind == .withdrawal, let (payment, merchant) = bank[movement.id] else { continue }
                let own = enabled ? shown(payment: payment.ownName, shop: rules[merchant], bankName: payment.place) : nil
                cash.movements[index].place = own ?? (merchant.isEmpty ? nil : bankNames[identities.identity(merchant)]) ?? payment.place
            }
            dashboard.cash = cash
        }
        var grouped: [String: [Transaction]] = [:]
        for row in dashboard.transactions {
            // Mirror the engine's overall totals (brief 71): a payment counts as spending when it is in a spending list
            // and as income when it has an income row; a transfer has neither, whatever its extra categories.
            guard row.coveredBy == nil, let key = row.nameKey,
                  !row.categoriesIn.isEmpty || !row.incomeBuckets.isEmpty else { continue }
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
                let cents = Int((abs(row.countedAmount) * 100).rounded())
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
            // Keep every searchable spelling, including own names hidden by the display setting or an override.
            var names: [String] = []
            var seen = Set<String>()
            func add(_ name: String?) {
                if let name, !name.isEmpty, seen.insert(name).inserted { names.append(name) }
            }
            for row in sorted {
                add(row.place)
                if let (payment, merchant) = bank[row.id] {
                    add(payment.place)
                    add(payment.ownName)
                    add(rules[merchant])
                } else if let receiptID = row.receiptId, let (_, merchant) = shops[receiptID] {
                    add(rules[merchant])
                }
            }
            return PaymentNameGroup(rows: sorted, amounts: total, months: months, names: names)
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
            detail.place = own ?? info.bankDisplayName
            detail.bankName = detail.place == info.bankName ? nil : info.bankName
            detail.isOwnName = own != nil
            detail.ownNameSource = own == nil ? nil : info.source
            detail.nameKey = PaymentNames.key(ownName: own, merchant: info.shopIdentity, bankName: info.bankName)
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
        let snapshot = try await shopSnapshot(engine: engine)
        guard let index = snapshot.payments.firstIndex(where: { $0.id == id }) else { throw LedgerError.notFound }
        let payment = snapshot.payments[index]
        let merchant = snapshot.paymentKeys[index]
        let identity = snapshot.shops.identity(merchant)
        let rule = snapshot.shops.rules(snapshot.names)[merchant]
        let count = merchant.isEmpty ? 0 : zip(snapshot.payments, snapshot.paymentKeys).filter {
            $0.0.id != id && snapshot.shops.identity($0.1) == identity
        }.count
        let shopName = PaymentNames.bankNames(payments: snapshot.payments, keys: snapshot.paymentKeys,
                                              bankLineIdentities: snapshot.bankLineIdentities, identities: snapshot.shops)[identity]
        return PaymentRenameInfo(bankName: payment.place, merchantKey: merchant, paymentOwnName: payment.ownName,
                                 shopOwnName: rule, otherPaymentCount: count,
                                 shopBankName: merchant.isEmpty ? nil : shopName, shopIdentity: identity)
    }

    /// Engine revisions can shorten foreign-card keys. Keep absent shops, and move only obsolete name keys to
    /// their longest current whole-word prefix. An existing current rule wins; lexical old-key order breaks ties.
    func rebuildMerchantRules(engine: AresiumEngine) async throws {
        assert(!Thread.isMainThread)
        let all = try payments()
        let keys = try await engine.merchantKeys(all.map { $0.sorting(raw: false) })
        var learned: [String: String] = [:]
        for (payment, key) in zip(all, keys)
            where !key.isEmpty && payment.categorySource == .manual && payment.category != nil {
            learned[key] = payment.category
        }
        try remember(learned)
        let current = Set(keys.filter { !$0.isEmpty })
        let candidates = current.sorted { $0.count == $1.count ? $0 < $1 : $0.count > $1.count }
        let stored = try modelContext.fetch(FetchDescriptor<StoredPaymentName>(sortBy: [SortDescriptor(\.merchant)]))
        var occupied = Set(stored.map(\.merchant))
        for rule in stored where !current.contains(rule.merchant) {
            guard let key = candidates.first(where: { rule.merchant.hasPrefix($0 + " ") }) else { continue }
            if !occupied.contains(key) {
                modelContext.insert(StoredPaymentName(merchant: key, name: rule.name))
                occupied.insert(key)
            }
            modelContext.delete(rule)
        }
        try moveFixedCostMarks(current: current)
        try modelContext.save()
    }

    func rename(id: String, name: String, scope: PaymentNameScope, engine: AresiumEngine) async throws {
        assert(!Thread.isMainThread)
        guard try payment(id) != nil else { throw LedgerError.notFound }
        let normalized = PickerTiming.measure("names.normalize") { PaymentNames.normalized(name) }
        switch scope {
        case .payment:
            let stored = try modelContext.fetch(FetchDescriptor<StoredPayment>(predicate: #Predicate { $0.id == id })).first
            stored?.ownName = normalized.isEmpty ? nil : normalized
        case .shop:
            let snapshot = try await shopSnapshot(engine: engine)
            guard let index = snapshot.payments.firstIndex(where: { $0.id == id }) else { throw LedgerError.notFound }
            let merchant = snapshot.paymentKeys[index]
            guard !merchant.isEmpty else { throw LedgerError.notFound }
            let identity = snapshot.shops.identity(merchant)
            let rules = try modelContext.fetch(FetchDescriptor<StoredPaymentName>())
            for rule in rules where rule.merchant != merchant && snapshot.shops.identity(rule.merchant) == identity {
                modelContext.delete(rule)
            }
            let stored = rules.first { $0.merchant == merchant }
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
    /// Search hits and name routes already carry the opaque group key.
    func nameGroup(_ key: String) -> PaymentNameGroup? { dashboard?.nameGroups?[key] }

    func nameGroup(for transaction: Transaction) -> PaymentNameGroup? {
        transaction.nameKey.flatMap { nameGroup($0) }
    }
}
