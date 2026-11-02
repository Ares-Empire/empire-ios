import Foundation
import Testing
@testable import Aresium

@MainActor
@Suite(.serialized)
struct CategoryEditingTests {
    private let auth = BackendAuth(token: nil)

    @Test(arguments: [AppLanguage.english, .german])
    func typedNamesReuseOfferTickOrMake(language: AppLanguage) async throws {
        try await AppLanguage.$scoped.withValue(language) {
            let phone = try await PhoneTest.backend(chosen: ["friends", "savings-investing"])
            try await phone.setOtherSide(false, for: "friends") // An existing spending-only Friends store.
            let result = try await phone.useCategory(named: "  FRÉUNDE  ", side: .income)
            #expect(result == CategoryUse(id: "friends", outcome: .offered, alsoOffered: .income))
            #expect(try await phone.categories().offered(for: .in).contains("friends"))
            let name = language == .english ? "Friends" : "Freunde"
            #expect(result.message(name: name) == (language == .english ? "Friends is now offered for money in too." : "Freunde gibt es jetzt auch für Einnahmen."))
            let before = try await phone.export()
            let reused = try await phone.useCategory(named: "friénds", side: .income)
            #expect(reused.outcome == .existing)
            #expect(reused.message(name: name) == (language == .english ? "Friends is already in your list." : "Freunde ist schon in deiner Liste."))
            #expect(try await phone.export() == before)
            #expect(try await phone.useCategory(named: "SPAREN & ANLEGEN", side: .income).outcome == .existing)
            let made = try await phone.useCategory(named: "  Fiktiv Café ", side: .income)
            #expect(made.outcome == .made && made.message(name: "Fiktiv Café") == nil)
            #expect(try await phone.useCategory(named: "fiktiv cafe", side: .spend).outcome == .offered)
            #expect(try await phone.categories().custom.count == 1)
            let ticked = try await phone.useCategory(named: "LEBENSMITTEL", side: .income)
            #expect(ticked == CategoryUse(id: "groceries", outcome: .ticked, alsoOffered: .income))
            #expect(ticked.message(name: language == .english ? "Groceries" : "Lebensmittel") == (language == .english ? "Groceries is ticked. Also for money in." : "Lebensmittel ist angehakt. Auch für Einnahmen."))
            let home = try await phone.useCategory(named: "Gehalt & Nebenjob", side: .income)
            #expect(home.outcome == .ticked && home.alsoOffered == nil)
            for refused in ["Not sorted", "NICHT SORTIERT", "Own transfers", "Eigene Umbuchungen", "Cash", "BÁRGELD", "Refunds"] {
                await #expect(throws: LedgerError.nameTaken) { try await phone.useCategory(named: refused, side: .spend) }
            }
            await #expect(throws: LedgerError.emptyName) { try await phone.useCategory(named: " \n ", side: .spend) }
        }
    }

    @Test(arguments: [AppLanguage.english, .german])
    func pickerNoticesClearTheFieldAndUseTheShownName(language: AppLanguage) async throws {
        try await AppLanguage.$scoped.withValue(language) {
            let phone = try await PhoneTest.backend(chosen: ["friends"])
            try await phone.setOtherSide(false, for: "friends")
            let model = CategoryPickerModel(phone: phone, settle: .seconds(60), changed: {})
            await model.load()
            model.newName = "fréunde"; model.newSide = .income
            await model.addCustom()
            #expect(model.problem == nil && model.newName.isEmpty)
            #expect(model.notice == (language == .english ? "Friends is now offered for money in too." : "Freunde gibt es jetzt auch für Einnahmen."))
            model.newName = "FRIENDS"
            await model.addCustom()
            #expect(model.notice == (language == .english ? "Friends is already in your list." : "Freunde ist schon in deiner Liste."))
            model.newName = "Lebensmittel"; model.newSide = .spend
            await model.addCustom()
            #expect(model.notice == (language == .english ? "Groceries is ticked." : "Lebensmittel ist angehakt."))
            #expect(await model.flush())
        }
    }

    @Test func freshFriendsBothWaysButExistingChoiceIsNeverChanged() async throws {
        let storage = PhoneTest.storage()
        let phone = try await PhoneTest.backend(storage: storage)
        let model = CategoryPickerModel(phone: phone, changed: {})
        await model.load()
        await model.toggle("friends")
        #expect(model.list?.hasOtherSide("friends") == true)
        #expect(await model.flush())
        try await phone.setOtherSide(false, for: "friends")
        try await phone.choose("friends")
        #expect(try await !phone.categories().hasOtherSide("friends"))
        let reopened = try await PhoneTest.backend(storage: storage)
        #expect(try await !reopened.categories().hasOtherSide("friends"))
        try await reopened.unchoose("friends", moveTo: nil)
        let result = try await reopened.useCategory(named: "Freunde", side: .spend)
        #expect(result.outcome == .ticked && result.alsoOffered == .income)
    }

    @Test(arguments: [AppLanguage.english, .german])
    func patriksChangeWindowOffersAndPicksFriends(language: AppLanguage) async throws {
        try await AppLanguage.$scoped.withValue(language) {
            let phone = try await PhoneTest.backend(chosen: ["salary", "friends"])
            try await phone.setOtherSide(false, for: "friends")
            _ = try await phone.importFiles([PhoneTest.vrBank([("01.10.2026", "Fictional employer", "Gehalt", 200000)])], auth: auth)
            let dashboard = DashboardStore(session: await PhoneTest.session(nil, transport: RoutedTransport()), backend: phone)
            await dashboard.reload()
            let row = try #require(dashboard.dashboard?.transactions.first)
            let window = dashboard.transactionDetailStore(for: row)
            await window.load(); window.beginRecategorisation()
            window.newCategory.name = "frÉunde"
            await window.createCategory()
            let shown = language == .english ? "Friends" : "Freunde"
            #expect(window.newCategory.problem == nil && window.target == shown)
            #expect(window.choices.filter { $0.name == shown }.count == 1)
            await window.save()
            #expect(window.saveError == nil)
            #expect(try await phone.ledger.payment(row.id)?.category == "friends")
        }
    }

    @Test(arguments: [AppLanguage.english, .german])
    func renameKeepsIdentityAndEverythingAttachedAndRestores(language: AppLanguage) async throws {
        try await AppLanguage.$scoped.withValue(language) {
            let storage = PhoneTest.storage()
            let phone = try await PhoneTest.backend(storage: storage, chosen: ["groceries", "friends"])
            let own = try await phone.addCustom(named: "Fiktiv Café", side: .income)
            try await phone.setOtherSide(true, for: own)
            _ = try await phone.importFiles([CategoryCountsTests.bankFile], auth: auth)
            let row = try #require(try await phone.ledger.payments().first { $0.category == "groceries" })
            try await phone.ledger.setCategory(row.id, category: "groceries", extras: [own], source: .manual)
            try await phone.ledger.remember(["fictional-rule": "groceries", "fictional-own": own])
            try await phone.ledger.addReceipt(CashEntryDraft(direction: .in, amount: 20, date: "2026-10-05", what: "Fictional gift", category: own).receipt(id: "gift"))
            let before = try await phone.export()
            let dashboard = DashboardStore(session: await PhoneTest.session(nil, transport: RoutedTransport()), backend: phone)
            await dashboard.reload()
            let original = try #require(try await phone.categories().name(of: "groceries"))
            var legacy = DashboardPlace()
            legacy.open(DashboardRoute(category: original, side: .expenses))
            legacy.followCategories(try await phone.categories())
            #expect(legacy.path.last?.categoryID == "groceries")
            var place = DashboardPlace()
            place.open(dashboard.route(category: original, side: .expenses, current: true))
            let sumKey = dashboard.sumCategoryKey(original)
            dashboard.sums.setName("fictional-name-key", in: sumKey, sums: true)
            try await phone.rename("groceries", to: "  Fiktiv Vorrat  ")
            try await phone.rename(own, to: "Fiktiv Café neu")
            #expect(dashboard.widgetCategoryRoute(original) == nil, "a link is checked even before the covered dashboard rebuilds")
            await dashboard.reloadIfCategoriesChanged()
            let list = try await phone.categories()
            place.followCategories(list)
            legacy.followCategories(list)
            #expect(legacy.path.last?.category == "Fiktiv Vorrat")
            #expect(place.path.last?.category == "Fiktiv Vorrat")
            #expect(list.name(of: "groceries") == "Fiktiv Vorrat" && list.id(named: "Fiktiv Vorrat") == "groceries")
            #expect(list.groups.flatMap(\.items).first { $0.id == "groceries" }?.originalName == original)
            #expect(dashboard.dashboard?.categories.contains { $0.name == "Fiktiv Vorrat" } == true)
            #expect(dashboard.dashboard?.transactions.first { $0.id == row.id }?.categoryName == "Fiktiv Vorrat")
            #expect(dashboard.sumCategoryKey("Fiktiv Vorrat") == sumKey)
            #expect(dashboard.sums.choices.sums(name: "fictional-name-key", category: dashboard.sumCategoryKey("Fiktiv Vorrat")))
            #expect(dashboard.widgetCategoryRoute(original) == nil)
            #expect(dashboard.widgetCategoryRoute("Fiktiv Vorrat")?.categoryID == "groceries")
            #expect(try await phone.categories(language: language == .english ? .german : .english).name(of: "groceries") == "Fiktiv Vorrat")
            let after = try await phone.export()
            #expect(after.schema == 7 && after.payments == before.payments && after.receipts == before.receipts && after.learned == before.learned)
            let oldOwn = try #require(before.categories.first { $0.id == own })
            let newOwn = try #require(after.categories.first { $0.id == own })
            #expect(oldOwn.id == newOwn.id && oldOwn.look == newOwn.look && oldOwn.side == newOwn.side && oldOwn.otherSide == newOwn.otherSide && oldOwn.order == newOwn.order)
            let restored = try await PhoneTest.backend()
            try await restored.restore(after.encoded())
            #expect(try await restored.ledger.chosen() == after.categories)
            let reopened = try await PhoneTest.backend(storage: storage)
            #expect(try await reopened.categories().name(of: "groceries") == "Fiktiv Vorrat")
            #expect(try await phone.useCategory(named: "FIKTIV VORRÁT", side: .spend).id == "groceries")
            #expect(try await phone.useCategory(named: "Lebensmittel", side: .spend).id == "groceries")
            try await phone.rename("groceries", to: "GROCERIES") // Its own original is allowed, in either language.
            try await phone.rename("groceries", to: "LEBENSMITTEL")
            try await phone.rename(own, to: "FIKTIV CAFE NEU") // Its own present name is allowed too.
            await #expect(throws: LedgerError.nameTaken) { try await phone.rename("groceries", to: "Freunde") }
            await #expect(throws: LedgerError.nameTaken) { try await phone.rename(own, to: "Groceries") }
            await #expect(throws: LedgerError.nameTaken) { try await phone.rename("groceries", to: "fiktiv cafe neu") }
            await #expect(throws: LedgerError.emptyName) { try await phone.rename("groceries", to: "  ") }
            try await phone.rename("groceries", to: nil)
            #expect(try await phone.categories().name(of: "groceries") == original)
            // Other's original English name is also a reserved dashboard word; its own original is still allowed.
            try await phone.choose("other")
            try await phone.rename("other", to: "ÓTHER")
            #expect(try await phone.categories().name(of: "other") == "ÓTHER")
            await #expect(throws: LedgerError.nameTaken) { try await phone.rename(own, to: "Other") }
            await #expect(throws: LedgerError.notFound) { try await phone.rename(CategoryCatalog.ownTransfers, to: "Fiktiv") }
        }
    }

    @Test(arguments: [false, true])
    func deleteAndRemoveResortManualChoicesCleanExtrasAndReceiptsAndKeepOnlyDefaultRules(custom: Bool) async throws {
        let phone = try await PhoneTest.backend(chosen: ["groceries", "friends"])
        let id = custom ? try await phone.addCustom(named: "Fictional hobby", side: .spend) : "friends"
        _ = try await phone.importFiles([CategoryCountsTests.bankFile], auth: auth)
        let payments = try await phone.ledger.payments()
        for payment in payments { try await phone.ledger.setCategory(payment.id, category: id, source: .manual) }
        let tagged = try #require(payments.first)
        try await phone.ledger.setCategory(tagged.id, category: "groceries", extras: [id], source: .manual)
        try await phone.ledger.remember(["fictional-learned": id])
        for direction in [ReceiptDirection.in, .out] {
            try await phone.ledger.addReceipt(CashEntryDraft(direction: direction, amount: 10, date: "2026-10-05", what: "Fictional cash", category: id).receipt(id: direction.rawValue))
        }
        var receipt = CashEntryDraft(direction: .out, amount: 5, date: "2026-10-05", what: "Fictional receipt", category: id).receipt(id: "card")
        receipt.kind = .receipt; receipt.method = .card
        try await phone.ledger.addReceipt(receipt)
        let model = CategoryPickerModel(phone: phone, settle: .seconds(60), changed: {})
        await model.load(); await model.askToRemove(id)
        #expect(model.removal?.count == payments.count - 1)
        await model.remove()
        #expect(model.problem == nil && model.removal == nil && model.list?.isChosen(id) == false)
        var place = DashboardPlace()
        place.open(DashboardRoute(category: "Removed", side: .expenses, categoryID: id))
        place.followCategories(try #require(model.list))
        #expect(place.path.isEmpty)
        let sorted = try await phone.ledger.payments()
        #expect(sorted.filter { $0.place.contains("REWE") }.allSatisfy { $0.category == "groceries" })
        #expect(sorted.filter { !$0.place.contains("REWE") && $0.id != tagged.id }.allSatisfy { $0.category == nil && $0.categorySource == .none })
        #expect(sorted.allSatisfy { !$0.extraCategories.contains(id) })
        #expect(try await phone.ledger.receipts().allSatisfy { $0.category == nil && $0.categorySource == .none })
        #expect(try await phone.ledger.learned()["fictional-learned"] == (custom ? nil : id))
        #expect(model.count(of: "groceries") == sorted.filter { $0.category == "groceries" }.count)
        if !custom {
            try await phone.choose(id)
            #expect(try await phone.ledger.learned()["fictional-learned"] == id)
        }
        await #expect(throws: LedgerError.notFound) { try await phone.unchoose(CategoryCatalog.ownTransfers, moveTo: nil) }
        #expect(await model.flush())
    }

    @Test func tickByNameSortsWaitingAndSchemasOneThroughFiveStillRestore() async throws {
        let phone = try await PhoneTest.backend()
        _ = try await phone.importFiles([CategoryCountsTests.bankFile], auth: auth)
        #expect(try await phone.paymentCount(in: "groceries") == 0)
        #expect(try await phone.useCategory(named: "groceries", side: .spend).outcome == .ticked)
        #expect(try await phone.paymentCount(in: "groceries") == 2)
        let file = try await phone.export()
        for schema in 1...5 {
            var old = file; old.schema = schema
            let restored = try await PhoneTest.backend()
            try await restored.restore(old.encoded())
            #expect(try await restored.ledger.payments() == old.payments)
        }
    }

    @Test func pickerRenameFailureRetainsTextAndOriginalNameCanBeRestored() async throws {
        let phone = try await PhoneTest.backend(chosen: ["friends", "groceries", "savings-investing"])
        var rebuilt = 0
        let model = CategoryPickerModel(phone: phone, changed: { rebuilt += 1 })
        await model.load(); model.beginRename("friends")
        #expect(model.renameName == "Friends" && !model.canRename)
        model.renameName = "  "
        #expect(!model.canRename)
        await model.rename() // Return can submit an empty field even though the button is disabled.
        #expect(model.problem == LedgerError.emptyName.localizedDescription && model.renameName == "  ")
        model.renameName = "groceries"; await model.rename()
        #expect(model.problem == LedgerError.nameTaken.localizedDescription && model.renameName == "groceries")
        model.beginRename("friends")
        #expect(model.renameName == "groceries")
        model.renameName = "Fictional circle"; await model.rename()
        #expect(model.problem == nil && model.list?.name(of: "friends") == "Fictional circle")
        #expect(rebuilt == 0)
        await model.useOriginalName("friends")
        #expect(model.list?.name(of: "friends") == "Friends")
        #expect(await model.flush()); #expect(rebuilt == 1)
        model.beginRename("savings-investing")
        model.renameName = "Fictional savings"; await model.rename()
        #expect(model.list?.name(of: "savings-investing") == "Fictional savings")
    }

    @Test(arguments: [AppLanguage.english, .german])
    func receiptAndBothCashWindowsPickEveryResolvedName(language: AppLanguage) async throws {
        try await AppLanguage.$scoped.withValue(language) {
            let phone = try await PhoneTest.backend(chosen: ["groceries", "salary", "savings-investing"])
            let reading = ReceiptReading(shop: "Fictional shop", categoryId: nil, date: "2026-10-05", time: nil,
                                         total: 5, currency: "EUR", method: .cash, language: language.code, from: "text",
                                         rows: [], sure: .init(shop: true, date: true, total: true, method: true))
            let receipt = ReceiptCheckModel(reading: reading, phone: phone, language: language)
            await receipt.load()
            // Existing, offered, ticked, made, and a transfer explicitly requested by name.
            for (name, expected) in [("lébensmittel", "groceries"), ("Gehalt & Nebenjob", "salary"),
                                     ("Drogerie", "drugstore"), ("Fiktiv Beleg", ""), ("Sparen & Anlegen", "savings-investing")] {
                receipt.newCategory.name = name
                await receipt.createCategory()
                #expect(receipt.newCategory.problem == nil)
                let id = expected.isEmpty ? try #require(try await phone.categories().id(named: name)) : expected
                #expect(receipt.category == id && receipt.choices.contains { $0.id == id })
            }
            for direction in [ReceiptDirection.in, .out] {
                let cash = CashEntryModel(phone: phone, language: language)
                cash.direction = direction
                await cash.load()
                for name in ["Groceries", "Gehalt & Nebenjob", "Freunde", "Fiktiv Bargeld", "Sparen & Anlegen"] {
                    cash.newCategory.name = name
                    await cash.createCategory()
                    #expect(cash.newCategory.problem == nil)
                    let id = try #require(try await phone.categories().reusableID(named: name))
                    #expect(cash.category == id && cash.choices.filter { $0.id == id }.count == 1)
                }
            }
            try await phone.rename("savings-investing", to: "Fiktiv Rücklage")
            var saved = CashEntryDraft(direction: .out, amount: 5, date: "2026-10-05", what: "Fictional transfer",
                                       category: "savings-investing").receipt(id: "transfer")
            let editCash = CashEntryModel(editing: saved, phone: phone, language: language)
            await editCash.load()
            #expect(editCash.category == "savings-investing")
            #expect(editCash.choices.first { $0.id == editCash.category }?.name == "Fiktiv Rücklage")
            saved.kind = .receipt; saved.method = .card
            let editReceipt = ReceiptCheckModel(editing: saved, phone: phone, language: language)
            await editReceipt.load()
            #expect(editReceipt.category == "savings-investing")
            #expect(editReceipt.choices.first { $0.id == editReceipt.category }?.name == "Fiktiv Rücklage")
        }
    }

    @Test func removalRunsLearnedRulesBeforeTheBuiltInSortingAndRetickingReactivatesDefaultRules() async throws {
        let phone = try await PhoneTest.backend(chosen: ["groceries", "friends"])
        _ = try await phone.importFiles([CategoryCountsTests.bankFile], auth: auth)
        let payments = try await phone.ledger.payments()
        let hall = try #require(payments.first { $0.place.contains("Kletterhalle") })
        let rewe = try #require(payments.first { $0.place.contains("REWE") })
        let rent = try #require(payments.first { $0.place.contains("Hausverwaltung") })
        let hallRules = try await phone.engine.learn(hall.sorting(raw: false), categoryID: "groceries")
        let rentRules = try await phone.engine.learn(rent.sorting(raw: false), categoryID: "friends")
        try await phone.ledger.remember(hallRules.merging(rentRules) { _, last in last })
        for payment in payments { try await phone.ledger.setCategory(payment.id, category: "friends", source: .manual) }
        try await phone.unchoose("friends", moveTo: nil)
        #expect(try await phone.ledger.payment(hall.id)?.categorySource == .learned)
        #expect(try await phone.ledger.payment(hall.id)?.category == "groceries")
        #expect(try await phone.ledger.payment(rewe.id)?.categorySource == .starter)
        #expect(try await phone.ledger.payment(rent.id)?.category == nil)
        try await phone.choose("friends")
        #expect(try await phone.ledger.payment(rent.id)?.category == "friends")
        #expect(try await phone.ledger.payment(rent.id)?.categorySource == .learned)
    }

    @Test func confirmationWordsHavePluralsAndEmptyCases() {
        let own = CategoryRemoval(id: "custom-fake", name: "Hobby", count: 1)
        #expect(own.title(language: .english) == "Delete Hobby?")
        #expect(own.title(language: .german) == "Hobby löschen?")
        #expect(own.message(language: .english) == "Its 1 payment is sorted again. Those Aresium can't sort go to Not sorted.")
        #expect(own.message(language: .german) == "Die Buchung darin wird neu sortiert. Was Aresium nicht sortieren kann, kommt zu Nicht sortiert.")
        let standard = CategoryRemoval(id: "friends", name: "Freunde", count: 12)
        #expect(standard.title(language: .german) == "Freunde entfernen?")
        #expect(standard.message(language: .german).hasPrefix("Die 12 Buchungen darin werden neu sortiert."))
        #expect(standard.message(language: .german).hasSuffix("Du kannst die Kategorie jederzeit wieder anhaken."))
        #expect(CategoryRemoval(id: "custom-fake", name: "Hobby", count: 0).message(language: .english).isEmpty)
        #expect(CategoryRemoval(id: "friends", name: "Friends", count: 0).message(language: .english) == "You can tick it again any time.")
    }
}
