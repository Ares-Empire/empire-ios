import Foundation
import Testing
@testable import Aresium

/// Aresium's windows (brief 40): "Is this the same payment?" put off with Later (the receipt waits, nothing is declined,
/// the next import asks again), Back in an unknown bank's file check (over the readings and into and out of the column
/// check), and what each window's Cancel would throw away (the receipt window, Edit receipt, Add cash, Edit entry). All
/// through the real engine; everything is made up.
@MainActor
struct WindowComfortTests {
    // MARK: helpers

    /// A store with these categories and these VR Bank rows (day, who, text, cents).
    private func phone(_ rows: [(String, String, String, Int)] = [],
                       chosen: [String] = ["groceries", "cash", "eating-out", "clothes", "salary"]) async throws -> PhoneBackend {
        let phone = try await PhoneTest.backend(chosen: chosen)
        if !rows.isEmpty { _ = try await phone.importFiles([PhoneTest.vrBank(rows)], auth: BackendAuth(token: nil)) }
        return phone
    }

    private func draft(_ shop: String = "MUSTERMARKT LINDE", date: String = "2026-10-26", total: Double = 27.65,
                       method: ReceiptMethod = .card, category: String? = "groceries") -> ReceiptDraft {
        ReceiptDraft(date: date, time: "14:31", shop: shop, total: total, currency: "EUR", method: method,
                     category: category, categorySource: category == nil ? .none : .starter,
                     rows: [shop, "SUMME EUR \(total)"], from: "text")
    }

    private func reading(nothing: Bool = false) -> ReceiptReading {
        guard !nothing else { return .nothing }
        return ReceiptReading(shop: "MUSTERMARKT LINDE", date: "2026-10-26", time: "14:31", total: 27.65, currency: "EUR",
                              method: .card, language: "de", from: "text", rows: ["MUSTERMARKT LINDE", "SUMME EUR 27,65"],
                              sure: .init(shop: true, date: true, total: true, method: true))
    }

    /// Two payments of the made-up receipt's amount, so saving it asks.
    private static let twoOfItsAmount = [("26.10.2026", "MUSTERMARKT LINDE", "Kartenzahlung", -2765),
                                         ("27.10.2026", "MUSTERMARKT LINDE", "Kartenzahlung", -2765)]

    /// Waits a moment for work started without waiting (Later's banner line).
    private func settle(until done: () -> Bool) async throws {
        for _ in 0..<100 where !done() { try await Task.sleep(for: .milliseconds(20)) }
    }

    // MARK: Later

    /// The question inside the receipt window after Save: Later closes it, the receipt was kept and waits, nothing is
    /// declined (the same payments are offered again), and the banner says so as after an answer.
    @Test func laterInTheReceiptWindowLeavesTheReceiptWaiting() async throws {
        let phone = try await phone(Self.twoOfItsAmount)
        let model = ReceiptCaptureModel { phone }
        var lines: [String] = []
        model.saved = { lines.append($0) }
        model.read([ReceiptPage(image: ReceiptSample.image())])
        await model.finished()
        guard case .checking(let check)? = model.reading?.phase else { Issue.record("no check window"); return }
        check.method = .card
        await model.save(check)
        guard case .asking(let question)? = model.reading?.phase else { Issue.record("not asked"); return }

        model.later()
        #expect(model.reading == nil)
        try await settle { !lines.isEmpty }
        #expect(lines == ["Receipt saved. It waits for the bank statement."])
        let stored = try #require(try await phone.receipt(question.receipt.id))
        #expect(stored.state == .waiting && stored.paymentID == nil && stored.declined.isEmpty, "nothing declined")
        let again = try await phone.matchWaitingReceipts()
        #expect(again.questions.map(\.receipt.id) == [question.receipt.id], "the next import asks again")
        #expect(again.questions.first?.options.count == question.options.count)
    }

    /// A swipe down on the question is Later; a swipe while it reads only stops the reading (no line).
    @Test func aSwipeOnTheQuestionIsLater() async throws {
        let phone = try await phone(Self.twoOfItsAmount)
        let model = ReceiptCaptureModel { phone }
        var lines: [String] = []
        model.saved = { lines.append($0) }
        model.read([ReceiptPage(image: ReceiptSample.image())])
        model.swipedAway()
        #expect(model.reading == nil)
        try await Task.sleep(for: .milliseconds(100))
        #expect(lines.isEmpty, "a reading swiped away keeps nothing")

        model.read([ReceiptPage(image: ReceiptSample.image())])
        await model.finished()
        guard case .checking(let check)? = model.reading?.phase else { Issue.record("no check window"); return }
        check.method = .card
        await model.save(check)
        guard case .asking(let question)? = model.reading?.phase else { Issue.record("not asked"); return }
        model.swipedAway()
        try await settle { !lines.isEmpty }
        #expect(model.reading == nil && lines == ["Receipt saved. It waits for the bank statement."])
        #expect(try await phone.receipt(question.receipt.id)?.declined.isEmpty == true)
    }

    /// After a bank import with two receipts to ask about: Later on the first (`dismissQuestion`, what the sheet's
    /// Later and a swipe do) leaves it waiting with nothing declined, and the second is asked next; the next import
    /// asks the first again.
    @Test func laterAfterAnImportLeavesItWaitingAndTheNextIsAsked() async throws {
        let phone = try await phone()
        _ = try await phone.saveReceipt(draft())
        _ = try await phone.saveReceipt(draft("PIZZERIA FIKTIVA", date: "2026-10-27", total: 23.43, category: "eating-out"))
        _ = try await phone.importFiles([PhoneTest.vrBank(Self.twoOfItsAmount + [
            ("27.10.2026", "PIZZERIA FIKTIVA", "Kartenzahlung", -2343),
            ("28.10.2026", "PIZZERIA FIKTIVA", "Kartenzahlung", -2343),
        ])], auth: BackendAuth(token: nil))
        let questions = phone.receiptQuestions
        #expect(questions.count == 2)
        let first = try #require(questions.first)

        phone.dismissQuestion(first)
        #expect(phone.receiptQuestions.map(\.id) == [questions[1].id], "the other one is asked next")
        let stored = try #require(try await phone.receipt(first.receipt.id))
        #expect(stored.state == .waiting && stored.declined.isEmpty)

        _ = try await phone.importFiles([PhoneTest.vrBank([("29.10.2026", "FIKTIV KIOSK", "Kartenzahlung", -150)])],
                                        auth: BackendAuth(token: nil))
        #expect(phone.receiptQuestions.map(\.id).contains(first.id), "asked again after the next import")
    }

    /// Edit receipt's question: Later ends Edit; the corrected values stay, the receipt waits, nothing is declined.
    @Test func laterInEditKeepsTheCorrectionAndWaits() async throws {
        let phone = try await phone([("27.10.2026", "MUSTERMARKT LINDE", "Kartenzahlung", -2765),
                                     ("27.10.2026", "MUSTERMARKT LINDE", "Kartenzahlung", -3120),
                                     ("29.10.2026", "MUSTERMARKT LINDE", "Kartenzahlung", -3120)])
        _ = try await phone.saveReceipt(draft())
        let id = try #require(try await phone.receipts().first?.id)
        var changes = 0
        let page = ReceiptPageModel(id: id, phone: phone) { changes += 1 }
        await page.load()
        await page.beginEdit()
        guard case .checking(let check)? = page.editing?.phase else { Issue.record("no edit window"); return }
        check.totalText = "31,20"
        await page.saveEdit(check)
        guard case .asking? = page.editing?.phase else { Issue.record("not asked"); return }

        page.endEdit()
        #expect(page.editing == nil)
        try await settle { changes > 0 }
        let stored = try #require(try await phone.receipt(id))
        #expect(stored.total == "31.20" && stored.state == .waiting && stored.declined.isEmpty)
    }

    // MARK: Back in the file check

    /// The file check's window for the made-up card statement (four readings).
    private func fileCheck() async throws -> (PhoneBackend, FileCheckModel) {
        let session = await PhoneTest.session(nil, transport: RoutedTransport())
        let phone = try await PhoneTest.backend(chosen: ["groceries", "eating-out"])
        let imports = ImportStore(dashboard: DashboardStore(session: session, backend: phone), background: PhoneActivity())
        imports.debugImport([FileCheckTests.cardFile])
        await imports.importPendingFiles()
        let request = try #require(imports.layoutRequest)
        return (phone, FileCheckModel(request: request, phone: phone, imports: imports))
    }

    /// No by mistake: Back shows the reading before with its line; the first reading has no Back.
    @Test func backShowsTheReadingBefore() async throws {
        let (phone, model) = try await fileCheck()
        #expect(!model.canGoBack)
        model.back()
        #expect(model.step == .reading(0), "nothing before the first")

        model.no()
        model.no()
        #expect(model.step == .reading(2) && model.canGoBack && model.change == "Money in and out swapped")
        model.back()
        #expect(model.step == .reading(1) && model.change == "Day and month swapped")
        #expect(model.payments.map(\.day) == ["2026-03-04", "2026-05-04", "2026-07-04"])
        model.back()
        #expect(model.step == .reading(0) && model.change == nil && !model.canGoBack)
        #expect(phone.summary.layouts == 0, "going back saves nothing")

        // Yes after going back keeps the reading shown.
        model.no()
        model.back()
        #expect(await model.yes())
        #expect(try await phone.ledger.layouts() == [model.readings[0].layout])
    }

    /// From the column check, Back returns to the last reading; No goes there again with the answers kept.
    @Test func backFromTheColumnCheckReturnsToTheLastReading() async throws {
        let (_, model) = try await fileCheck()
        for _ in model.readings { model.no() }
        #expect(model.step == .columns && model.canGoBack)
        let columns = try #require(model.columns)
        columns.choose(.counterparty, column: nil)

        model.back()
        #expect(model.step == .reading(model.readings.count - 1) && model.reading == model.readings.last)
        #expect(model.change == "Name and payment text swapped")
        model.no()
        #expect(model.step == .columns && model.columns === columns && columns.chosen(.counterparty) == nil,
                "the column check keeps its answers")
    }

    /// With no reading at all the column check comes at once, and has nothing to go back to.
    @Test func noBackWhenTheColumnCheckCameAtOnce() async throws {
        let (phone, model) = try await fileCheck()
        let bare = FileCheckModel(request: LayoutRequest(file: model.request.file, guess: model.request.guess, readings: []),
                                  phone: phone, imports: ImportStore(dashboard: DashboardStore(
                                      session: await PhoneTest.session(nil, transport: RoutedTransport()), backend: phone),
                                                                     background: PhoneActivity()))
        #expect(bare.step == .columns && !bare.canGoBack)
        bare.back()
        #expect(bare.step == .columns)
    }

    // MARK: what Cancel would throw away

    /// A new reading: something read cannot be had again (the photo is not kept), so Cancel asks at once; a receipt
    /// where nothing was read asks only once something is typed or changed.
    @Test func theReceiptWindowHasSomethingToDiscard() async throws {
        let phone = try await phone()
        let read = ReceiptCheckModel(reading: reading(), phone: phone, language: .english)
        await read.load()
        #expect(read.hasSomethingToDiscard && !read.hasChanges, "a reading, though nothing was changed")

        let blank = ReceiptCheckModel(reading: reading(nothing: true), phone: phone, language: .english)
        await blank.load()
        #expect(blank.nothingRead && !blank.hasSomethingToDiscard)
        blank.shop = "Fiktiv Kiosk"
        #expect(blank.hasSomethingToDiscard)
        blank.shop = ""
        #expect(!blank.hasSomethingToDiscard)
        blank.method = .cash
        #expect(blank.hasSomethingToDiscard, "a choice counts as a change too")
    }

    /// Edit receipt: Cancel asks only when a value changed; the same amount written another way is no change, and a
    /// value set back is none either.
    @Test func editReceiptHasSomethingToDiscardOnlyWhenChanged() async throws {
        let phone = try await phone()
        _ = try await phone.saveReceipt(draft(method: .cash))
        let stored = try #require(try await phone.receipts().first)
        let check = ReceiptCheckModel(editing: stored, phone: phone, language: .english)
        await check.load()
        #expect(!check.hasSomethingToDiscard)

        #expect(check.totalText == "27.65")
        check.totalText = "27,65"
        #expect(!check.hasSomethingToDiscard, "the same amount")
        check.totalText = "27,66"
        #expect(check.hasSomethingToDiscard)
        check.totalText = "27.65"
        #expect(!check.hasSomethingToDiscard, "set back")

        check.category = "eating-out"
        #expect(check.hasSomethingToDiscard)
        check.category = stored.category
        check.date = try #require(ReceiptDay.date("2026-10-20"))
        #expect(check.hasSomethingToDiscard)
    }

    /// Add cash: nothing typed closes at once; an amount, what, the day, the category, Paid from or Spent / Received
    /// changed asks (and holds swipe down).
    @Test func addCashHasSomethingToDiscard() async throws {
        let phone = try await phone([("02.10.2026", "Geldautomat Fiktivbank", "Bargeldauszahlung", -10000)])
        let window = CashEntryModel(phone: phone, today: try #require(ReceiptDay.date("2026-10-06")), language: .english)
        await window.load()
        #expect(!window.hasChanges)

        window.amountText = "12,50"
        #expect(window.hasChanges)
        window.amountText = ""
        #expect(!window.hasChanges)
        window.what = "Flohmarkt"
        #expect(window.hasChanges)
        window.what = ""
        window.category = "clothes"
        #expect(window.hasChanges)
        window.category = nil
        window.paidFrom = try #require(window.sources?.first?.id)
        #expect(window.hasChanges)
        window.paidFrom = nil
        #expect(!window.hasChanges)
        window.direction = .in
        #expect(window.hasChanges)
        window.direction = .out
        window.date = try #require(ReceiptDay.date("2026-10-05"))
        #expect(window.hasChanges)
    }

    /// Edit entry: filled from the entry, nothing to discard until a value changes; a saved category the window no
    /// longer offers (dropped as it loads) is no change of the person's.
    @Test func editEntryHasSomethingToDiscardOnlyWhenChanged() async throws {
        let phone = try await phone()
        let saved = try await phone.addCashEntry(CashEntryDraft(direction: .out, amount: 12, date: "2026-10-06",
                                                                what: "Flohmarkt", category: "clothes"))
        let edit = CashEntryModel(editing: saved, phone: phone, language: .english)
        await edit.load()
        #expect(!edit.hasChanges)
        edit.what = "Flohmarkt am Fluss"
        #expect(edit.hasChanges)
        edit.what = "Flohmarkt"
        edit.amountText = "12,00"
        #expect(!edit.hasChanges, "the same amount")

        let income = try await phone.addCashEntry(CashEntryDraft(direction: .out, amount: 5, date: "2026-10-06",
                                                                 what: "Kiosk", category: "salary"))
        let dropped = CashEntryModel(editing: income, phone: phone, language: .english)
        await dropped.load()
        #expect(dropped.category == nil && !dropped.hasChanges, "dropped by the window, not by the person")
    }
}
