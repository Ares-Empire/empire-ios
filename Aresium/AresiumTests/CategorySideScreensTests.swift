import Foundation
import Testing
@testable import Aresium

/// Brief 70: category sides on screen. The change window's Other category… tile (when it shows, its list and line,
/// picking from it), the long press that takes back a category offered here from the other side (its entry and what it
/// does), and Settings → Categories (the side shown and switched on one's own rows, "Also for money in" on and off, the
/// add row's side). The words in both languages. Everything is made up.
@MainActor
struct CategorySideScreensTests {
    private let none = BackendAuth(token: nil)

    /// Groceries and eating out (spending), salary (income) and savings (a transfer) ticked; a few made-up payments, one
    /// of them a friend's share of a dinner paid back.
    private func world(chosen: [String] = ["groceries", "eating-out", "salary", "savings-investing"])
        async throws -> (PhoneBackend, DashboardStore) {
        let phone = try await PhoneTest.backend(chosen: chosen)
        _ = try await phone.importFiles([PhoneTest.vrBank([
            ("05.10.2026", "REWE Markt GmbH", "REWE SAGT DANKE", -2345),
            ("12.10.2026", "Restaurant Fiktiva", "Essen", -4200),
            ("14.10.2026", "Erika Mustermann", "Anteil Essen", 2100),
            ("01.10.2026", "Fictional Employer GmbH", "Gehalt Oktober", 210000)])], auth: none)
        let dashboard = DashboardStore(session: await PhoneTest.session(nil, transport: RoutedTransport()), backend: phone)
        await dashboard.reload()
        return (phone, dashboard)
    }

    private func window(_ dashboard: DashboardStore, place: String,
                        mode: RecategorisationMode = .switchCategory) async throws -> TransactionDetailStore {
        let row = try #require(dashboard.dashboard?.transactions.first { $0.place.contains(place) })
        let store = dashboard.transactionDetailStore(for: row)
        await store.load()
        store.beginRecategorisation(mode: mode)
        return store
    }

    // MARK: Other category…

    @Test(arguments: [RecategorisationMode.switchCategory, .add])
    func otherCategoryShowsWhileTheOtherSideHasACategoryNotOfferedHere(mode: RecategorisationMode) async throws {
        let (_, dashboard) = try await world(chosen: ["groceries", "salary"])
        let moneyIn = try await window(dashboard, place: "Erika", mode: mode)
        #expect(moneyIn.paymentSide == .income)
        #expect(moneyIn.offersNewCategory && moneyIn.offersOtherCategory, "both action tiles for money in")
        #expect(moneyIn.otherSideChoices.map(\.name) == ["Groceries"], "the spending side's only category")
        // Picked: it shows before the tiles, and the list has nothing left, so the tile goes.
        moneyIn.pickFromOtherSide("Groceries")
        #expect(moneyIn.choices.last?.name == "Groceries")
        #expect(!moneyIn.offersOtherCategory)
        #expect(moneyIn.otherSideListLine == nil)
        #expect(moneyIn.offersNewCategory, "New category stays")
        let moneyOut = try await window(dashboard, place: "REWE", mode: mode)
        #expect(moneyOut.paymentSide == .spend)
        #expect(moneyOut.offersOtherCategory)
        #expect(moneyOut.otherSideChoices.map(\.name) == ["Salary & side jobs"])
    }

    @Test func noOtherCategoryInServerMode() async throws {
        let dashboard = DashboardStore(session: EmpireSession(app: .aresium, storage: PhoneTokens()), sample: true)
        await dashboard.reload()
        for amount in [-1.0, 1.0] {
            let row = try #require(dashboard.dashboard?.transactions.first { ($0.amount > 0) == (amount > 0) })
            let store = dashboard.transactionDetailStore(for: row)
            await store.load()
            store.beginRecategorisation()
            #expect(!store.choices.isEmpty)
            #expect(!store.offersOtherCategory && store.otherSideListLine == nil)
            #expect(store.stopOfferingEntry(for: store.choices[0].name) == nil, "no long press")
        }
    }

    @Test func theListSaysWhereItsCategoriesComeFromAndHoldsOnlyThoseNotOfferedHere() async throws {
        let (phone, dashboard) = try await world()
        let moneyIn = try await window(dashboard, place: "Erika")
        #expect(moneyIn.otherSideListLine == "From spending")
        let list = try await phone.categories()
        let spending = Set(list.chosen.map(\.id).filter { list.side(of: $0) == .spend }.compactMap { list.name(of: $0) })
        #expect(Set(moneyIn.otherSideChoices.map(\.name)) == spending)
        #expect(moneyIn.otherSideChoices.allSatisfy { $0.kind == .spend })
        #expect(!moneyIn.otherSideChoices.contains { $0.name == "Savings & investing" }, "transfers are offered already")
        // Offered for money in already: not in the list, but a tile.
        try await phone.setOtherSide(true, for: "eating-out")
        await dashboard.reloadIfCategoriesChanged()
        let again = try await window(dashboard, place: "Erika")
        #expect(again.otherSideChoices.map(\.name) == ["Groceries"])
        #expect(again.choices.contains { $0.name == "Eating out" })
        let moneyOut = try await window(dashboard, place: "REWE")
        #expect(moneyOut.otherSideListLine == "From income")
    }

    @Test func pickingFromTheListAndSavingOffersItHereFromThenOn() async throws {
        let (phone, dashboard) = try await world()
        let store = try await window(dashboard, place: "Erika")
        store.pickFromOtherSide("Eating out")
        #expect(store.target == "Eating out" && store.canSave)
        await store.save()
        #expect(store.saveError == nil)
        #expect(try await phone.categories().hasOtherSide("eating-out"))
        let next = try await window(dashboard, place: "Erika")
        #expect(next.choices.contains { $0.name == "Eating out" }, "a tile of this window now")
        #expect(!next.otherSideChoices.contains { $0.name == "Eating out" })
    }

    // MARK: the long press

    @Test func theLongPressTakesBackOnlyWhatIsOfferedHereFromTheOtherSide() async throws {
        let (phone, dashboard) = try await world()
        try await phone.setOtherSide(true, for: "eating-out")
        try await phone.setOtherSide(true, for: "salary")
        await dashboard.reloadIfCategoriesChanged()
        let moneyIn = try await window(dashboard, place: "Erika")
        #expect(moneyIn.offeredFromOtherSide("Eating out"))
        #expect(moneyIn.stopOfferingEntry(for: "Eating out") == "Not for money in")
        // This side's own, transfers and the payment's current category: no long press.
        #expect(moneyIn.stopOfferingEntry(for: "Salary & side jobs") == nil)
        #expect(moneyIn.stopOfferingEntry(for: "Savings & investing") == nil)
        #expect(moneyIn.stopOfferingEntry(for: "Own transfers") == nil)
        await moneyIn.stopOffering("Eating out")
        #expect(try await !phone.categories().hasOtherSide("eating-out"), "stored at once")
        #expect(!moneyIn.choices.contains { $0.name == "Eating out" })
        #expect(moneyIn.otherSideChoices.contains { $0.name == "Eating out" }, "in the list again")
        #expect(moneyIn.stopOfferingEntry(for: "Eating out") == nil)

        let moneyOut = try await window(dashboard, place: "REWE")
        #expect(moneyOut.stopOfferingEntry(for: "Salary & side jobs") == "Not for money out")
        #expect(moneyOut.stopOfferingEntry(for: "Groceries") == nil, "its current category")
        #expect(moneyOut.stopOfferingEntry(for: "Eating out") == nil)
    }

    @Test func aCategoryPickedInThisOpeningLeavesTheWindowWithoutAnythingStored() async throws {
        let (phone, dashboard) = try await world()
        let store = try await window(dashboard, place: "Erika", mode: .add)
        let before = try await phone.export()
        store.pickFromOtherSide("Groceries")
        #expect(store.extras.contains("Groceries"))
        #expect(store.stopOfferingEntry(for: "Groceries") == "Not for money in")
        await store.stopOffering("Groceries")
        #expect(!store.choices.contains { $0.name == "Groceries" })
        #expect(!store.extras.contains("Groceries"))
        #expect(store.otherSideChoices.contains { $0.name == "Groceries" }, "in the list again")
        #expect(try await phone.export() == before, "nothing was stored")
    }

    // MARK: Settings → Categories

    private func picker(_ phone: PhoneBackend) async -> (CategoryPickerModel, () -> Int) {
        var rebuilt = 0
        let model = CategoryPickerModel(phone: phone, settle: .seconds(60)) { rebuilt += 1 }
        await model.load()
        return (model, { rebuilt })
    }

    @Test func ownRowsSayTheirSideAndSwitchIt() async throws {
        let (phone, _) = try await world()
        let hobby = try await phone.addCustom(named: "Fictional hobby", side: .spend)
        let work = try await phone.addCustom(named: "Fictional work", side: .income)
        let (model, rebuilt) = await picker(phone)
        let own = model.custom
        #expect(own.map(\.side) == [.spend, .income])
        #expect(own.allSatisfy { $0.choosesSide }, "one's own say their side")
        #expect(own.allSatisfy { !$0.showsOtherSide })
        let defaults = model.groups.flatMap(\.items)
        #expect(defaults.allSatisfy { !$0.choosesSide }, "a default's side is its group")
        #expect(defaults.first { $0.id == "groceries" }?.side == .spend)
        #expect(defaults.first { $0.id == "salary" }?.side == .income)

        await model.setSide(.income, of: hobby)
        #expect(model.custom.first { $0.id == hobby }?.side == .income, "the row shows it at once")
        #expect(try await phone.categories().side(of: hobby) == .income)
        await model.setSide(.spend, of: work)
        #expect(model.custom.first { $0.id == work }?.side == .spend)
        #expect(model.problem == nil)
        // The dashboard is built again once, when the picker closes; nothing waits to be sorted.
        #expect(rebuilt() == 0)
        await model.flush()
        #expect(rebuilt() == 1)
    }

    @Test func alsoForTheOtherDirectionIsShownAndTurnedOnAndOff() async throws {
        let (phone, _) = try await world()
        let own = try await phone.addCustom(named: "Fictional club", side: .income)
        let (model, _) = await picker(phone)
        let item = { (id: String) in (model.groups.flatMap(\.items) + model.custom).first { $0.id == id } }
        // Every ticked category but a transfer can be offered on the other side; an unticked one cannot.
        #expect(item("groceries")?.canOfferOtherSide == true)
        #expect(item(own)?.canOfferOtherSide == true)
        #expect(item("savings-investing")?.canOfferOtherSide == false, "a transfer is offered both ways already")
        #expect(item("drugstore")?.canOfferOtherSide == false, "not ticked")

        await model.setOtherSide(true, for: "groceries")
        await model.setOtherSide(true, for: own)
        #expect(item("groceries")?.showsOtherSide == true)
        #expect(item(own)?.showsOtherSide == true)
        #expect(try await phone.categories().hasOtherSide("groceries"))
        await model.setOtherSide(false, for: "groceries")
        #expect(item("groceries")?.showsOtherSide == false)
        #expect(try await !phone.categories().hasOtherSide("groceries"))
        // A transfer is never changed.
        await model.setOtherSide(true, for: "savings-investing")
        #expect(try await !phone.categories().hasOtherSide("savings-investing"))
        #expect(model.problem == nil)
    }

    @Test func theAddRowAsksTheSideSpendingFirst() async throws {
        let (phone, _) = try await world()
        let (model, _) = await picker(phone)
        #expect(model.newSide == .spend)
        model.newName = "Fictional spending"
        await model.addCustom()
        model.newSide = .income
        model.newName = "Fictional tutoring"
        await model.addCustom()
        #expect(model.newSide == .income, "kept for the next one")
        #expect(model.custom.map(\.name) == ["Fictional spending", "Fictional tutoring"])
        #expect(model.custom.map(\.side) == [.spend, .income])
    }

    // MARK: words

    @Test func theWordsInBothLanguages() {
        let english: [String] = [
            CategorySideWording.name(.spend, language: .english), CategorySideWording.name(.income, language: .english),
            CategorySideWording.otherCategory(language: .english),
            CategorySideWording.otherSideList(for: .income, language: .english),
            CategorySideWording.otherSideList(for: .spend, language: .english),
            CategorySideWording.notFor(.income, language: .english), CategorySideWording.notFor(.spend, language: .english),
            CategorySideWording.alsoFor(otherSideOf: .spend, language: .english),
            CategorySideWording.alsoFor(otherSideOf: .income, language: .english)]
        #expect(english == ["Spending", "Income", "Other category…", "From spending", "From income", "Not for money in",
                            "Not for money out", "Also for money in", "Also for money out"])
        let german: [String] = [
            CategorySideWording.name(.spend, language: .german), CategorySideWording.name(.income, language: .german),
            CategorySideWording.otherCategory(language: .german),
            CategorySideWording.otherSideList(for: .income, language: .german),
            CategorySideWording.otherSideList(for: .spend, language: .german),
            CategorySideWording.notFor(.income, language: .german), CategorySideWording.notFor(.spend, language: .german),
            CategorySideWording.alsoFor(otherSideOf: .spend, language: .german),
            CategorySideWording.alsoFor(otherSideOf: .income, language: .german)]
        #expect(german == ["Ausgaben", "Einnahmen", "Andere Kategorie …", "Aus den Ausgaben", "Aus den Einnahmen",
                           "Nicht für Einnahmen", "Nicht für Ausgaben", "Auch für Einnahmen", "Auch für Ausgaben"])
    }
}
