import Foundation
import Testing
@testable import Aresium

/// Brief 41's comfort items with logic: a payment row's long press offers what its page offers and opens the same
/// windows, the import result goes with a swipe only where Dismiss would, and Log out logs out only after its question.
/// Everything is made up.
@MainActor
struct PaymentRowMenuTests {
    private let none = BackendAuth(token: nil)

    /// A phone store with a card payment from a shop that has more payments, a cash withdrawal, a cash receipt paid
    /// from it (so the withdrawal's category has a covered row), a card receipt waiting for its bank payment and a hand
    /// entry; the dashboard on it.
    private func phoneDashboard() async throws -> (PhoneBackend, DashboardStore) {
        let phone = try await PhoneTest.backend(chosen: ["groceries", "cash", "eating-out", "clothes"])
        _ = try await phone.importFiles([PhoneTest.vrBank([
            ("05.10.2026", "REWE Markt GmbH", "REWE SAGT DANKE", -2345),
            ("12.10.2026", "REWE Markt GmbH", "REWE SAGT DANKE", -1890),
            ("19.10.2026", "REWE Markt GmbH", "REWE SAGT DANKE", -3120),
            ("02.10.2026", "Geldautomat Fiktivbank", "Bargeldauszahlung", -10000)])], auth: none)
        _ = try await phone.saveReceipt(ReceiptDraft(date: "2026-10-04", shop: "Café Fiktiva", total: 23.40, currency: "EUR",
                                                     euroAmount: nil, method: .cash, category: "eating-out",
                                                     categorySource: .starter, rows: ["Café Fiktiva", "SUMME 23,40"],
                                                     from: "text"))
        _ = try await phone.saveReceipt(ReceiptDraft(date: "2026-10-26", shop: "MUSTERMARKT LINDE", total: 27.65,
                                                     currency: "EUR", euroAmount: nil, method: .card, category: "groceries",
                                                     categorySource: .starter, rows: ["MUSTERMARKT LINDE", "SUMME 27,65"],
                                                     from: "text"))
        _ = try await phone.addCashEntry(CashEntryDraft(direction: .out, amount: 12, date: "2026-10-06", what: "Flohmarkt",
                                                        category: "clothes", paidFrom: nil))
        let session = await PhoneTest.session(nil, transport: RoutedTransport())
        let dashboard = DashboardStore(session: session, backend: phone)
        await dashboard.reload()
        return (phone, dashboard)
    }

    // MARK: the menu follows the page

    @Test func eachRowOffersWhatItsPageOffers() async throws {
        let (_, dashboard) = try await phoneDashboard()
        let transactions = try #require(dashboard.dashboard?.transactions)
        let rewe = try #require(transactions.first { $0.place.contains("REWE") && $0.receiptId == nil })
        let withdrawal = try #require(transactions.first { $0.cashWithdrawal == true && $0.coveredBy == nil })
        let covered = try #require(transactions.first { $0.coveredBy != nil })
        let receipts = transactions.filter { $0.receiptId != nil }
        #expect(receipts.count == 3, "the cash receipt, the waiting card receipt and the hand entry")

        #expect(dashboard.page(for: rewe) == .payment)
        // Brief 44: Rename (phone mode, own names on) and "All from" while the name has other payments (REWE has two).
        #expect(dashboard.rowActions(for: rewe) == [.changeCategory, .rename, .allFromName])
        #expect(dashboard.page(for: withdrawal) == .payment)
        #expect(dashboard.rowActions(for: withdrawal) == [.changeCategory, .rename], "its only payment: no line")
        #expect(dashboard.page(for: covered) == .covered(receiptIDs: covered.coveredBy ?? []))
        #expect(dashboard.rowActions(for: covered).isEmpty, "the covered row's list has nothing to change")
        for receipt in receipts {
            #expect(dashboard.page(for: receipt) == .receipt(id: receipt.receiptId!))
            #expect(dashboard.rowActions(for: receipt) == [.edit], "a receipt's and an entry's page have Edit")
        }

        // Every payment row offers Change exactly when its page shows it (`TransactionDetailSheet`: `choices`).
        for transaction in transactions where dashboard.page(for: transaction) == .payment {
            let page = dashboard.transactionDetailStore(for: transaction)
            await page.load()
            #expect(dashboard.rowActions(for: transaction).contains(.changeCategory) == !page.choices.isEmpty,
                    "\(transaction.place)")
        }
    }

    @Test func aPageWithoutChangeGivesNoChange() async throws {
        // The server's dashboard with nothing to change income to: an income row's page shows no Change, so its row
        // offers none; spending still has its choices.
        let sample = try JSONSerialization.jsonObject(with: try JSONEncoder().encode(Dashboard.sample())) as! [String: Any]
        var edited = sample
        edited["pick"] = ["spend": (sample["pick"] as! [String: Any])["spend"]!, "income": [String]()]
        let transport = RoutedTransport()
        transport.answer("GET /api/data", 200, try JSONSerialization.data(withJSONObject: edited))
        let session = await PhoneTest.session("fictionalA", transport: transport)
        let dashboard = DashboardStore(session: session, client: APIClient(transport: transport))
        await dashboard.reload()
        let transactions = try #require(dashboard.dashboard?.transactions)
        let income = try #require(transactions.first { $0.amount > 0 })
        let spending = try #require(transactions.first { $0.amount < 0 })
        #expect(dashboard.rowActions(for: income).isEmpty)
        #expect(dashboard.rowActions(for: spending) == [.changeCategory])
        #expect(dashboard.page(for: income) == .payment, "server mode has no receipt rows")
    }

    @Test func theServersSampleOffersChangeAsItsPagesDo() async throws {
        let dashboard = DashboardStore(session: EmpireSession(app: .aresium, storage: PhoneTokens()), sample: true)
        await dashboard.reload()
        let transactions = try #require(dashboard.dashboard?.transactions)
        for transaction in transactions.prefix(40) {
            let page = dashboard.transactionDetailStore(for: transaction)
            await page.load()
            #expect(dashboard.page(for: transaction) == .payment)
            #expect(dashboard.rowActions(for: transaction).contains(.changeCategory) == !page.choices.isEmpty)
        }
    }

    // MARK: the same windows, the same flow

    @Test func changeCategoryOpensTheChangeSheetWithTheSameFlow() async throws {
        let (phone, dashboard) = try await phoneDashboard()
        var recategorised = 0
        dashboard.onRecategorised = { recategorised += 1 }       // the tour's switch step listens here
        let rewe = try #require(dashboard.dashboard?.transactions.first { $0.place.contains("REWE") && $0.receiptId == nil })
        let store = dashboard.transactionDetailStore(for: rewe)
        #expect(store.detail == nil, "nothing loaded before the long press")

        await store.beginRecategorisationFromRow()
        #expect(store.showsRecategorisation, "the change sheet is open")
        #expect(store.detail?.id == rewe.id)
        #expect(store.mode == .switchCategory && store.target == nil && !store.canSave, "as from the page's Change")

        let eatingOut = try #require(try await phone.categories().name(of: "eating-out"))
        store.select(eatingOut)
        await store.save()
        let question = try #require(store.followUp, "Also the other payments from REWE?")
        #expect(question.count == 2)
        #expect(store.showsRecategorisation, "asked in the open sheet")
        #expect(recategorised == 0)
        await store.answerFollowUp(moveOthers: true)
        #expect(!store.showsRecategorisation, "the sheet closes with the answer")
        #expect(recategorised == 1)
        let moved = try await phone.ledger.payments().filter { $0.counterparty == "REWE Markt GmbH" }
        #expect(moved.count == 3 && moved.allSatisfy { $0.category == "eating-out" }, "the shop is learned, the others moved")
    }

    @Test func changeCategorySaysWhyWhenThePaymentCannotLoad() async throws {
        let (_, dashboard) = try await phoneDashboard()
        let rewe = try #require(dashboard.dashboard?.transactions.first { $0.place.contains("REWE") && $0.receiptId == nil })
        // A row whose payment is no longer in the store.
        let gone = Transaction(id: "no-such-payment", date: rewe.date, day: rewe.day, month: rewe.month,
                               amount: rewe.amount, categoryName: rewe.categoryName, tags: [], place: rewe.place,
                               city: rewe.city, categoriesIn: rewe.categoriesIn, incomeBuckets: [])
        let store = dashboard.transactionDetailStore(for: gone)
        await store.beginRecategorisationFromRow()
        #expect(store.showsRecategorisation && store.detail == nil && store.loadError != nil,
                "the sheet stays open with the reason and Retry")
    }

    @Test func editOpensTheReceiptsAndTheEntrysWindow() async throws {
        let (phone, dashboard) = try await phoneDashboard()
        let transactions = try #require(dashboard.dashboard?.transactions)
        for (title, isEntry) in [("Café Fiktiva", false), ("Flohmarkt", true)] {
            let row = try #require(transactions.first { $0.receiptId != nil && $0.place == title })
            guard case let .receipt(id) = dashboard.page(for: row) else {
                Issue.record("\(title): not a receipt's row")
                continue
            }
            let page = ReceiptPageModel(id: id, phone: phone) {}
            await page.beginEdit()
            switch page.editing?.phase {
            case .checking?: #expect(!isEntry, "a scanned receipt: the check window")
            case .entry?: #expect(isEntry, "a hand entry: Add cash's window")
            default: Issue.record("\(title): Edit did not open")
            }
        }
    }
}

/// The import result's swipe down (brief 41): it does what Dismiss does, only where Dismiss (or the send card's Not now)
/// is offered.
@MainActor
struct ImportBannerSwipeTests {
    private func sampleImports() -> ImportStore {
        let dashboard = DashboardStore(session: EmpireSession(app: .aresium, storage: PhoneTokens()), sample: true)
        return ImportStore(dashboard: dashboard, background: PhoneActivity())
    }

    @Test func aResultGoesWithASwipeAsWithDismiss() {
        let imports = sampleImports()
        #expect(!imports.closesBySwipe, "nothing shown")
        imports.show("12 new transactions imported · 1 skipped", success: true)
        #expect(imports.closesBySwipe)
        imports.show("Not available with sample data", success: false)
        #expect(imports.closesBySwipe, "a failure with nothing to retry offers Dismiss")
        imports.close()
        #expect(imports.banner == nil && !imports.closesBySwipe)
    }

    @Test func notWhileRetryAndDiscardAreOffered() {
        let imports = sampleImports()
        imports.seedDebugImportFailure()
        #expect(imports.canRetry && imports.banner != nil)
        #expect(!imports.closesBySwipe, "a swipe would put the files aside without a choice")
        imports.discard()
        #expect(!imports.closesBySwipe)
    }

    @Test func theSendCardGoesWithASwipeExceptWhileSending() throws {
        let imports = sampleImports()
        let outbox = BankOutbox(file: PhoneTest.storage().bankOutboxURL, api: BankOutboxAPI(transport: RoutedTransport()),
                                appVersion: "1.0 (7)")
        let card = try #require(outbox.card(for: [BankFormatTests.format]))
        imports.show("3 new · 0 already there", success: true, share: card)
        #expect(imports.closesBySwipe, "as its Not now")
        card.debugPhase(.sending)
        #expect(!imports.closesBySwipe, "Not now waits while it sends")
        card.debugPhase(.sent)
        #expect(imports.closesBySwipe)
    }
}

/// Settings → Account → Log out (brief 41): the row asks; only the question's Log out logs out.
@MainActor
struct LogOutQuestionTests {
    @Test func onlyTheQuestionsLogOutLogsOut() {
        let question = LogOutQuestion()
        var logOuts = 0
        question.ask()                                           // the row
        #expect(question.isAsking && logOuts == 0)
        question.cancel()
        #expect(!question.isAsking && logOuts == 0)
        question.ask()
        question.confirm { logOuts += 1 }
        #expect(!question.isAsking && logOuts == 1)
    }

    @Test func itSaysAllAresAppsAndAresiumKeepsItsData() {
        #expect(LogOutQuestion.title(.english) == "Log out?")
        #expect(LogOutQuestion.title(.german) == "Abmelden?")
        #expect(LogOutQuestion.message(app: "Aresus", keepsData: false, language: .english)
                == "You'll be logged out of all Ares apps on this iPhone.")
        #expect(LogOutQuestion.message(app: "Aresium", keepsData: true, language: .english)
                == "You'll be logged out of all Ares apps on this iPhone. Your data in Aresium stays.")
        #expect(LogOutQuestion.message(app: "Aresus", keepsData: false, language: .german)
                == "Du wirst in allen Ares-Apps auf diesem iPhone abgemeldet.")
        #expect(LogOutQuestion.message(app: "Aresium", keepsData: true, language: .german)
                == "Du wirst in allen Ares-Apps auf diesem iPhone abgemeldet. Deine Daten in Aresium bleiben.")
        #expect(EmpireAppIdentity.aresium.accountOptional, "Aresium's Settings say its data stays")
    }
}
