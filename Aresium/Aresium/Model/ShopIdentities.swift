import Foundation

/// A job's complete merchant universe. Unknown shop identities depend on the supplied keys, so every lookup uses
/// payments, receipts and both kinds of stored rule together. Stored rules and exports remain merchant-keyed.
nonisolated struct ShopIdentities: Sendable {
    let byKey: [String: String]

    func identity(_ key: String) -> String { byKey[key] ?? "" }

    /// Match the engine: exact first, then the lexical first valid rule of this identity.
    func rules(_ rules: [String: String], allowed: Set<String>? = nil) -> [String: String] {
        guard !rules.isEmpty else { return [:] }
        var byShop: [String: String] = [:]
        for key in rules.keys.sorted() {
            let shop = identity(key)
            guard !shop.isEmpty, let value = rules[key], allowed?.contains(value) ?? true else { continue }
            if byShop[shop] == nil { byShop[shop] = value }
        }
        return byKey.reduce(into: [:]) { result, item in
            guard !item.key.isEmpty else { return }
            result[item.key] = rules[item.key] ?? byShop[item.value]
        }
    }
}

nonisolated struct ShopSnapshot: Sendable {
    let payments: [LedgerPayment]
    let receipts: [LedgerReceipt]
    let paymentKeys: [String]
    let receiptKeys: [String]
    let names: [String: String]
    let learned: [String: String]
    let shops: ShopIdentities
}

extension PhoneLedger {
    /// One identity bridge call per job, over distinct keys only; large arrays stay on the ledger executor.
    func shopSnapshot(engine: AresiumEngine) async throws -> ShopSnapshot {
        assert(!Thread.isMainThread)
        let payments = try PickerTiming.measure("names.snapshot") { try self.payments() }
        let receipts = try receipts()
        let names = Dictionary(uniqueKeysWithValues: try paymentNames().map { ($0.merchant, $0.name) })
        let learned = try learned()
        let input = payments.map { $0.sorting(raw: false) } + receipts.map {
            SortingPayment(counterparty: $0.shop, description: $0.shop ?? "", source: "bank", account: "receipt",
                           amount: -$0.totalValue, currency: $0.currency, date: $0.date)
        }
        let keys = try await engine.merchantKeys(input)
        let distinct = Array(Set(keys + names.keys + learned.keys)).sorted()
        let identities = try await engine.shopIdentities(distinct)
        return ShopSnapshot(payments: payments, receipts: receipts,
                            paymentKeys: Array(keys.prefix(payments.count)),
                            receiptKeys: Array(keys.dropFirst(payments.count)), names: names, learned: learned,
                            shops: ShopIdentities(byKey: Dictionary(uniqueKeysWithValues: zip(distinct, identities))))
    }

    func otherShopPayments(of merchant: String, besides id: String, target: String,
                           engine: AresiumEngine) async throws -> (ids: [String], keys: [String]) {
        let snapshot = try await shopSnapshot(engine: engine)
        let identity = snapshot.shops.identity(merchant)
        guard !identity.isEmpty else { return ([], []) }
        let ids = zip(snapshot.payments, snapshot.paymentKeys).compactMap { payment, key in
            snapshot.shops.identity(key) == identity && payment.id != id
                && !CategorySource.keeps(payment.categorySource.rawValue)
                && payment.categorySource != .structural && payment.category != CategoryCatalog.ownTransfers
                && payment.category != target ? payment.id : nil
        }
        let keys = snapshot.shops.byKey.keys.filter { snapshot.shops.identity($0) == identity && !$0.isEmpty }.sorted()
        return (ids, keys)
    }

    /// The learned category for one shop (a receipt's preset). As the engine's `sortPayments` does for one payment:
    /// identities over this key and the learned keys only, so opening a receipt never reads every stored payment.
    func learnedCategory(for payment: SortingPayment, engine: AresiumEngine, catalog: CategoryCatalog) async throws -> String? {
        assert(!Thread.isMainThread)
        guard let key = try await engine.merchantKeys([payment]).first, !key.isEmpty else { return nil }
        let learned = try learned()
        let allowed = Set(PhoneCategoryList(catalog: catalog, chosen: try chosen()).sortingIDs)
        let distinct = Array(Set(learned.keys).union([key])).sorted()
        let shops = ShopIdentities(byKey: Dictionary(uniqueKeysWithValues: zip(distinct, try await engine.shopIdentities(distinct))))
        guard let category = shops.rules(learned, allowed: allowed)[key], allowed.contains(category) else { return nil }
        return category
    }
}
