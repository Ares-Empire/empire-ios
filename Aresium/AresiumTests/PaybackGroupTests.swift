import Foundation
import Testing
@testable import Aresium

@MainActor
@Suite(.serialized)
struct PaybackGroupTests {
    private func candidate(_ id: String, _ amount: Double, date: String = "2026-10-10", rest: Double? = nil,
                           links: [PaymentLink]? = nil) -> PaybackCandidate {
        var row = Transaction(id: id, date: date, day: Int(date.suffix(2))!, month: String(date.prefix(7)), amount: amount,
            categoryName: "Other", tags: [], place: "Fictional Course", city: "", categoriesIn: amount < 0 ? ["Other"] : [],
            incomeBuckets: amount > 0 ? ["Other"] : [])
        row.paysBack = links
        return PaybackCandidate(transaction: row, state: PaybackState(direction: amount > 0 ? .moneyIn : .moneyOut,
            rest: rest ?? abs(amount)), names: ["Fictional Course", "Old bank spelling"])
    }

    private func group(_ payments: [PaybackCandidate]) -> PaybackGroup {
        PaybackGroup(direction: payments[0].state.direction, payments: payments, skipped: PaybackSkipped(),
                     totalRest: Double(payments.reduce(0) { $0 + (Paybacks.cents($1.state.rest) ?? 0) }) / 100, revision: nil)
    }

    private func payment(_ id: String, _ amount: String, date: String = "2026-10-10", category: String = "other",
                         currency: String = "EUR", links: [LedgerPayback]? = nil) -> LedgerPayment {
        LedgerPayment(id: id, account: "fictional-group", source: "bank", externalId: "fictional-" + id,
            bookingDate: date, amount: amount, currency: currency, text: "Fictional payment " + id,
            counterparty: "Fictional " + id, category: category, categorySource: .manual, extraCategories: [],
            sequence: 0, paysBack: links)
    }

    private func setup(_ payments: [LedgerPayment], engine: AresiumEngine? = nil) async throws -> (PhoneBackend, DashboardStore) {
        let phone = try await PhoneCountingTests.backend(engine: engine)
        let chosen = ["other", "groceries", "hobbies", "salary", "cash", "savings-investing"].enumerated().map {
            ChosenCategory(id: $0.element, order: $0.offset)
        }
        try await phone.ledger.restore(LedgerExport(exported: "2026-10-30",
            accounts: [LedgerAccount(id: "fictional-group", name: "Fictional Bank")], payments: payments,
            categories: chosen, learned: [], layouts: []), catalog: #require(phone.catalog))
        try await phone.refresh()
        let store = DashboardStore(session: await PhoneTest.session(nil, transport: RoutedTransport()), backend: phone)
        await store.reload()
        #expect(store.error == nil)
        return (phone, store)
    }

    @Test func onePaymentPoursOverThreeExpensesOldestFirst() throws {
        let expenses = group([candidate("last", -100, date: "2026-10-12"),
                              candidate("first", -100, date: "2026-10-10"), candidate("second", -100, date: "2026-10-11")])
        let plan = try PaybackPlan(group: expenses, others: [candidate("in", 240)])
        #expect(plan.links == [PaybackPlanLink(from: "in", to: "first", amount: 100, totalAmount: 100),
                              PaybackPlanLink(from: "in", to: "second", amount: 100, totalAmount: 100),
                              PaybackPlanLink(from: "in", to: "last", amount: 40, totalAmount: 40)])
        #expect(plan.expenses.map(\.rest) == [0, 0, 60])
        #expect(plan.hasLinks && plan.linked == 240 && plan.stillOpen == 60 && plan.staysIncome == 0)
        #expect(plan.expenseCount == 3 && plan.moneyInCount == 1)
    }

    @Test func threePaymentsFillOneExpenseLastKeepsIncomeAndTiesUseID() throws {
        let incoming = group([candidate("c", 50), candidate("b", 50), candidate("a", 50)])
        let plan = try PaybackPlan(group: incoming, others: [candidate("expense", -120)])
        #expect(plan.links.map(\.from) == ["a", "b", "c"])
        #expect(plan.links.map(\.amount) == [50, 50, 20])
        #expect(plan.paymentsIn.map(\.rest) == [0, 0, 30])
        #expect(plan.stillOpen == 0 && plan.staysIncome == 30 && plan.expenseCount == 1 && plan.moneyInCount == 3)
    }

    @Test func twoByTwoCentsAndBothDirectionsGiveIdenticalPlans() throws {
        let expenses = [candidate("e2", -0.30, date: "2026-10-11"), candidate("e1", -0.29)]
        let incoming = [candidate("i2", 0.40, date: "2026-10-12"), candidate("i1", 0.20)]
        let out = try PaybackPlan(group: group(expenses), others: incoming)
        let reverse = try PaybackPlan(group: group(incoming), others: expenses)
        #expect(out.links == reverse.links)
        #expect(out.links.map(\.amount) == [0.20, 0.09, 0.30])
        #expect(out.linked == 0.59 && out.staysIncome == 0.01 && out.stillOpen == 0)
        #expect(out.paymentsIn.map(\.amount) == [0.20, 0.39])
    }

    @Test func existingPairIsRaisedUsingOnlyBothRests() throws {
        let incoming = candidate("in", 100, rest: 40, links: [PaymentLink(payment: "first", amount: 60)])
        let expenses = group([candidate("first", -80, rest: 20), candidate("second", -50, date: "2026-10-11")])
        let plan = try PaybackPlan(group: expenses, others: [incoming])
        #expect(plan.links == [PaybackPlanLink(from: "in", to: "first", amount: 20, totalAmount: 80),
                              PaybackPlanLink(from: "in", to: "second", amount: 20, totalAmount: 20)])
        #expect(plan.linked == 40 && plan.stillOpen == 30 && plan.staysIncome == 0)
    }

    @Test func emptyPlanAndInvalidInputs() throws {
        let expenses = group([candidate("out", -10)])
        let empty = try PaybackPlan(group: expenses, others: [])
        #expect(!empty.hasLinks && empty.stillOpen == 10 && empty.linked == 0)
        #expect(throws: PaybackError.invalidPayment) { try PaybackPlan(group: expenses, others: [candidate("wrong", -5)]) }
        #expect(throws: PaybackError.invalidPayment) {
            try PaybackPlan(group: expenses, others: [candidate("in", 5), candidate("in", 5)])
        }
        for value in [0.001, -1, Double.nan, Double.infinity] {
            #expect(throws: PaybackError.invalidAmount) {
                try PaybackPlan(group: expenses, others: [candidate("bad", 10, rest: value)])
            }
        }
    }

    @Test func groupSkippedCountsSumsAndDirections() async throws {
        var withdrawal = payment("withdrawal", "-100.00", category: "cash")
        withdrawal.counterparty = "Geldautomat Fiktivbank"
        let (phone, store) = try await setup([payment("one", "-20.00"), payment("two", "-30.00"),
            payment("used", "-10.00"), payment("payer", "10.00", links: [LedgerPayback(payment: "used", amount: "10.00")]),
            payment("transfer", "-10.00", category: "savings-investing"),
            withdrawal, payment("foreign", "-15.00", currency: "USD")])
        _ = try await phone.saveReceipt(ReceiptDraft(date: "2026-10-10", shop: "Fictional Receipt", total: 5,
            currency: "EUR", method: .cash, category: "other", categorySource: .manual, rows: [], from: "text"))
        let receipt = try #require(try await phone.ledger.receipts().first)
        let cash = try await phone.addCashEntry(CashEntryDraft(direction: .out, amount: 5, date: "2026-10-10", what: "Fictional Entry"))
        await store.reloadAfterTransactionChange()
        let all: Set<String> = ["one", "two", "used", "transfer", "withdrawal", "foreign", receipt.id, cash.id]
        let selected = try #require(try await store.paybackGroup(ids: all))
        #expect(selected.direction == .moneyOut && selected.ids == ["one", "two"] && selected.totalRest == 50)
        #expect(selected.skipped == PaybackSkipped(receipts: 1, cashEntries: 1, transfers: 1, withdrawals: 1,
                                                   otherCurrencies: 1, nothingLeft: 1))
        #expect(try await store.paybackGroup(ids: ["one", "payer"]) == nil)
        #expect(try await store.paybackGroup(ids: ["used", "transfer"]) == nil)
        #expect(try await store.paybackGroup(ids: []) == nil)
        store.sums.setEverywhere(true)
        // All these fictional bank spellings may form separate shops; construct the same summed entry as the list.
        let rows = try #require(store.dashboard).transactions.filter { ["one", "two"].contains($0.id) }
            .map { TransactionRow(transaction: $0, tagged: false) }
        let sum = PaymentListEntry.summed(SummedPayments(key: "fictional-group", rows: rows))
        let fromSum = try #require(try await store.paybackGroup(ids: store.selectionIDs(for: sum)))
        #expect(fromSum.ids == selected.ids && fromSum.totalRest == 50)
        #expect(try await phone.dashboard(auth: BackendAuth(token: nil)).paybacksIgnored?.isEmpty != false)
    }

    @Test func groupSuggestionsFitsFirstAndWindowSpansEveryExpense() throws {
        let expenses = group([candidate("old", -120, date: "2026-05-01"), candidate("new", -120, date: "2026-07-01")])
        let candidates = [candidate("near-no-fit", 103, date: "2026-07-01"),
            candidate("whole", 240, date: "2026-07-03"), candidate("half", 120, date: "2026-07-02"),
            candidate("third", 80, date: "2026-07-04"), candidate("quarter", 60, date: "2026-07-05"),
            candidate("start", 77, date: "2026-04-01"), candidate("end", 77, date: "2026-10-29"),
            candidate("early", 120, date: "2026-03-31"), candidate("late", 120, date: "2026-10-30")]
        let hits = Paybacks.suggestions(forGroup: expenses, in: candidates)
        #expect(hits.prefix(4).map(\.id) == ["half", "whole", "third", "quarter"])
        #expect(hits.prefix(4).map(\.fit) == [.half, .whole, .third, .quarter])
        #expect(Set(hits.map(\.id)) == ["near-no-fit", "whole", "half", "third", "quarter", "start", "end"])
        #expect(Paybacks.search("old bank", forGroup: expenses, in: candidates).count == 9)
        #expect(Paybacks.search("", forGroup: expenses, in: candidates).isEmpty)
        #expect(Paybacks.suggestions(forGroup: expenses, in: (0..<12).map { candidate("i\($0)", 240) }).count == 8)
    }

    @Test func incomingGroupFitsTotalOrTwiceAndReverseWindow() throws {
        let incoming = group([candidate("old", 30, date: "2026-05-01"), candidate("new", 30, date: "2026-07-01")])
        let candidates = [candidate("whole", -60, date: "2026-06-30"), candidate("half", -120, date: "2026-07-01"),
            candidate("third-is-not-fit", -180, date: "2026-07-01"), candidate("start", -37, date: "2026-01-01"),
            candidate("end", -37, date: "2026-07-31"), candidate("early", -60, date: "2025-12-31"),
            candidate("late", -60, date: "2026-08-01"), candidate("used", -60, rest: 0)]
        let hits = Paybacks.suggestions(forGroup: incoming, in: candidates)
        #expect(hits.prefix(2).map(\.id) == ["half", "whole"])
        #expect(hits.prefix(2).map(\.fit) == [.half, .whole])
        #expect(hits.first { $0.id == "third-is-not-fit" }?.fit == nil)
        #expect(Set(hits.map(\.id)) == ["whole", "half", "third-is-not-fit", "start", "end"])
    }

    @Test func singlePaymentWrappersMatchGroupIncludingRestFitAndSearch() async throws {
        let (_, store) = try await setup([payment("out", "-100.00"),
            payment("old", "40.00", links: [LedgerPayback(payment: "out", amount: "40.00")]),
            payment("in", "60.00"), payment("distant", "60.01", date: "2027-10-10")])
        for id in ["out", "in"] {
            let group = try #require(try await store.paybackGroup(ids: [id]))
            let hits = try await store.paybackSuggestions(forGroup: group)
            let single = try await store.paybackSuggestions(for: id)
            #expect(hits.map(\.id) == single.map(\.id) && hits.map(\.fit) == single.map(\.fit))
            #expect(hits.map(\.amount) == single.map(\.amount))
            let found = try await store.paybackSearch("fictional", forGroup: group)
            let one = try await store.paybackSearch("fictional", for: id)
            #expect(found.map(\.id) == one.map(\.id) && found.map(\.fit) == one.map(\.fit))
            #expect(found.map(\.amount) == one.map(\.amount))
        }
        #expect(try await store.paybackSuggestions(for: "out").first?.fit == .rest)
    }

    @Test func groupSaveRaisesPairCreatesOthersAndOneUndoRestoresAll() async throws {
        let (phone, store) = try await setup([payment("e1", "-80.00"), payment("e2", "-90.00", date: "2026-10-11"),
            payment("i1", "100.00", links: [LedgerPayback(payment: "e1", amount: "20.00")]),
            payment("i2", "100.00", date: "2026-10-12")])
        let before = try await phone.ledger.batchSnapshot(), revision = store.revision
        let selected = try #require(try await store.paybackGroup(ids: ["e1", "e2"]))
        let preview = try await store.paybackPlan(group: selected, others: ["i1", "i2"])
        let saves = await phone.ledger.paybackTestRevision()
        let result = try await store.setPaybacks(group: selected, others: ["i2", "i1"])
        #expect(result.plan.links == preview.links && result.expenseCount == 2 && result.moneyInCount == 2)
        #expect(result.linked == 150 && result.stillOpen == 0 && result.staysIncome == 30)
        #expect(store.revision == revision + 1)
        #expect(await phone.ledger.paybackTestRevision() == saves + 1)
        #expect(try await phone.ledger.payment("i1")?.paysBack == [LedgerPayback(payment: "e1", amount: "80.00"),
                                                                  LedgerPayback(payment: "e2", amount: "20.00")])
        #expect(try await phone.ledger.payment("i2")?.paysBack == [LedgerPayback(payment: "e2", amount: "70.00")])
        #expect(store.dashboard?.paybacksIgnored?.isEmpty != false)
        #expect(try await result.undo.perform() == .undone)
        #expect(try await phone.ledger.batchSnapshot() == before)
        #expect(store.revision == revision + 2)
        #expect(await phone.ledger.paybackTestRevision() == saves + 2)
        #expect(try await result.undo.perform() == .unavailable)
    }

    @Test func stalePreviewEvenAfterChangeBackAndDifferentLedgerAreRefusedWithoutSaving() async throws {
        let (phone, store) = try await setup([payment("out", "-100.00"), payment("in", "100.00")])
        let selected = try #require(try await store.paybackGroup(ids: ["out"]))
        _ = try await store.paybackPlan(group: selected, others: ["in"])
        try await phone.ledger.setCategory("out", category: "groceries", source: .manual)
        try await phone.ledger.setCategory("out", category: "other", source: .manual)
        let before = try await phone.ledger.batchSnapshot(), saves = await phone.ledger.paybackTestRevision()
        await #expect(throws: BatchChangeError.changed) { _ = try await store.setPaybacks(group: selected, others: ["in"]) }
        #expect(try await phone.ledger.batchSnapshot() == before)
        #expect(await phone.ledger.paybackTestRevision() == saves)
        let (_, another) = try await setup([payment("out", "-100.00"), payment("in", "100.00")])
        await #expect(throws: BatchChangeError.changed) { _ = try await another.setPaybacks(group: selected, others: ["in"]) }
    }

    @Test func reverseSaveCountsEveryCategoryMonthDayAndIncome() async throws {
        var first = payment("e1", "-100.00", date: "2026-08-01", category: "groceries")
        first.extraCategories = ["other"]
        let (_, store) = try await setup([first, payment("e2", "-100.00", date: "2026-09-02", category: "hobbies"),
            payment("e3", "-100.00", date: "2026-10-03", category: "other"),
            payment("in", "240.00", date: "2026-10-04", category: "salary")])
        let selected = try #require(try await store.paybackGroup(ids: ["in"]))
        let result = try await store.setPaybacks(group: selected, others: ["e3", "e2", "e1"])
        #expect(result.expenseCount == 3 && result.moneyInCount == 1 && result.linked == 240 && result.stillOpen == 60)
        let dashboard = try #require(store.dashboard)
        #expect(dashboard.total.expense == 60 && dashboard.total.income == 0)
        #expect(dashboard.byMonth["2026-08"]?.expense == 0 && dashboard.byMonth["2026-09"]?.expense == 0)
        #expect(dashboard.byMonth["2026-10"]?.expense == 60 && dashboard.byMonth["2026-10"]?.income == 0)
        #expect(dashboard.total.categories.first { $0.name == "Other" }?.total == 60)
        #expect(!dashboard.total.categories.contains { ["Groceries", "Hobbies"].contains($0.name) && $0.total > 0 })
        #expect(dashboard.byMonth["2026-10"]?.dayExpense[2] == 60)
        #expect(dashboard.byMonth["2026-10"]?.dayIncome[3] == 0)
        #expect(dashboard.transactions.first { $0.id == "e1" }?.countedAmount == 0)
        #expect(dashboard.transactions.first { $0.id == "e2" }?.countedAmount == 0)
        #expect(dashboard.transactions.first { $0.id == "e3" }?.countedAmount == -60)
        #expect(dashboard.paybacksIgnored?.isEmpty != false)
    }

    @Test func serverModeAndInvalidPickedRowsDoNotSave() async throws {
        let (phone, store) = try await setup([payment("out", "-10.00"), payment("in", "10.00"),
                                             payment("transfer", "10.00", category: "savings-investing")])
        let selected = try #require(try await store.paybackGroup(ids: ["out"]))
        let saves = await phone.ledger.paybackTestRevision()
        for ids: Set<String> in [[], ["out"], ["missing"], ["transfer"]] {
            await #expect(throws: PaybackError.invalidPayment) { _ = try await store.setPaybacks(group: selected, others: ids) }
        }
        #expect(await phone.ledger.paybackTestRevision() == saves)
        let server = DashboardStore(session: await PhoneTest.session(nil, transport: RoutedTransport()), sample: true)
        #expect(try await server.paybackGroup(ids: ["out"]) == nil)
        #expect(try await server.paybackSuggestions(forGroup: selected).isEmpty)
        #expect(try await server.paybackSearch("fictional", forGroup: selected).isEmpty)
        await #expect(throws: BatchChangeError.unavailable) { _ = try await server.setPaybacks(group: selected, others: ["in"]) }
    }

    @Test func severalIncomingPaymentsSaveAndUndoWithOneRebuildEach() async throws {
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
        let (phone, store) = try await setup([payment("out", "-120.00"), payment("i1", "50.00"),
            payment("i2", "50.00", date: "2026-10-11"), payment("i3", "50.00", date: "2026-10-12")], engine: engine)
        let selected = try #require(try await store.paybackGroup(ids: ["i1", "i2", "i3"]))
        #expect(selected.direction == .moneyIn && selected.totalRest == 150)
        _ = try await store.paybackPlan(group: selected, others: ["out"])
        let builds = try #require(Int(try await engine.version())), saves = await phone.ledger.paybackTestRevision()
        let result = try await store.setPaybacks(group: selected, others: ["out"])
        #expect(try await engine.version() == String(builds + 1))
        #expect(await phone.ledger.paybackTestRevision() == saves + 1)
        #expect(result.expenseCount == 1 && result.moneyInCount == 3 && result.linked == 120 && result.staysIncome == 30)
        #expect(store.dashboard?.total.expense == 0 && store.dashboard?.total.income == 30)
        #expect(try await phone.paybackState(for: "i3")?.rest == 30)
        #expect(try await result.undo.perform() == .undone)
        #expect(try await engine.version() == String(builds + 2))
        #expect(await phone.ledger.paybackTestRevision() == saves + 2)
        #expect(store.dashboard?.total.expense == 120 && store.dashboard?.total.income == 150)
    }

    @Test func summaryWordsInBothLanguagesAndSingular() {
        #expect(PaybackGroupWording.summary(expenses: 3, linked: 240, stillOpen: 0, staysIncome: 60, language: .english)
            == "3 expenses, €240.00 paid back. €60.00 stays income.")
        #expect(PaybackGroupWording.summary(expenses: 3, linked: 240, stillOpen: 0, staysIncome: 60, language: .german)
            == "3 Ausgaben, 240,00\u{a0}€ zurückgezahlt. 60,00\u{a0}€ bleiben Einnahme.")
        #expect(PaybackGroupWording.open(30, language: .english) == "€30.00 still open.")
        #expect(PaybackGroupWording.open(30, language: .german) == "30,00\u{a0}€ noch offen.")
        #expect(PaybackGroupWording.summary(expenses: 1, linked: 20, stillOpen: 30, staysIncome: 0, language: .english)
            == "1 expense, €20.00 paid back. €30.00 still open.")
        #expect(PaybackGroupWording.summary(expenses: 1, linked: 20, stillOpen: 0, staysIncome: 0, language: .german)
            == "1 Ausgabe, 20,00\u{a0}€ zurückgezahlt.")
    }
}
