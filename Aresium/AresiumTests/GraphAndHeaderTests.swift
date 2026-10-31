import Foundation
import SwiftUI
import Testing
@testable import Aresium

// Brief 56: reading a graph by sliding over it (the nearest point and the chip), a month's page opened from Overview's
// graph (its rows, totals and chart from the store), the route to it, and the setting that lets the graph move away.

@MainActor
struct ChartReadingTests {
    private static func points(_ count: Int) -> [ChartPoint] {
        (0..<count).map { ChartPoint(index: $0, label: String($0 + 1), value: Double($0) * 10) }
    }

    @Test func theNearestPointFollowsTheFinger() {
        let points = Self.points(31)
        #expect(ChartReading.nearest(to: 14.2, in: points)?.index == 14)
        #expect(ChartReading.nearest(to: 14.7, in: points)?.index == 15)
        // Halfway between two days: the later one, so a finger moving right never waits a point behind.
        #expect(ChartReading.nearest(to: 14.5, in: points)?.index == 15)
        // Beyond either end of the plot: the first or the last point.
        #expect(ChartReading.nearest(to: -3, in: points)?.index == 0)
        #expect(ChartReading.nearest(to: 40, in: points)?.index == 30)
        #expect(ChartReading.nearest(to: 3, in: []) == nil)
        #expect(ChartReading.nearest(to: .nan, in: points) == nil)
    }

    @Test func theNearestPointOnAGraphWithGaps() {
        // A name's or category's months start at their own index; only points that are there count.
        let points = [2, 5, 6].map { ChartPoint(index: $0, label: "M\($0)", value: 1) }
        #expect(ChartReading.nearest(to: 3.4, in: points)?.index == 2)
        #expect(ChartReading.nearest(to: 3.6, in: points)?.index == 5)
        #expect(ChartReading.nearest(to: 0, in: points)?.index == 2)
        let one = [ChartPoint(index: 0, label: "Feb", value: 29.57)]
        #expect(ChartReading.nearest(to: 0.9, in: one)?.index == 0, "a graph of one month always reads it")
    }

    @Test func theChipNamesTheDayAndTheAmount() {
        let day = ChartPoint(index: 13, label: "14", value: 1234.5,
                             title: ChartReading.dayTitles(month: "2026-10", count: 31, language: .english)[13])
        #expect(ChartReading.chip(day, language: .english).title == "Wed 14 Oct")
        #expect(ChartReading.chip(day, language: .english).amount == "€1,234.50")
        let german = ChartPoint(index: 13, label: "14", value: 1234.5,
                                title: ChartReading.dayTitles(month: "2026-10", count: 31, language: .german)[13])
        #expect(ChartReading.chip(german, language: .german).title == "Mi. 14. Okt.")
        #expect(ChartReading.chip(german, language: .german).amount == "1.234,50\u{a0}€")
        #expect(ChartReading.line(day, language: .english) == "Wed 14 Oct, €1,234.50")
        // Without a title the chip shows the axis's label; the first day of a month is day 1.
        #expect(ChartReading.chip(ChartPoint(index: 0, label: "Sep", value: 0), language: .english).title == "Sep")
        #expect(ChartReading.chip(ChartPoint(index: 0, label: "Sep", value: 0), language: .english).amount == "€0.00")
        #expect(ChartReading.dayTitles(month: "2026-10", count: 31, language: .english).first == "Thu 1 Oct")
        #expect(ChartReading.dayTitles(month: "2026-10", count: 31, language: .english).last == "Sat 31 Oct")
        #expect(ChartReading.dayTitles(month: "2026-02", count: 28, language: .german).last == "Sa. 28. Feb.")
        #expect(ChartReading.dayTitles(month: "not a month", count: 3, language: .english) == ["1", "2", "3"])
        #expect(ChartReading.dayTitles(month: "2026-10", count: 0).isEmpty)
    }

    @Test func theStoreGivesEveryPointItsChipTitle() async throws {
        let store = DashboardStore(session: EmpireSession(app: .aresium, storage: PhoneTokens(), restoreOnLaunch: false), sample: true)
        await store.reload()
        let dashboard = try #require(store.dashboard)
        let days = store.startChart(side: .expenses, current: true)
        #expect(days.first?.label == "1")
        #expect(days.map(\.title) == ChartReading.dayTitles(month: "2026-10", count: days.count))
        #expect(days.first?.title == "Thu 1 Oct")
        let months = store.startChart(side: .expenses, current: false)
        #expect(months.map(\.title) == dashboard.months.map { $0.title() })
        #expect(months.map(\.label) == dashboard.months.map { $0.shortTitle() }, "the axis keeps its short names")
        #expect(store.categoryChart("Groceries", side: .expenses).map(\.title) == dashboard.months.map { $0.title() })
    }
}

/// A month's page: the start screen's pieces over one month (`DashboardScope.month`).
@MainActor
struct MonthPageTests {
    private func store() async -> DashboardStore {
        let store = DashboardStore(session: EmpireSession(app: .aresium, storage: PhoneTokens(), restoreOnLaunch: false), sample: true)
        await store.reload()
        return store
    }

    @Test func aMonthsPageCountsThatMonth() async throws {
        let store = await store()
        let dashboard = try #require(store.dashboard)
        let september = try #require(dashboard.byMonth["2026-09"])
        let scope = DashboardScope.month("2026-09")
        #expect(store.monthKey(scope) == "2026-09")
        #expect(store.totals(scope)?.expense == september.expense)
        #expect(store.totals(scope)?.income == september.income)
        #expect(store.rows(side: .expenses, scope: scope).map(\.category.name) == september.categories.map(\.name))
        #expect(store.rows(side: .expenses, scope: scope).map(\.total) == september.categories.map(\.total))
        #expect(store.rows(side: .income, scope: scope).map(\.total) == september.incomeBuckets.map(\.total))
        #expect(store.startChart(side: .expenses, scope: scope).map(\.value) == september.dayExpense)
        #expect(store.startChart(side: .income, scope: scope).map(\.value) == september.dayIncome)
        #expect(store.startChart(side: .expenses, scope: scope).count == september.dayExpense.count)
        #expect(store.startChart(side: .expenses, scope: scope)[4].title == "Sat 5 Sep")
        #expect(store.rangeLabel(scope) == "September 2026")
        // It differs from Current's month, which stays October.
        #expect(store.totals(.current)?.expense != september.expense)
        #expect(store.rangeLabel(.current) == "October 2026")
    }

    @Test func aMonthsCategoryOpensThatMonthsPayments() async throws {
        let store = await store()
        let scope = DashboardScope.month("2026-09")
        let name = try #require(store.rows(side: .expenses, scope: scope).first?.category.name)
        let route = store.route(category: name, side: .expenses, scope: scope)
        #expect(route == DashboardRoute(category: name, side: .expenses, month: "2026-09"))
        #expect(!store.transactions(category: name, month: "2026-09", side: .expenses).isEmpty)
        #expect(store.cashRoute(scope) == DashboardRoute(category: "", side: .expenses, month: "2026-09", cash: true))
        #expect(store.cashUnaccounted(scope) == 0, "the server sample has no cash")
    }

    /// Current and Overview read as before through the scope: the start screen is the same pieces.
    @Test func currentAndOverviewAreUnchanged() async throws {
        let store = await store()
        let dashboard = try #require(store.dashboard)
        #expect(store.totals(.current)?.expense == dashboard.byMonth["2026-10"]?.expense)
        #expect(store.totals(.overview)?.income == dashboard.total.income)
        #expect(store.rangeLabel(.overview) == "August 2026 – October 2026")
        #expect(store.route(category: "Groceries", side: .expenses, scope: .overview)
                == DashboardRoute(category: "Groceries", side: .expenses))
        #expect(store.route(category: "Groceries", side: .expenses, scope: .current).month == "2026-10")
        #expect(store.startChart(side: .income, scope: .overview).map(\.value) == dashboard.overview.income)
        #expect(DashboardScope(current: true) == .current && DashboardScope(current: false) == .overview)
        #expect(DashboardScope.month("2026-09").isMonth && DashboardScope.current.isMonth && !DashboardScope.overview.isMonth)
        // A month the dashboard no longer has: nothing to count, its key's name.
        #expect(store.totals(.month("2025-01")) == nil)
        #expect(store.rows(side: .expenses, scope: .month("2025-01")).isEmpty)
        #expect(store.startChart(side: .expenses, scope: .month("2025-01")).isEmpty)
    }

    /// A review message's month is Current's month; a month's page stays its own month.
    @Test func aReviewMonthMovesCurrentButNotAMonthsPage() async throws {
        let store = await store()
        store.showReview(month: "2026-08")
        #expect(store.monthKey(.current) == "2026-08")
        #expect(store.monthKey(.month("2026-09")) == "2026-09")
        store.showReview(month: nil)
        #expect(store.monthKey(.current) == "2026-10")
    }
}

/// The route to a month's page: a tap on a month of Overview's graph.
@MainActor
struct MonthRouteTests {
    @Test func aTapOnOverviewsGraphOpensThatMonthsPage() async throws {
        let store = DashboardStore(session: EmpireSession(app: .aresium, storage: PhoneTokens(), restoreOnLaunch: false), sample: true)
        await store.reload()
        let route = try #require(store.monthPage(atChartIndex: 1, side: .income))
        #expect(route == DashboardRoute(monthPage: "2026-09", side: .income))
        #expect(route.monthPage == "2026-09" && route.side == .income)
        // Not a month's payment list, a Cash page or a name's page: those read `month`, `cash` and `name`.
        #expect(route.month == nil && !route.cash && route.name == nil)
        #expect(route != DashboardRoute(category: "", side: .income, month: "2026-09"))
        #expect(store.monthPage(atChartIndex: 3, side: .expenses) == nil, "past the last month")
        #expect(store.monthPage(atChartIndex: -1, side: .expenses) == nil)
        #expect(store.monthKey(atChartIndex: 0) == "2026-08")
    }

    /// The tour's category step waits for a month's payments; a month's page pushed from the graph is not that.
    @Test func theToursCategoryStepIsNotTakenByAMonthsPage() async throws {
        let parent = FileManager.default.temporaryDirectory.appending(path: "aresium-56-tour-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: parent) }
        let now = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 27, hour: 12))!
        let tour = TourModel(showsGraph: true, graphMoves: true) {
            try await TourWorld.make(in: parent, now: now, makeEngine: { try PhoneTest.engine() })
        }
        await tour.start(at: .category)
        #expect(tour.phase == .running)
        defer { tour.end() }
        var place = tour.place
        place.current = false
        tour.update(place)
        place.path.append(DashboardRoute(monthPage: "2026-09", side: .expenses))
        tour.update(place)
        #expect(tour.step == .category)
        #expect(tour.graphMoves)
    }
}

/// Settings → Dashboard → "Graph moves away when scrolling": on by default, kept, and the numbers that line up the two
/// pages when a scroll comes to rest.
struct GraphMotionSettingTests {
    private static func defaults() -> UserDefaults {
        let name = "aresium.tests.graphMoves.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func itIsOnByDefault() {
        #expect(GraphMotionSetting.movesByDefault)
        #expect(GraphMotionSetting.moves(in: Self.defaults()))
        #expect(GraphMotionSetting.key.hasPrefix("aresium."))
        #expect(GraphMotionSetting.key != GraphSetting.key)
    }

    @Test(arguments: [false, true])
    func theChoiceIsKept(moves: Bool) {
        let defaults = Self.defaults()
        defaults.set(moves, forKey: GraphMotionSetting.key)
        #expect(GraphMotionSetting.moves(in: defaults) == moves)
    }

    /// The switch and the dashboard use `@AppStorage` with the key and the default: they read and write the same value,
    /// and a new launch reads it.
    @MainActor @Test func theSwitchAndTheDashboardAgree() {
        let defaults = Self.defaults()
        let stored = AppStorage(wrappedValue: GraphMotionSetting.movesByDefault, GraphMotionSetting.key, store: defaults)
        #expect(stored.wrappedValue, "nothing saved yet: on")
        stored.wrappedValue = false
        #expect(!GraphMotionSetting.moves(in: defaults))
        #expect(!AppStorage(wrappedValue: GraphMotionSetting.movesByDefault, GraphMotionSetting.key,
                            store: defaults).wrappedValue)
        #expect(GraphSetting.isShown(in: defaults), "the graph itself stays shown")
    }

    /// Not in the export: the export carries the data, not how the dashboard looks.
    @Test func itIsNotInTheExport() throws {
        let source = try String(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Aresium/Model/LedgerExport.swift"), encoding: .utf8)
        #expect(!source.contains("graphMoves") && !source.contains("GraphMotion"))
    }

    @MainActor @Test func thePagesLineUpWhenAScrollRests() {
        let height: CGFloat = 235
        #expect(GraphMotion.away(-40, graph: height) == 0, "pulled down to refresh: the graph is there")
        #expect(GraphMotion.away(100, graph: height) == 100)
        #expect(GraphMotion.away(900, graph: height) == height)
        // The other page follows the graph partly away to the same place, whatever it was.
        #expect(GraphMotion.follow(restingAt: 0, away: 100, graph: height) == 100)
        #expect(GraphMotion.follow(restingAt: 700, away: 100, graph: height) == 100)
        // Wholly away: a page at the top goes to where its graph is gone; one further down stays.
        #expect(GraphMotion.follow(restingAt: 0, away: height, graph: height) == height)
        #expect(GraphMotion.follow(restingAt: 600, away: height, graph: height) == nil)
        #expect(GraphMotion.follow(restingAt: 100, away: 100, graph: height) == nil, "already there")
        #expect(GraphMotion.follow(restingAt: 50, away: 0, graph: height) == 0, "back at the top: the graph is back")
        #expect(GraphMotion.leastContent(visible: 600, graph: height) == 835)
    }
}
