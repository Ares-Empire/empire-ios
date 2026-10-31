import Foundation
import Testing
@testable import Aresium

/// Brief 60: a new category straight from the change window. The window's New category tile makes one of one's own
/// categories through Settings → Categories' own path (`PhoneBackend.addCustom(named:)`), shows it before the tile and
/// picks it; Save then moves or adds the payment as with any category, and the shop question follows a Switch. A name
/// problem makes nothing and keeps the typed name; Cancel keeps the category. Phone mode and money out only; the tour's
/// window works on the tour's store. Everything is made up.
@MainActor
struct NewCategoryInChangeTests {
    private let none = BackendAuth(token: nil)

    /// A phone store with groceries and eating out ticked, three payments from one shop, one from another and a salary;
    /// the dashboard on it.
    private func phoneDashboard() async throws -> (PhoneBackend, DashboardStore) {
        let phone = try await PhoneTest.backend(chosen: ["groceries", "eating-out", "salary"])
        _ = try await phone.importFiles([PhoneTest.vrBank([
            ("05.10.2026", "REWE Markt GmbH", "REWE SAGT DANKE", -2345),
            ("12.10.2026", "REWE Markt GmbH", "REWE SAGT DANKE", -1890),
            ("19.10.2026", "REWE Markt GmbH", "REWE SAGT DANKE", -3120),
            ("08.10.2026", "Fiktiv Boulderhalle", "Eintritt", -1400),
            ("01.10.2026", "Fictional Employer GmbH", "Gehalt Oktober", 210000)])], auth: none)
        let session = await PhoneTest.session(nil, transport: RoutedTransport())
        let dashboard = DashboardStore(session: session, backend: phone)
        await dashboard.reload()
        return (phone, dashboard)
    }

    /// The change window open on the first payment whose place contains `place`, as its page's chip opens it.
    private func window(_ dashboard: DashboardStore, place: String,
                        mode: RecategorisationMode = .switchCategory) async throws -> TransactionDetailStore {
        let row = try #require(dashboard.dashboard?.transactions.first { $0.place.contains(place) })
        let store = dashboard.transactionDetailStore(for: row)
        await store.load()
        store.beginRecategorisation(mode: mode)
        #expect(store.showsRecategorisation)
        return store
    }

    /// One's own categories as Settings → Categories lists them: name and look.
    private func own(_ phone: PhoneBackend) async throws -> [CategoryGroup.Item] {
        try await phone.categories().custom
    }

    // MARK: making it

    @Test func switchMakesItPicksItAndSaveMovesThePaymentWithTheShopQuestion() async throws {
        let (phone, dashboard) = try await phoneDashboard()
        var recategorised = 0
        dashboard.onRecategorised = { recategorised += 1 }
        let store = try await window(dashboard, place: "REWE")
        let payment = store.paymentID
        #expect(store.offersNewCategory, "phone mode, money out")
        #expect(store.choices.last?.name != "Kletterhalle")

        store.beginNewCategory()
        #expect(store.newCategory.isAsking, "the alert with the name's field")
        #expect(store.newCategory.name.isEmpty, "the field starts empty")
        #expect(!store.newCategory.canCreate, "Create is off while the field is empty")
        store.newCategory.name = "   "
        #expect(!store.newCategory.canCreate, "spaces only count as empty")
        store.newCategory.name = "  Kletterhalle "
        #expect(store.newCategory.canCreate)

        await store.createCategory()
        #expect(store.newCategory.problem == nil)
        #expect(store.newCategory.name.isEmpty, "the field is done with")
        // Made as Settings → Categories makes it: trimmed, ticked, with its own icon and colour.
        let made = try #require(try await own(phone).first)
        #expect(try await own(phone).count == 1)
        #expect(made.name == "Kletterhalle" && made.chosen)
        #expect(made.look == OwnCategoryLook.look(for: "Kletterhalle", besides: []))
        // In the grid at once, last (just before the tile), with that look, and picked.
        let tile = try #require(store.choices.last)
        #expect(tile.name == "Kletterhalle")
        #expect(tile.icon == made.look.icon && tile.color == made.look.color)
        #expect(store.target == "Kletterhalle")
        #expect(store.canSave, "Save is on")
        // Nothing about the payment is saved before Save.
        #expect(try await phone.ledger.payment(payment)?.category == "groceries")
        #expect(recategorised == 0)

        await store.save()
        let question = try #require(store.followUp, "Also the other payments from REWE?")
        #expect(question.count == 2 && question.category == "Kletterhalle")
        #expect(try await phone.ledger.payment(payment)?.category == made.id)
        await store.answerFollowUp(moveOthers: true)
        #expect(!store.showsRecategorisation)
        #expect(recategorised == 1, "the tour's switch step listens here")
        let rewe = try await phone.ledger.payments().filter { $0.counterparty == "REWE Markt GmbH" }
        #expect(rewe.count == 3 && rewe.allSatisfy { $0.category == made.id }, "the others moved with the shop")
        // The shop learned the new category: its next payment goes there by itself.
        _ = try await phone.importFiles([PhoneTest.vrBank([("26.10.2026", "REWE Markt GmbH", "REWE SAGT DANKE", -990)],
                                                          name: "vr-next.csv")], auth: none)
        let next = try #require(try await phone.ledger.payments().first { $0.bookingDate == "2026-10-26" })
        #expect(next.category == made.id)
        #expect(dashboard.dashboard?.transactions.first { $0.id == payment }?.categoryName == "Kletterhalle")
    }

    @Test func addMakesItAndPicksItAsAnExtra() async throws {
        let (phone, dashboard) = try await phoneDashboard()
        let store = try await window(dashboard, place: "REWE", mode: .add)
        #expect(store.offersNewCategory, "in Add too")
        store.beginNewCategory()
        store.newCategory.name = "Haushalt Fiktiv"
        await store.createCategory()
        let made = try #require(try await own(phone).first)
        #expect(store.choices.last?.name == "Haushalt Fiktiv")
        #expect(store.extras == ["Haushalt Fiktiv"], "one of the extras")
        #expect(store.mode == .add && store.target == nil)
        #expect(store.canSave)
        #expect(try await phone.ledger.payment(store.paymentID)?.extraCategories.isEmpty == true, "nothing before Save")

        await store.save()
        #expect(store.followUp == nil && !store.showsRecategorisation)
        let saved = try #require(try await phone.ledger.payment(store.paymentID))
        #expect(saved.category == "groceries", "Add keeps it where it is")
        #expect(saved.extraCategories == [made.id])
    }

    @Test func twoMadeInOneOpeningComeLastInTheOrderMade() async throws {
        let (_, dashboard) = try await phoneDashboard()
        let store = try await window(dashboard, place: "REWE", mode: .add)
        for name in ["Zuhause", "Auto"] {
            store.newCategory.name = name
            await store.createCategory()
        }
        #expect(store.choices.suffix(2).map(\.name) == ["Zuhause", "Auto"])
        #expect(store.extras == ["Zuhause", "Auto"])
        // A new opening shows them where the dashboard puts them (no longer after the others by force).
        store.showsRecategorisation = false
        store.beginRecategorisation(mode: .add)
        let order = dashboard.dashboard?.recategorisationChoices(amount: -1).map(\.name)
        #expect(store.choices.map(\.name) == order)
    }

    // MARK: a name problem

    @Test(arguments: ["Lebensmittel", "GROCERIES", "Bargeld", "Cash", "Not sorted", "Boulder", "   "])
    func aTakenReservedOrEmptyNameMakesNothingAndKeepsTheName(name: String) async throws {
        let (phone, dashboard) = try await phoneDashboard()
        try await phone.addCustom(named: "Boulder")              // one of one's own, made earlier
        await dashboard.reload()
        let store = try await window(dashboard, place: "REWE")
        let before = try await own(phone)
        let choices = store.choices.map(\.name)

        store.beginNewCategory()
        store.newCategory.name = name
        await store.createCategory()                 // Create (the alert keeps it off for an empty name)
        #expect(try await own(phone) == before, "no category is made")
        #expect(store.choices.map(\.name) == choices)
        #expect(store.target == nil && !store.canSave, "nothing picked")
        #expect(store.newCategory.name == name, "the typed name is kept")
        // Settings → Categories' words for the same problem.
        let settings = CategoryPickerModel(phone: phone, changed: {})
        await settings.load()
        settings.newName = name
        await settings.addCustom()
        let problem = try #require(store.newCategory.problem)
        #expect(problem == settings.problem)
        let expected = name.trimmingCharacters(in: .whitespaces).isEmpty ? LedgerError.emptyName : LedgerError.nameTaken
        #expect(problem == expected.localizedDescription)

        // The next tap opens the alert with the name, to correct it.
        store.newCategory.isAsking = false
        store.beginNewCategory()
        #expect(store.newCategory.isAsking && store.newCategory.name == name)
        store.newCategory.name = "Fiktiv Neu"
        await store.createCategory()
        #expect(store.newCategory.problem == nil, "the line goes with a name that works")
        #expect(store.target == "Fiktiv Neu")
    }

    @Test func cancellingTheAlertDropsTheNameAndItsProblem() async throws {
        let (_, dashboard) = try await phoneDashboard()
        let store = try await window(dashboard, place: "REWE")
        store.beginNewCategory()
        store.newCategory.name = "Bargeld"
        await store.createCategory()
        #expect(store.newCategory.problem != nil)
        store.beginNewCategory()
        store.newCategory.cancel()
        #expect(store.newCategory.name.isEmpty && store.newCategory.problem == nil)
    }

    // MARK: Cancel after making one

    @Test func cancelAfterMakingKeepsTheCategoryAndLeavesThePayment() async throws {
        let (phone, dashboard) = try await phoneDashboard()
        var recategorised = 0
        dashboard.onRecategorised = { recategorised += 1 }
        let store = try await window(dashboard, place: "Boulderhalle")
        let before = try #require(try await phone.ledger.payment(store.paymentID))
        store.newCategory.name = "Klettern"
        await store.createCategory()
        #expect(store.target == "Klettern")

        store.showsRecategorisation = false                      // the window's Cancel
        let after = try #require(try await phone.ledger.payment(store.paymentID))
        #expect(after.category == before.category && after.extraCategories == before.extraCategories,
                "only the payment's change is dropped")
        #expect(after.categorySource == before.categorySource)
        #expect(try await own(phone).map(\.name) == ["Klettern"], "the category stays, as any own category")
        #expect(recategorised == 0)
        // Opened again: nothing picked, the category among the choices.
        store.beginRecategorisation()
        #expect(store.target == nil && store.newCategory.name.isEmpty && store.newCategory.problem == nil)
        #expect(store.choices.contains { $0.name == "Klettern" })
    }

    // MARK: where the tile shows

    @Test func noTileInServerMode() async throws {
        let dashboard = DashboardStore(session: EmpireSession(app: .aresium, storage: PhoneTokens()), sample: true)
        await dashboard.reload()
        let spending = try #require(dashboard.dashboard?.transactions.first { $0.amount < 0 })
        let store = dashboard.transactionDetailStore(for: spending)
        await store.load()
        store.beginRecategorisation()
        #expect(!store.choices.isEmpty, "the window has its categories")
        #expect(!store.offersNewCategory)
        store.beginNewCategory()
        #expect(!store.newCategory.isAsking)
        store.newCategory.name = "Fiktiv"
        await store.createCategory()
        #expect(store.newCategory.problem == nil && store.target == nil)
    }

    /// Money in moves among the income list, which takes a category only once its payments add up to money in: one made
    /// just now is a spending one, so there is no tile for money in.
    @Test func noTileForMoneyInWhoseListCannotHoldANewCategory() async throws {
        let (phone, dashboard) = try await phoneDashboard()
        let salary = try await window(dashboard, place: "Employer")
        #expect(!salary.choices.isEmpty)
        #expect(!salary.offersNewCategory)
        salary.beginNewCategory()
        #expect(!salary.newCategory.isAsking)
        #expect(!Dashboard.takesNewCategory(amount: 2100) && Dashboard.takesNewCategory(amount: -23.45))

        // The engine's lists: a category made just now is a choice for money out only.
        try await phone.addCustom(named: "Nebenjob")
        await dashboard.reloadAfterTransactionChange()
        let built = try #require(dashboard.dashboard)
        #expect(built.recategorisationChoices(amount: -10).contains { $0.name == "Nebenjob" })
        #expect(!built.recategorisationChoices(amount: 10).contains { $0.name == "Nebenjob" })
        #expect(!salary.choices.contains { $0.name == "Nebenjob" })
    }

    // MARK: the tour

    /// 27 Oct 2026, noon: the made-up months end in October.
    private static let now = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 27, hour: 12))!

    @Test func inTheTourItGoesWithTheToursStoreAndTheStepGoesOn() async throws {
        // The person's own store, with payments and a category of their own.
        let personal = PhoneTest.storage()
        let person = try await PhoneTest.backend(storage: personal, chosen: ["groceries", "eating-out"])
        _ = try await person.importFiles([PhoneTest.vrBank([("01.10.2026", "REWE Markt GmbH", "REWE", -2000)])],
                                         auth: none)
        try await person.addCustom(named: "Boulder")
        let before = try await person.ledger.export(on: Self.now)

        let parent = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appending(path: "build/60-test-tours/\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let tour = TourModel(showsGraph: true, graphMoves: true) {
            try await TourWorld.make(in: parent, now: Self.now, makeEngine: { try PhoneTest.engine() })
        }
        await tour.start(at: .switchCategory)
        #expect(tour.step == .switchCategory && tour.target == .change)
        let world = try #require(tour.world)
        let payment = try #require(tour.place.payment, "the step opens a payment's page")
        let store = world.dashboard.transactionDetailStore(for: payment)
        await store.load()
        store.beginRecategorisation()
        #expect(store.offersNewCategory, "the tile stays in the tour")

        store.newCategory.name = "Tour-Kategorie"
        await store.createCategory()
        #expect(store.target == "Tour-Kategorie")
        #expect(tour.step == .switchCategory, "making it is no move yet")
        await store.save()
        if store.followUp != nil { await store.answerFollowUp(moveOthers: false) }
        #expect(tour.step != .switchCategory, "the step goes on when the payment is moved")
        #expect(try await world.phone.categories().custom.contains { $0.name == "Tour-Kategorie" })

        #expect(try await person.ledger.export(on: Self.now) == before, "the person's store is untouched")
        #expect(try await person.categories().custom.map(\.name) == ["Boulder"])
        tour.end()
        #expect(try await PhoneTest.backend(storage: personal).ledger.export(on: Self.now) == before)
    }
}

/// Brief 60, items 10 and 11: the receipt window (a new reading and Edit receipt) and the cash entry window (Add cash and
/// Edit entry) end their category menu with New category…, through the same `NewCategoryModel` as the change window:
/// the category is made with `addCustom`, offered and picked there; a name problem makes nothing and keeps the name; the
/// windows' Cancel keeps the category. Everything is made up.
@MainActor
struct NewCategoryInWindowsTests {
    private let none = BackendAuth(token: nil)

    private func phone() async throws -> PhoneBackend {
        let phone = try await PhoneTest.backend(chosen: ["groceries", "cash", "eating-out", "salary"])
        _ = try await phone.importFiles([PhoneTest.vrBank([
            ("05.10.2026", "REWE Markt GmbH", "REWE SAGT DANKE", -2345),
            ("02.10.2026", "Geldautomat Fiktivbank", "Bargeldauszahlung", -10000)])], auth: none)
        return phone
    }

    private func reading() -> ReceiptReading {
        ReceiptReading(shop: "MUSTERMARKT LINDE", categoryId: nil, date: "2026-10-26", time: "14:31", total: 27.65,
                       currency: "EUR", method: .cash, language: "de", from: "text",
                       rows: ["MUSTERMARKT LINDE", "SUMME EUR 27,65"], sure: .init(shop: true, date: true, total: true, method: true))
    }

    @Test func theReceiptWindowMakesItPicksItAndSavesIt() async throws {
        let phone = try await phone()
        let check = ReceiptCheckModel(reading: reading(), phone: phone, language: .english)
        await check.load()
        #expect(check.category == nil)
        check.newCategory.begin()
        #expect(check.newCategory.isAsking)
        check.newCategory.name = "Fiktiv Markt"
        await check.createCategory()
        let made = try #require(try await phone.categories().custom.first)
        #expect(made.name == "Fiktiv Markt")
        #expect(check.category == made.id, "picked in the window")
        let offered = try #require(check.choices.first { $0.id == made.id })
        #expect(offered.look == made.look)
        #expect(check.choices.last?.id == nil, "Not sorted stays last")
        #expect(check.newCategory.problem == nil && check.newCategory.name.isEmpty)
        #expect(check.hasSomethingToDiscard, "a change of the person's: Cancel asks first")

        #expect(await check.save() == .cash)
        let receipt = try #require(try await phone.receipts().first)
        #expect(receipt.category == made.id && receipt.categorySource == .manual)
    }

    @Test func editReceiptOffersItToo() async throws {
        let phone = try await phone()
        let first = ReceiptCheckModel(reading: reading(), phone: phone, language: .english)
        await first.load()
        #expect(await first.save() == .cash)
        let edit = ReceiptCheckModel(editing: try #require(try await phone.receipts().first), phone: phone,
                                     language: .english)
        await edit.load()
        edit.newCategory.name = "Fiktiv Laden"
        await edit.createCategory()
        let made = try #require(try await phone.categories().custom.first)
        #expect(edit.category == made.id && edit.hasChanges)
    }

    @Test func theReceiptWindowsCancelKeepsTheCategoryAndTheChangeWindowOffersIt() async throws {
        let phone = try await phone()
        let session = await PhoneTest.session(nil, transport: RoutedTransport())
        let dashboard = DashboardStore(session: session, backend: phone)
        await dashboard.reload()

        let check = ReceiptCheckModel(reading: reading(), phone: phone, language: .english)
        await check.load()
        check.newCategory.name = "Wochenmarkt"
        await check.createCategory()
        // The window's Cancel (Discard): nothing is kept of the receipt, the category stays.
        #expect(phone.summary.receipts == 0)
        #expect(try await phone.categories().custom.map(\.name) == ["Wochenmarkt"])
        #expect(dashboard.dashboard?.pick.spend.contains("Wochenmarkt") == false, "no payment changed: not rebuilt yet")

        // A payment's change window opened afterwards offers it (the dashboard is built again as its page loads).
        let rewe = try #require(dashboard.dashboard?.transactions.first { $0.place.contains("REWE") })
        let page = dashboard.transactionDetailStore(for: rewe)
        await page.load()
        page.beginRecategorisation()
        #expect(page.choices.contains { $0.name == "Wochenmarkt" })
        // Without a change since, the page's load builds nothing again.
        let revision = dashboard.revision
        await dashboard.transactionDetailStore(for: rewe).load()
        #expect(dashboard.revision == revision)
    }

    @Test(arguments: [ReceiptDirection.out, .in])
    func addCashMakesItAndPicksItForSpentAndReceived(direction: ReceiptDirection) async throws {
        let phone = try await phone()
        let window = CashEntryModel(direction: direction, phone: phone,
                                    today: try #require(ReceiptDay.date("2026-10-06")), language: .english)
        await window.load()
        window.newCategory.begin()
        window.newCategory.name = direction == .out ? "Flohmarkt" : "Verkauf Fiktiv"
        await window.createCategory()
        let made = try #require(try await phone.categories().custom.first)
        #expect(window.category == made.id, "picked")
        #expect(window.choices.contains { $0.id == made.id } && window.choices.last?.id == nil)
        #expect(window.hasChanges, "Cancel asks first")
        // One's own is in both lists: switching sides keeps it.
        window.direction = direction == .out ? .in : .out
        #expect(window.category == made.id)
        window.direction = direction

        window.amountText = "12"
        let saved = try #require(await window.save())
        #expect(saved.category == made.id && saved.direction == direction)
    }

    @Test func addCashsCancelKeepsTheCategoryAndEditEntryOffersIt() async throws {
        let phone = try await phone()
        let window = CashEntryModel(phone: phone, language: .english)
        await window.load()
        window.newCategory.name = "Kinokasse"
        await window.createCategory()
        #expect(phone.summary.receipts == 0, "the entry was never saved")
        #expect(try await phone.categories().custom.map(\.name) == ["Kinokasse"])

        let entry = try await phone.addCashEntry(CashEntryDraft(direction: .out, amount: 5, date: "2026-10-06",
                                                                what: "Eis", category: nil, paidFrom: nil))
        let edit = CashEntryModel(editing: entry, phone: phone, language: .english)
        await edit.load()
        #expect(edit.choices.contains { $0.name == "Kinokasse" })
        edit.newCategory.name = "Eis Fiktiv"
        await edit.createCategory()
        #expect(edit.category == (try await phone.categories().custom.last?.id))
    }

    @Test(arguments: ["Bargeld", "Groceries", "  "])
    func aNameProblemInTheMenusMakesNothingAndKeepsTheName(name: String) async throws {
        let phone = try await phone()
        let check = ReceiptCheckModel(reading: reading(), phone: phone, language: .english)
        await check.load()
        let cash = CashEntryModel(phone: phone, language: .english)
        await cash.load()
        cash.category = "eating-out"
        for model in [check.newCategory, cash.newCategory] {
            model.begin()
            model.name = name
        }
        await check.createCategory()
        await cash.createCategory()
        #expect(try await phone.categories().custom.isEmpty, "nothing made")
        let expected = name.trimmingCharacters(in: .whitespaces).isEmpty ? LedgerError.emptyName : LedgerError.nameTaken
        #expect(check.newCategory.problem == expected.localizedDescription)
        #expect(cash.newCategory.problem == expected.localizedDescription)
        #expect(check.newCategory.name == name && cash.newCategory.name == name, "kept to correct")
        #expect(check.category == nil && cash.category == "eating-out", "the category chosen stays")
        cash.newCategory.begin()
        #expect(cash.newCategory.isAsking && cash.newCategory.name == name)
    }
}
