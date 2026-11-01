import Foundation
import Testing
@testable import Aresium

/// Brief 82: several payments changed at once, what the screens decide. The select icon only where selecting is offered,
/// the header's words and the bar's states, a summed row ticking its payments, selecting ending with its list, the change
/// window for a selection (its title, choices, Save and the questions it asks, one view with one payment's), one name for
/// a selection and its question, the words in both languages. Everything is made up.
@MainActor
@Suite(.serialized)
struct SelectionScreensTests {
    private func payment(_ id: String, _ shop: String, amount: String = "-10.00", category: String? = "groceries",
                         source: CategorySource = .starter, own: String? = nil, day: String = "2026-10-02") -> LedgerPayment {
        LedgerPayment(id: id, account: "fictional-select", source: "bank", externalId: "fictional-" + id,
                      bookingDate: day, amount: amount, currency: "EUR", text: "Fictional purchase",
                      counterparty: shop, category: category, categorySource: category == nil ? .none : source,
                      extraCategories: [], sequence: Int(id.filter(\.isNumber)) ?? 0, ownName: own)
    }

    private func receipt(_ id: String, _ shop: String, entry: Bool = false,
                         category: String? = "groceries") -> LedgerReceipt {
        LedgerReceipt(id: id, date: "2026-10-03", time: nil, shop: shop, total: "4.00", currency: "EUR", euroAmount: nil,
                      method: .cash, category: category, categorySource: category == nil ? .none : .manual, rows: [], from: "text",
                      paymentID: nil, created: Date(timeIntervalSince1970: 1), direction: .out,
                      kind: entry ? .manual : .receipt)
    }

    /// Groceries, household, hobbies, cash withdrawals and salary chosen; Fictional Shop three times, Juniper Market
    /// twice, all in Groceries in October, plus a receipt and a cash entry there.
    private func setup(_ payments: [LedgerPayment]? = nil, receipts: [LedgerReceipt]? = nil)
        async throws -> (PhoneBackend, DashboardStore) {
        let phone = try await PhoneCountingTests.backend()
        let chosen = ["groceries", "household", "hobbies", "cash", "salary"].enumerated().map {
            ChosenCategory(id: $0.element, order: $0.offset)
        }
        let payments = payments ?? [
            payment("p1", "Fictional Shop", day: "2026-10-02"), payment("p2", "Fictional Shop", day: "2026-10-05"),
            payment("p3", "Fictional Shop", day: "2026-10-09"), payment("p4", "Juniper Market", day: "2026-10-11"),
            payment("p5", "Juniper Market", day: "2026-10-14"),
        ]
        try await phone.ledger.restore(LedgerExport(exported: "2026-10-30",
            accounts: [LedgerAccount(id: "fictional-select", name: "Fictional bank")], payments: payments,
            categories: chosen, learned: [], layouts: [],
            receipts: receipts ?? [receipt("r1", "Fictional Receipt"), receipt("e1", "Fictional Entry", entry: true)]),
            catalog: #require(phone.catalog))
        try await phone.refresh()
        let store = DashboardStore(session: await PhoneTest.session(nil, transport: RoutedTransport()), backend: phone)
        await store.reload()
        #expect(store.error == nil)
        return (phone, store)
    }

    private let groceries = DashboardRoute(category: "Groceries", side: .expenses, month: "2026-10")

    private func entries(_ store: DashboardStore) -> [PaymentListEntry] {
        store.paymentList(category: "Groceries", month: "2026-10", side: .expenses).entries
    }

    private func entry(_ store: DashboardStore, _ id: String) throws -> PaymentListEntry {
        try #require(entries(store).first { store.selectionIDs(for: $0).contains(id) })
    }

    // MARK: the icon

    @Test func theIconOnlyWhereSelectingIsOffered() async throws {
        let (_, store) = try await setup()
        #expect(store.offersSelection(on: groceries), "a category's month list in phone mode")
        #expect(!store.offersSelection(on: DashboardRoute(category: "Groceries", side: .expenses)), "its months")
        #expect(!store.offersSelection(on: DashboardRoute(category: "Groceries", side: .expenses, month: "2026-09")),
                "a month without payments")
        #expect(!store.offersSelection(on: DashboardRoute(category: "", side: .expenses, month: "2026-10", cash: true)))
        #expect(!store.offersSelection(on: DashboardRoute(monthPage: "2026-10", side: .expenses)))
        #expect(!store.offersSelection(on: DashboardRoute(name: PaymentNameRoute(key: "x", title: "Fictional Shop"),
                                                          month: "2026-10")), "a name's month")
        #expect(!store.offersSelection(on: .search))
        let server = DashboardStore(session: EmpireSession(app: .aresium, storage: PhoneTokens()), sample: true)
        await server.reload()
        let category = try #require(server.dashboard?.categories.first?.name)
        let month = try #require(server.dashboard?.months.last?.key)
        #expect(!server.offersSelection(on: DashboardRoute(category: category, side: .expenses, month: month)),
                "server mode offers nothing")
    }

    // MARK: ticking

    @Test func aTapTicksAndAllAndNoneAndASummedRowTicksItsPayments() async throws {
        let (_, store) = try await setup()
        var selection = PaymentSelection(route: groceries)
        #expect(SelectionWording.title(selection.live(in: store).count) == "Select payments")
        #expect(SelectionWording.allButton(allTicked: selection.allTicked(in: store)) == "All")
        let first = try entry(store, "p1")
        #expect(selection.isTicked(first, in: store) == false)
        selection.toggle(first, in: store)
        #expect(selection.ids == ["p1"] && selection.isTicked(first, in: store) == true)
        #expect(SelectionWording.title(selection.ids.count) == "1 selected")
        selection.toggle(first, in: store)
        #expect(selection.ids.isEmpty)
        selection.toggleAll(in: store)
        #expect(selection.ids == ["p1", "p2", "p3", "p4", "p5", "r1", "e1"] && selection.allTicked(in: store))
        #expect(SelectionWording.allButton(allTicked: true) == "None")
        selection.toggleAll(in: store)
        #expect(selection.ids.isEmpty)

        // Added up, Fictional Shop is one row with one circle that stands for its three payments.
        store.sums.setEverywhere(true)
        let sum = try #require(entries(store).first { if case .summed = $0 { true } else { false } })
        let members = store.selectionIDs(for: sum)
        #expect(members.count >= 2)
        selection.toggle(sum, in: store)
        #expect(selection.ids == members && selection.isTicked(sum, in: store) == true)
        selection.ids.remove(try #require(members.first))
        #expect(selection.isTicked(sum, in: store) == false, "partly ticked reads as not ticked")
        selection.toggle(sum, in: store)
        #expect(selection.ids == members, "a tap then ticks them all")
        selection.toggle(sum, in: store)
        #expect(selection.ids.isEmpty)
        // A payment that left the list (a stale id) is not counted.
        selection.ids = ["p1", "gone"]
        #expect(selection.live(in: store) == ["p1"])
    }

    @Test func aCoveredRowHasNoCircle() async throws {
        let (_, store) = try await setup([
            payment("p1", "Geldautomat Fiktivbank", amount: "-100.00", category: "cash", source: .starter),
        ], receipts: [receipt("r1", "Fictional Kiosk", category: nil)])
        let cash = store.paymentList(category: "Cash withdrawals", month: "2026-10", side: .expenses)
        let route = DashboardRoute(category: "Cash withdrawals", side: .expenses, month: "2026-10")
        let selection = PaymentSelection(route: route)
        #expect(cash.entries.contains { entry in
            if case let .payment(row, _) = entry { row.transaction.coveredBy != nil } else { false }
        }, "the withdrawal's covered row")
        for entry in cash.entries {
            if case let .payment(row, _) = entry, row.transaction.coveredBy != nil {
                #expect(selection.isTicked(entry, in: store) == nil, "no circle")
            } else {
                #expect(selection.isTicked(entry, in: store) == false)
            }
        }
    }

    @Test func selectingBelongsToTheListOnTop() {
        var place = DashboardPlace()
        let months = DashboardRoute(category: "Groceries", side: .expenses)
        place.path = [months, groceries]
        place.selection = PaymentSelection(route: groceries, ids: ["p1"])
        // The category's id filled in, then a rename: the same list, so selecting follows it.
        place.path[1].categoryID = "groceries"
        #expect(place.selection?.route.categoryID == "groceries" && place.selection?.ids == ["p1"])
        place.path[1].category = "Food"
        #expect(place.selection?.route.category == "Food" && place.selection?.ids == ["p1"])
        #expect(place.selection?.belongs(to: place.path[1]) == true)
        // Another page on top (the back arrow, a pushed page): selecting ends.
        place.path.removeLast()
        #expect(place.selection == nil)
        place.path.append(groceries)
        place.selection = PaymentSelection(route: groceries)
        place.open(DashboardRoute(name: PaymentNameRoute(key: "k", title: "Fictional Shop")))
        #expect(place.selection == nil)
        #expect(!groceries.isSameList(as: DashboardRoute(category: "Groceries", side: .income, month: "2026-10")))
        #expect(!groceries.isSameList(as: DashboardRoute(category: "Groceries", side: .expenses, month: "2026-09")))
    }

    // MARK: the bar

    @Test func theBarsStates() async throws {
        let (phone, store) = try await setup()
        let none = SelectionBarState(summary: store.selectionSummary([]), ownNames: store.ownNames)
        #expect(!none.category && !none.name && none.offersName, "both off at 0 selected")
        let receiptsOnly = SelectionBarState(summary: store.selectionSummary(["r1", "e1"]), ownNames: store.ownNames)
        #expect(receiptsOnly.category && !receiptsOnly.name, "receipts and cash keep their typed Shop")
        let mixed = SelectionBarState(summary: store.selectionSummary(["p1", "r1"]), ownNames: store.ownNames)
        #expect(mixed.category && mixed.name)
        phone.setOwnNames(false)
        let hidden = SelectionBarState(summary: store.selectionSummary(["p1"]), ownNames: store.ownNames)
        #expect(hidden.category && !hidden.name && !hidden.offersName, "no Name while own names are off")
    }

    // MARK: the change window

    @Test func theWindowForASelectionNamesItAndOffersTheSidesCategories() async throws {
        let (_, store) = try await setup()
        var outcomes: [SelectionOutcome] = []
        let window = SelectionCategoryChange(ids: ["p1", "p2", "r1"], route: groceries, store: store) { outcomes.append($0) }
        let heading = try #require(window.heading)
        #expect(heading.title == "3 payments" && heading.amount == -24 && heading.current == "Groceries")
        #expect(heading.selection && heading.reason == nil)
        AppLanguage.$scoped.withValue(.german) { #expect(SelectionWording.payments(3) == "3 Buchungen") }
        #expect(SelectionWording.payments(1) == "1 payment")
        #expect(!window.choices.contains { $0.name == "Groceries" }, "not the category they are in")
        #expect(window.choices.contains { $0.name == "Household" })
        #expect(window.paymentSide == .spend && window.offersNewCategory)
        #expect(!window.canSave, "nothing picked")
        window.select("Household")
        #expect(window.target == "Household" && window.canSave)
        window.mode = .add
        #expect(!window.canSave, "Add needs a category picked")
        #expect(!window.choices.contains { $0.name == "Own transfers" })
        window.select("Groceries")
        #expect(window.extras.isEmpty, "never the current category")
        #expect(outcomes.isEmpty)
    }

    @Test func switchAsksAboutTheShopsOtherPaymentsAndAllMovesThemWithOneUndo() async throws {
        let (phone, store) = try await setup()
        let before = try await phone.ledger.export(on: Date(timeIntervalSince1970: 0))
        var outcomes: [SelectionOutcome] = []
        let window = SelectionCategoryChange(ids: ["p1", "p2"], route: groceries, store: store) { outcomes.append($0) }
        window.select("Household")
        await window.save()
        #expect(window.saveError == nil)
        guard case let .merchant(_, wording)? = window.question else { Issue.record("no shop question"); return }
        #expect(wording.question() == "Also move 1 other payment from Fictional Shop?")
        #expect(wording.allTitle() == "Move 1 more" && wording.onlyTitle() == "Only these")
        #expect(outcomes.isEmpty, "the window waits for the answer")
        window.answer(moveOthers: true)
        for _ in 0..<100 where outcomes.isEmpty { try await Task.sleep(for: .milliseconds(20)) }
        guard case let .done(message, undo)? = outcomes.first else { Issue.record("not done"); return }
        #expect(message == "3 payments moved to Household", "the selection and the shop's other payment")
        #expect(try await phone.ledger.payments().filter { ["p1", "p2", "p3"].contains($0.id) }
            .allSatisfy { $0.category == "household" })
        #expect(!store.transactions(category: "Groceries", month: "2026-10", side: .expenses)
            .contains { ["p1", "p2", "p3"].contains($0.id) }, "they left the list")
        #expect(try await undo.perform() == .undone)
        #expect(try await phone.ledger.export(on: Date(timeIntervalSince1970: 0)) == before)
        #expect(store.transactions(category: "Groceries", month: "2026-10", side: .expenses).count == 7)
    }

    @Test func onlyTheseLeavesTheOthersAndARefusedUndoSaysSo() async throws {
        let (phone, store) = try await setup()
        var outcomes: [SelectionOutcome] = []
        let window = SelectionCategoryChange(ids: ["p4"], route: groceries, store: store) { outcomes.append($0) }
        window.select("Hobbies")
        await window.save()
        #expect(window.question != nil)
        window.answer(moveOthers: false)
        guard case let .done(message, undo)? = outcomes.first else { Issue.record("not done"); return }
        #expect(message == "1 payment moved to Hobbies")
        #expect(try await phone.ledger.payment("p5")?.category == "groceries")
        // Something else is saved meanwhile: the undo is refused, in words the bar shows.
        _ = try await store.switchCategory(ids: ["p1"], to: "Household")
        let outcome = try await undo.perform()
        #expect(outcome == .unavailable && outcome.message == "Cannot undo because the data changed.")
    }

    @Test func addAsksToRemoveThemFromTheListsCategoryThenSaves() async throws {
        let (phone, store) = try await setup()
        var outcomes: [SelectionOutcome] = []
        let window = SelectionCategoryChange(ids: ["p1", "p4"], route: groceries, store: store) { outcomes.append($0) }
        window.mode = .add
        window.select("Hobbies")
        #expect(window.canSave)
        await window.save()
        guard case let .remove(question)? = window.question else { Issue.record("no removal question"); return }
        #expect(question.title() == "Also remove them from Groceries?")
        #expect(question.message() == "Then they count only under Hobbies.")
        #expect(try await phone.ledger.payment("p1")?.extraCategories.isEmpty == true, "nothing saved before the answer")
        await window.answerRemoveCurrent(remove: false)
        if case .merchant = window.question { window.answer(moveOthers: false) }
        guard case let .done(message, _)? = outcomes.first else { Issue.record("not done"); return }
        #expect(message == "Hobbies added to 2 payments")
        let saved = try #require(try await phone.ledger.payment("p1"))
        #expect(saved.category == "groceries" && saved.extraCategories == ["hobbies"])
    }

    @Test func oneViewForOnePaymentAndASelection() async throws {
        let (_, store) = try await setup()
        let row = try #require(store.dashboard?.transactions.first { $0.id == "p1" })
        let single = store.transactionDetailStore(for: row)
        await single.load()
        single.beginRecategorisation()
        let heading = try #require(single.heading)
        #expect(heading.title == row.place && heading.amount == nil && !heading.selection)
        #expect(single.choices.contains { $0.name == "Groceries" }, "one payment's current category shows as current")
        #expect(CategoryWindowWording.modeLine(.switchCategory, current: "Groceries", selection: false)
                == "Wrong category? Pick the one it belongs in — it moves there.")
        for language in [AppLanguage.english, .german] {
            let line = CategoryWindowWording.modeLine(.switchCategory, current: "Groceries", selection: true,
                                                      language: language)
            #expect(line == (language == .english ? "Wrong category? Pick the one they belong in — they move there."
                                                  : "Falsche Kategorie? Wähl die richtige – die Buchungen wandern dorthin."))
            let add = CategoryWindowWording.modeLine(.add, current: "Groceries", selection: true, language: language)
            #expect(add == (language == .english
                ? "Also show these under other categories. Each stays counted once, so nothing is double-counted."
                : "Zeig sie auch unter anderen Kategorien. Jede wird nur einmal gezählt, nichts doppelt."))
        }
    }

    // MARK: one name

    @Test func nameStartsWithTheNameTheyShareAndAsksAboutTheShopsOthers() async throws {
        let (phone, store) = try await setup()
        var outcomes: [SelectionOutcome] = []
        let shared = SelectionRename(ids: ["p1", "p2", "r1"], store: store) { outcomes.append($0) }
        #expect(shared.count == 2 && shared.skipped == 1)
        #expect(shared.start == "Fictional Shop" && shared.text == "Fictional Shop" && !shared.canRename)
        #expect(SelectionWording.nameTitle(shared.count) == "Name for 2 payments")
        #expect(SelectionWording.keepShop(shared.skipped) == "Receipts and cash entries keep their shop.")
        #expect(SelectionWording.keepShop(0) == nil)
        let mixed = SelectionRename(ids: ["p1", "p4"], store: store) { outcomes.append($0) }
        #expect(mixed.start.isEmpty, "two names: the field starts empty")
        shared.text = "  "
        #expect(!shared.canRename)
        shared.text = "Corner shop"
        #expect(shared.canRename)
        await shared.rename()
        let question = try #require(shared.question)
        #expect(question.selected == 2 && question.others == 1 && question.shopCount == 1 && question.shop == "Fictional Shop")
        #expect(question.title() == "Also the other 1 payment from Fictional Shop?")
        #expect(question.allTitle() == "All 3" && question.onlyTitle() == "Only these")
        #expect(outcomes.isEmpty)
        await shared.answer(all: true)
        guard case let .done(message, undo)? = outcomes.first else { Issue.record("not done"); return }
        #expect(message.hasPrefix("Name changed for 2 payments"))
        let names = try await phone.ledger.payments().filter { ["p1", "p2", "p3"].contains($0.id) }
        #expect(names.allSatisfy { $0.ownName == nil }, "All gives the shop the name, no payment's own")
        #expect(store.dashboard?.transactions.filter { ["p1", "p2", "p3"].contains($0.id) }
            .allSatisfy { $0.place == "Corner shop" } == true, "the shop's other payment too")
        #expect(try await undo.perform() == .undone)
        #expect(store.dashboard?.transactions.first { $0.id == "p3" }?.place == "Fictional Shop")
    }

    @Test func onlyTheseNamesTheSelectedAlone() async throws {
        let (_, store) = try await setup()
        var outcomes: [SelectionOutcome] = []
        let model = SelectionRename(ids: ["p4"], store: store) { outcomes.append($0) }
        model.text = "Market by the park"
        await model.rename()
        #expect(model.question != nil)
        await model.answer(all: false)
        guard case .done? = outcomes.first else { Issue.record("not done"); return }
        let rows = try #require(store.dashboard?.transactions)
        #expect(rows.first { $0.id == "p4" }?.place == "Market by the park")
        #expect(rows.first { $0.id == "p5" }?.place == "Juniper Market")
    }

    @Test func theNamesQuestionInBothLanguages() {
        for language in [AppLanguage.english, .german] {
            let english = language == .english
            let shops = SelectionRenameQuestion(name: "X", selected: 10, others: 14, shopCount: 3, shop: nil)
            #expect(shops.title(language: language) == (english ? "Also the other 14 payments from these 3 shops?"
                                                                 : "Auch die anderen 14 Buchungen von diesen 3 Geschäften?"))
            #expect(shops.message(language: language) == (english
                ? "With All, new payments from these shops get the name too."
                : "Mit „Alle“ bekommen auch neue Buchungen von diesen Geschäften den Namen."))
            #expect(shops.allTitle(language: language) == (english ? "All 24" : "Alle 24"))
            #expect(shops.onlyTitle(language: language) == (english ? "Only these" : "Nur diese"))
            let one = SelectionRenameQuestion(name: "X", selected: 10, others: 1, shopCount: 2, shop: nil)
            #expect(one.title(language: language) == (english ? "Also the other payment from these 2 shops?"
                                                               : "Auch die andere Buchung von diesen 2 Geschäften?"))
            let rewe = SelectionRenameQuestion(name: "X", selected: 10, others: 23, shopCount: 1, shop: "REWE")
            #expect(rewe.title(language: language) == (english ? "Also the other 23 payments from REWE?"
                                                                : "Auch die anderen 23 Buchungen von REWE?"))
            #expect(rewe.message(language: language) == (english ? "With All, new payments from REWE get the name too."
                                                                  : "Mit „Alle“ bekommen auch neue Buchungen von REWE den Namen."))
            let unnamed = SelectionRenameQuestion(name: "X", selected: 2, others: 5, shopCount: 1, shop: nil)
            #expect(unnamed.title(language: language) == (english ? "Also the other 5 payments from this shop?"
                                                                   : "Auch die anderen 5 Buchungen von diesem Geschäft?"))
            #expect(SelectionWording.title(0, language: language) == (english ? "Select payments" : "Buchungen auswählen"))
            #expect(SelectionWording.title(3, language: language) == (english ? "3 selected" : "3 ausgewählt"))
            #expect(SelectionWording.allButton(allTicked: false, language: language) == (english ? "All" : "Alle"))
            #expect(SelectionWording.allButton(allTicked: true, language: language) == (english ? "None" : "Keine"))
            #expect(SelectionWording.nameTitle(10, language: language) == (english ? "Name for 10 payments" : "Name für 10 Buchungen"))
            #expect(SelectionWording.payments(10, language: language) == (english ? "10 payments" : "10 Buchungen"))
            #expect(SelectionWording.keepShop(2, language: language) == (english
                ? "Receipts and cash entries keep their shop." : "Belege und Bargeld-Einträge behalten ihr Geschäft."))
        }
    }
}
