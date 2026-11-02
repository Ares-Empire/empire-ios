import Foundation
import Testing
@testable import Aresium

@MainActor
struct ShopIdentityTests {
    private let auth = BackendAuth(token: nil)

    private func phone() async throws -> PhoneBackend {
        let phone = try await PhoneCountingTests.backend(chosen: ["groceries", "hobbies", "household"])
        _ = try await phone.importFiles([PhoneTest.vrBank([
            ("01.02.2026", "MGP Vinted - Kleiderkreisel", "Fictional purchase", -1000),
            ("02.10.2026", "Vinted, UAB", "Fictional purchase", -2000),
            ("03.10.2026", "dm-drogerie markt", "Fictional purchase", -3000),
            ("04.10.2026", "dm Drogeriemarkt", "Fictional purchase", -4000),
            ("05.10.2026", "Erika Mustermann", "Fictional purchase", -5000),
            ("06.10.2026", "Mustermann Erika", "Fictional purchase", -6000),
            ("07.10.2026", "Apple", "Fictional purchase", -7000),
            ("08.10.2026", "Applebee's", "Fictional purchase", -8000),
        ]), paypal()], auth: auth)
        return phone
    }

    private func paypal() -> ImportFile {
        ImportFile(name: "fictional-identity-paypal.csv", data: Data("""
        Datum,Name,Typ,Währung,Brutto,Netto,Transaktionscode,Auswirkung auf Guthaben
        09.10.2026,"Vinted, UAB",Allgemeine Zahlung,EUR,"-9,00","-9,00",FICTIONAL-VINTED,Debit
        10.10.2026,dm Drogeriemarkt,Allgemeine Zahlung,EUR,"-11,00","-11,00",FICTIONAL-DM,Debit
        """.utf8))
    }

    @Test func bankLineProbesShareTheNameJobAndNeverBecomeRuleKeys() async throws {
        let phone = try await PhoneCountingTests.backend()
        _ = try await phone.importFiles([PhoneTest.vrBank([
            ("01.10.2026", "Fictional Payment Service", "Purchase from Fictional Shop", -1000)])], auth: auth)
        try await phone.ledger.addReceipt(LedgerReceipt(id: "probe-receipt", date: "2026-10-02", time: nil,
                shop: "Fictional Receipt Shop", total: "2.00", currency: "EUR", euroAmount: nil, method: .cash,
                category: nil, categorySource: .none, rows: [], from: "text", paymentID: nil, created: .now))
        let engine = try AresiumEngine(script: """
        let merchantCalls = 0, identityCalls = 0, cardCalls = 0;
        globalThis.AresiumEngine = {
            merchantKey: row => {
                const index = merchantCalls++;
                if (index > 2 ||
                    (index === 0 && (row.counterparty !== "Fictional Payment Service" || !row.description)) ||
                    (index === 1 && row.counterparty !== "Fictional Receipt Shop") ||
                    (index === 2 && (row.counterparty !== "Fictional Payment Service" || row.description !== ""))) {
                    throw new Error("Expected full payment, receipt and line-only probe in order");
                }
                return ["payment key", "receipt key", "line-only key"][index];
            },
            cardMerchant: line => {
                if (++cardCalls !== 1 || line !== "Fictional Payment Service") {
                    throw new Error("Expected the original line in the engine card-statement check");
                }
                return null;
            },
            shopIdentities: keys => {
                if (cardCalls !== 1 || merchantCalls !== 3 || ++identityCalls !== 1 || keys.join("|") !== "line-only key|payment key|receipt key") {
                    throw new Error("Expected one complete identity universe");
                }
                return keys.map(key => key === "receipt key" ? "receipt shop" : "payment shop");
            }
        };
        """)
        let snapshot = try await phone.ledger.shopSnapshot(engine: engine)
        #expect(snapshot.paymentKeys == ["payment key"] && snapshot.receiptKeys == ["receipt key"])
        #expect(snapshot.bankLineIdentities == ["payment shop"])
        #expect(snapshot.shops.byKey == ["payment key": "payment shop", "receipt key": "receipt shop"],
                "probe keys cannot enter the set of keys used for learning or name rules")
    }

    @Test func bridgePreservesOrderDuplicatesAndSeparatesNearMisses() async throws {
        let engine = try await AresiumEngine.bundledForPhone()
        let keys = ["mgp vinted - kleiderkreisel", "vinted uab", "dm-drogerie markt", "dm drogeriemarkt",
                    "erika mustermann", "mustermann erika", "apple", "applebee's", "", "vinted uab"]
        let identities = try await engine.shopIdentities(keys)
        #expect(identities.count == keys.count)
        #expect(identities[0] == identities[1] && identities[1] == identities[9])
        #expect(identities[2] == identities[3] && identities[4] == identities[5])
        #expect(identities[6] != identities[7] && identities[8].isEmpty)
        #expect(try await engine.shopIdentities([]).isEmpty)
        let bad = try AresiumEngine(script: "globalThis.AresiumEngine = { shopIdentities: () => [] };")
        await #expect(throws: EngineError.invalidAnswer("shopIdentities: wrong count")) {
            _ = try await bad.shopIdentities(["fictional shop"])
        }
        let wrongType = try AresiumEngine(script: "globalThis.AresiumEngine = { shopIdentities: () => [7] };")
        await #expect(throws: EngineError.self) { _ = try await wrongType.shopIdentities(["fictional shop"]) }
    }

    @Test func groupsDetailsRenameAndReceiptsShareOneShop() async throws {
        let phone = try await phone()
        let payments = try await phone.ledger.payments()
        let first = payments[0], other = payments[1]
        let before = try await phone.dashboard(auth: auth)
        let group = try #require(before.nameGroups?["merchant:vinted"])
        #expect(group.count == 3 && group.moneyOut == 39)
        #expect(before.nameGroups?.values.contains { $0.count == 3 && $0.moneyOut == 81 } == true)
        #expect(before.nameGroups?.values.contains { $0.count == 2 && $0.moneyOut == 110 } == true)
        let apple = try #require(before.transactions.first { $0.place == "Apple" })
        let bees = try #require(before.transactions.first { $0.place == "Applebee's" })
        #expect(apple.nameKey != bees.nameKey)
        let info = try await phone.renameInfo(id: first.id)
        #expect(info.otherPaymentCount == 2)
        _ = try await phone.rename(id: first.id, name: "Second hand", scope: .shop)
        #expect(try await phone.renameInfo(id: other.id).shopOwnName == "Second hand")
        #expect(try await phone.transactionDetail(id: other.id, auth: auth).nameKey == "own:second hand")
        _ = try await phone.saveReceipt(ReceiptDraft(date: "2026-10-12", shop: "Vinted UAB", total: 4,
                            currency: "EUR", method: .cash, category: "hobbies", categorySource: .manual,
                            rows: [], from: "text"))
        let named = try await phone.dashboard(auth: auth)
        #expect(named.nameGroups?["own:second hand"]?.count == 4)
        #expect(named.nameGroups?["own:second hand"]?.moneyOut == 43)
        #expect(named.transactions.first { $0.receiptId != nil }?.place == "Vinted UAB")
        phone.setOwnNames(false)
        #expect(try await phone.dashboard(auth: auth).nameGroups?["merchant:vinted"]?.count == 4)
        #expect(try await phone.transactionDetail(id: other.id, auth: auth).nameKey == "merchant:vinted")
        phone.setOwnNames(true)
        _ = try await phone.rename(id: other.id, name: "Gift", scope: .payment)
        _ = try await phone.rename(id: first.id, name: "", scope: .shop)
        #expect(try await phone.ledger.paymentNames().isEmpty)
        #expect(try await phone.renameInfo(id: other.id).ownName == "Gift")
    }

    @Test func conflictingNameRulesAreExactFirstThenLexicalAndShopRenameConsolidates() async throws {
        let source = try await phone()
        var export = try await source.export()
        let keys = try await source.engine.merchantKeys(export.payments.map { $0.sorting(raw: false) })
        export.nameRules = [PaymentNameRule(merchant: keys[1], name: "New exact"),
                            PaymentNameRule(merchant: keys[0], name: "Old exact")]
        let target = try await PhoneCountingTests.backend()
        try await target.restore(export.encoded())
        let first = export.payments[0], second = export.payments[1]
        #expect(try await target.renameInfo(id: first.id).shopOwnName == "Old exact")
        #expect(try await target.renameInfo(id: second.id).shopOwnName == "New exact")
        _ = try await target.importFiles([PhoneTest.vrBank([
            ("15.10.2026", "Kleiderkreisel", "Fictional purchase", -1300),
        ])], auth: auth)
        let third = try #require(try await target.ledger.payments().last)
        let lexical = zip([keys[0], keys[1]], ["Old exact", "New exact"]).sorted { $0.0 < $1.0 }.first!.1
        #expect(try await target.renameInfo(id: third.id).shopOwnName == lexical)
        let dashboard = try await target.dashboard(auth: auth)
        #expect(dashboard.transactions.first { $0.id == third.id }?.place == lexical)
        _ = try await target.rename(id: second.id, name: "One shop", scope: .shop)
        #expect(try await target.ledger.paymentNames() == [PaymentNameRule(merchant: keys[1], name: "One shop")])
        #expect(try await target.renameInfo(id: first.id).shopOwnName == "One shop")
        _ = try await target.rename(id: third.id, name: "", scope: .shop)
        #expect(try await target.ledger.paymentNames().isEmpty)
    }

    @Test func categoryQuestionCountEqualsMovedAndAllReplacesConflictingExactRules() async throws {
        let phone = try await phone()
        _ = try await phone.importFiles([PhoneTest.vrBank([
            ("16.10.2026", "Kleiderkreisel", "Fictional manual", -1600),
            ("17.10.2026", "Vinted UAB", "Fictional transfer", -1700),
            ("18.10.2026", "Vinted UAB", "Fictional receipt", -1800),
            ("19.10.2026", "Vinted UAB", "Already in target", -1900),
        ])], auth: auth)
        let payments = try await phone.ledger.payments()
        let first = payments[0]
        let keys = try await phone.engine.merchantKeys(payments.map { $0.sorting(raw: false) })
        try await phone.ledger.remember([keys[0]: "household", keys[1]: "household", "vinted": "groceries"])
        try await phone.ledger.setCategory(payments[10].id, category: "groceries", source: .manual)
        try await phone.ledger.setCategory(payments[11].id, category: CategoryCatalog.ownTransfers, source: .structural)
        try await phone.ledger.setCategory(payments[12].id, category: "groceries", source: .receipt)
        try await phone.ledger.setCategory(payments[13].id, category: "hobbies", source: .starter)
        let result = try await phone.switchCategory(id: first.id, to: "Hobbies", auth: auth)
        let question = try #require(result.followUp)
        let before = try await phone.ledger.payments()
        let learnedBefore = try await phone.ledger.learned()
        #expect(learnedBefore[keys[1]] == "household", "Only this one has not consolidated the shop")
        #expect(question.count == 2)
        try await question.apply()
        let after = try await phone.ledger.payments()
        let changed = zip(before, after).filter { $0.category != $1.category }
        #expect(changed.count == question.count)
        #expect(Set(changed.map { $0.0.id }) == Set([payments[1].id, payments[8].id]))
        #expect(after[10].category == "groceries" && after[11].category == CategoryCatalog.ownTransfers)
        #expect(after[12].category == "groceries" && after[13].category == "hobbies")
        let learned = try await phone.ledger.learned()
        #expect(learned[keys[0]] == "hobbies" && learned[keys[1]] == "hobbies" && learned["vinted"] == "hobbies")
        _ = try await phone.importFiles([PhoneTest.vrBank([
            ("20.10.2026", "Vinted, UAB", "Fictional next", -2000),
            ("21.10.2026", "MGP Vinted - Kleiderkreisel", "Fictional next", -2100),
        ])], auth: auth)
        #expect(try await phone.ledger.payments().suffix(2).allSatisfy { $0.category == "hobbies" && $0.categorySource == .learned })
    }

    @Test func receiptLearnedCategoryUsesExactThenValidLexicalFallback() async throws {
        let phone = try await phone()
        let payments = try await phone.ledger.payments()
        let keys = try await phone.engine.merchantKeys(payments.map { $0.sorting(raw: false) })
        try await phone.ledger.remember([keys[0]: "hobbies", keys[1]: "household"])
        #expect(try await phone.learnedCategory(forShop: "Vinted, UAB") == "household")
        #expect(try await phone.learnedCategory(forShop: "Kleiderkreisel") == "hobbies")
        #expect(try await phone.learnedCategory(forShop: "Applebee's") == nil)
        try await phone.ledger.remember(["kleiderkreisel": "not-chosen"])
        #expect(try await phone.learnedCategory(forShop: "Kleiderkreisel") == nil, "Invalid exact rule blocks fallback")
        try await phone.ledger.remember([keys[0]: "not-chosen"])
        #expect(try await phone.learnedCategory(forShop: "Vinted") == "household", "Invalid fallback rules are skipped")
    }
    @Test func eachLookupBatchesAllDistinctKeysOnceOnWorkers() async throws {
        let source = try await phone()
        var export = try await source.export()
        export.nameRules = [PaymentNameRule(merchant: "fictional absent name", name: "My absent shop")]
        export.learned = [LearnedRule(merchant: "fictional absent learned", category: "hobbies")]
        let url = try #require(AresiumEngine.bundledScriptURL())
        let script = try String(contentsOf: url, encoding: .utf8) + """
        ;(() => {
            const original = globalThis.AresiumEngine;
            let calls = 0, last = [];
            globalThis.AresiumEngine = {
                ...original,
                shopIdentities: keys => { calls++; last = keys; return original.shopIdentities(keys); },
                get version() { return JSON.stringify({ calls, keys: last }); }
            };
        })();
        """
        let engine = try await Task.detached { try AresiumEngine(script: script) }.value
        let target = try await PhoneCountingTests.backend(engine: engine)
        try await target.restore(export.encoded())
        try await target.ledger.addReceipt(LedgerReceipt(id: "fictional-identity-batch", date: "2026-10-22", time: nil,
                shop: "Fictional Receipt Only", total: "2.00", currency: "EUR", euroAmount: nil, method: .cash,
                category: "hobbies", categorySource: .manual, rows: [], from: "text", paymentID: nil, created: .now))
        struct Calls: Decodable { let calls: Int; let keys: [String] }
        func calls() async throws -> Calls {
            try JSONDecoder().decode(Calls.self, from: Data(try await engine.version().utf8))
        }
        let recording = PickerTiming.Recording()
        var renameKeys: [String] = []
        try await PickerTiming.$recording.withValue(recording) {
            _ = try await target.dashboard(auth: auth)
            #expect(try await calls().calls == 1)
            _ = try await target.renameInfo(id: export.payments[0].id)
            #expect(try await calls().calls == 2)
            renameKeys = try await calls().keys
            _ = try await target.learnedCategory(forShop: "Vinted")
            #expect(try await calls().calls == 3)
        }
        // A rename looks at every key: payments, receipts and both kinds of stored rule.
        #expect(renameKeys.count == Set(renameKeys).count)
        #expect(Set(["fictional absent name", "fictional absent learned", "fictional receipt only"])
                    .isSubset(of: Set(renameKeys)))
        // A receipt's preset only its own key and the learned keys, as sortPayments does for one payment.
        let last = try await calls()
        #expect(last.keys.count == Set(last.keys).count)
        let learned = try await target.ledger.learned()
        #expect(learned["fictional absent learned"] != nil)
        #expect(Set(last.keys) == Set(learned.keys).union(["vinted"]))
        let spans = recording.values.filter { $0.name == "names.identities" }
        #expect(spans.count == 3 && spans.allSatisfy { $0.kind == "worker" })
    }

    @Test func changedEngineMigratesForeignCardNamesAndRebuildsLearnedKeys() async throws {
        let defaults = PhoneTest.defaults()
        let old = try await PhoneCountingTests.backend(chosen: ["hobbies"], defaults: defaults, version: "old")
        _ = try await old.importFiles([PhoneTest.vrBank([
            ("01.10.2026", "FIKTIVSHOP  USA MUSTERSTADT USD 7,43 KURS: 1,1234 Umsatz vom 30.09.2026", "Purchase", -662),
            ("02.10.2026", "FIKTIVSHOP PLUS  USA MUSTERSTADT USD 8,43 KURS: 1,1234 Umsatz vom 01.10.2026", "Purchase", -750),
            ("03.10.2026", "EXAKTSHOP  USA MUSTERSTADT USD 9,43 KURS: 1,1234 Umsatz vom 02.10.2026", "Purchase", -839),
        ])], auth: auth)
        var export = try await old.export()
        let keys = try await old.engine.merchantKeys(export.payments.map { $0.sorting(raw: false) })
        #expect(keys == ["fiktivshop", "fiktivshop plus", "exaktshop"])
        export.payments[0].category = "hobbies"
        export.payments[0].categorySource = .manual
        export.learned = [LearnedRule(merchant: "fiktivshop usa musterstadt usd 7 43 kurs: 1 1234 umsatz vom", category: "hobbies")]
        export.nameRules = [
            PaymentNameRule(merchant: "fiktivshop usa musterstadt usd 7 43 kurs: 1 1234 umsatz vom", name: "Card shop"),
            PaymentNameRule(merchant: "fiktivshop plus usa musterstadt usd 8 43 kurs: 1 1234 umsatz vom", name: "Longer prefix"),
            PaymentNameRule(merchant: "exaktshop usa musterstadt usd 9 43 kurs: 1 1234 umsatz vom", name: "Obsolete"),
            PaymentNameRule(merchant: "exaktshop", name: "Current exact"),
            PaymentNameRule(merchant: "fiktivshopping", name: "No word boundary"),
            PaymentNameRule(merchant: "absent shop", name: "Keep absent"),
        ]
        // Restore directly to represent the store before a bundle change (backend restore also migrates).
        let target = try await PhoneCountingTests.backend(chosen: [], defaults: defaults, version: "old")
        try await target.ledger.restore(export, catalog: #require(target.catalog))
        let updated = PhoneBackend(ledger: target.ledger, engine: target.engine, defaults: defaults, engineVersion: { "new" })
        try await updated.load()
        let names = Dictionary(uniqueKeysWithValues: try await updated.ledger.paymentNames().map { ($0.merchant, $0.name) })
        #expect(names == ["fiktivshop": "Card shop", "fiktivshop plus": "Longer prefix", "exaktshop": "Current exact",
                          "fiktivshopping": "No word boundary", "absent shop": "Keep absent"])
        #expect(try await updated.ledger.learned()["fiktivshop"] == "hobbies")
        #expect(try await updated.renameInfo(id: export.payments[0].id).shopOwnName == "Card shop")
        try await updated.load()
        #expect(try await updated.ledger.paymentNames().count == 5)
        _ = try await updated.importFiles([PhoneTest.vrBank([
            ("20.10.2026", "FIKTIVSHOP  USA MUSTERSTADT USD 12,43 KURS: 1,1234 Umsatz vom 19.10.2026", "Purchase", -1106),
        ])], auth: auth)
        let next = try #require(try await updated.ledger.payments().last)
        #expect(next.category == "hobbies" && next.categorySource == .learned)
        #expect(try await updated.transactionDetail(id: next.id, auth: auth).place == "Card shop")
    }

    @Test func phoneSampleKeepsDashboardGroupsNamesAndCounts() async throws {
        let phone = try await PhoneSample.backend(empty: false, storage: PhoneTest.storage()).backend
        let payments = try await phone.ledger.payments()
        let keys = try await phone.engine.merchantKeys(payments.map { $0.sorting(raw: false) })
        let before = try await phone.dashboard(auth: auth)
        let list = try await phone.categories()
        let original = try await phone.engine.dashboard(PhoneDashboard.input(payments: payments, list: list,
                                                                            today: phone.today(), receipts: []))
        // Display names are applied after counting. Restore original names before comparing all engine fields.
        let originals = Dictionary(uniqueKeysWithValues: original.transactions.map { ($0.id, $0.place) })
        var counted = before
        counted.nameGroups = nil
        for index in counted.transactions.indices {
            counted.transactions[index].nameKey = nil
            counted.transactions[index].isOwnName = nil
            counted.transactions[index].place = originals[counted.transactions[index].id] ?? counted.transactions[index].place
            counted.transactions[index].bankName = nil
            counted.transactions[index].ledgerSequence = nil
            counted.transactions[index].fixedCostKey = nil
            counted.transactions[index].purpose = nil           // brief 99's text, added after counting too
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        #expect(try encoder.encode(counted) == encoder.encode(original))
        let kinds = Dictionary(original.categories.map { ($0.name, $0.kind) }, uniquingKeysWith: { first, _ in first })
        let eligible = Set(original.transactions.filter {
            $0.coveredBy == nil && (kinds[$0.categoryName] == .spend || !$0.incomeBuckets.isEmpty)
        }.map(\.id))
        let allKeys = zip(payments, keys).map { ($0.0.id, $0.1) }
        let expected = Dictionary(grouping: allKeys.filter { eligible.contains($0.0) }, by: { $0.1 })
        let allCounts = Dictionary(grouping: allKeys, by: { $0.1 })
        let snapshot = try await phone.ledger.shopSnapshot(engine: phone.engine)
        for group in try #require(before.nameGroups).values {
            let row = try #require(group.rows.first)
            let index = try #require(payments.firstIndex { $0.id == row.id })
            let key = keys[index]
            #expect(group.count == expected[key]?.count)
            for row in group.rows {
                let identity = snapshot.shops.identity(key)
                let newest = zip(zip(snapshot.payments, snapshot.paymentKeys), snapshot.bankLineIdentities).filter {
                    snapshot.shops.identity($0.0.1) == identity && $0.1 == identity
                }.last?.0.0
                #expect(row.place == (key.isEmpty ? originals[row.id] : newest?.place ?? originals[row.id]))
            }
            #expect(try await phone.renameInfo(id: row.id).otherPaymentCount == (allCounts[key]?.count ?? 1) - 1)
        }
    }

}
