import Foundation
import Testing
@testable import Aresium

/// Brief 55: a day's tile reads as a date ("4." in German, "4" in English), and the name's page opens its months as
/// pages: the months with payments of the name (oldest first, as a category's), each month's rows as a category's month
/// list orders them, the route, the stack's rules (All goes back to the name's page, a rename follows on every page of
/// the name) and what a month's page does after a rename. Everything is made up.
struct DayWordingTests {
    @Test func everyDayOfTheMonthInBothLanguages() {
        for day in 1...31 {
            #expect(DayWording.alone(day, language: .german) == "\(day).", "German writes a day alone with its dot")
            #expect(DayWording.alone(day, language: .english) == "\(day)", "English puts no dot after a day")
        }
        #expect(DayWording.alone(4, language: .german) == "4.")
        #expect(DayWording.alone(31, language: .german) == "31.")
        #expect(DayWording.alone(4, language: .english) == "4")
    }

    @Test func aDayFromItsDate() {
        #expect(DayWording.alone(date: "2026-10-04", language: .german) == "4.")
        #expect(DayWording.alone(date: "2026-10-31", language: .english) == "31")
        #expect(DayWording.alone(date: "2026-02-01", language: .german) == "1.")
        #expect(DayWording.alone(date: "not a day", language: .german) == "–")
        #expect(DayWording.alone(date: "", language: .english) == "–")
    }

    @Test func theAppsLanguageByDefault() {
        AppLanguage.$scoped.withValue(.german) { #expect(DayWording.alone(9) == "9.") }
        AppLanguage.$scoped.withValue(.english) { #expect(DayWording.alone(9) == "9") }
    }
}

struct DashboardPlaceTests {
    private let rewe = PaymentNameRoute(key: "merchant:rewe", title: "REWE")

    @Test func aNamesMonthIsItsOwnRoute() {
        let month = DashboardRoute(name: rewe, month: "2026-10")
        #expect(month.name == rewe && month.month == "2026-10" && !month.cash && month.category.isEmpty)
        #expect(month != DashboardRoute(name: rewe), "the name's page and its month's are two pages")
        #expect(month != DashboardRoute(name: rewe, month: "2026-09"))
        #expect(month != DashboardRoute(category: "", side: .expenses, month: "2026-10"), "not a category's month")
        #expect(month == DashboardRoute(name: PaymentNameRoute(key: "merchant:rewe", title: "REWE"), month: "2026-10"))
    }

    @Test func pagesArePushedAndAllGoesBackToTheNamesPage() {
        var place = DashboardPlace()
        let category = DashboardRoute(category: "Groceries", side: .expenses)
        let month = DashboardRoute(category: "Groceries", side: .expenses, month: "2026-10")
        place.open(category)
        place.open(month)
        place.open(DashboardRoute(name: rewe))
        place.open(DashboardRoute(name: rewe, month: "2026-10"))
        #expect(place.path == [category, month, DashboardRoute(name: rewe), DashboardRoute(name: rewe, month: "2026-10")])

        // All on a row of the name's month: back to the name's page below, no second copy of it.
        place.open(DashboardRoute(name: rewe))
        #expect(place.path == [category, month, DashboardRoute(name: rewe)])
        // Another name's page is pushed as before.
        let lidl = PaymentNameRoute(key: "merchant:lidl", title: "LIDL")
        place.open(DashboardRoute(name: lidl))
        #expect(place.path.last == DashboardRoute(name: lidl) && place.path.count == 4)

        place.back()
        place.back()
        #expect(place.path == [category, month])
        place.path = []
        place.back()
        #expect(place.path.isEmpty, "nothing to go back to")
    }

    @Test func aRenameFollowsOnEveryPageOfTheName() {
        let month = DashboardRoute(category: "Groceries", side: .expenses, month: "2026-10")
        var place = DashboardPlace(path: [month, DashboardRoute(name: rewe), DashboardRoute(name: rewe, month: "2026-09")])
        let weekly = PaymentNameRoute(key: "own:weekly shop", title: "Weekly shop")
        place.follow(rewe, to: weekly)
        #expect(place.path == [month, DashboardRoute(name: weekly), DashboardRoute(name: weekly, month: "2026-09")])

        // The same name spelt differently: the key stays, the title follows.
        let shouted = PaymentNameRoute(key: weekly.key, title: "WEEKLY SHOP")
        place.follow(weekly, to: shouted)
        #expect(place.path.compactMap(\.name) == [shouted, shouted])
        #expect(place.path.first == month, "other pages stay")
    }
}

@MainActor
struct NameMonthsTests {
    private let auth = BackendAuth(token: nil)

    /// Penny over three months with a gap: July (a purchase), August (none of Penny, only another shop), September (a
    /// refund only) and October (two purchases and a refund, under two spellings of the shop).
    private func store() async throws -> (PhoneBackend, DashboardStore) {
        let phone = try await PhoneCountingTests.backend(chosen: ["groceries", "eating-out"])
        _ = try await phone.importFiles([PhoneTest.vrBank([
            ("03.07.2026", "PENNY Markt Berlin", "Purchase", -1200),
            ("10.08.2026", "Fiktiv Einzelladen", "Purchase", -1500),
            ("12.09.2026", "PENNY Markt Berlin", "Refund", 300),
            ("05.10.2026", "PENNY Markt Berlin", "Refund", 500),
            ("03.10.2026", "PENNY Markt Berlin", "Purchase", -3000),
            ("02.10.2026", "Kartenzahlung PENNY Markt 12345", "Purchase", -2000)])], auth: auth)
        let session = await PhoneTest.session(nil, transport: RoutedTransport())
        let dashboard = DashboardStore(session: session, backend: phone)
        await dashboard.reload()
        return (phone, dashboard)
    }

    private func row(_ text: String, amount: Double, in dashboard: DashboardStore) throws -> Transaction {
        try #require(dashboard.dashboard?.transactions.first { $0.place.contains(text) && $0.amount == amount })
    }

    private func pennyRoute(_ dashboard: DashboardStore) throws -> PaymentNameRoute {
        let penny = try row("PENNY Markt Berlin", amount: -30, in: dashboard)
        return PaymentNameRoute(key: try #require(penny.nameKey), title: penny.place)
    }

    @Test func theMonthsWithTheNameOldestFirstAndEachMonthsRows() async throws {
        let (_, dashboard) = try await store()
        let route = try pennyRoute(dashboard)
        let board = try #require(dashboard.dashboard)
        #expect(board.months.contains { $0.key == "2026-08" }, "August is a month of the dashboard")
        let page = try #require(dashboard.namePage(route.key))
        #expect(page.count == 5 && page.spends)
        #expect(page.months.map(\.month.key) == ["2026-07", "2026-09", "2026-10"],
                "oldest first; August, without Penny, has no row")
        #expect(page.month("2026-08") == nil)
        #expect(page.months.map(\.total) == [12, 0, 50], "the bars count money out, as the graph")
        #expect(page.months.map(\.other) == [0, 3, 5], "the refunds")
        #expect(page.chart.map(\.value).reduce(0, +) == 62 && page.chart.count == board.months.count)

        // A month's rows: as a category's month list orders them, by day; the refund among them.
        let october = try #require(page.month("2026-10")?.rows)
        #expect(october.map(\.transaction.amount) == [-20, -30, 5])
        #expect(october.map(\.transaction.day) == [2, 3, 5])
        #expect(october.allSatisfy { !$0.tagged && $0.transaction.nameKey == route.key })
        let listed = dashboard.transactions(category: "Groceries", month: "2026-10", side: .expenses)
            .map(\.transaction.id).filter { id in october.contains { $0.id == id } }
        #expect(listed == october.map(\.id).filter { listed.contains($0) }, "the same order as the category's list")
        // A month with only a refund still opens: its payment is nowhere else on the name's page.
        #expect(page.month("2026-09")?.rows.map(\.transaction.amount) == [3])
        #expect(page.month("2026-07")?.rows.count == 1)
    }

    @Test func aMonthWithOnlyARefundWritesItSigned() {
        #expect(NameWording.otherSide(80, spends: true, language: .english) == "+€80")
        #expect(NameWording.otherSide(80, spends: true, language: .german) == "+80\u{a0}€")
        #expect(NameWording.otherSide(50, spends: false, language: .english) == "−€50", "money out of a salary's name")
    }

    @Test func thePageIsBuiltOncePerDashboard() async throws {
        let (phone, dashboard) = try await store()
        let route = try pennyRoute(dashboard)
        let first = try #require(dashboard.namePage(route.key))
        #expect(dashboard.builtNamePages.pages.count == 1 && dashboard.builtNamePages.revision == dashboard.revision)
        #expect(dashboard.namePage(route.key)?.count == first.count)
        #expect(dashboard.namePage("own:nobody") == nil, "a name without payments has no page")

        // A payment renamed alone: the next dashboard builds the page again, one payment fewer.
        let purchase = try row("PENNY Markt Berlin", amount: -30, in: dashboard)
        _ = try await phone.rename(id: purchase.id, name: "Party", scope: .payment)
        await dashboard.reloadAfterTransactionChange()
        #expect(dashboard.builtNamePages.revision != dashboard.revision, "not built for the new dashboard yet")
        let again = try #require(dashboard.namePage(route.key))
        #expect(again.count == 4 && again.month("2026-10")?.rows.map(\.transaction.amount) == [-20, 5])
    }

    @Test func aMonthsPageFollowsARenameOrGoesBack() async throws {
        let (phone, dashboard) = try await store()
        let route = try pennyRoute(dashboard)
        func step(_ payment: Transaction?, month: String?, route: PaymentNameRoute) -> NamePageStep {
            NamePageStep(after: payment, route: route, month: month, groups: dashboard.dashboard?.nameGroups)
        }

        // Only this one, in October: the payment leaves, the month still has Penny; the page stays.
        let purchase = try row("PENNY Markt Berlin", amount: -30, in: dashboard)
        _ = try await phone.rename(id: purchase.id, name: "Party", scope: .payment)
        await dashboard.reloadAfterTransactionChange()
        #expect(step(try row("Party", amount: -30, in: dashboard), month: "2026-10", route: route) == NamePageStep())

        // September's only payment renamed alone: no Penny left there, one page back.
        let refund = try row("PENNY Markt Berlin", amount: 3, in: dashboard)
        _ = try await phone.rename(id: refund.id, name: "Bottle deposit", scope: .payment)
        await dashboard.reloadAfterTransactionChange()
        #expect(step(try row("Bottle deposit", amount: 3, in: dashboard), month: "2026-09", route: route)
                == NamePageStep(back: true))
        #expect(step(try row("Bottle deposit", amount: 3, in: dashboard), month: nil, route: route) == NamePageStep(),
                "the name's page itself never goes back")

        // The whole shop renamed from October's page: it follows to the new name, the month keeps its payments.
        let other = try row("PENNY Markt Berlin", amount: 5, in: dashboard)
        _ = try await phone.rename(id: other.id, name: "Weekly shop", scope: .shop)
        await dashboard.reloadAfterTransactionChange()
        #expect(dashboard.dashboard?.nameGroups?[route.key] == nil, "the old name has no payments left")
        let renamed = try row("Weekly shop", amount: 5, in: dashboard)
        let next = PaymentNameRoute(key: try #require(renamed.nameKey), title: "Weekly shop")
        #expect(step(renamed, month: "2026-10", route: route) == NamePageStep(follow: next))
        #expect(dashboard.namePage(next.key)?.month("2026-10")?.rows.count == 2)

        // Without a dashboard (it is loading) nothing moves.
        #expect(NamePageStep(after: renamed, route: route, month: "2026-10", groups: nil) == NamePageStep())
    }
}
