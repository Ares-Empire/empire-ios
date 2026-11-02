import Foundation
import Testing
@testable import Aresium

/// Receipts you can correct (brief 33 part A): every field of the check window changed and saved; Edit after saving
/// (a new total, date, currency or card or cash unjoins and matches again, a new shop or category only updates); what
/// Aresium learns from corrections (the shop's name for the next receipt read the same way, the category for the shop;
/// never the total or card or cash); ledger schema 3 opening a version 2 store; export 3 and restoring 2 and 1. All
/// through the real engine, everything made up.
@MainActor
struct ReceiptCorrectionTests {
    // MARK: helpers

    /// A store with these categories and these VR Bank rows (day, who, text, cents).
    private func phone(_ rows: [(String, String, String, Int)] = [],
                       chosen: [String] = ["groceries", "cash", "eating-out"]) async throws -> PhoneBackend {
        let phone = try await PhoneTest.backend(chosen: chosen)
        if !rows.isEmpty { _ = try await phone.importFiles([PhoneTest.vrBank(rows)], auth: BackendAuth(token: nil)) }
        return phone
    }

    private func reading(shop: String? = "MUSTERMARKT LINDE", date: String? = "2026-10-26", total: Double? = 27.65,
                         currency: String? = "EUR", method: ReceiptMethod? = .card, categoryId: String? = nil,
                         sure: Bool = true) -> ReceiptReading {
        ReceiptReading(shop: shop, categoryId: categoryId, date: date, time: "14:31", total: total, currency: currency,
                       method: method, language: "de", from: "text", rows: [shop ?? "", "SUMME EUR 27,65"],
                       sure: .init(shop: sure, date: sure, total: sure, method: sure))
    }

    private func draft(_ shop: String? = "MUSTERMARKT LINDE", date: String = "2026-10-26", total: Double = 27.65,
                       method: ReceiptMethod = .card, category: String? = "groceries",
                       shopAsRead: String? = nil) -> ReceiptDraft {
        ReceiptDraft(date: date, time: "14:31", shop: shop, total: total, currency: "EUR", method: method,
                     category: category, categorySource: category == nil ? .none : .starter,
                     rows: [shop ?? "", "SUMME EUR \(total)"], from: "text", shopAsRead: shopAsRead)
    }

    private func payment(_ phone: PhoneBackend, _ who: String, cents: Int) async throws -> LedgerPayment {
        try #require(try await phone.ledger.payments().first { $0.counterparty == who && Int(($0.amountValue * 100).rounded()) == cents })
    }

    /// The check window for a receipt saved before (its page's Edit).
    private func edit(_ phone: PhoneBackend, _ id: String) async throws -> ReceiptCheckModel {
        let stored = try #require(try await phone.receipt(id))
        let check = ReceiptCheckModel(editing: stored, phone: phone, language: .english)
        await check.load()
        return check
    }

    // MARK: every field editable

    /// Shop, date, total, its currency, card or cash, the euros and the category: each one changed in the window is
    /// what is kept, also the ones the engine was sure of.
    @Test func everyFieldCanBeChangedAndIsSaved() async throws {
        let phone = try await phone()
        let check = ReceiptCheckModel(reading: reading(), phone: phone, language: .english)
        await check.load()
        #expect(check.fieldsRead == ReceiptCheckModel.Field.allCases, "all sure: nothing to check first")
        #expect(check.currency == "EUR" && check.method == .card)

        check.shop = "Mustermarkt Linde"
        check.date = try #require(ReceiptDay.date("2026-10-25"))
        check.totalText = "12,40"
        check.currency = "GBP"                       // a euro receipt's currency can be changed too
        check.method = .cash
        #expect(check.missing == "Type what it cost in euros.")
        check.euroText = "14,56"
        check.category = "eating-out"
        #expect(try #require(await check.save()) == .cash)

        let stored = try #require(try await phone.receipts().first)
        #expect(stored.shop == "Mustermarkt Linde" && stored.date == "2026-10-25" && stored.time == nil)
        #expect(stored.total == "12.40" && stored.currency == "GBP" && stored.euroAmount == "14.56")
        #expect(stored.method == .cash && stored.category == "eating-out" && stored.categorySource == .manual)
        #expect(stored.shopAsRead == "MUSTERMARKT LINDE", "the shop as read is kept for learning later")
    }

    /// Edit opens the same window filled from the stored receipt: every value as saved, nothing marked to check.
    @Test func editOpensTheWindowFilledFromTheReceipt() async throws {
        let phone = try await phone()
        var foreign = draft("Fictional Pub", total: 9.80, method: .cash, category: "eating-out")
        foreign.currency = "GBP"
        foreign.euroAmount = 11.50
        _ = try await phone.saveReceipt(foreign)
        let id = try #require(try await phone.receipts().first?.id)

        let check = try await edit(phone, id)
        #expect(check.editing?.id == id && !check.nothingRead && check.fieldsToCheck.isEmpty)
        #expect(check.shop == "Fictional Pub" && ReceiptDay.day(check.date) == "2026-10-26")
        #expect(check.totalText == "9.80" && check.currency == "GBP" && check.method == .cash)
        #expect(check.euroText == "11.50" && check.category == "eating-out")
        #expect(check.note(.shop) == nil && check.matchesAgainNote == nil && check.canSave)
        // Saved unchanged: only updated, the category's source as it was.
        #expect(try #require(await check.save()) == .updated)
        #expect(try await phone.receipt(id)?.categorySource == .starter)
    }

    // MARK: edit after saving

    /// A new total unjoins the receipt and matches it again: the one payment of the new amount joins; the old payment
    /// loses the category it had from the receipt.
    @Test func aNewTotalUnjoinsAndMatchesAgain() async throws {
        let phone = try await phone([("27.10.2026", "MUSTERMARKT LINDE", "Kartenzahlung", -2765),
                                     ("28.10.2026", "MUSTERMARKT LINDE", "Kartenzahlung", -3120)])
        let first = try await payment(phone, "MUSTERMARKT LINDE", cents: -2765)
        let second = try await payment(phone, "MUSTERMARKT LINDE", cents: -3120)
        guard case .joined(let joined, true) = try await phone.saveReceipt(draft()) else { Issue.record("not joined"); return }
        #expect(joined.id == first.id)
        let id = try #require(try await phone.receipts().first?.id)

        let check = try await edit(phone, id)
        check.totalText = "31,20"
        #expect(check.matchesAgainNote == "Aresium looks for its bank payment again when you save.")
        guard case .joined(let now, true) = try #require(await check.save()) else { Issue.record("not joined again"); return }
        #expect(now.id == second.id)
        #expect(try await phone.receipt(id)?.paymentID == second.id)
        #expect(try await phone.receipt(id)?.total == "31.20")
        let old = try #require(try await phone.ledger.payment(first.id))
        #expect(old.category == nil && old.categorySource == .none, "the category it had from the receipt goes")
        #expect(try await phone.ledger.payment(second.id)?.categorySource == .receipt)
    }

    /// A new total that two payments have: asked (D8), never joined by itself; meanwhile it waits.
    @Test func aNewTotalWithTwoPaymentsIsAsked() async throws {
        let phone = try await phone([("27.10.2026", "MUSTERMARKT LINDE", "Kartenzahlung", -2765),
                                     ("27.10.2026", "MUSTERMARKT LINDE", "Kartenzahlung", -3120),
                                     ("29.10.2026", "MUSTERMARKT LINDE", "Kartenzahlung", -3120)])
        guard case .joined = try await phone.saveReceipt(draft()) else { Issue.record("not joined"); return }
        let id = try #require(try await phone.receipts().first?.id)

        let check = try await edit(phone, id)
        check.totalText = "31,20"
        guard case .question(let question) = try #require(await check.save()) else { Issue.record("not asked"); return }
        #expect(question.options.count == 2 && question.options.allSatisfy { $0.candidate?.why == .severalSame })
        #expect(try await phone.receipt(id)?.state == .waiting, "nothing joined before the answer")
        try await phone.answer(question, with: question.options[0].payment.id)
        #expect(try await phone.receipt(id)?.paymentID == question.options[0].payment.id)
    }

    /// A new date or card → cash also matches again: as cash it leaves its bank payment.
    @Test func cashInsteadOfCardLeavesTheBankPayment() async throws {
        let phone = try await phone([("27.10.2026", "MUSTERMARKT LINDE", "Kartenzahlung", -2765),
                                     ("02.10.2026", "Geldautomat Fiktivbank", "Bargeldauszahlung", -10000)])
        _ = try await phone.saveReceipt(draft())
        let id = try #require(try await phone.receipts().first?.id)
        let check = try await edit(phone, id)
        check.method = .cash
        #expect(check.matchesAgainNote != nil, "it was joined")
        #expect(try #require(await check.save()) == .cash)
        #expect(try await phone.receipt(id)?.paymentID == nil)
        #expect(try await payment(phone, "MUSTERMARKT LINDE", cents: -2765).category == nil)
        let dashboard = try await phone.dashboard(auth: BackendAuth(token: nil))
        #expect(dashboard.transactions.contains { $0.receiptId == id && !$0.isWaitingReceipt }, "counted as cash")
    }

    /// A new shop or category only updates: still joined to the same payment, which follows the category it had from
    /// the receipt; the category picked by hand is learned for the shop, the new name for the shop as read.
    @Test func aNewShopOrCategoryOnlyUpdates() async throws {
        let phone = try await phone([("27.10.2026", "MUSTERMARKT LINDE", "Kartenzahlung", -2765)])
        _ = try await phone.saveReceipt(draft(shopAsRead: "MUSTERMARKT LINDE"))
        let joined = try await payment(phone, "MUSTERMARKT LINDE", cents: -2765)
        let id = try #require(try await phone.receipts().first?.id)

        let check = try await edit(phone, id)
        check.shop = "Mustermarkt Linde"
        check.category = "eating-out"
        #expect(check.matchesAgainNote == nil)
        #expect(try #require(await check.save()) == .updated)
        let stored = try #require(try await phone.receipt(id))
        #expect(stored.paymentID == joined.id && stored.shop == "Mustermarkt Linde")
        #expect(stored.category == "eating-out" && stored.categorySource == .manual)
        let payment = try #require(try await phone.ledger.payment(joined.id))
        #expect(payment.category == "eating-out" && payment.categorySource == .receipt, "it follows its receipt")
        #expect(try await phone.ledger.learned().values.contains("eating-out"))
        #expect(try await phone.correctedShopName(read: "MUSTERMARKT LINDE") == "Mustermarkt Linde", "learned after saving too")

        // A payment sorted by hand keeps its own category whatever the receipt says.
        try await phone.ledger.setCategory(joined.id, category: "groceries", source: .manual)
        let again = try await edit(phone, id)
        again.category = "cash"
        _ = await again.save()
        #expect(try await phone.ledger.payment(joined.id)?.category == "groceries")
    }

    /// The page's model: Edit, Save, and the page shows the receipt as it is now.
    @Test func thePageEditsTheReceipt() async throws {
        let phone = try await phone()
        _ = try await phone.saveReceipt(draft(method: .cash))
        let id = try #require(try await phone.receipts().first?.id)
        var changes = 0
        let page = ReceiptPageModel(id: id, phone: phone) { changes += 1 }
        await page.load()
        await page.beginEdit()
        guard case .checking(let check)? = page.editing?.phase else { Issue.record("no edit window"); return }
        check.shop = "Mustermarkt Linde"
        await page.saveEdit(check)
        #expect(page.editing == nil && changes == 1)
        #expect(page.receipt?.shop == "Mustermarkt Linde")
    }

    // MARK: learning from corrections

    /// A shop name the person changed is shown for the next receipt read the same way, marked "Corrected by you
    /// before" and no longer one to check. Through Vision and the engine with the made-up receipt.
    @Test func aCorrectedShopIsShownForTheNextReceiptReadTheSameWay() async throws {
        let phone = try await phone()
        let capture = try await ReceiptReader.read([ReceiptPage(image: ReceiptSample.image())])
        let first = ReceiptCheckModel(reading: try await phone.readReceipt(capture), phone: phone, language: .english)
        await first.load()
        let read = try #require(first.reading.shop)
        #expect(first.shop == read && first.mark(.shop) == .unsure, "the made-up shop is not on the shop list")
        first.shop = "Mustermarkt Linde"
        _ = try #require(await first.save())

        let next = ReceiptCheckModel(reading: try await phone.readReceipt(capture), phone: phone, language: .english)
        await next.load()
        #expect(next.shop == "Mustermarkt Linde" && next.mark(.shop) == .corrected)
        #expect(!next.fieldsToCheck.contains(.shop) && next.fieldsRead.contains(.shop))
        #expect(next.note(.shop) == "Corrected by you before.")
        let german = ReceiptCheckModel(reading: try await phone.readReceipt(capture), phone: phone, language: .german)
        await german.load()
        #expect(german.note(.shop) == "Von dir schon einmal korrigiert.")
        // Typed over, the note goes (the name is the person's own again).
        next.shop = "Linde"
        #expect(next.note(.shop) == nil)

        // Read the same way: case, spaces and signs do not matter.
        let other = ReceiptCheckModel(reading: reading(shop: "Mustermarkt - Linde.", sure: false), phone: phone)
        await other.load()
        #expect(other.shop == "Mustermarkt Linde")
        // Another shop is not touched.
        let unrelated = ReceiptCheckModel(reading: reading(shop: "MUSTERMARKT LINDEN", sure: false), phone: phone)
        await unrelated.load()
        #expect(unrelated.shop == "MUSTERMARKT LINDEN" && unrelated.mark(.shop) == .unsure)
    }

    /// Saved with the name exactly as read, a correction from before is dropped.
    @Test func keepingTheNameAsReadForgetsTheCorrection() async throws {
        let phone = try await phone()
        _ = try await phone.saveReceipt(draft("Mustermarkt Linde", method: .cash, shopAsRead: "MUSTERMARKT LINDE"))
        let corrected = ReceiptCheckModel(reading: reading(sure: false), phone: phone)
        await corrected.load()
        #expect(corrected.shop == "Mustermarkt Linde")
        corrected.shop = "MUSTERMARKT LINDE"
        _ = try #require(await corrected.save())
        #expect(try await phone.ledger.shopNames().isEmpty)
        let next = ReceiptCheckModel(reading: reading(sure: false), phone: phone)
        await next.load()
        #expect(next.shop == "MUSTERMARKT LINDE" && next.mark(.shop) == .unsure)
    }

    /// The category picked by hand for a receipt is learned for its shop (as a Switch): the next receipt of that shop
    /// has it preset, and the shop's bank payments are sorted into it.
    @Test func theCategoryPickedForAShopIsPresetNextTime() async throws {
        let phone = try await phone()
        let first = ReceiptCheckModel(reading: reading(shop: "Pizzeria Fiktiva", total: 23.40, method: .cash), phone: phone)
        await first.load()
        #expect(first.category == nil)
        first.category = "eating-out"
        _ = try #require(await first.save())

        let next = ReceiptCheckModel(reading: reading(shop: "Pizzeria Fiktiva", total: 18.10, method: .cash), phone: phone)
        await next.load()
        #expect(next.category == "eating-out" && next.draft()?.categorySource == .learned)
        _ = try await phone.importFiles([PhoneTest.vrBank([("28.10.2026", "Pizzeria Fiktiva", "Kartenzahlung", -1990)])],
                                        auth: BackendAuth(token: nil))
        #expect(try await payment(phone, "Pizzeria Fiktiva", cents: -1990).category == "eating-out")
    }

    /// The total and card or cash are never learned: the next receipt shows what is read on it.
    @Test func theTotalAndCardOrCashAreNotLearned() async throws {
        let phone = try await phone()
        let first = ReceiptCheckModel(reading: reading(), phone: phone)
        await first.load()
        first.totalText = "27,56"
        first.method = .cash
        _ = try #require(await first.save())
        let next = ReceiptCheckModel(reading: reading(), phone: phone, language: .english)
        await next.load()
        #expect(next.totalText == "27.65" && next.method == .card)
    }

    @Test func shopNamesAreReadTheSameWay() {
        #expect(ShopNames.key("MUSTERMARKT  LINDE.") == "mustermarktlinde")
        #expect(ShopNames.key("Bäckerei Groß 2") == "bäckereigroß2")
        #expect(ShopNames.key("*** ---") == "")
        #expect(ShopNames.change(read: "REWE", saved: "REWE Linde") == .remember(ShopNameCorrection(read: "rewe", name: "REWE Linde")))
        #expect(ShopNames.change(read: "REWE", saved: "  REWE ") == .forget(read: "rewe"))
        #expect(ShopNames.change(read: nil, saved: "REWE") == nil)
        #expect(ShopNames.change(read: "REWE", saved: nil) == nil, "an emptied field says nothing")
        #expect(ShopNames.change(read: "***", saved: "Kiosk") == nil)
    }

    // MARK: storage: schema 3

    /// A store made by schema version 2's code (AresiumTests/Fixtures/ledger-v2.store, made 2026-10-28 by today's main
    /// before schema 3: 4 payments, 1 account, 1 learned shop, 1 layout, 4 chosen categories, 5 receipts: one joined,
    /// one cash, two card ones waiting (one in pounds), one cash in pounds with its euros) opens, keeps everything, gives
    /// the receipts their defaults and takes schema 3's values.
    @Test func aVersion2StoreOpensAndMovesOn() async throws {
        let storage = PhoneTest.storage()
        try FileManager.default.createDirectory(at: storage.directory, withIntermediateDirectories: true)
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appending(path: "Fixtures/ledger-v2.store")
        try FileManager.default.copyItem(at: fixture, to: storage.storeURL)

        let ledger = try await Task.detached { try storage.open() }.value
        let summary = try await ledger.summary()
        #expect(summary.payments == 4 && summary.accounts == 1 && summary.learned == 1 && summary.layouts == 1)
        #expect(summary.receipts == 5 && summary.chosen.count == 4)
        let receipts = try await ledger.receipts()
        #expect(receipts.allSatisfy { $0.direction == .out && $0.kind == .receipt && $0.paidFrom == nil && $0.shopAsRead == nil })
        let joined = try #require(receipts.first { $0.shop == "MUSTERMARKT LINDE" })
        #expect(joined.state == .joined && joined.time == "14:31")
        #expect(try await ledger.payment(try #require(joined.paymentID))?.categorySource == .receipt)
        #expect(receipts.first { $0.shop == "Fictional Pub" }?.euroAmount == "11.50")
        #expect(receipts.filter { $0.state == .waiting }.count == 2)
        #expect(try await ledger.shopNames().isEmpty)

        // Schema 3's values are kept.
        let withdrawal = try #require(try await ledger.payments().first { $0.counterparty == "Geldautomat Fiktivbank" })
        var cash = try #require(receipts.first { $0.shop == "Cafe Fiktiva" })
        cash.paidFrom = withdrawal.id
        try await ledger.updateReceipt(cash)
        try await ledger.addReceipt(LedgerReceipt(id: "gift", date: "2026-10-20", time: nil, shop: "Fictional gift",
                                                  total: "50.00", currency: "EUR", euroAmount: nil, method: .cash,
                                                  category: nil, categorySource: .none, rows: [], from: "text",
                                                  paymentID: nil, created: .now, direction: .in, kind: .manual))
        try await ledger.apply(.remember(ShopNameCorrection(read: "mustermarktlinde", name: "Mustermarkt Linde")))
        let reopened = try await Task.detached { try storage.open() }.value
        #expect(try await reopened.receipt(cash.id)?.paidFrom == withdrawal.id)
        let gift = try #require(try await reopened.receipt("gift"))
        #expect(gift.direction == .in && gift.kind == .manual)
        #expect(try await reopened.shopName(read: "mustermarktlinde") == "Mustermarkt Linde")

        // The dashboard builds from it.
        let phone = PhoneBackend(ledger: reopened, engine: try PhoneTest.engine())
        phone.today = { "2026-10-28" }
        try await phone.load()
        #expect(try await phone.dashboard(auth: BackendAuth(token: nil)).byMonth["2026-10"] != nil)
    }

    /// Export schema 3 carries the corrected shop names and the receipts' new fields; files of schema 2 and 1 still
    /// restore (their receipts take the defaults).
    @Test func exportThreeAndRestoreOfTwoAndOne() async throws {
        let phone = try await phone([("27.10.2026", "MUSTERMARKT LINDE", "Kartenzahlung", -2765)])
        _ = try await phone.saveReceipt(draft("Mustermarkt Linde", shopAsRead: "MUSTERMARKT LINDE"))       // joins
        _ = try await phone.saveReceipt(draft("Cafe Fiktiva", total: 8.40, method: .cash, category: "eating-out"))
        let export = try await phone.export()
        #expect(export.schema == 7 && LedgerExport.currentSchema == 7)
        #expect(export.shopNames == [ShopNameCorrection(read: "mustermarktlinde", name: "Mustermarkt Linde")])
        let file = try export.encoded()
        let text = String(decoding: file, as: UTF8.self)
        #expect(text.contains("\"shopNames\"") && text.contains("\"direction\" : \"out\"") && text.contains("\"shopAsRead\""))

        let restored = try await PhoneTest.backend()
        try await restored.restore(file)
        #expect(try await restored.receipts().map(\.id).sorted() == export.receipts.map(\.id).sorted())
        #expect(try await restored.ledger.shopNames() == export.shopNames)
        #expect(try await restored.receipts().contains { $0.shopAsRead == "MUSTERMARKT LINDE" && $0.paymentID != nil })

        // Schema 2: the same file as brief 31's app wrote it (no shop names, no new receipt fields).
        var two = try JSONSerialization.jsonObject(with: file) as! [String: Any]
        two["schema"] = 2
        two.removeValue(forKey: "shopNames")
        two["receipts"] = (two["receipts"] as! [[String: Any]]).map { receipt in
            receipt.filter { !["direction", "kind", "paidFrom", "shopAsRead"].contains($0.key) }
        }
        let fromTwo = try await PhoneTest.backend()
        try await fromTwo.restore(try JSONSerialization.data(withJSONObject: two))
        let receipts = try await fromTwo.receipts()
        #expect(receipts.count == 2 && receipts.allSatisfy { $0.direction == .out && $0.kind == .receipt && $0.shopAsRead == nil })
        #expect(try await fromTwo.ledger.shopNames().isEmpty)
        // A schema 2 file with schema 3's fields is not one Aresium wrote.
        var mixed = two
        mixed["shopNames"] = [["read": "rewe", "name": "REWE Linde"]]
        #expect(throws: LedgerError.self) { try LedgerExport.decode(try JSONSerialization.data(withJSONObject: mixed)) }

        // Schema 1: no receipts at all.
        var one = two
        one["schema"] = 1
        one.removeValue(forKey: "receipts")
        let fromOne = try await PhoneTest.backend()
        try await fromOne.restore(try JSONSerialization.data(withJSONObject: one))
        #expect(try await fromOne.ledger.summary().payments == 1)
        #expect(try await fromOne.receipts().isEmpty)
    }

    /// Schema 3's fields are checked before anything is restored.
    @Test func schema3FieldsAreChecked() async throws {
        let phone = try await phone([("02.10.2026", "Geldautomat Fiktivbank", "Bargeldauszahlung", -10000)])
        let catalog = try #require(phone.catalog)
        let withdrawal = try #require(try await phone.ledger.payments().first)
        let base = try await phone.export()
        func receipt(_ id: String, method: ReceiptMethod = .cash, direction: ReceiptDirection = .out,
                     paidFrom: String? = nil) -> LedgerReceipt {
            LedgerReceipt(id: id, date: "2026-10-05", time: nil, shop: "Fictional", total: "8.40", currency: "EUR",
                          euroAmount: nil, method: method, category: nil, categorySource: .none, rows: [], from: "text",
                          paymentID: nil, created: .now, direction: direction, paidFrom: paidFrom)
        }
        func check(_ receipts: [LedgerReceipt], names: [ShopNameCorrection] = []) throws {
            var export = base
            export.receipts = receipts
            export.shopNames = names
            try export.validate(catalog: catalog)
        }
        // Paid from a withdrawal, or from cash received (listed later in the file): fine.
        try check([receipt("a", paidFrom: withdrawal.id), receipt("b", paidFrom: "gift"), receipt("gift", direction: .in)])
        #expect(throws: LedgerError.self) { try check([receipt("a", paidFrom: "nothing")]) }
        #expect(throws: LedgerError.self) { try check([receipt("a", method: .card, paidFrom: withdrawal.id)]) }
        #expect(throws: LedgerError.self) { try check([receipt("a", method: .card, direction: .in)]) }
        #expect(throws: LedgerError.self) { try check([receipt("a", direction: .in, paidFrom: withdrawal.id)]) }
        #expect(throws: LedgerError.self) { try check([], names: [ShopNameCorrection(read: "REWE", name: "x")]) }
        #expect(throws: LedgerError.self) { try check([], names: [ShopNameCorrection(read: "rewe", name: " ")]) }
    }
}
