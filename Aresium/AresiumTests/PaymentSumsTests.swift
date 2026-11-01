import Foundation
import Testing
@testable import Aresium

/// Brief 53: adding up the payments of one name in a category's list. The choices (four levels, the more specific wins,
/// the icon's and the name page's clearing, kept in the app's defaults, the tour's own), the grouping (where the summed
/// row stands, its net sum, what stays single), the swipe's rule with two actions, and the menus.
struct SumChoicesTests {
    @Test func offByDefault() {
        let choices = SumChoices()
        #expect(!choices.sums(name: "n", category: "c"))
        #expect(!choices.sumsAll(["n"], in: "c") && !choices.sumsName("n"))
        #expect(!choices.sumsAll([], in: "c"), "a list without a name to add up shows off")
    }

    @Test func eachLevelAndTheMoreSpecificWins() {
        var choices = SumChoices()
        choices.everywhere = true
        #expect(choices.sums(name: "vinted", category: "clothes"), "everywhere")
        choices.categories["clothes"] = false
        #expect(!choices.sums(name: "vinted", category: "clothes"), "a category over everywhere")
        #expect(choices.sums(name: "vinted", category: "groceries"), "other categories keep everywhere's")
        choices.names["vinted"] = true
        #expect(choices.sums(name: "vinted", category: "clothes"), "a name over its category")
        #expect(!choices.sums(name: "zalando", category: "clothes"))
        choices.setName("vinted", in: "clothes", sums: false)
        #expect(!choices.sums(name: "vinted", category: "clothes"), "a name in a category over everything")
        #expect(choices.sums(name: "vinted", category: "groceries"), "only in that category")
        choices.everywhere = false
        choices.categories = [:]
        choices.names = [:]
        #expect(!choices.sums(name: "vinted", category: "clothes"))
        choices.setName("vinted", in: "clothes", sums: true)
        #expect(choices.sums(name: "vinted", category: "clothes") && !choices.sums(name: "vinted", category: "groceries"))
    }

    @Test func theIconsTapMeansAllOrNoneThere() {
        var choices = SumChoices()
        choices.everywhere = true
        choices.setName("vinted", in: "clothes", sums: false)
        choices.setName("zalando", in: "clothes", sums: false)
        choices.setName("vinted", in: "groceries", sums: false)
        let names = ["vinted", "zalando", "other"]
        #expect(!choices.sumsAll(names, in: "clothes"), "the icon shows what the list shows: two single names")
        choices.toggleCategory("clothes", names: names)   // the opposite of what it showed: all
        #expect(choices.categories["clothes"] == nil, "equal to everywhere's: not stored")
        #expect(choices.pairs["clothes"] == nil && choices.sumsAll(names, in: "clothes"))
        #expect(choices.pairs["groceries"]?["vinted"] == false, "other categories' choices stay")
        choices.toggleCategory("clothes", names: names)   // none
        #expect(choices.categories["clothes"] == false && !choices.sumsAll(names, in: "clothes"))
        #expect(names.allSatisfy { !choices.sums(name: $0, category: "clothes") })
        #expect(choices.sums(name: "new", category: "groceries"), "other categories keep everywhere's")
    }

    /// Patrik, 2026-10-31, Oct 2026 Kleidung: Vinted added up and separated by hand, then the icon did nothing.
    @Test func theIconWorksAfterAddUpAndSeparateByHand() {
        var choices = SumChoices()
        choices.setName("vinted", in: "clothes", sums: true)
        choices.setName("vinted", in: "clothes", sums: false)
        #expect(choices == SumChoices(), "Separate after Add up leaves nothing behind")
        #expect(!choices.sumsAll(["vinted"], in: "clothes"))
        choices.toggleCategory("clothes", names: ["vinted"])
        #expect(choices.sumsAll(["vinted"], in: "clothes") && choices.sums(name: "vinted", category: "clothes"))

        // The category on by its icon, then its only name separated by the swipe: the icon shows off, and one tap
        // adds it up again (it had shown on and the tap turned the category off, so nothing changed on screen).
        var other = SumChoices()
        other.toggleCategory("clothes", names: ["vinted"])
        other.setName("vinted", in: "clothes", sums: false)
        #expect(!other.sumsAll(["vinted"], in: "clothes"))
        other.toggleCategory("clothes", names: ["vinted"])
        #expect(other.sums(name: "vinted", category: "clothes") && other.pairs.isEmpty)
    }

    @Test func theIconsTapOutvotesANamesOwnChoiceInItsCategory() {
        var choices = SumChoices()
        choices.everywhere = true
        choices.setName("dm", sums: false)                  // the name's page: not in every category
        #expect(choices.names["dm"] == false)
        let names = ["dm", "rossmann"]
        choices.toggleCategory("drugstore", names: names)   // showed off (dm single): all
        #expect(choices.sumsAll(names, in: "drugstore"))
        #expect(choices.pairs["drugstore"] == ["dm": true], "only the name that said otherwise")
        #expect(!choices.sums(name: "dm", category: "clothes"), "elsewhere the name's own choice stays")
    }

    @Test func aChoiceEqualToWhatItWouldBeIsNotStored() {
        var choices = SumChoices()
        choices.setName("vinted", in: "clothes", sums: false)
        #expect(choices.pairs.isEmpty, "single already")
        choices.setName("vinted", sums: false)
        #expect(choices.names.isEmpty, "everywhere's already")
        choices.setName("vinted", sums: true)
        choices.setName("vinted", sums: false)
        #expect(choices.names.isEmpty, "the switch back leaves nothing")
        choices.categories["clothes"] = true
        choices.setName("vinted", in: "clothes", sums: false)
        #expect(choices.pairs["clothes"] == ["vinted": false], "differs from its category: stored")
        choices.setName("vinted", in: "clothes", sums: true)
        #expect(choices.pairs.isEmpty, "back to its category's")
    }

    @Test func theNamePagesSwitchClearsTheNamesChoicesInCategories() {
        var choices = SumChoices()
        choices.categories["clothes"] = true                // so the single names' Separate differs and is kept
        choices.setName("vinted", in: "clothes", sums: false)
        choices.setName("vinted", in: "gifts", sums: true)
        choices.setName("zalando", in: "clothes", sums: false)
        choices.setName("vinted", sums: true)
        #expect(choices.names["vinted"] == true && choices.sumsName("vinted"))
        #expect(choices.sums(name: "vinted", category: "clothes") && choices.sums(name: "vinted", category: "gifts"))
        #expect(choices.pairs["gifts"] == nil, "an empty category's entry goes")
        #expect(choices.pairs["clothes"] == ["zalando": false], "other names keep theirs")
        choices.setName("vinted", sums: false)
        #expect(choices.names["vinted"] == nil && !choices.sumsName("vinted"), "off is everywhere's: not set")
        #expect(choices.sums(name: "vinted", category: "clothes") && !choices.sums(name: "vinted", category: "gifts"),
                "the name follows each category's own choice again")
    }
}

@MainActor
struct PaymentSumsStoreTests {
    @Test func keptInTheAppsDefaultsNotInMemoryOnes() throws {
        let defaults = PhoneTest.defaults()
        let sums = PaymentSums(defaults: defaults)
        #expect(sums.isKept && sums.choices == SumChoices())
        sums.setEverywhere(true)
        sums.toggleCategory("id:clothes", names: ["merchant:zalando"])
        sums.setName("merchant:vinted", in: "id:groceries", sums: false)
        let again = PaymentSums(defaults: defaults)
        #expect(again.choices == sums.choices, "a new launch (or a language restart) reads them back")
        #expect(defaults.data(forKey: PaymentSums.key) != nil)

        let memory = PaymentSums()
        let revision = memory.revision
        memory.setEverywhere(true)
        #expect(!memory.isKept && memory.choices.everywhere && memory.revision != revision)
        memory.setEverywhere(true)
        #expect(memory.revision == revision + 1, "no change, no new revision")
    }

    @Test func deleteAllForgetsThem() {
        let defaults = PhoneTest.defaults()
        let sums = PaymentSums(defaults: defaults)
        sums.setName("merchant:vinted", sums: true)
        sums.deleteAll()
        #expect(sums.choices == SumChoices() && defaults.data(forKey: PaymentSums.key) == nil)
        #expect(PaymentSums(defaults: defaults).choices == SumChoices())
    }
}

@MainActor
struct PaymentListTests {
    private func row(_ id: String, day: Int, amount: Double, key: String?, covered: Bool = false) -> TransactionRow {
        let date = String(format: "2026-10-%02d", day)
        var transaction = Transaction(id: id, date: date, day: day, month: "2026-10", amount: amount,
                                      categoryName: "Clothes", tags: [], place: "Shop " + (key ?? id), city: "",
                                      categoriesIn: ["Clothes"], incomeBuckets: [])
        transaction.nameKey = key
        if covered { transaction.coveredBy = ["receipt-1"] }
        return TransactionRow(transaction: transaction, tagged: false)
    }

    @Test func aSummedNameStandsWhereItsNewestPaymentWouldBe() throws {
        let rows = [row("a1", day: 1, amount: -10, key: "a"), row("b", day: 2, amount: -5, key: "b"),
                    row("a2", day: 3, amount: -20, key: "a"), row("c", day: 4, amount: -7, key: "c"),
                    row("a3", day: 5, amount: -30, key: "a"), row("d", day: 6, amount: -1, key: "d")]
        let list = PaymentList(rows: rows) { $0 == "a" }
        #expect(list.entries.map(\.id) == ["b", "c", "sum:a", "d"])
        let sum = try #require(list.summed("a"))
        #expect(sum.rows.map(\.id) == ["a1", "a2", "a3"], "its payments in the list's order")
        #expect(sum.count == 3 && sum.newest.id == "a3" && sum.firstDay == "2026-10-01" && sum.lastDay == "2026-10-05")
        #expect(list.canSum)
        #expect(list.rows.count == 6, "the list's own rows stay as they are")
    }

    @Test func theNetSumInCents() throws {
        let rows = [row("p1", day: 2, amount: -20.10, key: "p"), row("p2", day: 3, amount: -30.20, key: "p"),
                    row("p3", day: 5, amount: 5.00, key: "p")]
        let sum = try #require(PaymentList(rows: rows) { _ in true }.summed("p"))
        #expect(sum.cents == -4530 && sum.total == -45.30, "a refund among the purchases lowers it")
        let tiny = [row("t1", day: 1, amount: -0.1, key: "t"), row("t2", day: 2, amount: -0.2, key: "t")]
        #expect(PaymentList(rows: tiny) { _ in true }.summed("t")?.total == -0.3)
    }

    @Test func oneOrNoPaymentOfANameStaysSingle() {
        let rows = [row("a", day: 1, amount: -10, key: "alone"), row("x", day: 2, amount: -10, key: nil),
                    row("y", day: 3, amount: -10, key: nil)]
        let list = PaymentList(rows: rows) { _ in true }
        #expect(list.entries.map(\.id) == ["a", "x", "y"], "rows without a name never add up together")
        #expect(!list.canSum)
        for entry in list.entries {
            guard case let .payment(_, addsUp) = entry else { Issue.record("summed"); continue }
            #expect(!addsUp)
        }
    }

    @Test func notChosenRowsOfferAddUp() {
        let rows = [row("a1", day: 1, amount: -10, key: "a"), row("a2", day: 2, amount: -10, key: "a"),
                    row("b", day: 3, amount: -10, key: "b")]
        let list = PaymentList(rows: rows) { _ in false }
        let offers = list.entries.map { entry -> Bool in
            if case let .payment(_, addsUp) = entry { return addsUp }
            return false
        }
        #expect(offers == [true, true, false] && list.canSum)
    }

    @Test func notOfferedEveryRowStaysSingle() {
        let rows = [row("a1", day: 1, amount: -10, key: "a"), row("a2", day: 2, amount: -10, key: "a")]
        let list = PaymentList(rows: rows, offered: false) { _ in true }
        #expect(list.entries.map(\.id) == ["a1", "a2"] && !list.canSum)
    }

    @Test func coveredRowsAreUntouched() {
        // A withdrawal's covered row is the receipts', not a payment: it never adds up, even under a name's key.
        let rows = [row("w1", day: 1, amount: -50, key: "atm"), row("cov", day: 1, amount: 20, key: "atm", covered: true),
                    row("w2", day: 9, amount: -50, key: "atm")]
        let list = PaymentList(rows: rows) { _ in true }
        #expect(list.entries.map(\.id) == ["cov", "sum:atm"])
        #expect(list.summed("atm")?.count == 2 && list.summed("atm")?.total == -100)
    }

    @Test func theRowsWords() {
        #expect(SumWording.count(10) == "10×")
        let english = SumWording.days(from: "2026-10-04", to: "2026-10-28", language: .english)
        let german = SumWording.days(from: "2026-10-04", to: "2026-10-28", language: .german)
        #expect(english.contains("4") && english.contains("28") && english.contains("Oct"), "\(english)")
        #expect(german.contains("4.") && german.contains("28.") && german.contains("Okt"), "\(german)")
        #expect(SumWording.days(from: "2026-10-04", to: "2026-10-04", language: .english).contains("4 Oct"))
        #expect(SumWording.addUp(language: .german) == "Summieren" && SumWording.separate(language: .german) == "Auflösen")
        #expect(SumWording.addUp(language: .english) == "Add up" && SumWording.separate(language: .english) == "Separate")
    }
}

/// The swipe's numbers with two actions (Add up or Separate, then All): the row opens at 168 pt, a full swipe (All) needs
/// 252 pt on an iPhone 17's row (378 pt), the actions share the room until then.
struct RowSwipeTwoActionsTests {
    private let width: CGFloat = 378

    @Test func opensAtTwoActionsAndFullSwipesBeyondThem() {
        #expect(RowSwipeRule.openWidth(count: 1) == 84 && RowSwipeRule.openWidth(count: 2) == 168)
        #expect(RowSwipeRule.fullSwipe(width: width, count: 1) == width * 0.55, "one action as before")
        #expect(RowSwipeRule.fullSwipe(width: width, count: 2) == 252)
        #expect(RowSwipeRule.fullSwipe(width: 600, count: 2) == 330, "half the row on a wider one")
        #expect(!RowSwipeRule.isArmed(offset: -251, width: width, count: 2))
        #expect(RowSwipeRule.isArmed(offset: -252, width: width, count: 2))
        #expect(RowSwipeRule.offset(translation: 30, wasOpen: true, width: width, count: 2) == -138)
        #expect(RowSwipeRule.offset(translation: -900, wasOpen: true, width: width, count: 2) == -width)
    }

    @Test func lettingGo() {
        #expect(RowSwipeRule.end(offset: -260, velocity: 0, width: width, count: 2) == .perform)
        #expect(RowSwipeRule.end(offset: -200, velocity: 0, width: width, count: 2) == .open, "between open and full")
        #expect(RowSwipeRule.end(offset: -90, velocity: 0, width: width, count: 2) == .open, "past half the two")
        #expect(RowSwipeRule.end(offset: -80, velocity: 0, width: width, count: 2) == .closed)
        #expect(RowSwipeRule.end(offset: -30, velocity: -600, width: width, count: 2) == .open, "a fling left")
        #expect(RowSwipeRule.end(offset: -160, velocity: 600, width: width, count: 2) == .closed, "a fling right")
    }

    @Test func theActionsShareTheRoomUntilTheFullSwipe() {
        #expect(RowSwipeRule.widths(revealed: 162, count: 2, armed: false) == [78, 78], "open: each drawn 78 pt")
        #expect(RowSwipeRule.widths(revealed: 78, count: 1, armed: false) == [78])
        #expect(RowSwipeRule.widths(revealed: 4, count: 2, armed: false) == [0, 0])
        #expect(RowSwipeRule.widths(revealed: 250, count: 2, armed: true) == [0, 250], "the last takes it all")
        #expect(RowSwipeRule.widths(revealed: 10, count: 0, armed: false).isEmpty)
    }
}

/// The model on a real phone store: Penny twice in October's Groceries plus a refund (income since brief 71), REWE once, the category's
/// key in both languages, the menus, Delete data and the tour.
@MainActor
struct PaymentSumsStoreFlowTests {
    private let auth = BackendAuth(token: nil)

    private func phone(defaults: UserDefaults = PhoneTest.defaults()) async throws -> PhoneBackend {
        let phone = try await PhoneCountingTests.backend(chosen: ["groceries", "eating-out"], defaults: defaults)
        _ = try await phone.importFiles([PhoneTest.vrBank([
            ("01.09.2026", "PENNY Markt GmbH München", "Purchase", -1000),
            ("02.10.2026", "PENNY Markt Berlin", "Purchase", -2000),
            ("03.10.2026", "PENNY Markt Berlin", "Purchase", -3000),
            ("05.10.2026", "PENNY Markt Berlin", "Refund", 500),
            ("04.10.2026", "Fiktiv Einzelladen", "Purchase", -1500),
            ("06.10.2026", "REWE Markt GmbH", "Purchase", -1200)])], auth: auth)
        return phone
    }

    private func store(_ phone: PhoneBackend, sums: PaymentSums = PaymentSums()) async -> DashboardStore {
        let session = await PhoneTest.session(nil, transport: RoutedTransport())
        let dashboard = DashboardStore(session: session, backend: phone, sums: sums)
        await dashboard.reload()
        return dashboard
    }

    private func groceries(_ dashboard: DashboardStore, name: String = "Groceries") -> PaymentList {
        dashboard.paymentList(category: name, month: "2026-10", side: .expenses)
    }

    @Test func theCategorysKeyIsItsIdInBothLanguages() async throws {
        let phone = try await phone()
        try await phone.addCustom(named: "Climbing", side: .spend)
        let dashboard = await store(phone)
        #expect(dashboard.sumCategoryKey("Groceries") == "id:groceries")
        let german = AppLanguage.$scoped.withValue(.german) { dashboard.sumCategoryKey("Lebensmittel") }
        #expect(german == "id:groceries")
        #expect(dashboard.sumCategoryKey("Climbing").hasPrefix("id:custom-"))
        #expect(dashboard.sumCategoryKey("Refunds") == "name:Refunds", "the dashboard's own entries keep their name")
    }

    @Test func aLanguageSwitchKeepsThem() async throws {
        let defaults = PhoneTest.defaults()
        let phone = try await phone()
        // Chosen while the app showed German: Lebensmittel's icon.
        let german = await AppLanguage.$scoped.withValue(.german) { () async -> Bool in
            let dashboard = await store(phone, sums: PaymentSums(defaults: defaults))
            #expect(dashboard.category("Lebensmittel", side: .expenses) != nil)
            dashboard.sums.toggleCategory(dashboard.sumCategoryKey("Lebensmittel"),
                                          names: groceries(dashboard, name: "Lebensmittel").sumKeys)
            return groceries(dashboard, name: "Lebensmittel").entries.contains { if case .summed = $0 { true } else { false } }
        }
        #expect(german)
        // The restart in English builds new stores; the choices come from the app's defaults.
        let english = await store(phone, sums: PaymentSums(defaults: defaults))
        let list = groceries(english)
        let penny = try #require(list.entries.compactMap { if case let .summed(sum) = $0 { sum } else { nil } }.first)
        #expect(penny.count == 2 && penny.total == -50, "−20 −30; the +5 refund counts under income (brief 71)")
        #expect(list.allSummed, "the icon shows on in English too")
    }

    @Test func summingChangesNoTotalAndBuildsOncePerChange() async throws {
        let dashboard = await store(try await phone())
        let before = try #require(dashboard.dashboard)
        let monthsBefore = dashboard.months(category: "Groceries", side: .expenses).map(\.total)
        let single = groceries(dashboard)
        #expect(single.canSum && single.entries.count == single.rows.count, "nothing summed by default")
        #expect(dashboard.builtLists.lists.count == 1)
        _ = groceries(dashboard)
        #expect(dashboard.builtLists.revision == dashboard.revision && dashboard.builtLists.lists.count == 1)

        dashboard.sums.setEverywhere(true)
        let summed = groceries(dashboard)
        #expect(summed.entries.count == single.rows.count - 1 && summed.rows.count == single.rows.count)
        // Brief 71: the refund is not in Groceries' spending list but in its income list.
        #expect(!single.rows.contains { $0.transaction.amount > 0 })
        #expect(dashboard.paymentList(category: "Groceries", month: "2026-10", side: .income).rows.map(\.transaction.amount) == [5])
        #expect(dashboard.builtLists.sums == dashboard.sums.revision, "built again after the change")
        let after = try #require(dashboard.dashboard)
        #expect(after.total.expense == before.total.expense && after.byMonth["2026-10"]?.expense == before.byMonth["2026-10"]?.expense)
        #expect(dashboard.months(category: "Groceries", side: .expenses).map(\.total) == monthsBefore)
    }

    /// Fix 58 on a real store: the icon follows the list, and after Add up and Separate by hand one tap adds up all.
    @Test func theIconFollowsTheListAfterAddUpAndSeparate() async throws {
        let dashboard = await store(try await phone())
        let category = dashboard.sumCategoryKey("Groceries")
        let first = groceries(dashboard)
        #expect(!first.sumKeys.isEmpty && !first.allSummed)
        let penny = try #require(first.rows.compactMap { PaymentList.nameKey($0.transaction) }
            .first { key in first.rows.filter { PaymentList.nameKey($0.transaction) == key }.count > 1 })
        dashboard.sums.setName(penny, in: category, sums: true)
        #expect(groceries(dashboard).summed(penny) != nil)
        dashboard.sums.setName(penny, in: category, sums: false)
        #expect(groceries(dashboard).summed(penny) == nil && dashboard.sums.choices == SumChoices())
        dashboard.sums.toggleCategory(category, names: groceries(dashboard).sumKeys)
        let all = groceries(dashboard)
        #expect(all.allSummed && all.summed(penny) != nil, "one tap: every name there as one row")
        dashboard.sums.toggleCategory(category, names: all.sumKeys)
        #expect(!groceries(dashboard).allSummed && groceries(dashboard).entries.count == all.rows.count)
    }

    @Test func theMenusOfferWhatTheSwipeOffers() async throws {
        let dashboard = await store(try await phone())
        let list = groceries(dashboard)
        let penny = try #require(list.entries.first { $0.title.contains("PENNY") })
        #expect(dashboard.rowActions(for: penny) == [.changeCategory, .rename, .addUp, .allFromName])
        let lone = try #require(list.entries.first { $0.title.contains("REWE") })
        #expect(dashboard.rowActions(for: lone) == [.changeCategory, .rename], "a name alone here: no Add up")

        let pennyRow = try #require(list.rows.first { $0.transaction.place.contains("PENNY") })
        let pennyKey = try #require(PaymentList.nameKey(pennyRow.transaction))
        dashboard.sums.setName(pennyKey, in: dashboard.sumCategoryKey("Groceries"), sums: true)
        let summed = try #require(groceries(dashboard).entries.first { if case .summed = $0 { true } else { false } })
        #expect(dashboard.rowActions(for: summed) == [.separate, .allFromName])
        // A row outside a category's list keeps its menu (brief 47).
        #expect(dashboard.rowActions(for: pennyRow.transaction) == [.changeCategory, .rename, .allFromName])
    }

    @Test func deleteDataClearsThem() async throws {
        let defaults = PhoneTest.defaults()
        let transport = RoutedTransport()
        let session = await PhoneTest.session(nil, transport: transport)
        let dashboard = DashboardStore(session: session, backend: nil, sums: PaymentSums(defaults: defaults))
        let modes = ModeStore(session: session, dashboard: dashboard, client: APIClient(transport: transport),
                              defaults: PhoneTest.defaults(), markerDefaults: PhoneTest.defaults(),
                              storage: PhoneTest.storage(), makeEngine: { try PhoneTest.engine() })
        await modes.start()
        dashboard.sums.setEverywhere(true)
        dashboard.sums.setName("merchant:penny", sums: false)
        #expect(defaults.data(forKey: PaymentSums.key) != nil)
        try await modes.deleteLocalData()
        #expect(dashboard.sums.choices == SumChoices() && defaults.data(forKey: PaymentSums.key) == nil)
    }

    @Test func theTourHasItsOwnInMemory() async throws {
        let defaults = PhoneTest.defaults()
        let person = PaymentSums(defaults: defaults)
        person.setName("merchant:vinted", in: "id:clothes", sums: true)
        let kept = defaults.data(forKey: PaymentSums.key)
        let standard = UserDefaults.standard.data(forKey: PaymentSums.key)

        let parent = FileManager.default.temporaryDirectory.appending(path: "sums-tour-" + UUID().uuidString)
        let world = try await TourWorld.make(in: parent, makeEngine: { try PhoneTest.engine() })
        defer { world.delete() }
        let tour = world.dashboard.sums
        #expect(tour !== person && !tour.isKept && tour.choices == SumChoices(), "empty, in memory")
        #expect(world.dashboard.offersSums, "the tour's lists add up, on its own choices (brief 59)")
        tour.setEverywhere(true)
        tour.toggleCategory("id:groceries", names: ["merchant:penny"])
        #expect(person.choices.pairs["id:clothes"]?["merchant:vinted"] == true && !person.choices.everywhere)
        #expect(defaults.data(forKey: PaymentSums.key) == kept)
        #expect(UserDefaults.standard.data(forKey: PaymentSums.key) == standard, "the app's own defaults untouched")
    }
}
