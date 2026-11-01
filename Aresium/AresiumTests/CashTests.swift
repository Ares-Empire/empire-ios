import Foundation
import Testing
@testable import Aresium

/// Cash (brief 33 part B, the engine of brief 32): hand entries spent and received (stored as receipts of kind manual,
/// never joined), Paid from (saved, passed to the engine, cleared when its source goes), the Cash page's numbers and
/// words from the engine's `cash`, the Add cash window's categories, the name check, and a store with only cash
/// showing the dashboard. All through the real engine; everything is made up.
@MainActor
struct CashTests {
    // MARK: helpers

    private static let chosen = ["groceries", "cash", "eating-out", "clothes", "salary", "parents-family"]

    /// A store with these categories and these VR Bank rows (day, who, text, cents).
    private func phone(_ rows: [(String, String, String, Int)] = []) async throws -> PhoneBackend {
        let phone = try await PhoneTest.backend(chosen: Self.chosen)
        if !rows.isEmpty { _ = try await phone.importFiles([PhoneTest.vrBank(rows)], auth: BackendAuth(token: nil)) }
        return phone
    }

    private func withdrawal(_ day: String, cents: Int = -10000) -> (String, String, String, Int) {
        (day, "Geldautomat Fiktivbank", "Bargeldauszahlung", cents)
    }

    private func cashReceipt(_ shop: String, date: String, total: Double, category: String? = "groceries") -> ReceiptDraft {
        ReceiptDraft(date: date, shop: shop, total: total, currency: "EUR", method: .cash, category: category,
                     categorySource: category == nil ? .none : .starter, rows: [shop], from: "text")
    }

    private func entry(_ direction: ReceiptDirection, _ amount: Double, _ date: String, _ what: String?,
                       category: String? = nil, paidFrom: String? = nil) -> CashEntryDraft {
        CashEntryDraft(direction: direction, amount: amount, date: date, what: what, category: category, paidFrom: paidFrom)
    }

    private func dashboard(_ phone: PhoneBackend) async throws -> Dashboard {
        try await phone.dashboard(auth: BackendAuth(token: nil))
    }

    private func page(_ phone: PhoneBackend) async throws -> CashPage {
        CashPage(cash: try #require(try await phone.cash()))
    }

    // MARK: hand entries

    /// Spent and received entries are kept as receipts of kind manual: cash, their direction, no rows, never a bank
    /// payment, not even when a bank payment of the same amount and day comes in.
    @Test func paidFromListsTheLastThreeMonthsFirst() {
        func source(_ id: String, _ date: String) -> CashSource {
            CashSource(CashMovement(id: id, date: date, amount: 100, kind: .withdrawal, place: "Geldautomat Fiktivbank",
                                    category: "Cash withdrawals", paidFrom: nil, coveredBy: [], left: 100))
        }
        let sources = [source("oct", "2026-10-18"), source("aug", "2026-08-01"), source("jul", "2026-07-18"),
                       source("mar", "2026-03-18")]
        let groups = CashPage.split(sources, before: "2026-10-28", selected: nil)
        #expect(groups.recent.map(\.id) == ["oct", "aug"])                // 10 and 88 days back
        #expect(groups.older.map(\.id) == ["jul", "mar"])                 // 102 and 224 days back: behind "Show older"
        // A chosen older source stays in sight.
        #expect(CashPage.split(sources, before: "2026-10-28", selected: "mar").recent.map(\.id) == ["oct", "aug", "mar"])
    }

    @Test func handEntriesAreStoredWithTheirFieldsAndNeverJoined() async throws {
        let phone = try await phone()
        let spent = try await phone.addCashEntry(entry(.out, 12, "2026-10-06", " Flohmarkt ", category: "clothes"))
        let gift = try await phone.addCashEntry(entry(.in, 50, "2026-10-03", "Geburtstag Oma", category: "parents-family"))

        let storedSpent = try #require(try await phone.receipt(spent.id))
        #expect(storedSpent.kind == .manual && storedSpent.method == .cash && storedSpent.direction == .out)
        #expect(storedSpent.shop == "Flohmarkt" && storedSpent.total == "12.00" && storedSpent.currency == "EUR")
        #expect(storedSpent.rows.isEmpty && storedSpent.paymentID == nil && storedSpent.categorySource == .manual)
        let storedGift = try #require(try await phone.receipt(gift.id))
        #expect(storedGift.direction == .in && storedGift.kind == .manual && storedGift.paidFrom == nil)

        // A bank payment of the same amount and day changes nothing: entries are never matched or joined.
        _ = try await phone.importFiles([PhoneTest.vrBank([("06.10.2026", "Flohmarkt", "Kartenzahlung", -1200)])],
                                        auth: BackendAuth(token: nil))
        #expect(try await phone.receipt(spent.id)?.paymentID == nil)
        #expect(phone.receiptQuestions.isEmpty)

        // Counted: the spent one in its category, the received one as income in its category.
        let dashboard = try await dashboard(phone)
        let spentRow = try #require(dashboard.transactions.first { $0.receiptId == spent.id })
        #expect(spentRow.amount == -12 && spentRow.categoryName == "Clothes")
        let giftRow = try #require(dashboard.transactions.first { $0.receiptId == gift.id })
        #expect(giftRow.amount == 50 && giftRow.incomeBuckets == ["Parents & family"])
        #expect(dashboard.byMonth["2026-10"]?.income == 50)
        #expect(ReceiptRowWording.line(giftRow, language: .english) == "Cash received")
        #expect(ReceiptRowWording.line(spentRow, movement: dashboard.cash?.movements.first { $0.id == spent.id },
                                       language: .english) == "Cash, entered by hand")
    }

    /// The engine never gets a payment for a hand entry (it would drop it as joined), even if one were stored.
    @Test func aHandEntryNeverCarriesAPaymentToTheEngine() {
        var stored = entry(.out, 12, "2026-10-06", "Flohmarkt").receipt(id: "e1")
        stored.paymentID = "p1"
        let source = PhoneDashboard.source(stored, named: [:])
        #expect(source.paymentId == nil && source.kind == .manual && source.direction == .out)
        // Received cash is paid from nothing; card money neither.
        var received = entry(.in, 50, "2026-10-03", nil).receipt(id: "e2")
        received.paidFrom = "w1"
        #expect(PhoneDashboard.source(received, named: [:]).paidFrom == nil)
    }

    /// Add cash's window: spending categories for spent, income ones for received (one's own in both, Not sorted
    /// last); switching drops a category that does not fit and Paid from for received; Save keeps it, Edit updates it.
    @Test func theAddCashWindow() async throws {
        let phone = try await phone([withdrawal("02.10.2026")])
        let custom = try await phone.addCustom(named: "Fictional hobby", side: .spend)
        let window = CashEntryModel(phone: phone, today: try #require(ReceiptDay.date("2026-10-06")), language: .english)
        await window.load()
        let spendIDs = window.choices.map(\.id)
        #expect(spendIDs.contains("eating-out") && spendIDs.contains("cash") && spendIDs.contains(custom))
        #expect(!spendIDs.contains("salary") && spendIDs.last == .some(nil))
        #expect(window.missing == "Type the amount." && !window.canSave)
        #expect(window.sources?.map(\.kind) == [.withdrawal] && window.paidFromName == "Automatic")

        window.category = "eating-out"
        window.paidFrom = try #require(window.sources?.first?.id)
        #expect(window.paidFromName == "Withdrawal of 2 Oct")
        window.direction = .in
        #expect(window.category == nil && window.paidFrom == nil, "eating out is no income; received is paid from nothing")
        #expect(window.choices.map(\.id).contains("salary") && !window.choices.map(\.id).contains(custom))
        window.category = "parents-family"
        window.amountText = "50"
        window.what = "Geburtstag Oma"
        let saved = try #require(await window.save())
        #expect(saved.direction == .in && saved.category == "parents-family" && saved.total == "50.00")

        let edit = CashEntryModel(editing: saved, phone: phone, language: .english)
        await edit.load()
        #expect(edit.amountText == "50.00" && edit.what == "Geburtstag Oma" && edit.direction == .in)
        edit.amountText = "60,00"
        let updated = try #require(await edit.save())
        #expect(updated.id == saved.id && updated.created == saved.created)
        #expect(try await phone.receipt(saved.id)?.total == "60.00")
    }

    // MARK: Paid from

    /// Paid from is kept and passed to the engine: the spending takes from that source, the withdrawal stays untouched;
    /// set back to automatic, the latest source before it pays.
    @Test func paidFromIsSavedAndPassed() async throws {
        let phone = try await phone([withdrawal("05.10.2026")])
        let gift = try await phone.addCashEntry(entry(.in, 50, "2026-10-03", "Geburtstag Oma", category: "parents-family"))
        let spent = try await phone.addCashEntry(entry(.out, 20, "2026-10-06", "Flohmarkt", category: "clothes",
                                                       paidFrom: gift.id))
        #expect(try await phone.receipt(spent.id)?.paidFrom == gift.id)
        let input = PhoneDashboard.input(payments: try await phone.ledger.payments(), list: try await phone.categories(),
                                         today: "2026-10-27", receipts: try await phone.receipts())
        #expect(input.receipts?.first { $0.id == spent.id }?.paidFrom == gift.id)

        var page = try await page(phone)
        let withdrawalID = try #require(page.cash.movements.first { $0.kind == .withdrawal }?.id)
        #expect(page.movement(spent.id)?.paidFrom == [gift.id])
        #expect(page.movement(gift.id)?.left == 30 && page.movement(withdrawalID)?.left == 100)
        #expect(CashWording.paidFrom(try #require(page.movement(spent.id)), in: page, language: .english)
                == "From the cash received on 3 Oct")

        try await phone.setPaidFrom(spent.id, to: withdrawalID)
        page = try await self.page(phone)
        #expect(page.movement(spent.id)?.paidFrom == [withdrawalID] && page.movement(withdrawalID)?.left == 80)
        try await phone.setPaidFrom(spent.id, to: nil)
        #expect(try await phone.receipt(spent.id)?.paidFrom == nil)
        page = try await self.page(phone)
        #expect(page.movement(spent.id)?.paidFrom == [withdrawalID], "automatic: the latest source before it")

        // A card receipt has no Paid from.
        _ = try await phone.saveReceipt(ReceiptDraft(date: "2026-10-07", shop: "Fictional", total: 5, currency: "EUR",
                                                     method: .card, categorySource: .none, rows: [], from: "text"))
        let card = try #require(try await phone.receipts().first { $0.method == .card })
        try await phone.setPaidFrom(card.id, to: withdrawalID)
        #expect(try await phone.receipt(card.id)?.paidFrom == nil)
    }

    /// Deleting a gift: what was paid from it goes back to automatic, and the engine takes it from the withdrawal
    /// before it; the gift is gone from the page.
    @Test func deletingAGift() async throws {
        let phone = try await phone([withdrawal("02.10.2026")])
        let gift = try await phone.addCashEntry(entry(.in, 50, "2026-10-03", "Geburtstag Oma"))
        let spent = try await phone.addCashEntry(entry(.out, 20, "2026-10-06", "Flohmarkt", paidFrom: gift.id))
        #expect(try await page(phone).movement(spent.id)?.paidFrom == [gift.id])

        try await phone.deleteReceipt(gift.id)
        #expect(try await phone.receipt(spent.id)?.paidFrom == nil)
        let page = try await page(phone)
        #expect(page.movement(gift.id) == nil)
        let withdrawal = try #require(page.cash.movements.first { $0.kind == .withdrawal })
        #expect(page.movement(spent.id)?.paidFrom == [withdrawal.id] && withdrawal.left == 80)
        // The withdrawal's category shows the part taken as accounted for, now by the entry.
        let covered = try #require(try await dashboard(phone).transactions.first { $0.coveredBy != nil })
        #expect(covered.coveredBy == [spent.id] && covered.amount == 20)
        #expect(ReceiptRowWording.title(covered, language: .english) == "Accounted for")
        #expect(ReceiptRowWording.line(covered, language: .german) == "Dort gezählt, wo es ausgegeben wurde")
    }

    // MARK: the Cash page

    /// Two months: September a withdrawal and a cash receipt; October a gift, a withdrawal, an entry paid from the gift
    /// and a receipt the withdrawal pays. The page's numbers and movements are the engine's.
    @Test func theCashPageOverTwoMonths() async throws {
        let phone = try await phone([withdrawal("02.09.2026"), withdrawal("05.10.2026")])
        let september = try await phone.saveReceipt(cashReceipt("Fictional Market", date: "2026-09-05", total: 30))
        #expect(september == .cash)
        let gift = try await phone.addCashEntry(entry(.in, 50, "2026-10-03", "Geburtstag Oma", category: "parents-family"))
        let flea = try await phone.addCashEntry(entry(.out, 20, "2026-10-06", "Flohmarkt", category: "clothes",
                                                      paidFrom: gift.id))
        _ = try await phone.saveReceipt(cashReceipt("Cafe Fiktiva", date: "2026-10-08", total: 25, category: "eating-out"))

        let dashboard = try await dashboard(phone)
        let page = CashPage(cash: try #require(dashboard.cash))
        #expect(page.monthKeys == ["2026-10", "2026-09"])
        #expect(page.month("2026-09") == CashMonth(withdrawn: 100, received: 0, spent: 30, unaccounted: 70))
        #expect(page.month("2026-10") == CashMonth(withdrawn: 100, received: 50, spent: 45, unaccounted: 75))
        #expect(page.month("2026-08") == .none)

        let october = page.movements(in: "2026-10")
        #expect(october.map(\.kind) == [.receipt, .manual, .withdrawal, .received], "newest first")
        #expect(october.map(\.amount) == [-25, -20, 100, 50], "from the wallet's side")
        #expect(october.first { $0.kind == .received }?.left == 30)
        #expect(october.first { $0.kind == .withdrawal }?.left == 75)
        let cafe = try #require(october.first)
        #expect(CashWording.paidFrom(cafe, in: page, language: .english) == "From the withdrawal of 5 Oct")
        #expect(CashWording.paidFrom(cafe, in: page, language: .german) == "Aus der Abhebung vom 5. Okt.")
        #expect(page.movement(flea.id)?.category == "Clothes")
        // Withdrawals are marked on the dashboard; the page counts in no total (the gift is income once, as such).
        #expect(dashboard.transactions.filter { $0.cashWithdrawal == true }.count == 2)
        #expect(dashboard.byMonth["2026-10"]?.income == 50)

        // Paid from's choices on the 6th: the sources on or before it, newest first.
        #expect(page.sources(onOrBefore: "2026-10-06").map(\.kind) == [.withdrawal, .received, .withdrawal])
        #expect(page.sources(onOrBefore: "2026-10-04", besides: gift.id).map(\.date) == ["2026-09-02"])
    }

    @Test func theCashWordsInBothLanguages() {
        func nbsp(_ text: String) -> String { text.replacingOccurrences(of: "\u{00A0}", with: " ") }
        #expect(CashWording.kind(.withdrawal, language: .english) == "Withdrawal")
        #expect(CashWording.kind(.received, language: .german) == "Erhalten")
        #expect(CashWording.kind(.manual, language: .german) == "Eintrag")
        #expect(CashWording.unaccounted(.english) == "Not accounted for")
        #expect(CashWording.unaccounted(.german) == "Nicht erfasst")
        #expect(nbsp(CashWording.left(30, language: .german)) == "30,00 € übrig")
        #expect(CashWording.left(30, language: .english) == "€30.00 left")
        #expect(CashRowWording.line(unaccounted: 75, language: .english) == "€75.00 not accounted for")
        #expect(nbsp(CashRowWording.line(unaccounted: 75, language: .german)) == "75,00 € nicht erfasst")
        #expect(CashRowWording.line(unaccounted: 0, language: .english) == "Withdrawals, cash received and spent")
        #expect(CashRowWording.monthLine(CashMonth(withdrawn: 100, received: 0, spent: 30, unaccounted: 70),
                                         language: .english) == "Withdrawn €100.00 · Spent €30.00 · €70.00 not accounted for")
        let empty = CashPage(cash: CashView(months: [:], movements: []))
        let alone = CashMovement(id: "r", date: "2026-10-08", amount: -5, kind: .receipt, place: "", category: "Uncategorised",
                                 paidFrom: [], coveredBy: nil, left: nil)
        #expect(CashWording.paidFrom(alone, in: empty, language: .english) == "From cash not recorded here")
        #expect(CashWording.title(alone, language: .english) == "Receipt")
        #expect(CashWording.choice(nil, language: .german) == "Automatisch")
    }

    // MARK: names

    /// "Cash" / "Bargeld" is the page, so one's own category may not take it (in either language, any case); the
    /// withdrawals' category is named by the engine.
    @Test func theNameCheckRefusesCash() async throws {
        let phone = try await phone()
        for language in [AppLanguage.english, .german] {
            let list = try await phone.categories(language: language)
            for name in ["Cash", "bargeld", "BARGELD", "Cash withdrawals", "Abhebungen"] {
                #expect(throws: LedgerError.nameTaken) { try list.checkedName(name) }
            }
            #expect(try list.checkedName("Cash box") == "Cash box")
        }
        await #expect(throws: LedgerError.nameTaken) { try await phone.addCustom(named: "Bargeld", side: .spend) }
        let list = try await phone.categories(language: .german)
        #expect(list.name(of: "cash") == "Abhebungen")
        #expect(try await phone.categories(language: .english).name(of: "cash") == "Cash withdrawals")
    }

    // MARK: only cash

    /// Cash entered by hand into a store without bank payments is data: the dashboard shows (not "No data yet") and
    /// builds from the entry alone, with the Cash page.
    @Test func onlyCashShowsTheDashboard() async throws {
        let phone = try await phone()
        let records = { phone.summary.payments + phone.summary.receipts }
        #expect(MainScreen.choose(tour: nil, hasMode: true, waitsForServerLogin: false, phoneRecords: records()) == .firstScreen)
        _ = try await phone.addCashEntry(entry(.out, 6.5, "2026-10-20", "Eis", category: "eating-out"))
        #expect(MainScreen.choose(tour: nil, hasMode: true, waitsForServerLogin: false, phoneRecords: records()) == .dashboard)
        let dashboard = try await dashboard(phone)
        #expect(dashboard.byMonth["2026-10"]?.expense == 6.5)
        #expect(dashboard.cash?.movements.map(\.kind) == [.manual])
        #expect(dashboard.cash?.movements.first?.paidFrom == [])
    }
}
