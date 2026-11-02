import Foundation
import Testing
@testable import Aresium

/// Money paid back on screen (brief 203): the words in both languages, what a payment's page shows, the window's
/// amount check, its ends and limits, and the whole flow on a real phone store (suggestions, Link, the page following,
/// change, remove, undo, a search beyond the suggestions), the lists' counted numbers and a name that counts nothing.
@MainActor
@Suite(.serialized)
struct PaybackScreensTests {
    private let auth = BackendAuth(token: nil)
    /// 2 Nov 2026: the made-up payments are in October.
    private static let now = Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 12))!

    private func payment(_ id: String, _ amount: String, day: String = "2026-10-10", name: String? = nil,
                         category: String? = "other", links: [LedgerPayback]? = nil) -> LedgerPayment {
        LedgerPayment(id: id, account: "fictional-paybacks", source: "bank", externalId: "fictional-" + id,
                      bookingDate: day, amount: amount, currency: "EUR", text: "Fictional payment " + id,
                      counterparty: name ?? "Fictional " + id, category: category,
                      categorySource: category == nil ? .none : .manual, extraCategories: [], sequence: 0, paysBack: links)
    }

    private func setup(_ payments: [LedgerPayment]) async throws -> (PhoneBackend, DashboardStore) {
        let phone = try await PhoneCountingTests.backend()
        let chosen = ["other", "groceries", "salary"].enumerated().map { ChosenCategory(id: $0.element, order: $0.offset) }
        try await phone.ledger.restore(LedgerExport(exported: "2026-10-30",
            accounts: [LedgerAccount(id: "fictional-paybacks", name: "Fictional Bank")], payments: payments,
            categories: chosen, learned: [], layouts: []), catalog: #require(phone.catalog))
        try await phone.refresh()
        let store = DashboardStore(session: await PhoneTest.session(nil, transport: RoutedTransport()), backend: phone)
        await store.reload()
        #expect(store.error == nil)
        return (phone, store)
    }

    /// A payment's page as it opens: its detail, then whether it can be linked.
    private func page(_ id: String, in store: DashboardStore) async throws -> TransactionDetailStore {
        let row = try #require(store.bankPayment(id))
        let page = store.transactionDetailStore(for: row)
        await page.load()
        await page.paybacks.load()
        return page
    }

    private func content(_ page: TransactionDetailStore, _ language: AppLanguage = .english) throws -> PaybackSectionContent {
        PaybackSectionContent(detail: try #require(page.detail), state: page.paybacks.state, language: language)
    }

    // MARK: the words

    @Test func theWordsInBothLanguages() {
        #expect(PaybackWording.action(direction: .moneyIn, linked: false, language: .english) == "Pays back an expense…")
        #expect(PaybackWording.action(direction: .moneyIn, linked: false, language: .german) == "Zahlt eine Ausgabe zurück …")
        #expect(PaybackWording.action(direction: .moneyOut, linked: false, language: .english) == "Paid back to you…")
        #expect(PaybackWording.action(direction: .moneyOut, linked: false, language: .german) == "Wurde zurückgezahlt …")
        #expect(PaybackWording.action(direction: .moneyOut, linked: true, language: .german) == "Auch zurückgezahlt von …")
        #expect(PaybackWording.action(direction: .moneyIn, linked: true, language: .english) == "Also pays back…")
        #expect(PaybackWording.heading(direction: .moneyOut, language: .german) == "Zurückgezahlt")
        #expect(PaybackWording.heading(direction: .moneyIn, language: .german) == "Zahlt zurück")
        #expect(PaybackWording.summary(direction: .moneyOut, counted: -64, language: .english)
                == "Your share, €64.00, counts as spent.")
        #expect(PaybackWording.summary(direction: .moneyOut, counted: -64, language: .german)
                == "Dein Anteil, 64,00\u{a0}€, zählt als Ausgabe.")
        #expect(PaybackWording.summary(direction: .moneyOut, counted: 0, language: .english)
                == "Paid back in full: none of it counts as spent.")
        #expect(PaybackWording.summary(direction: .moneyIn, counted: 16, language: .german)
                == "Der Rest, 16,00\u{a0}€, zählt als Einnahme.")
        #expect(PaybackWording.summary(direction: .moneyIn, counted: 0, language: .german) == "Nichts davon zählt als Einnahme.")
        #expect([PaybackFit.whole, .half, .third, .quarter, .rest].map { PaybackWording.fit($0, language: .german) }
                == ["ganz", "die Hälfte", "ein Drittel", "ein Viertel", "der Rest"])
        #expect(PaybackWording.fit(.half, language: .english) == "half")
        #expect(PaybackWording.day("2026-10-29", now: Self.now, language: .english) == "29 Oct")
        #expect(PaybackWording.day("2025-10-29", now: Self.now, language: .german) == "29. Okt. 2025")
        let link = PaybackDetailLink(payment: "in", place: "Fictional Friend", date: "2026-10-29", amount: 80, linkedAmount: 64)
        #expect(PaybackWording.linkLine(link, now: Self.now, language: .english) == "29 Oct · +80.00")
        #expect(PaybackWording.spokenLink(link, direction: .moneyOut, now: Self.now, language: .english)
                == "Fictional Friend, 29 Oct, €64.00 paid back")
        #expect(PaybackWording.spokenLink(link, direction: .moneyIn, now: Self.now, language: .german)
                == "Fictional Friend, 29. Okt., zahlt 64,00\u{a0}€ zurück")
        #expect(PaybackWording.windowTitle(direction: .moneyOut, language: .german) == "Rückzahlung")
        #expect(PaybackWording.question(direction: .moneyIn, language: .german) == "Welche Ausgaben werden damit zurückgezahlt?")
        #expect(PaybackWording.question(direction: .moneyOut, language: .english) == "Which payments paid this back?")
        #expect(PaybackWording.maximum(64, language: .german) == "Höchstens 64,00\u{a0}€.")
        #expect(PaybackWording.linked(64, language: .english) == "Linked: €64.00 paid back.")
        #expect(PaybackWording.changed(50, language: .german) == "Geändert auf 50,00\u{a0}€.")
        #expect(PaybackWording.removed(language: .german) == "Verknüpfung entfernt.")
        #expect(PaybackWording.noMatch(" Zalando ", language: .german) == "Keine Buchung für „Zalando“ gefunden.")
        for language in [AppLanguage.english, .german] {
            #expect(!PaybackWording.noSuggestion(language: language).isEmpty)
            #expect(!PaybackWording.amountQuestion(language: language).isEmpty)
            #expect(!PaybackWording.changeLink(language: language).isEmpty)
        }
        #expect(TourStep.payback.text(.english)
                == "Paid back by someone? If you like, link the payment here: then only your share counts.")
        #expect(TourStep.payback.text(.german).contains("Wenn du magst") && TourStep.payback.text(.german).contains("Anteil"))
    }

    /// A list row: the counted number (a counted 0 without a sign), and why it differs from the bank's.
    @Test func listRowsSayWhatCountsAndWhy() {
        func row(_ amount: Double, counted: Double? = nil, paidBack: Double? = nil, paysBack: [PaymentLink]? = nil) -> Transaction {
            Transaction(id: "t", date: "2026-10-28", day: 28, month: "2026-10", amount: amount, categoryName: "Other",
                        tags: [], place: "Fictional", city: "", categoriesIn: amount < 0 ? ["Other"] : [],
                        incomeBuckets: amount > 0 ? ["Other"] : [], counted: counted, paidBack: paidBack, paysBack: paysBack)
        }
        let names = ["trip": "Fictional Trip"]
        let expense = row(-128, counted: -64, paidBack: 64)
        #expect(PaybackWording.rowAmount(expense, language: .english) == "−64.00")
        #expect(PaybackWording.rowLine(expense, name: { names[$0] }, language: .english) == "€128.00 · €64.00 back")
        #expect(PaybackWording.rowLine(expense, name: { names[$0] }, language: .german) == "128,00\u{a0}€ · 64,00\u{a0}€ zurück")
        #expect(!PaybackWording.countsNothing(expense))
        let used = row(64, counted: 0, paysBack: [PaymentLink(payment: "trip", amount: 64)])
        #expect(PaybackWording.rowAmount(used, language: .english) == "0.00")
        #expect(PaybackWording.rowAmount(used, language: .german) == "0,00")
        #expect(PaybackWording.countsNothing(used))
        #expect(PaybackWording.rowLine(used, name: { names[$0] }, language: .english) == "€64.00 · pays back Fictional Trip")
        #expect(PaybackWording.rowLine(used, name: { names[$0] }, language: .german) == "64,00\u{a0}€ · zahlt Fictional Trip zurück")
        let two = row(100, counted: 20, paysBack: [PaymentLink(payment: "a", amount: 40), PaymentLink(payment: "b", amount: 40)])
        #expect(PaybackWording.rowLine(two, name: { names[$0] }, language: .german) == "100,00\u{a0}€ · zahlt 2 Ausgaben zurück")
        #expect(PaybackWording.rowAmount(two, language: .english) == "+20.00")
        let plain = row(-12.5)
        #expect(PaybackWording.rowLine(plain, name: { names[$0] }) == nil)
        #expect(PaybackWording.rowAmount(plain, language: .english) == "−12.50" && !PaybackWording.countsNothing(plain))
        #expect(PaybackWording.summedLine(original: -228, counted: -164, language: .english) == "€64.00 back")
        #expect(PaybackWording.summedLine(original: 164, counted: 100, language: .german) == "64,00\u{a0}€ keine Einnahme")
        #expect(PaybackWording.summedLine(original: -228, counted: -228) == nil)
    }

    /// The window's ends, the amount check and the most a link can take.
    @Test func endsAmountsAndLimits() {
        #expect(PaybackEnds(payment: "in", direction: .moneyIn, other: "out") == PaybackEnds(payment: "out", direction: .moneyOut, other: "in"))
        let ends = PaybackEnds(payment: "out", direction: .moneyOut, other: "in")
        #expect(ends.from == "in" && ends.to == "out")
        #expect(PaybackAmountCheck("64,00", maximum: 64) == .ok(64))
        #expect(PaybackAmountCheck("64.00", maximum: 64) == .ok(64))
        #expect(PaybackAmountCheck("12,5", maximum: 64) == .ok(12.5))
        #expect(PaybackAmountCheck("64,01", maximum: 64) == .tooMuch)
        #expect(PaybackAmountCheck("", maximum: 64) == .empty)
        #expect(PaybackAmountCheck("0", maximum: 64) == .empty)
        #expect(PaybackAmountCheck("abc", maximum: 64) == .empty)
        let other = Transaction(id: "in", date: "2026-10-29", day: 29, month: "2026-10", amount: 80, categoryName: "Other",
                                tags: [], place: "Fictional Friend", city: "", categoriesIn: [], incomeBuckets: ["Other"])
        // A change: each end has its rest plus the link's own euros.
        let change = PaybackPick(other: other, direction: .moneyOut, linked: 30, rest: 64, otherRest: 50)
        #expect(change.maximum == 80 && change.suggested == 30)
        #expect(change.expenseFree == 94 && change.incomeFree == 80)
        #expect(PaybackPick(other: other, direction: .moneyOut, linked: 30, rest: 0, otherRest: 50).maximum == 30)
        // Brief 206: what the typed euros leave open on the expense and as income on the payment in.
        let left = change.left(after: 50)
        #expect(left.open == 44 && left.income == 30)
        #expect(PaybackWording.afterAmount(open: left.open, income: left.income, language: .english)
                == "€44.00 still open. €30.00 stays income.")
        #expect(PaybackWording.afterAmount(open: 0, income: 16, language: .german) == "16,00\u{a0}€ bleiben Einnahme.")
        #expect(PaybackWording.afterAmount(open: 0, income: 0) == nil)
        // From a suggestion: the payment in's rest and the expense's, whichever side the page is.
        let state = PaybackState(direction: .moneyIn, rest: 80)
        let suggestion = PaybackSuggestion(transaction: other, state: state, fit: nil, amount: 64)
        let fromExpense = PaybackPick(suggestion, rest: 64)
        #expect(fromExpense.expenseFree == 64 && fromExpense.incomeFree == 80 && fromExpense.suggested == 64)
        #expect(fromExpense.left(after: 64).open == 0 && fromExpense.left(after: 64).income == 16)
    }

    // MARK: the page and the window on a real store

    @Test func linkFromAPaymentInThenChangeRemoveAndUndo() async throws {
        let (_, store) = try await setup([
            payment("trip", "-120.00", day: "2026-10-09", name: "Fictional Lake House", category: "groceries"),
            payment("in", "60.00", day: "2026-10-10", name: "Fictional Friend"),
            payment("old", "-30.00", day: "2026-01-05", name: "Fictional Old Shop")])
        #expect(store.dashboard?.total.expense == 150)

        // The payment in: the quiet action only.
        let incoming = try await page("in", in: store)
        var shown = try content(incoming)
        #expect(shown.links.isEmpty && shown.heading == nil && shown.summary == nil)
        #expect(shown.action == "Pays back an expense…")
        #expect(try content(incoming, .german).action == "Zahlt eine Ausgabe zurück …")

        // The window: the half fits first; its euros are filled in.
        incoming.paybacks.begin(detail: try #require(incoming.detail))
        let window = try #require(incoming.paybacks.window)
        #expect(window.direction == .moneyIn && !window.isEditing)
        await window.load()
        let first = try #require(window.suggestions?.first)
        #expect(first.transaction.id == "trip" && first.fit == .half)
        #expect(window.suggestions?.contains { $0.transaction.id == "old" } == false, "too long before: only the search finds it")
        #expect(PaybackWording.choiceLine(first, now: Self.now, language: .english) == "9 Oct · half")
        // The search finds what the suggestions leave out.
        window.query = "old shop"
        await window.search()
        #expect(window.results?.map(\.transaction.id) == ["old"] && window.resultsQuery == "old shop")
        window.query = ""
        await window.search()
        #expect(window.results == nil)
        // One payment on each side: a tick, then Next to the typed euros (brief 206).
        #expect(window.confirmsByAmount && !window.canNext && !window.canLink)
        window.toggle(first)
        #expect(window.isTicked(first.id) && window.confirmsByAmount && window.canNext)
        #expect(window.summary?.rows.map(\.name) == ["Fictional Lake House"])
        window.next()
        #expect(window.showsAmount && window.amountText == "60.00" && window.pick?.maximum == 60)
        #expect(window.afterAmount == "€60.00 still open.")
        window.amountText = "60,01"
        #expect(window.check == .tooMuch && !window.canConfirm)
        window.amountText = "60"
        #expect(window.canConfirm)
        #expect(await window.confirm())
        #expect(incoming.paybacks.window == nil, "the window closes")
        #expect(incoming.paybacks.undo?.message == "Linked: €60.00 paid back.")
        #expect(store.dashboard?.total.expense == 90 && store.dashboard?.total.income == 0)

        // The page follows: the link, what still counts, no action (all of it used).
        await incoming.refresh()
        shown = try content(incoming)
        #expect(shown.heading == "Pays back" && shown.links.map(\.payment) == ["trip"])
        #expect(shown.summary == "None of it counts as income." && shown.action == nil)

        // The expense's page: its link and its share; the rest can be linked still.
        let trip = try await page("trip", in: store)
        shown = try content(trip)
        #expect(shown.heading == "Paid back" && shown.links.first?.place == "Fictional Friend")
        #expect(shown.links.first?.linkedAmount == 60)
        #expect(shown.summary == "Your share, €60.00, counts as spent." && shown.action == "Also paid back by…")
        // Its list row counts its share and says why.
        let row = try #require(store.bankPayment("trip"))
        #expect(PaybackWording.rowAmount(row, language: .english) == "−60.00")
        let incomingRow = try #require(store.bankPayment("in"))
        #expect(PaybackWording.rowLine(incomingRow, name: { store.paybackName($0) }, language: .english)
                == "€60.00 · pays back Fictional Lake House")

        // Change the euros from the expense's page: its maximum is both rests plus the link's own.
        let link = try #require(shown.links.first)
        trip.paybacks.edit(link, detail: try #require(trip.detail))
        let change = try #require(trip.paybacks.window)
        await change.load()
        #expect(change.isEditing && change.pick?.maximum == 60 && change.amountText == "60.00")
        #expect(!change.canConfirm, "unchanged: nothing to save")
        change.amountText = "50"
        #expect(await change.confirm())
        #expect(trip.paybacks.undo?.message == "Changed to €50.00.")
        #expect(store.dashboard?.total.expense == 100 && store.dashboard?.total.income == 10)

        // Remove it; the undo bar's Undo brings it back.
        await trip.refresh()
        let changed = try #require(content(trip).links.first)
        #expect(changed.linkedAmount == 50)
        await trip.paybacks.remove(changed, direction: .moneyOut)
        #expect(trip.paybacks.undo?.message == "Link removed.")
        #expect(store.dashboard?.total.expense == 150)
        await trip.refresh()
        let removed = try content(trip)
        #expect(removed.links.isEmpty && removed.action == "Paid back to you…")
        let undo = try #require(trip.paybacks.undo?.undo)
        await undo()
        #expect(store.dashboard?.total.expense == 100)
        await trip.refresh()
        #expect(try content(trip).links.first?.linkedAmount == 50)
    }

    /// Where a payment cannot take part, the page shows nothing of it (server mode too).
    @Test func nothingWhereAPaymentCannotTakePart() async throws {
        let (_, store) = try await setup([payment("transfer", "-120.00", category: nil), payment("in", "60.00")])
        let loaded = try await page("in", in: store)
        #expect(try content(loaded).action != nil)
        // A detail without links and without a state (server mode, a transfer, a withdrawal): empty.
        let detail = try #require(loaded.detail)
        #expect(PaybackSectionContent(detail: detail, state: nil).isEmpty)
        // A state of the other direction never offers the action.
        #expect(PaybackSectionContent(detail: detail, state: PaybackState(direction: .moneyOut, rest: 60)).action == nil)
        #expect(PaybackSectionContent(detail: detail, state: PaybackState(direction: .moneyIn, rest: 0)).isEmpty)
    }

    /// A name that counts nothing (its one payment wholly used to pay back) keeps its own side on its page, in its
    /// "All from" line and in the search.
    @Test func aNameThatCountsNothingKeepsItsSide() async throws {
        let (_, store) = try await setup([payment("trip", "-120.00", name: "Fictional Lake House"),
                                          payment("in", "60.00", day: "2026-10-11", name: "Fictional Friend")])
        _ = try await store.setPayback(from: "in", to: "trip", amount: 60)
        let row = try #require(store.bankPayment("in"))
        let group = try #require(row.nameKey.flatMap { store.dashboard?.nameGroups?[$0] })
        #expect(group.moneyIn == 0 && group.moneyOut == 0 && !group.spends)
        #expect(NameWording.summary(group, language: .english) == "1 payment · €0.00 received")
        let key = try #require(row.nameKey)
        let page = try #require(store.namePage(key))
        #expect(!page.spends)
        let hit = try #require(store.searchNames("Fictional Friend").first)
        let line = SearchPage.Row(hit, group: group, now: Self.now, language: .english)
        #expect(line.moneyOut == nil && line.moneyIn == nil && line.nothing == "0.00")
        // An expense that counts: its side as before.
        let trip = try #require(store.bankPayment("trip"))
        let tripGroup = try #require(trip.nameKey.flatMap { store.dashboard?.nameGroups?[$0] })
        #expect(tripGroup.spends)
    }

    /// The tour's sample: the trip half paid back by a made-up friend, its page showing the link.
    @Test func theToursTripShowsItsLink() async throws {
        let world = try await TourWorld.make(in: PhoneTest.storage().root, now: Self.now, makeEngine: { try PhoneTest.engine() })
        defer { world.delete() }
        let id = try #require(world.paybackTrip)
        let trip = try await page(id, in: world.dashboard)
        let shown = try content(trip)
        #expect(shown.links.map(\.place) == [TourData.paybackPersonName])
        #expect(shown.summary == "Your share, €64.00, counts as spent." && shown.action == "Also paid back by…")
    }
}
