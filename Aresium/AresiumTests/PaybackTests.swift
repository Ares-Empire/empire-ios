import Foundation
import SwiftData
import Testing
@testable import Aresium

@MainActor
@Suite(.serialized)
struct PaybackTests {
    private let auth = BackendAuth(token: nil)

    private func payment(_ id: String, _ amount: String, day: String = "2026-10-10", name: String? = nil,
                         category: String? = "other", links: [LedgerPayback]? = nil) -> LedgerPayment {
        LedgerPayment(id: id, account: "fictional-paybacks", source: "bank", externalId: "fictional-" + id,
                      bookingDate: day, amount: amount, currency: "EUR", text: "Fictional payment " + id,
                      counterparty: name ?? "Fictional " + id, category: category,
                      categorySource: category == nil ? .none : .manual, extraCategories: [], sequence: 0, paysBack: links)
    }

    private func setup(_ payments: [LedgerPayment], engine: AresiumEngine? = nil) async throws -> (PhoneBackend, DashboardStore) {
        let phone = try await PhoneCountingTests.backend(engine: engine)
        let chosen = ["other", "groceries", "savings-investing", "salary", "cash"].enumerated().map { ChosenCategory(id: $0.element, order: $0.offset) }
        try await phone.ledger.restore(LedgerExport(exported: "2026-10-30",
            accounts: [LedgerAccount(id: "fictional-paybacks", name: "Fictional Bank")], payments: payments,
            categories: chosen, learned: [], layouts: []), catalog: #require(phone.catalog))
        try await phone.refresh()
        let store = DashboardStore(session: await PhoneTest.session(nil, transport: RoutedTransport()), backend: phone)
        await store.reload()
        #expect(store.error == nil)
        return (phone, store)
    }

    private func clean(_ phone: PhoneBackend) async throws {
        #expect(try await phone.dashboard(auth: auth).paybacksIgnored?.isEmpty != false)
    }

    @Test func countedNumbersAndDetailsAtBothEndsAndUndo() async throws {
        var expense = payment("trip", "-120.00", day: "2026-09-30", name: "Fictional Trip", category: "groceries")
        expense.extraCategories = ["other"]
        let (phone, store) = try await setup([expense, payment("in", "60.00", day: "2026-10-01", name: "Robin Example", category: "salary")])
        let revision = store.revision
        let undo = try await store.setPayback(from: "in", to: "trip", amount: 60)
        #expect(store.revision == revision + 1)
        let dashboard = try #require(store.dashboard)
        #expect(dashboard.total.expense == 60 && dashboard.total.income == 0)
        #expect(dashboard.byMonth["2026-09"]?.expense == 60 && dashboard.byMonth["2026-10"]?.income == 0)
        #expect(dashboard.total.categories.first { $0.name == "Groceries" }?.total == 60)
        #expect(dashboard.total.categories.first { $0.name == "Other" }?.total == 60)
        let out = try #require(dashboard.transactions.first { $0.id == "trip" })
        let incoming = try #require(dashboard.transactions.first { $0.id == "in" })
        #expect(out.amount == -120 && out.countedAmount == -60 && out.paidBack == 60)
        #expect(incoming.amount == 60 && incoming.countedAmount == 0 && !incoming.incomeBuckets.isEmpty)
        let group = try #require(out.nameKey.flatMap { dashboard.nameGroups?[$0] })
        #expect(group.moneyOut == 60 && group.months["2026-09"]?.moneyOut == 60)
        let hits = store.searchNames("Fictional Trip")
        #expect(hits.first?.moneyOut == 60)
        let rows = [TransactionRow(transaction: out, tagged: false), TransactionRow(transaction: out, tagged: false)]
        #expect(SummedPayments(key: "fictional", rows: rows).total == -120)
        #expect(store.day("2026-09-30").expenses.total == 60)
        #expect(store.day("2026-10-01").income.total == 0)
        #expect(store.selectionSummary(["trip"]).total == 60)
        #expect(store.selectionSummary(["in"]).total == 0 && store.selectionSummary(["in"]).side == .income)
        let detail = try await phone.transactionDetail(id: "trip", auth: auth)
        #expect(detail.amount == -120 && detail.countedAmount == -60 && detail.paidBack == 60)
        #expect(detail.paidBackBy == [PaybackDetailLink(payment: "in", place: "Robin Example", date: "2026-10-01", amount: 60, linkedAmount: 60)])
        let other = try await phone.transactionDetail(id: "in", auth: auth)
        #expect(other.paysBackTotal == 60 && other.countedAmount == 0)
        #expect(other.paysBack?.first?.payment == "trip" && other.paysBack?.first?.amount == -120)
        #expect(try await store.paybackState(for: "trip")?.rest == 60)
        #expect(try await store.paybackState(for: "in")?.rest == 0)
        try await clean(phone)
        #expect(try await undo.perform() == .undone)
        #expect(store.revision == revision + 2 && store.dashboard?.total.expense == 120 && store.dashboard?.total.income == 60)
        #expect(try await undo.perform() == .unavailable)
        try await clean(phone)
    }

    @Test func limitsCentsChangeRemoveAndStaleUndo() async throws {
        let (phone, store) = try await setup([payment("out", "-100.00"), payment("out2", "-60.00"),
                                            payment("in", "80.00"), payment("in2", "90.00")])
        _ = try await store.setPayback(from: "in", to: "out", amount: 60)
        await #expect(throws: PaybackError.payerLimit) { _ = try await store.setPayback(from: "in", to: "out2", amount: 20.01) }
        await #expect(throws: PaybackError.expenseLimit) { _ = try await store.setPayback(from: "in2", to: "out", amount: 40.01) }
        for value in [0, -1, 0.001, 20.005, Double.infinity, Double.nan] {
            await #expect(throws: PaybackError.invalidAmount) { _ = try await store.setPayback(from: "in", to: "out", amount: value) }
        }
        for (from, to) in [("out", "in"), ("in", "in2"), ("in", "in"), ("missing", "out")] {
            await #expect(throws: PaybackError.invalidPayment) { _ = try await store.setPayback(from: from, to: to, amount: 1) }
        }
        let change = try await store.setPayback(from: "in", to: "out", amount: 79.99)
        #expect(try await store.paybackState(for: "in")?.rest == 0.01)
        #expect(try await change.perform() == .undone)
        #expect(try await store.paybackState(for: "in")?.rest == 20)
        _ = try await store.setPayback(from: "in", to: "out2", amount: 20)
        _ = try await store.setPayback(from: "in2", to: "out", amount: 40)
        #expect(try await store.paybackState(for: "out")?.rest == 0)
        let removed = try await store.removePayback(from: "in", to: "out")
        #expect(try await store.paybackState(for: "out")?.rest == 60)
        #expect(try await removed.perform() == .undone)
        #expect(try await store.paybackState(for: "out")?.rest == 0)
        let stale = try await store.removePayback(from: "in", to: "out2")
        try await phone.ledger.setCategory("out2", category: "groceries", source: .manual)
        #expect(try await stale.perform() == .unavailable)
        try await clean(phone)
    }

    @Test func suggestionsFitsWindowExclusionsAndDeterministicDateTies() async throws {
        let (phone, store) = try await setup([
            payment("in", "60.00", day: "2026-10-11"), payment("half", "-120.00"),
            payment("whole", "-60.00", day: "2026-10-09"), payment("third", "-180.00", day: "2026-10-08"),
            payment("quarter", "-240.00", day: "2026-10-07"), payment("none", "-87.00", day: "2026-10-11"),
            payment("too-old", "-120.00", day: "2026-01-01"), payment("too-new", "-120.00", day: "2026-12-01"),
            payment("transfer", "-120.00", category: "savings-investing"),
            payment("withdrawal", "-120.00", name: "Geldautomat Fiktivbank", category: "cash"),
            payment("used", "-60.00"), payment("payer", "60.00", links: [LedgerPayback(payment: "used", amount: "60.00")])])
        let hits = try await store.paybackSuggestions(for: "in")
        #expect(hits.prefix(4).map(\.id) == ["half", "whole", "third", "quarter"])
        #expect(hits.prefix(4).map(\.fit) == [.half, .whole, .third, .quarter])
        #expect(hits.first?.amount == 60 && hits.first { $0.id == "none" }?.fit == nil)
        #expect(!hits.contains { ["used", "payer", "transfer", "withdrawal", "too-old", "too-new", "in"].contains($0.id) })
        #expect(try await store.paybackState(for: "transfer") == nil)
        #expect(try await store.paybackState(for: "withdrawal") == nil)
        #expect(try await store.paybackSuggestions(for: "half").first?.id == "in")
        try await clean(phone)

        let (_, ties) = try await setup([payment("in", "60.00", day: "2026-10-11"),
                                        payment("before", "-120.00", day: "2026-10-10"),
                                        payment("after", "-120.00", day: "2026-10-12")])
        #expect(try await ties.paybackSuggestions(for: "in").map(\.id) == ["after", "before"])
    }

    @Test func restFitOneCentAndSearchEveryMatchingPaymentOutsideWindow() async throws {
        let (phone, store) = try await setup([payment("out", "-100.00", day: "2025-01-01", name: "Fictional Course"),
            payment("old", "40.00", day: "2025-01-02", links: [LedgerPayback(payment: "out", amount: "40.00")]),
            payment("in", "60.00", day: "2026-10-10", name: "Robin Example"),
            payment("in2", "60.01", day: "2026-10-11", name: "Robin Example")])
        #expect(try await store.paybackSuggestions(for: "out").isEmpty)
        let search = try await store.paybackSearch("robin", for: "out")
        #expect(search.map(\.id) == ["in2", "in"] && search.allSatisfy { $0.fit == .rest && $0.amount == 60 })
        #expect(try await store.paybackSearch("fictional course", for: "in").first?.id == "out")
        #expect(try await store.paybackSearch("", for: "out").isEmpty)
        _ = try await phone.rename(id: "in", name: "Course instalment", scope: .payment)
        #expect(try await phone.paybackSearch("instalment", for: "out").map(\.id) == ["in"])
        phone.setOwnNames(false)
        #expect(try await phone.paybackSearch("instalment", for: "out").map(\.id) == ["in"])
        _ = try await phone.rename(id: "in", name: "Course repayments", scope: .shop)
        #expect(try await phone.paybackSearch("repayments", for: "out").map(\.id) == ["in2", "in"])
        try await clean(phone)
    }

    @Test func transferSwitchAtEitherEndBatchQuickSortAndCategoryRemovalUndoRestoreLinks() async throws {
        for id in ["in", "out"] {
            let (phone, store) = try await setup([payment("out", "-120.00"), payment("in", "60.00")])
            _ = try await store.setPayback(from: "in", to: "out", amount: 60)
            let before = try await phone.export()
            let result = try await phone.switchCategory(id: id, to: "Savings & investing", auth: auth)
            #expect(try await phone.ledger.payment("in")?.paysBack == nil)
            try await clean(phone)
            #expect(try await result.undo?.perform() == .undone)
            #expect(try await phone.export().payments == before.payments)
            try await clean(phone)
            let batch = try await store.switchCategory(ids: [id], to: "Savings & investing", span: .allMonths)
            #expect(try await phone.ledger.payment("in")?.paysBack == nil)
            #expect(try await batch.undo.perform() == .undone)
            try await clean(phone)
        }
        let (phone, store) = try await setup([payment("out", "-120.00"), payment("in", "60.00")])
        _ = try await store.setPayback(from: "in", to: "out", amount: 60)
        let undo = try await phone.unchoose("other", moveTo: "savings-investing")
        #expect(try await phone.ledger.payment("in")?.paysBack == nil)
        try await clean(phone)
        #expect(try await undo.perform() == .undone)
        #expect(try await phone.ledger.payment("in")?.paysBack == [LedgerPayback(payment: "out", amount: "60.00")])
        try await clean(phone)
    }

    @Test func quickSortUsesCountedAmountAndServerOffersNothing() async throws {
        let (_, store) = try await setup([payment("out", "-120.00", category: nil), payment("in", "60.00", category: nil)])
        _ = try await store.setPayback(from: "in", to: "out", amount: 60)
        #expect(store.quickSortGroups.first { $0.ids.contains("out") }?.total == 60)
        #expect(store.quickSortGroups.first { $0.ids.contains("in") }?.total == 0)
        let server = DashboardStore(session: await PhoneTest.session(nil, transport: RoutedTransport()), sample: true)
        await server.reload()
        #expect(try await server.paybackState(for: "any") == nil)
        #expect(try await server.paybackSuggestions(for: "any").isEmpty)
        #expect(try await server.paybackSearch("name", for: "any").isEmpty)
        await #expect(throws: BatchChangeError.unavailable) { _ = try await server.setPayback(from: "in", to: "out", amount: 1) }
    }

    @Test func exportSevenRoundTripSixWithoutLinksAndDuplicateImportKeepsThem() async throws {
        let phone = try await PhoneCountingTests.backend(chosen: ["other"])
        let file = PhoneTest.vrBank([("10.10.2026", "Fictional Trip", "Trip", -12000),
                                     ("11.10.2026", "Robin Example", "Half of trip", 6000)])
        _ = try await phone.importFiles([file], auth: auth)
        let payments = try await phone.ledger.payments()
        let out = try #require(payments.first { $0.amountValue < 0 }), incoming = try #require(payments.first { $0.amountValue > 0 })
        _ = try await phone.setPayback(from: incoming.id, to: out.id, amount: 60)
        let before = try await phone.export()
        #expect(before.schema == 7)
        let decoded = try LedgerExport.decode(before.encoded())
        #expect(decoded == before && decoded.payments.first { $0.id == incoming.id }?.paysBack?.first?.amount == "60.00")
        let copy = try await PhoneCountingTests.backend()
        try await copy.restore(decoded.encoded())
        #expect(try await copy.export().payments == before.payments)
        try await clean(copy)
        _ = try await phone.importFiles([file], auth: auth)
        #expect(try await phone.export().payments == before.payments)
        try await clean(phone)
        var six = before
        six.schema = 6
        for index in six.payments.indices { six.payments[index].paysBack = nil }
        let old = try LedgerExport.decode(six.encoded())
        let restored = try await PhoneCountingTests.backend()
        try await restored.restore(old.encoded())
        #expect(try await restored.export().payments.allSatisfy { $0.paysBack == nil })
        #expect(try await restored.dashboard(auth: auth).total.expense == 120)
    }

    @Test func setChangeRemoveAndUndoSaveAndRebuildOnceEach() async throws {
        let script = try String(contentsOf: #require(AresiumEngine.bundledScriptURL()), encoding: .utf8) + """
        ;(() => {
            const E = globalThis.AresiumEngine;
            let dashboards = 0;
            globalThis.AresiumEngine = { ...E,
                buildDashboard: (...args) => { dashboards++; return E.buildDashboard(...args); },
                get version() { return String(dashboards); }
            };
        })();
        """
        let engine = try await Task.detached { try AresiumEngine(script: script) }.value
        let (phone, store) = try await setup([payment("out", "-120.00"), payment("in", "60.00")], engine: engine)
        var builds = try await engine.version(), saves = await phone.ledger.paybackTestRevision()
        let undo = try await store.setPayback(from: "in", to: "out", amount: 30)
        #expect(try await engine.version() == String((Int(builds) ?? 0) + 1))
        #expect(await phone.ledger.paybackTestRevision() == saves + 1)
        builds = try await engine.version(); saves = await phone.ledger.paybackTestRevision()
        _ = try await phone.transactionDetail(id: "out", auth: auth)
        #expect(try await engine.version() == builds, "detail reuses the same engine result")
        #expect(try await undo.perform() == .undone)
        #expect(try await engine.version() == String((Int(builds) ?? 0) + 1))
        #expect(await phone.ledger.paybackTestRevision() == saves + 1)
        _ = try await store.setPayback(from: "in", to: "out", amount: 30)
        for amount: Double? in [40, nil] {
            builds = try await engine.version(); saves = await phone.ledger.paybackTestRevision()
            if let amount { _ = try await store.setPayback(from: "in", to: "out", amount: amount) }
            else { _ = try await store.removePayback(from: "in", to: "out") }
            #expect(try await engine.version() == String((Int(builds) ?? 0) + 1))
            #expect(await phone.ledger.paybackTestRevision() == saves + 1)
        }
    }

    @Test func pureRankingWindowBoundariesResultCapAndUncappedSearch() throws {
        func candidate(_ id: String, amount: Double, day: String, rest: Double? = nil) -> PaybackCandidate {
            let transaction = Transaction(id: id, date: day, day: Int(day.suffix(2))!, month: String(day.prefix(7)),
                amount: amount, categoryName: "Other", tags: [], place: "Fictional Course", city: "",
                categoriesIn: amount < 0 ? ["Other"] : [], incomeBuckets: amount > 0 ? ["Other"] : [])
            return PaybackCandidate(transaction: transaction, state: PaybackState(direction: amount > 0 ? .moneyIn : .moneyOut,
                rest: rest ?? abs(amount)), names: ["Fictional Course", "Former bank line"])
        }
        let expense = candidate("out", amount: -120, day: "2026-05-01")
        let boundaries = [candidate("before", amount: 60, day: "2026-04-01"),
                          candidate("after", amount: 60, day: "2026-08-29"),
                          candidate("early", amount: 60, day: "2026-03-31"),
                          candidate("late", amount: 60, day: "2026-08-30")]
        #expect(Set(Paybacks.suggestions(for: expense, in: boundaries).map(\.id)) == ["before", "after"])
        #expect(Paybacks.search("former bank", for: expense, in: boundaries).count == 4)
        #expect(Paybacks.suggestions(for: boundaries[0], in: [expense]).first?.id == "out")
        let many = (0..<60).map { candidate("in-\($0)", amount: 60, day: "2026-05-02") }
        #expect(Paybacks.suggestions(for: expense, in: many).count == 8)
        #expect(Paybacks.search("fictional", for: expense, in: many).count == 60)
        #expect(Paybacks.suggestion(candidate("cent", amount: 59.99, day: "2026-05-02"), for: expense)?.fit == .half)
        #expect(Paybacks.suggestion(candidate("fraction", amount: 33.33, day: "2026-05-02"),
                                    for: candidate("third", amount: -100, day: "2026-05-01"))?.fit == .third)
    }

    @Test func versionSixStoreMigratesAndSevenPersistsLinksWhenReopened() async throws {
        let storage = PhoneTest.storage()
        try FileManager.default.createDirectory(at: storage.directory, withIntermediateDirectories: true)
        var oldPayment = payment("out", "-120.00")
        oldPayment.raw = .null
        try await Task.detached {
            let schema = Schema(versionedSchema: LedgerSchemaV6.self)
            let config = ModelConfiguration("Aresium", schema: schema, url: storage.storeURL, cloudKitDatabase: .none)
            let container = try ModelContainer(for: schema, configurations: config)
            let context = ModelContext(container)
            context.insert(LedgerSchemaV6.Account(id: "fictional-paybacks", name: "Fictional Bank", iban: nil, bank: nil, currency: "EUR"))
            context.insert(LedgerSchemaV6.Payment(oldPayment))
            context.insert(LedgerSchemaV6.Chosen(id: "other", customName: nil, order: 0))
            try context.save()
        }.value
        let ledger = try await Task.detached { try storage.open() }.value
        #expect(try await ledger.payment("out") == oldPayment)
        let phone = PhoneBackend(ledger: ledger, engine: try await AresiumEngine.bundledForPhone(), defaults: PhoneTest.defaults())
        try await phone.load()
        _ = try await phone.importFiles([PhoneTest.vrBank([("11.10.2026", "Robin Example", "Half of trip", 6000)])], auth: auth)
        let incoming = try #require(try await ledger.payments().first { $0.amountValue > 0 })
        _ = try await phone.setPayback(from: incoming.id, to: "out", amount: 60)
        let reopened = try await Task.detached { try storage.open() }.value
        #expect(try await reopened.payment(incoming.id)?.paysBack == [LedgerPayback(payment: "out", amount: "60.00")])
        #expect(try await reopened.export().schema == 7)
        try await clean(phone)
    }

    @Test func rawEngineReportsIgnoredLinksAndRestoreRejectsThemBeforeWriting() async throws {
        let (phone, _) = try await setup([payment("out", "-120.00", name: "Geldautomat Fiktivbank", category: "cash"),
                                         payment("in", "60.00")])
        var file = try await phone.export()
        let index = try #require(file.payments.firstIndex { $0.id == "in" })
        file.payments[index].paysBack = [LedgerPayback(payment: "out", amount: "60.00")]
        let list = try await phone.categories()
        let raw = try await phone.engine.dashboard(PhoneDashboard.input(payments: file.payments, list: list, today: phone.today()))
        #expect(raw.paybacksIgnored?.first?.reason == "target-withdrawal")
        let empty = try await PhoneCountingTests.backend()
        await #expect(throws: LedgerError.invalidExport("ignored payback")) { try await empty.restore(file.encoded()) }
        #expect(try await empty.ledger.summary().isEmpty)
        for links in [[LedgerPayback(payment: "missing", amount: "1.00")],
                      [LedgerPayback(payment: "out", amount: "0.001")],
                      [LedgerPayback(payment: "out", amount: "60.01")],
                      [LedgerPayback(payment: "out", amount: "40.00"), LedgerPayback(payment: "out", amount: "20.00")]] {
            file.payments[index].paysBack = links
            await #expect(throws: (any Error).self) { try await empty.restore(file.encoded()) }
            #expect(try await empty.ledger.summary().isEmpty)
        }
    }

    @Test func receiptCashRowsAndForeignCurrencyCannotParticipate() async throws {
        let (phone, store) = try await setup([payment("out", "-120.00"), payment("in", "60.00")])
        _ = try await phone.saveReceipt(ReceiptDraft(date: "2026-10-10", shop: "Fictional Receipt", total: 20,
            currency: "EUR", method: .cash, category: "other", categorySource: .manual, rows: [], from: "text"))
        let receipt = try #require(try await phone.ledger.receipts().first)
        let cash = try await phone.addCashEntry(CashEntryDraft(direction: .in, amount: 60, date: "2026-10-11", what: "Fictional gift"))
        await store.reloadAfterTransactionChange()
        #expect(try await store.paybackState(for: receipt.id) == nil)
        #expect(try await store.paybackState(for: cash.id) == nil)
        await #expect(throws: PaybackError.invalidPayment) { _ = try await store.setPayback(from: cash.id, to: "out", amount: 1) }
        await #expect(throws: PaybackError.invalidPayment) { _ = try await store.setPayback(from: "in", to: receipt.id, amount: 1) }
        var foreign = payment("foreign", "-120.00")
        // Currency is immutable on ledger values, just as on a bank payment; use a separate fixture.
        foreign = LedgerPayment(id: "foreign", account: foreign.account, source: "bank", externalId: "fictional-foreign",
            bookingDate: foreign.bookingDate, amount: foreign.amount, currency: "USD", text: foreign.text,
            category: "other", categorySource: .manual, extraCategories: [], sequence: 0)
        let (_, foreignStore) = try await setup([foreign, payment("in", "60.00")])
        #expect(try await foreignStore.paybackState(for: "foreign") == nil)
        try await clean(phone)
    }

    @Test func widgetAndMonthlyReviewReadTheEngineNumbers() async throws {
        let (phone, store) = try await setup([payment("out", "-120.00", category: "groceries"), payment("in", "60.00")])
        _ = try await store.setPayback(from: "in", to: "out", amount: 60)
        let dashboard = try #require(store.dashboard)
        let widget = try #require(WidgetSnapshot(dashboard: dashboard, phone: true))
        #expect(widget.expense == 60 && widget.dayExpenseRunning.last == 60)
        #expect(widget.categories.first { $0.name == "Groceries" }?.total == 60)
        var preferences = MessagePreferences()
        preferences.enabled = true
        preferences.importReminder = false
        var history = MessageHistory()
        history.accountImports["fictional-paybacks"] = try #require(ReceiptDay.date("2026-11-01"))
        let plan = MessagePlan.requests(preferences: preferences, history: history, context: MessageContext(phone: true, language: .english),
            dashboard: dashboard, accountsByMonth: ["2026-10": ["fictional-paybacks"]],
            now: try #require(ReceiptDay.date("2026-11-02")), calendar: ReceiptDay.calendar)
        #expect(plan.count == 1 && plan[0].body == "October: 60 € spent, 0 € in. Most on Groceries: 60 €.")
        try await clean(phone)
    }

    @Test func sampleTripIsLinkedAndNextDayAndIgnoredAlwaysEmpty() async throws {
        let world = try await TourWorld.make(in: PhoneTest.storage().root, now: #require(ReceiptDay.date("2026-11-02")))
        let dashboard = try #require(world.dashboard.dashboard)
        let trip = try #require(dashboard.transactions.first { $0.place == TourData.paybackTripName })
        let payer = try #require(dashboard.transactions.first { $0.place == TourData.paybackPersonName })
        #expect(trip.amount == -128 && trip.countedAmount == -64 && payer.countedAmount == 0)
        let tripDate = try #require(ReceiptDay.date(trip.date)), payerDate = try #require(ReceiptDay.date(payer.date))
        #expect(ReceiptDay.calendar.dateComponents([.day], from: tripDate, to: payerDate).day == 1)
        #expect(dashboard.paybacksIgnored == nil)
    }
}

extension PhoneLedger {
    func paybackTestRevision() -> UInt64 { batchObserver().value }
}
