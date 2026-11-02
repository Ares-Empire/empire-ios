import Foundation
import Testing
@testable import Aresium

/// Money paid back for several payments at once, on screen (brief 206; the data is brief 205's): the words in both
/// languages, the window's heading and the summary of how the money goes, the selection bar's item, and the one window
/// on a real store from a selection (several expenses, one payment in; several payments in, one expense) and from one
/// payment's page (several ticked), with one undo for all. Made-up payments only.
@MainActor
@Suite(.serialized)
struct PaybackManyScreensTests {
    /// 2 Nov 2026: the made-up payments are in October.
    private static let now = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 12))!

    private func payment(_ id: String, _ amount: String, day: String, name: String, category: String? = "other",
                         links: [LedgerPayback]? = nil) -> LedgerPayment {
        LedgerPayment(id: id, account: "fictional-many", source: "bank", externalId: "fictional-" + id,
                      bookingDate: day, amount: amount, currency: "EUR", text: "Fictional payment " + id,
                      counterparty: name, category: category,
                      categorySource: category == nil ? .none : .manual, extraCategories: [], sequence: 0, paysBack: links)
    }

    private func setup(_ payments: [LedgerPayment]) async throws -> (PhoneBackend, DashboardStore) {
        let phone = try await PhoneCountingTests.backend()
        let chosen = ["other", "eating-out", "parents-family", "savings-investing"].enumerated().map {
            ChosenCategory(id: $0.element, order: $0.offset)
        }
        try await phone.ledger.restore(LedgerExport(exported: "2026-10-30",
            accounts: [LedgerAccount(id: "fictional-many", name: "Fictional Bank")], payments: payments,
            categories: chosen, learned: [], layouts: []), catalog: #require(phone.catalog))
        try await phone.refresh()
        let store = DashboardStore(session: await PhoneTest.session(nil, transport: RoutedTransport()), backend: phone)
        await store.reload()
        #expect(store.error == nil)
        return (phone, store)
    }

    /// Two made-up dinners and a made-up café out, two made-up friends paying back; a made-up course and a made-up
    /// parent's two transfers towards it; a transfer between one's own accounts.
    private var sample: [LedgerPayment] {
        [payment("pizza", "-48.00", day: "2026-10-03", name: "Fictional Pizzeria", category: "eating-out"),
         payment("grill", "-36.00", day: "2026-10-10", name: "Fictional Grill", category: "eating-out"),
         payment("cafe", "-40.00", day: "2026-10-15", name: "Fictional Cafe", category: "eating-out"),
         payment("savings", "-50.00", day: "2026-10-16", name: "Fictional Savings", category: "savings-investing"),
         payment("fiona", "40.00", day: "2026-10-11", name: "Fictional Fiona", category: nil),
         payment("felix", "100.00", day: "2026-10-18", name: "Fictional Felix", category: nil),
         payment("course", "-200.00", day: "2026-10-08", name: "Fictional Language School"),
         payment("parent1", "150.00", day: "2026-10-06", name: "Fictional Parent", category: "parents-family"),
         payment("parent2", "100.00", day: "2026-10-13", name: "Fictional Parent", category: "parents-family")]
    }

    /// The window's done: what the undo bar says and its undo.
    private final class Done {
        var message: String?
        var undo: BatchUndo?
        var calls = 0
    }

    private func suggestion(_ id: String, in window: PaybackWindow) throws -> PaybackSuggestion {
        try #require(window.choices?.first { $0.id == id } ?? window.results?.first { $0.id == id })
    }

    // MARK: the words

    @Test func theWordsInBothLanguages() {
        #expect(PaybackWording.question(direction: .moneyOut, several: true, language: .english)
                == "Which payments paid these back?")
        #expect(PaybackWording.question(direction: .moneyOut, several: true, language: .german)
                == "Welche Buchungen haben diese zurückgezahlt?")
        #expect(PaybackWording.question(direction: .moneyIn, several: true, language: .english)
                == "Which expenses do these pay back?")
        #expect(PaybackWording.question(direction: .moneyOut, language: .german) == "Welche Buchungen haben das zurückgezahlt?")
        #expect(PaybackWording.groupTitle(count: 3, direction: .moneyOut, language: .english) == "3 expenses")
        #expect(PaybackWording.groupTitle(count: 3, direction: .moneyOut, language: .german) == "3 Ausgaben")
        #expect(PaybackWording.groupTitle(count: 2, direction: .moneyIn, language: .english) == "2 payments in")
        #expect(PaybackWording.groupTitle(count: 2, direction: .moneyIn, language: .german) == "2 Einnahmen")
        #expect(PaybackWording.leftOut(PaybackSkipped(), direction: .moneyOut) == nil)
        #expect(PaybackWording.leftOut(PaybackSkipped(receipts: 1), direction: .moneyOut, language: .english)
                == "Left out: 1 receipt.")
        let many = PaybackSkipped(receipts: 2, cashEntries: 1, transfers: 1, withdrawals: 2, otherCurrencies: 1,
                                  nothingLeft: 1)
        #expect(PaybackWording.leftOut(many, direction: .moneyOut, language: .english)
                == "Left out: 2 receipts, 1 cash entry, 1 transfer, 2 withdrawals, 1 in another currency, 1 paid back in full.")
        #expect(PaybackWording.leftOut(many, direction: .moneyIn, language: .german)
                == "Nicht dabei: 2 Belege, 1 Bargeld-Eintrag, 1 Umbuchung, 2 Abhebungen, 1 in anderer Währung, 1 schon ganz verknüpft.")
        #expect(PaybackWording.free(30, language: .english) == "€30.00 left")
        #expect(PaybackWording.free(30, language: .german) == "30,00\u{a0}€ übrig")
        let full = PaybackAllocation(id: "e", amount: 48, rest: 0), open = PaybackAllocation(id: "e", amount: 16, rest: 24.15)
        #expect(PaybackWording.planLine(full, date: "2026-10-03", now: Self.now, language: .english) == "3 Oct · in full")
        #expect(PaybackWording.planLine(open, date: "2026-10-15", now: Self.now, language: .german)
                == "15. Okt. · 24,15\u{a0}€ noch offen")
        #expect(SelectionWording.paybackItem(side: .expenses, language: .english) == "Paid back")
        #expect(SelectionWording.paybackItem(side: .income, language: .german) == "Zahlt zurück")
        #expect(SelectionWording.paybackItem(side: .expenses, language: .german) == "Zurückgezahlt")
    }

    /// How the money goes, as the window shows it: oldest first, in full or what stays open, then brief 205's sentence
    /// and what stays open or stays income (never both).
    @Test func theSummaryReadsThePlan() throws {
        func candidate(_ id: String, _ amount: Double, _ date: String) -> PaybackCandidate {
            let row = Transaction(id: id, date: date, day: Int(date.suffix(2))!, month: String(date.prefix(7)),
                                  amount: amount, categoryName: "Other", tags: [], place: "Fictional " + id, city: "",
                                  categoriesIn: amount < 0 ? ["Other"] : [], incomeBuckets: amount > 0 ? ["Other"] : [])
            return PaybackCandidate(transaction: row, state: PaybackState(direction: amount < 0 ? .moneyOut : .moneyIn,
                                                                         rest: abs(amount)), names: [])
        }
        let expenses = [candidate("cafe", -40.15, "2026-10-15"), candidate("pizza", -48, "2026-10-03"),
                        candidate("grill", -36, "2026-10-10")]
        let group = PaybackGroup(direction: .moneyOut, payments: expenses, skipped: PaybackSkipped(), totalRest: 124.15,
                                 revision: nil)
        let felix = candidate("felix", 100, "2026-10-18")
        let all = Dictionary(uniqueKeysWithValues: (expenses + [felix]).map { ($0.transaction.id, $0.transaction) })
        let one = PaybackPlanSummary(plan: try PaybackPlan(group: group, others: [felix]), transactions: all,
                                     now: Self.now, language: .english)
        #expect(one.rows.map(\.name) == ["Fictional pizza", "Fictional grill", "Fictional cafe"], "oldest first")
        #expect(one.rows.map(\.amount) == [48, 36, 16])
        #expect(one.rows.map(\.line) == ["3 Oct · in full", "10 Oct · in full", "15 Oct · €24.15 still open"])
        #expect(one.rows[0].spoken == "Fictional pizza, 3 Oct · in full, €48.00 back")
        #expect(one.paidBack == "3 expenses, €100.00 paid back." && one.left == "€24.15 still open.")
        let fiona = candidate("fiona", 40, "2026-10-11")
        let both = PaybackPlanSummary(plan: try PaybackPlan(group: group, others: [felix, fiona]),
                                      transactions: all.merging([("fiona", fiona.transaction)]) { $1 },
                                      now: Self.now, language: .german)
        #expect(both.rows.map(\.amount) == [48, 36, 40.15])
        #expect(both.paidBack == "3 Ausgaben, 124,15\u{a0}€ zurückgezahlt." && both.left == "15,85\u{a0}€ bleiben Einnahme.")
        // A plan that runs out before the last expense: it gets nothing and stays open in full.
        let little = PaybackPlanSummary(plan: try PaybackPlan(group: group, others: [candidate("small", 50, "2026-10-20")]),
                                        transactions: all, now: Self.now, language: .english)
        #expect(little.rows.map(\.amount) == [48, 2, 0])
        #expect(little.rows.last?.line == "15 Oct · €40.15 still open" && little.left == "€74.15 still open.")
        #expect(little.paidBack == "2 expenses, €50.00 paid back.")
    }

    // MARK: on a real store

    /// The heading for a group: the count and the euros it can be paid back, what was left out; one payment as brief 203.
    /// The selection bar's item is off while the ticked payments have no group.
    @Test func headingAndTheBarsItem() async throws {
        let (_, store) = try await setup(sample)
        let group = try #require(try await store.paybackGroup(ids: ["pizza", "grill", "cafe", "savings"]))
        let heading = PaybackHeading(group: group, language: .english)
        #expect(heading.title == "3 expenses" && heading.amount == "−124.00" && heading.isExpense)
        #expect(heading.leftOut == "Left out: 1 transfer.")
        let incoming = try #require(try await store.paybackGroup(ids: ["parent1", "parent2"]))
        let german = PaybackHeading(group: incoming, language: .german)
        #expect(german.title == "2 Einnahmen" && german.amount == "+250,00" && !german.isExpense && german.leftOut == nil)
        let single = PaybackHeading(group: try #require(try await store.paybackGroup(ids: ["pizza"])), language: .english)
        #expect(single.title == "Fictional Pizzeria" && single.amount == "−48.00")
        // The bar: its word by the list's side; off without a group (nothing ticked, a transfer alone, both directions).
        #expect(try await store.paybackGroup(ids: []) == nil)
        #expect(try await store.paybackGroup(ids: ["savings"]) == nil)
        #expect(try await store.paybackGroup(ids: ["pizza", "felix"]) == nil)
        let summary = store.selectionSummary(["pizza", "grill"])
        let on = SelectionBarState(summary: summary, ownNames: true, side: .expenses, payback: true)
        #expect(on.payback && on.paybackTitle == "Paid back")
        #expect(!SelectionBarState(summary: summary, ownNames: true).payback)
        #expect(SelectionBarState(summary: summary, ownNames: true, side: .income).paybackTitle == "Pays back")
    }

    /// Three expenses selected, one payment in ticked: the oldest filled first, Link pours it, the undo bar's line, the
    /// rows' numbers; one undo removes all three links.
    @Test func threeExpensesAndOnePaymentInWithOneUndo() async throws {
        let (phone, store) = try await setup(sample)
        let before = store.dashboard?.total.expense
        let group = try #require(try await store.paybackGroup(ids: ["pizza", "grill", "cafe"]))
        let done = Done()
        let window = PaybackWindow(store: store, group: group) { message, undo in
            done.message = message
            done.undo = undo
            done.calls += 1
        }
        #expect(window.isSeveral && !window.confirmsByAmount && !window.canLink)
        await window.load()
        let suggested = try #require(window.suggestions)
        #expect(suggested.contains { $0.id == "felix" } && suggested.contains { $0.id == "fiona" })
        #expect(!suggested.contains { $0.id == "pizza" }, "never this side's own payments")
        window.toggle(try suggestion("felix", in: window))
        #expect(!window.confirmsByAmount && window.canLink, "several on this side: Link pours")
        let summary = try #require(window.summary)
        #expect(summary.rows.map(\.id) == ["pizza", "grill", "cafe"] && summary.rows.map(\.amount) == [48, 36, 16])
        #expect(window.plan?.stillOpen == 24 && window.plan?.staysIncome == 0)
        #expect(await window.link())
        #expect(done.calls == 1 && done.message == "3 expenses, €100.00 paid back. €24.00 still open.")
        #expect(store.dashboard?.total.expense == (before ?? 0) - 100)
        #expect(store.bankPayment("pizza").map { PaybackWording.rowAmount($0, language: .english) } == "0.00")
        #expect(store.bankPayment("cafe").flatMap { PaybackWording.rowLine($0, name: { _ in nil }, language: .english) }
                == "€40.00 · €16.00 back")
        #expect(try await phone.ledger.payment("felix")?.paysBack?.count == 3)
        let undone = try #require(done.undo)
        #expect(try await undone.perform() == .undone)
        #expect(try await phone.ledger.payment("felix")?.paysBack == nil, "one undo removes all three links")
        #expect(store.dashboard?.total.expense == before)
    }

    /// Two payments in selected on an income list, one expense found by name and ticked: it is paid back in full and the
    /// rest stays income, said before Link.
    @Test func twoPaymentsInAndOneExpense() async throws {
        let (phone, store) = try await setup(sample)
        let income = store.dashboard?.total.income
        let group = try #require(try await store.paybackGroup(ids: ["parent1", "parent2"]))
        let done = Done()
        let window = PaybackWindow(store: store, group: group) { message, undo in
            done.message = message
            done.undo = undo
        }
        #expect(window.direction == .moneyIn)
        await window.load()
        window.query = "language school"
        await window.search()
        let course = try suggestion("course", in: window)
        window.toggle(course)
        window.query = ""
        await window.search()
        #expect(window.choices?.contains { $0.id == "course" } == true, "a ticked result stays shown")
        let summary = try #require(window.summary)
        #expect(summary.rows.map(\.line) == ["8 Oct · in full"])
        #expect(summary.left == "€50.00 stays income.")
        #expect(await window.link())
        #expect(done.message == "1 expense, €200.00 paid back. €50.00 stays income.")
        #expect(store.bankPayment("course")?.countedAmount == 0)
        #expect(store.dashboard?.total.income == (income ?? 0) - 200)
        #expect(try await phone.ledger.payment("parent1")?.paysBack == [LedgerPayback(payment: "course", amount: "150.00")])
        #expect(try await phone.ledger.payment("parent2")?.paysBack == [LedgerPayback(payment: "course", amount: "50.00")])
    }

    /// One payment in's page: two expenses ticked are linked at once (Link, not Next); the page's undo bar says it and
    /// its Undo takes both back. One ticked goes on to the typed euros, as brief 203.
    @Test func onePaymentsPageTicksTwo() async throws {
        let (phone, store) = try await setup(sample)
        let page = store.transactionDetailStore(for: try #require(store.bankPayment("felix")))
        await page.load()
        await page.paybacks.load()
        page.paybacks.begin(detail: try #require(page.detail))
        let window = try #require(page.paybacks.window)
        #expect(!window.isSeveral && window.heading.title == "Fictional Felix")
        await window.load()
        window.toggle(try suggestion("grill", in: window))
        #expect(window.confirmsByAmount && window.canNext && !window.canLink)
        window.toggle(try suggestion("pizza", in: window))
        #expect(!window.confirmsByAmount && window.canLink)
        let summary = try #require(window.summary)
        #expect(summary.rows.map(\.id) == ["pizza", "grill"], "oldest first, whatever the order of the ticks")
        #expect(summary.left == "€16.00 stays income.")
        #expect(await window.link())
        #expect(page.paybacks.window == nil, "the window closes")
        #expect(page.paybacks.undo?.message == "2 expenses, €84.00 paid back. €16.00 stays income.")
        await page.refresh()
        let shown = PaybackSectionContent(detail: try #require(page.detail), state: page.paybacks.state, language: .english)
        #expect(shown.links.map(\.payment).sorted() == ["grill", "pizza"])
        #expect(shown.summary == "The rest, €16.00, counts as income.")
        let undo = try #require(page.paybacks.undo?.undo)
        await undo()
        #expect(try await phone.ledger.payment("felix")?.paysBack == nil)
    }

    /// A change between opening the window and Link refuses with the selection's line; nothing is saved and the window
    /// stays open with the line.
    @Test func aChangeMeanwhileRefuses() async throws {
        let (phone, store) = try await setup(sample)
        let group = try #require(try await store.paybackGroup(ids: ["pizza", "grill"]))
        let done = Done()
        let window = PaybackWindow(store: store, group: group) { _, _ in done.calls += 1 }
        await window.load()
        window.toggle(try suggestion("felix", in: window))
        try await phone.ledger.setCategory("cafe", category: "other", source: .manual)
        #expect(await window.link() == false)
        #expect(done.calls == 0 && window.problem == BatchChangeError.changed.errorDescription)
        #expect(try await phone.ledger.payment("felix")?.paysBack == nil)
    }
}
