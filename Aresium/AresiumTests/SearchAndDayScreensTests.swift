import Foundation
import Testing
@testable import Aresium

/// Brief 77, the screens of the search and a day's page: which tap on a graph opens a day and on which side, the day
/// page's words and an empty side, the search only in phone mode, what a result's lines say (found by the bank's other
/// line, by an own name, the money both ways), what shows before anything is typed, and that the day's sheet and the
/// search follow the store.
@MainActor
struct SearchAndDayScreensTests {
    private let auth = BackendAuth(token: nil)
    /// 30 Oct 2026, noon: the made-up payments are in 2026.
    private static let now = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 30, hour: 12))!

    private func store(_ phone: PhoneBackend? = nil) async -> DashboardStore {
        let session = EmpireSession(app: .aresium, storage: PhoneTokens(), restoreOnLaunch: false)
        let store = phone.map { DashboardStore(session: session, backend: $0) }
            ?? DashboardStore(session: session, sample: true)
        await store.reload()
        return store
    }

    /// A made-up shop under two bank lines (the older one first), a grocer, and money in on one day.
    private func phone() async throws -> PhoneBackend {
        let phone = try await PhoneCountingTests.backend(chosen: ["groceries", "clothes", "salary"])
        _ = try await phone.importFiles([PhoneTest.vrBank([
            ("01.02.2026", "MGP Vinted - Kleiderkreisel", "Fictional purchase", -1000),
            ("02.10.2026", "Vinted, UAB", "Fictional purchase", -2000),
            ("12.10.2026", "Vinted, UAB", "Fictional sale", 3500),
            ("12.10.2026", "REWE Markt GmbH", "REWE SAGT DANKE", -1240),
            ("14.10.2026", "REWE Markt GmbH", "REWE SAGT DANKE", -860),
        ])], auth: auth)
        return phone
    }

    // MARK: a day's page

    @Test func aShortTapOnADayOpensThatDayOnThePagesSide() async throws {
        let store = await store(try await phone())
        #expect(store.dayRoute(atChartIndex: 11, side: .income, scope: .month("2026-10"))
                == DayRoute(date: "2026-10-12", side: .income))
        #expect(store.dayRoute(atChartIndex: 0, side: .expenses, scope: .month("2026-10"))
                == DayRoute(date: "2026-10-01", side: .expenses))
        let current = try #require(store.currentMonth?.key)
        #expect(store.dayRoute(atChartIndex: 13, side: .expenses, scope: .current)?.date == current + "-14",
                "Current's graph is its month's days")
        #expect(store.dayRoute(atChartIndex: 2, side: .expenses, scope: .overview) == nil, "Overview's points are months")
        #expect(store.dayRoute(atChartIndex: 31, side: .expenses, scope: .month("2026-10")) == nil, "past the month's end")
        #expect(store.dayRoute(atChartIndex: -1, side: .expenses, scope: .month("2026-10")) == nil)
        #expect(store.dayRoute(atChartIndex: 3, side: .expenses, scope: .month("2019-01")) == nil, "a month not there")
    }

    @Test func aDaysPageSaysItsDayAndAnEmptySideInOneLine() async throws {
        #expect(DayPageWording.title("2026-10-14", language: .english) == "Wednesday, 14 October 2026")
        #expect(DayPageWording.title("2026-10-14", language: .german) == "Mittwoch, 14. Oktober 2026")
        #expect(DayPageWording.empty(.income, language: .english) == "No income on this day.")
        #expect(DayPageWording.empty(.income, language: .german) == "Keine Einnahmen an diesem Tag.")
        #expect(DayPageWording.empty(.expenses, language: .german) == "Keine Ausgaben an diesem Tag.")

        let store = await store(try await phone())
        let both = store.day("2026-10-12")
        #expect(both.expenses.rows.map(\.transaction.place) == ["REWE Markt GmbH"])
        #expect(both.income.rows.map(\.transaction.amount) == [35])
        let empty = store.day("2026-10-14")
        #expect(!empty.expenses.rows.isEmpty && empty.income.rows.isEmpty && empty.income.total == 0,
                "the income side is the one quiet line")
    }

    /// Each row says its category (on a day's page nothing implies it), before what the month's list says there.
    @Test func aDaysRowsSayTheirCategory() async throws {
        #expect(DayPageWording.line(category: "Groceries", listLine: "", language: .english) == "Groceries")
        #expect(DayPageWording.line(category: "Groceries", listLine: "Munich", language: .english) == "Groceries · Munich")
        #expect(DayPageWording.line(category: CategoryName.uncategorised, listLine: " ", language: .german)
                == "Nicht sortiert")
        #expect(DayPageWording.line(category: "Cash withdrawals", listLine: "Counted where it was spent",
                                    language: .english) == "Cash withdrawals · Counted where it was spent")

        let store = await store(try await phone())
        let row = try #require(store.day("2026-10-12").expenses.rows.first)
        let groceries = try #require(try await store.phone?.categories().name(of: "groceries"))
        #expect(row.category.name == groceries)
    }

    /// The day's page reads the store each time it draws: after a row's page changed something, it shows the new state.
    @Test func theDaysPageShowsTheStoreAsItIsNow() async throws {
        let phone = try await phone()
        let store = await store(phone)
        let before = try #require(store.day("2026-10-14").expenses.rows.first)
        let detail = store.transactionDetailStore(for: before.transaction)
        await detail.prepareRename()
        await detail.rename(to: "Fiktiv Supermarkt", scope: .payment)
        let after = try #require(store.day("2026-10-14").expenses.rows.first)
        #expect(after.id == before.id && after.transaction.place == "Fiktiv Supermarkt")
    }

    // MARK: the search

    @Test func theSearchIsOfferedOnlyInPhoneMode() async throws {
        #expect(await store().offersSearch == false, "server rows have no names")
        #expect(await store(try await phone()).offersSearch)
        #expect(DashboardRoute.search.search && DashboardRoute.search.name == nil && DashboardRoute.search.month == nil)
        var place = DashboardPlace()
        place.open(.search)
        #expect(place.path == [.search], "a page on the dashboard's stack")
    }

    @Test func aResultFoundByTheBanksOlderLineSaysSo() async throws {
        let store = await store(try await phone())
        let hit = try #require(store.searchNames("Kleider").first)
        #expect(hit.shownName == "Vinted, UAB" && hit.matchedName == "MGP Vinted - Kleiderkreisel")
        let group = store.nameGroup(hit.key)
        #expect(SearchPage.kind(of: "MGP Vinted - Kleiderkreisel", in: group) == .bank)
        let english = SearchPage.Row(hit, group: group, now: Self.now, language: .english)
        #expect(english.title == "Vinted, UAB")
        #expect(english.match == "Bank's name: MGP Vinted - Kleiderkreisel")
        #expect(english.line.hasPrefix("3 payments · 12 Oct · "))
        #expect(english.moneyOut == "−30.00" && english.moneyIn == "+35.00", "the money both ways")
        let german = SearchPage.Row(hit, group: group, now: Self.now, language: .german)
        #expect(german.match == "Bei der Bank: MGP Vinted - Kleiderkreisel", "one line: the shorter word")
        #expect(german.line.hasPrefix("3 Buchungen · 12. Okt. · "))
        #expect(german.moneyOut == "−30,00" && german.moneyIn == "+35,00")
        #expect(english.spoken.contains("Bank's name: MGP Vinted - Kleiderkreisel"))

        let shown = try #require(store.searchNames("vinted").first)
        #expect(SearchPage.Row(shown, group: store.nameGroup(shown.key), language: .english).match == nil,
                "found by the shown name: no second line")
        #expect(store.searchNames("Luma Fiktiv").isEmpty)
        #expect(SearchPage.noMatch(" Luma ", language: .english) == "No name found for “Luma”.")
        #expect(SearchPage.noMatch("Luma", language: .german) == "Kein Name für „Luma“ gefunden.")
    }

    @Test func aResultFoundByAnOwnNameSaysSoAndAnOwnNameFindsTheBanksLine() async throws {
        let phone = try await phone()
        let store = await store(phone)
        let vinted = try #require(store.dashboard?.transactions.first { $0.place == "Vinted, UAB" && $0.amount < 0 })
        _ = try await phone.rename(id: vinted.id, name: "Second-hand clothes", scope: .shop)
        await store.reloadAfterTransactionChange()
        let byBank = try #require(store.searchNames("UAB").first)
        #expect(byBank.shownName == "Second-hand clothes")
        #expect(SearchPage.Row(byBank, group: store.nameGroup(byBank.key), language: .english).match
                == "Bank's name: Vinted, UAB")

        // Own names off: the bank's name shows, and the hidden own name still finds it.
        await store.setOwnNames(false)
        let byOwn = try #require(store.searchNames("second-hand").first)
        #expect(byOwn.shownName == "Vinted, UAB" && byOwn.matchedName == "Second-hand clothes")
        let group = store.nameGroup(byOwn.key)
        #expect(SearchPage.kind(of: "Second-hand clothes", in: group) == .own)
        #expect(SearchPage.Row(byOwn, group: group, language: .english).match == "Your name: Second-hand clothes")
        #expect(SearchPage.Row(byOwn, group: group, language: .german).match == "Dein Name: Second-hand clothes")
        await store.setOwnNames(true)
    }

    @Test func aResultsLineWritesTheYearOnlyForAnotherYear() {
        let now = Self.now
        #expect(SearchPage.line(count: 1, newestDate: "2026-10-03", category: "Groceries", now: now, language: .english)
                == "1 payment · 3 Oct · Groceries")
        #expect(SearchPage.line(count: 4, newestDate: "2025-12-03", category: "Groceries", now: now, language: .english)
                == "4 payments · 3 Dec 2025 · Groceries")
        #expect(SearchPage.line(count: 4, newestDate: "2025-12-03", category: CategoryName.uncategorised, now: now,
                                language: .german) == "4 Buchungen · 3. Dez. 2025 · Nicht sortiert")
        let result = NameSearchResult(key: "k", shownName: "Fiktiv Werke", matchedName: nil, count: 2, moneyOut: 0,
                                      moneyIn: 2450, newestDate: "2026-10-01", categoryName: "Salary")
        let row = SearchPage.Row(result, group: nil, now: now, language: .english)
        #expect(row.moneyOut == nil && row.moneyIn == "+2,450.00", "money in only: no zero out")
        let nothing = NameSearchResult(key: "z", shownName: "Zero", matchedName: "Old", count: 1, moneyOut: 0,
                                       moneyIn: 0, newestDate: "2026-10-01", categoryName: "Other")
        let zero = SearchPage.Row(nothing, group: nil, now: now, language: .english)
        #expect(zero.moneyOut == nil && zero.moneyIn == nil, "no money either way: no amount")
        #expect(zero.match == "Old", "a name of no known kind: the name alone")
    }

    /// Before anything is typed: the line on what it finds and the names of the newest payments, newest first.
    @Test func beforeTypingTheNewestNamesShow() async throws {
        let store = await store(try await phone())
        let latest = store.latestNames()
        #expect(latest.map(\.shownName) == ["REWE Markt GmbH", "Vinted, UAB"])
        #expect(latest.allSatisfy { $0.matchedName == nil })
        #expect(store.latestNames(limit: 1).count == 1)
        #expect(SearchPage.hint(language: .german) == "Findet deine eigenen Namen und die der Bank.")
        #expect(SearchPage.prompt(language: .german) == "Namen suchen")
        #expect(SearchPage.latestHeading(language: .german) == "Zuletzt")
        #expect(await self.store().latestNames().isEmpty, "server mode: none")

        let groups = ["b": group("Beta", date: "2026-10-03"), "a": group("Alpha", date: "2026-10-03", count: 2),
                      "c": group("Gamma", date: "2026-10-05")]
        #expect(NameSearch.latest(in: groups, limit: 8).map(\.key) == ["c", "a", "b"], "newest, then more payments")
        #expect(NameSearch.latest(in: groups, limit: 0).isEmpty)
    }

    private func group(_ name: String, date: String, count: Int = 1) -> PaymentNameGroup {
        let rows = (0..<count).map { index in
            Transaction(id: "\(name)-\(index)", date: date, day: 3, month: "2026-10", amount: -5,
                        categoryName: "Fictional", tags: [], place: name, city: "", categoriesIn: ["Fictional"],
                        incomeBuckets: [])
        }
        return PaymentNameGroup(rows: rows, amounts: PaymentNameAmounts(moneyOut: 5, moneyIn: 0), months: [:])
    }
}
