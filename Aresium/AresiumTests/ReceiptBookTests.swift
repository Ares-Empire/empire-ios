import Foundation
import Testing
@testable import Aresium

/// Receipts kept (brief 31 part B): the store (a version 1 store opens and moves on), export and restore (schema 2, and
/// 1 still), joining on Save and after a bank import, the question, waiting, cash and its covered row, deleting, the
/// check window's rules, all through the real engine. Everything is made up.
@MainActor
struct ReceiptBookTests {
    // MARK: helpers

    /// A store with these categories and these VR Bank rows (day, who, text, cents).
    private func phone(_ rows: [(String, String, String, Int)] = [],
                       chosen: [String] = ["groceries", "cash", "eating-out"]) async throws -> PhoneBackend {
        let phone = try await PhoneTest.backend(chosen: chosen)
        if !rows.isEmpty { _ = try await phone.importFiles([PhoneTest.vrBank(rows)], auth: BackendAuth(token: nil)) }
        return phone
    }

    private func draft(_ shop: String? = "MUSTERMARKT LINDE", date: String = "2026-10-26", total: Double = 27.65,
                       currency: String = "EUR", euros: Double? = nil, method: ReceiptMethod = .card,
                       category: String? = "groceries") -> ReceiptDraft {
        ReceiptDraft(date: date, shop: shop, total: total, currency: currency, euroAmount: euros, method: method,
                     category: category, categorySource: category == nil ? .none : .starter,
                     rows: ["\(shop ?? "")", "SUMME EUR \(total)"], from: "text")
    }

    private func payment(_ phone: PhoneBackend, _ who: String) async throws -> LedgerPayment {
        try #require(try await phone.ledger.payments().first { $0.counterparty == who })
    }

    private func dashboard(_ phone: PhoneBackend) async throws -> Dashboard {
        try await phone.dashboard(auth: BackendAuth(token: nil))
    }

    // MARK: storage

    /// A store made by schema version 1's code (AresiumTests/Fixtures/ledger-v1, made 2026-10-27 before receipts
    /// existed: 4 payments, 1 account, 1 learned shop, 1 layout, 4 chosen categories) opens, keeps everything and takes
    /// receipts.
    @Test func aStoreMadeBeforeReceiptsOpensAndKeepsEverything() async throws {
        let storage = PhoneTest.storage()
        try FileManager.default.createDirectory(at: storage.directory, withIntermediateDirectories: true)
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appending(path: "Fixtures/ledger-v1/ledger.store")
        try FileManager.default.copyItem(at: fixture, to: storage.storeURL)

        let ledger = try await Task.detached { try storage.open() }.value
        let summary = try await ledger.summary()
        #expect(summary.payments == 4 && summary.accounts == 1 && summary.learned == 1 && summary.layouts == 1)
        #expect(summary.chosen.map(\.id).prefix(3) == ["groceries", "cash", "eating-out"] && summary.chosen.count == 4)
        #expect(summary.receipts == 0)
        #expect(try await ledger.payments().contains { $0.counterparty == "REWE Markt GmbH" && $0.category == "groceries" })

        try await ledger.addReceipt(draft().receipt(id: "r1"))
        let reopened = try await Task.detached { try storage.open() }.value
        #expect(try await reopened.receipts().map(\.id) == ["r1"])
        #expect(try await reopened.summary().payments == 4)
    }

    @Test func exportAndRestoreCarryTheReceipts() async throws {
        let phone = try await phone([("26.10.2026", "MUSTERMARKT LINDE", "Kartenzahlung", -2765)])
        _ = try await phone.saveReceipt(draft())                                     // joins
        _ = try await phone.saveReceipt(draft("Café Fiktiva", total: 8.40, method: .cash, category: "eating-out"))
        let export = try await phone.export()
        #expect(export.schema == 4 && export.receipts.count == 2)
        let file = try export.encoded()
        #expect(String(decoding: file, as: UTF8.self).contains("\"receipts\""))

        let other = try await PhoneTest.backend()
        try await other.restore(file)
        let restored = try await other.receipts()
        #expect(restored.map(\.id).sorted() == export.receipts.map(\.id).sorted())
        #expect(restored.first { $0.method == .card }?.paymentID != nil, "the join is kept")
        #expect(try await other.ledger.summary().receipts == 2)
        // A store with receipts is not empty: nothing restores into it.
        await #expect(throws: LedgerError.notEmpty) { try await other.restore(file) }
    }

    /// Exports made before receipts (schema 1, no `receipts`) still restore.
    @Test func aSchema1ExportStillRestores() async throws {
        let phone = try await phone([("26.10.2026", "MUSTERMARKT LINDE", "Kartenzahlung", -2765)])
        var old = try JSONSerialization.jsonObject(with: try await phone.export().encoded()) as! [String: Any]
        old["schema"] = 1
        old.removeValue(forKey: "receipts")
        let other = try await PhoneTest.backend()
        try await other.restore(try JSONSerialization.data(withJSONObject: old))
        #expect(try await other.ledger.summary().payments == 1)
        #expect(try await other.receipts().isEmpty)
        // A schema 1 file with receipts in it is not one Aresium wrote.
        old["receipts"] = [[String: Any]]()
        old["receipts"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode([draft().receipt(id: "x")]))
        #expect(throws: LedgerError.self) { try LedgerExport.decode(try JSONSerialization.data(withJSONObject: old)) }
    }

    /// "Delete Aresium data" and "Forgot the code?" delete the store, receipts with it.
    @Test func deletingAresiumDataTakesTheReceipts() async throws {
        let storage = PhoneTest.storage()
        let phone = try await PhoneTest.backend(storage: storage)
        _ = try await phone.saveReceipt(draft(method: .cash))
        #expect(try await phone.ledger.summary().receipts == 1)
        try storage.delete()
        let fresh = try await Task.detached { try storage.open() }.value
        #expect(try await fresh.summary().receipts == 0)
    }

    // MARK: joining on Save

    /// One exact match joins at once; the payment was not sorted, so it takes the receipt's category (source receipt,
    /// "Sorted by its receipt."), and the purchase counts once.
    @Test func anExactMatchJoinsAndGivesAnUnsortedPaymentItsCategory() async throws {
        let phone = try await phone([("27.10.2026", "MUSTERMARKT LINDE", "Kartenzahlung", -2765)])
        let before = try await payment(phone, "MUSTERMARKT LINDE")
        #expect(before.category == nil, "the shop list does not know the made-up shop")

        guard case let .joined(joined, gave) = try await phone.saveReceipt(draft()) else { Issue.record("not joined"); return }
        #expect(joined.id == before.id && gave)
        let after = try await payment(phone, "MUSTERMARKT LINDE")
        #expect(after.category == "groceries" && after.categorySource == .receipt)
        let detail = try await phone.transactionDetail(id: after.id, auth: BackendAuth(token: nil))
        #expect(PaymentPage(detail, language: .english).categoryReason == "Sorted by its receipt.")
        #expect(PaymentPage(detail, language: .german).categoryReason == "Nach seinem Beleg sortiert.")

        let dashboard = try await dashboard(phone)
        #expect(dashboard.byMonth["2026-10"]?.expense == 27.65, "counted once")
        #expect(!dashboard.transactions.contains { $0.receiptId != nil })
        #expect(try await phone.receipt(joinedTo: after.id)?.state == .joined)
    }

    /// A payment sorted before keeps its category when a receipt joins it.
    @Test func aSortedPaymentKeepsItsCategory() async throws {
        let phone = try await phone([("27.10.2026", "MUSTERMARKT LINDE", "Kartenzahlung", -2765)])
        let id = try await payment(phone, "MUSTERMARKT LINDE").id
        try await phone.ledger.setCategory(id, category: "eating-out", source: .manual)
        guard case .joined(_, false) = try await phone.saveReceipt(draft()) else { Issue.record("not joined as such"); return }
        #expect(try await phone.ledger.payment(id)?.category == "eating-out")
    }

    /// Two payments with the receipt's amount: asked, never joined by itself. One is chosen: joined.
    @Test func twoSameAmountsAreAsked() async throws {
        let phone = try await phone([("26.10.2026", "MUSTERMARKT LINDE", "Kartenzahlung", -2765),
                                     ("28.10.2026", "MUSTERMARKT LINDE", "Kartenzahlung", -2765)])
        guard case let .question(question) = try await phone.saveReceipt(draft()) else { Issue.record("not asked"); return }
        #expect(question.options.count == 2)
        #expect(question.options.allSatisfy { $0.candidate?.why == .severalSame })
        #expect(ReceiptWording.difference(question.options[0].candidate, sameAmount: 2, language: .english)
                == "One of 2 payments with this amount")
        #expect(try await phone.receipt(question.receipt.id)?.state == .waiting, "nothing joined before the answer")

        try await phone.answer(question, with: question.options[1].payment.id)
        #expect(try await phone.receipt(question.receipt.id)?.paymentID == question.options[1].payment.id)
    }

    /// The bank took €20 more at the same shop: cash back or a tip, asked.
    @Test func cashBackIsAsked() async throws {
        let phone = try await phone([("26.10.2026", "MUSTERMARKT LINDE", "Kartenzahlung", -4765)])
        guard case let .question(question) = try await phone.saveReceipt(draft()) else { Issue.record("not asked"); return }
        let option = try #require(question.options.first)
        #expect(option.candidate?.why == .amountDiffers && option.candidate?.difference == 20)
        #expect(ReceiptWording.difference(option.candidate, sameAmount: 0, language: .english)
                == "€20.00 more: cash back or a tip?")
        #expect(ReceiptWording.difference(option.candidate, sameAmount: 0, language: .german)?
                    .replacingOccurrences(of: "\u{00A0}", with: " ") == "20,00 € mehr: Bargeld an der Kasse oder Trinkgeld?")

        // None of these: it waits, and those payments are not offered for it again.
        try await phone.answer(question, with: nil)
        #expect(try await phone.receipt(question.receipt.id)?.declined == [option.payment.id])
        #expect(try await phone.matchWaitingReceipts().questions.isEmpty)
    }

    /// No payment yet: it waits and counts on its own, marked as waiting, in its category.
    @Test func withoutItsPaymentItWaitsAndCounts() async throws {
        let phone = try await phone()
        #expect(try await phone.saveReceipt(draft()) == .waiting)
        let row = try #require(try await dashboard(phone).transactions.first { $0.receiptId != nil })
        #expect(row.isWaitingReceipt && row.amount == -27.65 && row.categoryName == "Groceries")
    }

    // MARK: after a bank import

    @Test func afterAnImportWaitingReceiptsJoinOrAreAsked() async throws {
        let phone = try await phone()
        _ = try await phone.saveReceipt(draft())                                        // waits for 27.65
        _ = try await phone.saveReceipt(draft("Pizzeria Fiktiva", total: 23.40, category: "eating-out"))
        let results = try await phone.importFiles([PhoneTest.vrBank([
            ("27.10.2026", "MUSTERMARKT LINDE", "Kartenzahlung", -2765),
            ("27.10.2026", "PIZZERIA FIKTIVA", "Kartenzahlung", -2340),
            ("29.10.2026", "PIZZERIA FIKTIVA", "Kartenzahlung", -2340),
        ])], auth: BackendAuth(token: nil))
        let files = PhoneTest.phoneResults(results)
        #expect(files.map(\.receiptsJoined) == [1])
        #expect(phone.importSummary(results).hasSuffix("· 1 receipt joined"))
        #expect(ImportWording.summary(files, language: .german).hasSuffix("· 1 Beleg verbunden"))
        #expect(phone.receiptQuestions.map { $0.receipt.shop } == ["Pizzeria Fiktiva"])
        #expect(phone.receiptQuestions.first?.options.count == 2)
        let joined = try await phone.receipts().first { $0.shop == "MUSTERMARKT LINDE" }
        #expect(joined?.state == .joined)
    }

    // MARK: cash

    /// A cash receipt counts in its category and takes its amount out of the withdrawal before it: the withdrawal's
    /// category shows a "covered by receipts" row, the total spending stays the same.
    @Test func aCashReceiptIsCoveredByTheWithdrawalBeforeIt() async throws {
        let phone = try await phone([("02.10.2026", "Geldautomat Fiktivbank", "Bargeldauszahlung", -10000)])
        let withdrawal = try await payment(phone, "Geldautomat Fiktivbank")
        #expect(withdrawal.category == "cash")
        let before = try await dashboard(phone).byMonth["2026-10"]?.expense

        #expect(try await phone.saveReceipt(draft("Café Fiktiva", date: "2026-10-05", total: 23.40, method: .cash,
                                                  category: "eating-out")) == .cash)
        let dashboard = try await dashboard(phone)
        let receiptRow = try #require(dashboard.transactions.first { $0.receiptId != nil })
        #expect(receiptRow.amount == -23.40 && receiptRow.categoryName == "Eating out" && !receiptRow.isWaitingReceipt)
        let covered = try #require(dashboard.transactions.first { $0.coveredBy != nil })
        #expect(covered.amount == 23.40 && covered.categoryName == "Cash withdrawals" && covered.coveredBy == [receiptRow.receiptId!])
        #expect(covered.incomeBuckets.isEmpty, "never income")
        #expect(dashboard.byMonth["2026-10"]?.expense == before, "the spending stays the same")
    }

    /// Deleting a receipt unjoins it (its payment loses the category it took from it) and uncovers the cash.
    @Test func deletingAReceiptUnjoinsAndUncovers() async throws {
        let phone = try await phone([("27.10.2026", "MUSTERMARKT LINDE", "Kartenzahlung", -2765),
                                     ("02.10.2026", "Geldautomat Fiktivbank", "Bargeldauszahlung", -10000)])
        _ = try await phone.saveReceipt(draft())
        _ = try await phone.saveReceipt(draft("Café Fiktiva", date: "2026-10-05", total: 23.40, method: .cash,
                                              category: "eating-out"))
        let receipts = try await phone.receipts()
        #expect(try await dashboard(phone).transactions.contains { $0.coveredBy != nil })

        for receipt in receipts { try await phone.deleteReceipt(receipt.id) }
        #expect(try await payment(phone, "MUSTERMARKT LINDE").category == nil, "the category it took from the receipt goes")
        let dashboard = try await dashboard(phone)
        #expect(!dashboard.transactions.contains { $0.coveredBy != nil || $0.receiptId != nil })
        #expect(try await phone.receipts().isEmpty)
    }

    /// Unjoined by hand: it waits again and counts on its own.
    @Test func unjoiningMakesItWaitAgain() async throws {
        let phone = try await phone([("27.10.2026", "MUSTERMARKT LINDE", "Kartenzahlung", -2765)])
        _ = try await phone.saveReceipt(draft())
        let receipt = try #require(try await phone.receipts().first)
        try await phone.unjoin(receipt: receipt.id)
        #expect(try await phone.receipt(receipt.id)?.state == .waiting)
        #expect(try await dashboard(phone).transactions.contains { $0.isWaitingReceipt })
        // "Join with a payment…" offers it again, and joins it.
        let options = try await phone.joinOptions(for: receipt.id)
        #expect(options.map(\.payment.counterparty) == ["MUSTERMARKT LINDE"])
        try await phone.join(receipt: receipt.id, to: options[0].payment.id)
        #expect(try await phone.receipt(receipt.id)?.state == .joined)
    }

    /// Changing a receipt's category teaches Aresium its shop, as a Switch does.
    @Test func changingTheCategoryLearnsTheShop() async throws {
        let phone = try await phone()
        _ = try await phone.saveReceipt(draft("Pizzeria Fiktiva", total: 23.40, category: nil))
        let receipt = try #require(try await phone.receipts().first)
        try await phone.setReceiptCategory(receipt.id, to: "eating-out")
        #expect(try await phone.receipt(receipt.id)?.category == "eating-out")
        #expect(try await phone.ledger.learned().values.contains("eating-out"))
    }

    // MARK: the check window

    private func reading(shop: String? = "MUSTERMARKT LINDE", date: String? = "2026-10-26", total: Double? = 27.65,
                         currency: String? = "EUR", method: ReceiptMethod? = .card, categoryId: String? = nil,
                         sure: Bool = true) -> ReceiptReading {
        ReceiptReading(shop: shop, categoryId: categoryId, date: date, time: "14:31", total: total, currency: currency,
                       method: method, language: "de", from: "text", rows: ["MUSTERMARKT LINDE"],
                       sure: .init(shop: sure, date: sure, total: sure, method: sure))
    }

    @Test func unsureFieldsComeFirst() async throws {
        let phone = try await phone()
        var unsure = reading()
        unsure.sure = .init(shop: true, date: false, total: true, method: false)
        unsure.method = nil
        let check = ReceiptCheckModel(reading: unsure, phone: phone, language: .english)
        #expect(check.fieldsToCheck == [.date, .method] && check.fieldsRead == [.shop, .total])
        #expect(check.note(.date) == "Aresium is not sure about this.")
        #expect(check.note(.method) == "Not found on the receipt.")
        #expect(check.note(.shop) == nil)

        let all = ReceiptCheckModel(reading: reading(), phone: phone, language: .english)
        #expect(all.fieldsToCheck.isEmpty && all.canSave)

        let nothing = ReceiptCheckModel(reading: .nothing, phone: phone, language: .english)
        #expect(nothing.nothingRead && nothing.fieldsToCheck == ReceiptCheckModel.Field.allCases)
        #expect(nothing.shop.isEmpty && nothing.totalText.isEmpty && nothing.method == nil)
        #expect(nothing.missing == "Type the total.")
        nothing.totalText = "12,30"
        nothing.method = .cash
        #expect(nothing.canSave && nothing.draft()?.total == 12.30)
    }

    /// Card or cash not read: nothing chosen and Save waits; with a matching bank payment, Card is chosen (and says why).
    @Test func cardOrCashNotReadMustBeChosen() async throws {
        let empty = try await phone()
        let alone = ReceiptCheckModel(reading: reading(method: nil, sure: false), phone: empty, language: .english)
        await alone.load()
        #expect(alone.method == nil && !alone.canSave && alone.missing == "Choose card or cash.")

        let withPayment = try await phone([("27.10.2026", "MUSTERMARKT LINDE", "Kartenzahlung", -2765)])
        let matched = ReceiptCheckModel(reading: reading(method: nil, sure: false), phone: withPayment, language: .english)
        await matched.load()
        #expect(matched.method == .card && matched.cardBecauseOfMatch && matched.canSave)
        #expect(matched.note(.method) == "Not on the receipt. Card is chosen because a bank payment matches.")
    }

    /// Another currency paid in cash: the amount in euros is asked and required; the dashboard counts the euros.
    @Test func foreignCashNeedsTheAmountInEuros() async throws {
        let phone = try await phone()
        let check = ReceiptCheckModel(reading: reading(shop: "Fictional Café", total: 12.40, currency: "GBP", method: .cash),
                                      phone: phone, language: .english)
        #expect(check.isForeign && check.needsEuros && !check.canSave)
        #expect(check.missing == "Type what it cost in euros.")
        check.euroText = "14,56"
        #expect(check.canSave)
        guard case .cash = try #require(await check.save()) else { Issue.record("not saved as cash"); return }
        let receipt = try #require(try await phone.receipts().first)
        #expect(receipt.total == "12.40" && receipt.currency == "GBP" && receipt.euroAmount == "14.56" && receipt.euros == 14.56)
        let row = try #require(try await dashboard(phone).transactions.first { $0.receiptId == receipt.id })
        #expect(row.amount == -14.56)

        // Paid by card, it is not asked: the bank payment in euros will say.
        check.method = .card
        #expect(!check.needsEuros && check.canSave)
    }

    /// A card receipt in another currency waits outside the dashboard until it is joined.
    @Test func aForeignCardReceiptWaitsOutsideTheDashboard() async throws {
        let phone = try await phone()
        #expect(try await phone.saveReceipt(draft("Fictional Shop", total: 12.40, currency: "GBP")) == .waiting)
        #expect(try await dashboard(phone).transactions.isEmpty)
        #expect(try await phone.receipts().first?.state == .waiting)
    }

    /// The preset category is the shop list's, kept as such; a category picked by hand teaches the shop.
    @Test func thePresetCategoryAndOnePickedByHand() async throws {
        let phone = try await phone()
        let preset = ReceiptCheckModel(reading: reading(shop: "REWE", categoryId: "groceries"), phone: phone)
        await preset.load()
        #expect(preset.category == "groceries" && preset.draft()?.categorySource == .starter)
        #expect(preset.choices.last?.id == nil, "Not sorted is offered last")
        preset.category = "eating-out"
        #expect(preset.draft()?.categorySource == .manual)
        // A category the person has not chosen is not preset.
        let notChosen = ReceiptCheckModel(reading: reading(shop: "dm", categoryId: "drugstore"), phone: phone)
        await notChosen.load()
        #expect(notChosen.category == nil)
    }

    // MARK: words

    @Test func theStateLinesInBothLanguages() {
        #expect(ReceiptWording.state(.waiting, language: .english) == "Waiting for the bank statement")
        #expect(ReceiptWording.state(.waiting, language: .german) == "Wartet auf den Kontoauszug")
        #expect(ReceiptWording.state(.cash, language: .german) == "Bar bezahlt")
        #expect(ReceiptAmount.typed("1.027,65") == 1027.65 && ReceiptAmount.typed("27.5") == 27.5
                && ReceiptAmount.typed("€ 12") == 12 && ReceiptAmount.typed("abc") == nil && ReceiptAmount.typed("0") == nil)
    }

    // MARK: the made-up receipt through Vision and the engine

    @Test func theMadeUpReceiptIsReadByTheEngine() async throws {
        let phone = try await phone()
        let capture = try await ReceiptReader.read([ReceiptPage(image: ReceiptSample.image())])
        let reading = try await phone.readReceipt(capture)
        #expect(reading.from == "code")
        #expect(reading.total == 27.65 && reading.currency == "EUR" && reading.method == .card)
        #expect(reading.date == "2026-10-26")
        #expect(reading.shop?.localizedCaseInsensitiveContains("Mustermarkt") == true)
        #expect(reading.rows.contains { $0.contains("SUMME") })
        print("MADE-UP READING", reading)
    }
}
