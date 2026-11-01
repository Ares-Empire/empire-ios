import Foundation
import Testing
@testable import Aresium

@MainActor
@Suite(.serialized)
struct BatchChangesTests {
    private func payment(_ id: String, _ shop: String, amount: String = "-10.00", category: String? = nil,
                         source: CategorySource = .none, extras: [String] = [], own: String? = nil,
                         bank: String = "bank", day: String = "2026-10-02") -> LedgerPayment {
        LedgerPayment(id: id, account: "fictional-batch", source: bank, externalId: "fictional-" + id,
                      bookingDate: day, amount: amount, currency: "EUR", text: "Fictional purchase",
                      counterparty: shop, category: category, categorySource: source, extraCategories: extras,
                      sequence: Int(id.filter(\.isNumber)) ?? 0, ownName: own)
    }

    private func receipt(_ id: String, _ shop: String, entry: Bool = false, incoming: Bool = false,
                         category: String? = nil, total: String = "4.00", card: Bool = false) -> LedgerReceipt {
        LedgerReceipt(id: id, date: "2026-10-03", time: nil, shop: shop, total: total, currency: "EUR", euroAmount: nil,
                      method: card ? .card : .cash, category: category, categorySource: category == nil ? .none : .manual,
                      rows: [], from: "text", paymentID: nil, created: Date(timeIntervalSince1970: 1),
                      direction: incoming ? .in : .out, kind: entry ? .manual : .receipt)
    }

    private func setup(_ payments: [LedgerPayment], receipts: [LedgerReceipt] = [],
                       learned: [LearnedRule] = [], names: [PaymentNameRule] = [], engine: AresiumEngine? = nil)
        async throws -> (PhoneBackend, DashboardStore) {
        let phone = try await PhoneCountingTests.backend(engine: engine)
        let chosen = ["groceries", "hobbies", "household", "cash", "salary"].enumerated().map {
            ChosenCategory(id: $0.element, order: $0.offset)
        }
        try await phone.ledger.restore(LedgerExport(exported: "2026-10-30",
            accounts: [LedgerAccount(id: "fictional-batch", name: "Fictional batch bank")], payments: payments,
            categories: chosen, learned: learned, layouts: [], receipts: receipts, nameRules: names),
            catalog: #require(phone.catalog))
        try await phone.refresh()
        let store = DashboardStore(session: await PhoneTest.session(nil, transport: RoutedTransport()), backend: phone)
        await store.reload()
        #expect(store.error == nil)
        return (phone, store)
    }

    private func snapshot(_ phone: PhoneBackend) async throws -> LedgerExport {
        try await phone.ledger.export(on: Date(timeIntervalSince1970: 0))
    }

    @Test func selectableSumsReceiptsEntriesCoveredRowsAndSide() async throws {
        let (_, store) = try await setup([
            payment("p1", "Fictional Shop"), payment("p2", "Fictional Shop", amount: "-20.00"),
            payment("p3", "Geldautomat Fiktivbank", amount: "-100.00", category: "cash", source: .starter),
        ], receipts: [receipt("r1", "Fictional Receipt"), receipt("e1", "Fictional Entry", entry: true, total: "6.00"),
                      receipt("e2", "Fictional Gift", entry: true, incoming: true)])
        store.sums.setEverywhere(true)
        let list = store.paymentList(category: CategoryName.uncategorised, month: "2026-10", side: .expenses)
        #expect(store.offersSelection(in: list))
        let sum = try #require(list.entries.first { if case .summed = $0 { return true }; return false })
        #expect(store.selectionIDs(for: sum) == ["p1", "p2"])
        let ids = list.entries.reduce(into: Set<String>()) { $0.formUnion(store.selectionIDs(for: $1)) }
        #expect(ids == ["p1", "p2", "r1", "e1"])
        let summary = store.selectionSummary(ids.union(["stale"]))
        #expect(summary.counts == BatchCounts(bankPayments: 2, receipts: 1, cashEntries: 1))
        #expect(summary.count == 4 && summary.side == .expenses && summary.total == 40)
        #expect(summary.canSwitch && summary.canRename && summary.bankPayments == 2)
        let cash = store.paymentList(category: "Cash withdrawals", month: "2026-10", side: .expenses)
        let covered = try #require(cash.entries.first { entry in
            if case let .payment(row, _) = entry { return row.transaction.coveredBy != nil }; return false
        })
        #expect(store.selectionIDs(for: covered).isEmpty)
        #expect(store.selectableRows(in: cash).map(\.id) == ["p3"])
        let coveredOnly = PaymentList(rows: cash.rows.filter { $0.transaction.coveredBy != nil }, sums: { _ in false })
        #expect(!store.offersSelection(in: coveredOnly))
        #expect(store.selectionSummary([covered.id]).count == 0)
        #expect(!store.offersSelection(category: "Hobbies", month: "2026-09", side: .expenses))
        let incoming = store.selectionSummary(["e2"])
        #expect(incoming.side == .income && incoming.counts.cashEntries == 1 && !incoming.canRename)
        #expect(store.offeredCategories(for: ["e2"]).contains { $0.name == "Salary & side jobs" })
        #expect(!store.offeredCategories(for: ["e2"]).contains { $0.name == "Groceries" })
        store.phone?.setOwnNames(false)
        #expect(!store.selectionSummary(ids).canRename)
    }

    @Test func switchSeveralShopsAndApplyOneQuestionThenUndoBoth() async throws {
        let (phone, store) = try await setup([
            payment("p1", "MGP Vinted - Kleiderkreisel", extras: ["hobbies", "household"]),
            payment("p2", "Vinted, UAB", bank: "paypal"), payment("p3", "dm-drogerie markt"),
            payment("p4", "Vinted UAB"), payment("p5", "dm Drogeriemarkt", category: "groceries", source: .starter),
            payment("p6", "Vinted UAB", category: "groceries", source: .manual),
            payment("p7", "Vinted UAB", category: "groceries", source: .structural),
            payment("p8", "Vinted UAB", category: "groceries", source: .receipt),
            payment("p9", "Vinted UAB", category: CategoryCatalog.ownTransfers, source: .learned),
            payment("p10", "Vinted UAB", category: "hobbies", source: .starter),
        ], learned: [LearnedRule(merchant: "mgp vinted - kleiderkreisel", category: "household"),
                     LearnedRule(merchant: "vinted uab", category: "groceries"),
                     LearnedRule(merchant: "absent fictional shop", category: "household")])
        let before = try await snapshot(phone), revision = store.revision
        let result = try await store.switchCategory(ids: ["p1", "p2", "p3"], to: "Hobbies")
        #expect(store.revision == revision + 1 && result.changed.bankPayments == 3 && result.skipped.total == 0)
        let selected = try await phone.ledger.payments().filter { ["p1", "p2", "p3"].contains($0.id) }
        #expect(selected.allSatisfy { $0.category == "hobbies" && $0.categorySource == .manual })
        #expect(selected.first { $0.id == "p1" }?.extraCategories == ["household"])
        let keys = try await phone.engine.merchantKeys(selected.map { $0.sorting(raw: false) })
        let learned = try await phone.ledger.learned()
        #expect(keys.allSatisfy { learned[$0] == "hobbies" })
        let followUp = try #require(result.followUp)
        #expect(followUp.count == 2 && followUp.shopCount == 2 && followUp.shop == nil)
        #expect(followUp.question == "Also move 2 other payments from 2 shops?")
        let applied = try await followUp.apply()
        #expect(store.revision == revision + 2 && applied.changed.bankPayments == 2 && applied.undo === result.undo)
        let after = try await phone.ledger.payments()
        #expect(after.filter { ["p4", "p5"].contains($0.id) }.allSatisfy { $0.category == "hobbies" && $0.categorySource == .learned })
        for id in ["p6", "p7", "p8", "p9", "p10"] {
            #expect(after.first { $0.id == id } == before.payments.first { $0.id == id })
        }
        #expect(try await phone.ledger.learned()["vinted uab"] == "hobbies")
        #expect(try await result.undo.perform() == .undone)
        #expect(store.revision == revision + 3)
        #expect(try await snapshot(phone) == before)
        #expect(try await applied.undo.perform() == .unavailable)
        await #expect(throws: BatchChangeError.unavailable) { _ = try await followUp.apply() }
    }

    @Test func switchReceiptsLearnsTheirShopButCashEntriesDoNotAndUndoRestoresSources() async throws {
        let (phone, store) = try await setup([
            payment("p1", "Fictional Bank Shop", category: "household", source: .starter, extras: ["groceries"]),
            payment("p2", "Cobalt Receiptcorner"), payment("p3", "Juniper Picnic"),
        ], receipts: [receipt("r1", "Cobalt Receiptcorner", category: "household", card: true),
                      receipt("e1", "Juniper Picnic", entry: true, category: "household")],
            learned: [LearnedRule(merchant: "fictional bank shop", category: "household")])
        let before = try await snapshot(phone)
        let result = try await store.switchCategory(ids: ["p1", "r1", "e1"], to: "Groceries")
        #expect(result.changed == BatchCounts(bankPayments: 1, receipts: 1, cashEntries: 1))
        #expect(try await phone.ledger.receipts().allSatisfy { $0.category == "groceries" && $0.categorySource == .manual })
        let rules = try await phone.ledger.learned()
        #expect(rules["fictional bank shop"] == "groceries" && rules["cobalt receiptcorner"] == "groceries")
        #expect(rules["juniper picnic"] == nil)
        let followUp = try #require(result.followUp)
        #expect(followUp.count == 1 && followUp.shopCount == 1 && followUp.shop == "Cobalt Receiptcorner")
        #expect(followUp.question == "Also move 1 other payment from Cobalt Receiptcorner?")
        #expect(try await result.undo.perform() == .undone)
        #expect(try await snapshot(phone) == before)
    }

    @Test func addSkipsAlreadyPrimaryExtraReceiptsAndEntriesWithoutLearning() async throws {
        let (phone, store) = try await setup([
            payment("p1", "Fictional Shop", category: "household", source: .starter, extras: ["hobbies"]),
            payment("p2", "Fictional Shop", category: "groceries", source: .manual),
            payment("p3", "Fictional Shop", category: "household", source: .receipt, extras: ["groceries"]),
        ], receipts: [receipt("r1", "Fictional Receipt", category: "household"),
                      receipt("e1", "Fictional Entry", entry: true, category: "household")])
        let before = try await snapshot(phone), revision = store.revision
        let result = try await store.addCategory(ids: ["p1", "p2", "p3", "r1", "e1"], name: "Groceries")
        #expect(result.changed == BatchCounts(bankPayments: 1))
        #expect(result.skipped == BatchCounts(bankPayments: 2, receipts: 1, cashEntries: 1) && result.followUp == nil)
        #expect(result.message == "Groceries added to 1 payment · 4 skipped")
        let payment = try #require(try await phone.ledger.payment("p1"))
        #expect(payment.extraCategories == ["hobbies", "groceries"] && payment.categorySource == .starter)
        #expect(try await phone.ledger.learned().isEmpty)
        #expect(store.revision == revision + 1)
        #expect(try await result.undo.perform() == .undone)
        #expect(try await snapshot(phone) == before)
    }

    private func renameSetup() async throws -> (PhoneBackend, DashboardStore) {
        try await setup([
            payment("p1", "MGP Vinted - Kleiderkreisel", own: "Old own one"),
            payment("p2", "Vinted, UAB", own: "Old own two", bank: "paypal"),
            payment("p3", "dm-drogerie markt", own: "Old dm"), payment("p4", "PayPal", own: "Old keyless"),
            payment("p5", "Kleiderkreisel"), payment("p6", "dm Drogeriemarkt", own: "Other override"),
            payment("p7", "PayPal"),
        ], receipts: [receipt("r1", "Fictional Receipt"), receipt("e1", "Fictional Entry", entry: true)], names: [
            PaymentNameRule(merchant: "mgp vinted - kleiderkreisel", name: "Old exact Vinted"),
            PaymentNameRule(merchant: "vinted uab", name: "Second exact Vinted"),
            PaymentNameRule(merchant: "dm-drogerie markt", name: "Old shop dm"),
            PaymentNameRule(merchant: "absent fictional shop", name: "Keep absent"),
        ])
    }

    @Test func renameCountsDistinctIdentitiesAndKeylessHasNoOthers() async throws {
        let (_, store) = try await renameSetup()
        let info = try await store.renameInfo(ids: ["p1", "p2", "p3", "p4", "r1", "e1"])
        #expect(info.bankPaymentCount == 4 && info.shopCount == 2 && info.otherPaymentCount == 2 && info.allPaymentCount == 6)
        #expect(info.skipped == BatchCounts(receipts: 1, cashEntries: 1))
        #expect(try await store.renameInfo(ids: ["p4"]).otherPaymentCount == 0)
    }

    @Test func renamePaymentsAndEmptyNameLeaveShopRulesAndUndoExactly() async throws {
        let (phone, store) = try await renameSetup()
        let ids: Set<String> = ["p1", "p2", "p3", "p4", "r1", "e1"]
        let before = try await snapshot(phone)
        let name = String(repeating: "👩🏽‍🚀", count: 61)
        let result = try await store.rename(ids: ids, to: " \n" + name + "  ", scope: .payments)
        #expect(result.changed.bankPayments == 4 && result.skipped == BatchCounts(receipts: 1, cashEntries: 1))
        let after = try await snapshot(phone)
        #expect(after.payments.filter { ids.contains($0.id) }.allSatisfy { $0.ownName == String(name.prefix(60)) })
        #expect(after.nameRules == before.nameRules && after.receipts == before.receipts && after.learned == before.learned)
        #expect(try await result.undo.perform() == .undone)
        #expect(try await snapshot(phone) == before)
        let empty = try await store.rename(ids: ids, to: " \n ", scope: .payments)
        #expect(try await phone.ledger.payments().filter { ids.contains($0.id) }.allSatisfy { $0.ownName == nil })
        #expect(try await phone.ledger.paymentNames() == before.nameRules)
        #expect(try await empty.undo.perform() == .undone)
        #expect(try await snapshot(phone) == before)
    }

    @Test func renameShopsConsolidatesRulesDropsSelectedOverridesAndEmptyRemovesRules() async throws {
        let (phone, store) = try await renameSetup()
        let ids: Set<String> = ["p1", "p2", "p3", "p4", "r1", "e1"]
        let before = try await snapshot(phone), revision = store.revision
        let result = try await store.rename(ids: ids, to: "  One name\n", scope: .shops)
        let after = try await snapshot(phone)
        #expect(result.followUp == nil && store.revision == revision + 1)
        #expect(after.payments.filter { ["p1", "p2", "p3"].contains($0.id) }.allSatisfy { $0.ownName == nil })
        #expect(after.payments.first { $0.id == "p4" }?.ownName == "One name")
        #expect(after.payments.first { $0.id == "p6" }?.ownName == "Other override")
        #expect(after.nameRules.count == 3 && after.nameRules.filter { $0.name == "One name" }.count == 2)
        #expect(try await phone.renameInfo(id: "p5").shopOwnName == "One name")
        #expect(after.receipts == before.receipts)
        #expect(try await result.undo.perform() == .undone)
        #expect(try await snapshot(phone) == before)
        let empty = try await store.rename(ids: ids, to: "", scope: .shops)
        #expect(try await phone.ledger.paymentNames() == [PaymentNameRule(merchant: "absent fictional shop", name: "Keep absent")])
        #expect(try await phone.ledger.payments().filter { ids.contains($0.id) }.allSatisfy { $0.ownName == nil })
        #expect(try await empty.undo.perform() == .undone)
        #expect(try await snapshot(phone) == before)
    }

    @Test func undoAndFollowUpRefuseAfterSingleChangeAndChangeBackOrImport() async throws {
        let (phone, store) = try await setup([payment("p1", "Fictional Shop"), payment("p2", "Fictional Shop")])
        let result = try await store.switchCategory(ids: ["p1"], to: "Groceries")
        let question = try #require(result.followUp)
        let unchanged = try await snapshot(phone)
        try await phone.ledger.setCategory("p2", category: "hobbies", source: .manual)
        try await phone.ledger.setCategory("p2", category: nil, source: .none)
        #expect(try await snapshot(phone) == unchanged)
        #expect(try await result.undo.perform() == .unavailable, "revision catches a change even after its values are put back")
        await #expect(throws: BatchChangeError.unavailable) { _ = try await question.apply() }
        #expect(try await snapshot(phone) == unchanged)
        let second = try await store.addCategory(ids: ["p1"], name: "Hobbies")
        _ = try await phone.importFiles([PhoneTest.vrBank([("10.10.2026", "Fictional Other Shop", "Purchase", -123)])],
                                        auth: BackendAuth(token: nil))
        let imported = try await snapshot(phone)
        #expect(try await second.undo.perform() == .unavailable)
        #expect(try await snapshot(phone) == imported)
        #expect(BatchUndoOutcome.unavailable.message == "Cannot undo because the data changed.")
    }

    @Test func pendingFollowUpRefusesAfterAnotherChangeWithoutMovingAnything() async throws {
        let (phone, store) = try await setup([payment("p1", "Fictional Shop"), payment("p2", "Fictional Shop")])
        let result = try await store.switchCategory(ids: ["p1"], to: "Groceries")
        try await phone.ledger.setCategory("p2", category: "household", source: .manual)
        let before = try await snapshot(phone)
        await #expect(throws: BatchChangeError.changed) { _ = try await result.followUp?.apply() }
        #expect(try await snapshot(phone) == before)
    }

    @Test func categoriesOmitOnlyACommonPrimaryAndServerOffersNothing() async throws {
        let (_, store) = try await setup([payment("p1", "Fictional Shop", category: "groceries", source: .manual),
                                         payment("p2", "Fictional Shop", category: "hobbies", source: .manual)])
        #expect(!store.offeredCategories(for: ["p1"]).contains { $0.name == "Groceries" })
        #expect(store.offeredCategories(for: ["p1", "p2"]).contains { $0.name == "Groceries" })
        #expect(store.offeredCategories(for: []).isEmpty)
        let server = DashboardStore(session: await PhoneTest.session(nil, transport: RoutedTransport()), sample: true)
        await server.reload()
        let row = try #require(server.dashboard?.transactions.first)
        let entry = PaymentListEntry.payment(TransactionRow(transaction: row, tagged: false), addsUp: false)
        #expect(server.selectionIDs(for: entry).isEmpty && server.selectionSummary([row.id]).count == 0)
        #expect(server.offeredCategories(for: [row.id]).isEmpty)
        #expect(!server.offersSelection(in: PaymentList(rows: [TransactionRow(transaction: row, tagged: false)], sums: { _ in false })))
        await #expect(throws: BatchChangeError.unavailable) { _ = try await server.switchCategory(ids: [row.id], to: "Groceries") }
    }

    @Test func selectionValidationAndTourLedgerUseTheSameAPI() async throws {
        let (_, store) = try await setup([payment("p1", "Fictional Shop"), payment("p2", "Fictional Shop", amount: "10.00"),
                                         payment("p3", "Fictional Shop", day: "2026-09-02")])
        for ids: Set<String> in [[], ["missing"], ["p1", "p2"], ["p1", "p3"]] {
            await #expect(throws: BatchChangeError.invalidSelection) { _ = try await store.rename(ids: ids, to: "No", scope: .payments) }
        }
        let phone = try await PhoneSample.backend(empty: false, storage: PhoneTest.storage()).backend
        let tour = DashboardStore(session: await PhoneTest.session(nil, transport: RoutedTransport()), backend: phone)
        await tour.reload()
        let row = try #require(tour.dashboard?.transactions.first { $0.receiptId == nil && $0.coveredBy == nil && !$0.categoriesIn.isEmpty })
        let result = try await tour.rename(ids: [row.id], to: "Fictional tour name", scope: .payments)
        #expect(tour.dashboard?.transactions.first { $0.id == row.id }?.place == "Fictional tour name")
        #expect(try await result.undo.perform() == .undone)
    }

    @Test func fiveHundredRowsFromSixtyShopsInOneLedgerOperation() async throws {
        let payments = (0..<500).map { payment("p\($0)", "Batchshop\(Self.letters($0 % 60))fictive") }
        let engine = try await countingEngine()
        let (phone, _) = try await setup(payments, engine: engine)
        let ids = Set(payments.map(\.id))
        #expect(try await phone.renameInfo(ids: ids).shopCount == 60)
        let before = try await snapshot(phone)
        let sorts = try await engine.version()
        let recording = PickerTiming.Recording()
        let result = try await PickerTiming.$recording.withValue(recording) {
            try await phone.ledger.changeBatch(ids: ids, action: .switchCategory("Groceries"), engine: phone.engine,
                                               catalog: #require(phone.catalog))
        }
        let ms = try #require(recording.values.first { $0.name == "batch.change" }).ms
        let learns = recording.values.filter { $0.name == "batch.learn" }
        #expect(learns.count == 1 && learns.allSatisfy { $0.kind == "worker" })
        print("BATCH switch-500 / 60 shops: \(String(format: "%.3f", ms)) ms (ledger + batched engine learning + save + undo snapshots); learn bridge: \(String(format: "%.3f", learns.first?.ms ?? 0)) ms")
        #expect(result.changed.bankPayments == 500 && result.followUp == nil && result.undo.revision == 1)
        #expect(try await phone.ledger.learned().count == 60)
        #expect(try await engine.version() == sorts.replacingOccurrences(of: "learn=0", with: "learn=500"))
        #expect(ms < 300)
        #expect(try await phone.ledger.undoBatch(result.undo))
        #expect(try await snapshot(phone) == before)
    }

    private func countingEngine(failLearning: Bool = false) async throws -> AresiumEngine {
        let url = try #require(AresiumEngine.bundledScriptURL())
        let script = try String(contentsOf: url, encoding: .utf8) + """
        ;(() => {
            const E = globalThis.AresiumEngine;
            let learns = 0, sorts = 0;
            globalThis.AresiumEngine = {
                ...E,
                learn: (...args) => {
                    learns++;
                    if (\(failLearning ? "true" : "false") && learns === 2) throw new Error("Fictional learning failure");
                    return E.learn(...args);
                },
                sortPayments: (...args) => { sorts++; return E.sortPayments(...args); },
                get version() { return `learn=${learns},sort=${sorts}`; }
            };
        })();
        """
        return try await Task.detached { try AresiumEngine(script: script) }.value
    }

    @Test func failedLearningChangesNoRowsOrRules() async throws {
        let engine = try await countingEngine(failLearning: true)
        let (phone, store) = try await setup([payment("p1", "Fictional Shop"), payment("p2", "Fictional Other Shop")], engine: engine)
        let before = try await snapshot(phone), revision = store.revision
        await #expect(throws: EngineError.javascript("Fictional learning failure")) {
            _ = try await store.switchCategory(ids: ["p1", "p2"], to: "Groceries")
        }
        #expect(try await snapshot(phone) == before)
        #expect(store.revision == revision)
    }

    @Test func resultAndQuestionWordsInBothLanguages() {
        #expect(BatchWording.result(.addCategory, count: 1, category: "Groceries", skipped: BatchCounts(), language: .english)
                == "Groceries added to 1 payment")
        #expect(BatchWording.result(.switchCategory, count: 1, category: "Groceries", skipped: BatchCounts(), language: .english)
                == "1 payment moved to Groceries")
        #expect(BatchWording.result(.rename, count: 2, category: nil, skipped: BatchCounts(receipts: 1), language: .german)
                == "Name für 2 Buchungen geändert · 1 übersprungen")
        #expect(BatchWording.question(count: 1, shops: 1, shop: "Fiktiver Laden", language: .german)
                == "Auch 1 weitere Buchung von Fiktiver Laden verschieben?")
        #expect(BatchWording.question(count: 5, shops: 2, shop: nil, language: .german)
                == "Auch 5 weitere Buchungen von 2 Geschäften verschieben?")
    }

    private static func letters(_ index: Int) -> String {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyz")
        return String(alphabet[index / 26]) + String(alphabet[index % 26])
    }
}
