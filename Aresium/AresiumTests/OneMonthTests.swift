import Foundation
import Testing
@testable import Aresium

/// Only one month of payments (Patrik, 2026-10-27: an unknown bank's file with one week of February, then Overview,
/// the graph and a category showed an empty plot). The dashboard's months span the data, so every graph gets one
/// point, which a line and its area cannot draw: `SeriesChart` draws it as a stem with a dot around
/// `ChartAxis.singlePointDomain`, and the range names the month once.
@MainActor
struct OneMonthTests {
    private let none = BackendAuth(token: nil)

    @Test func oneMonthOfPaymentsGivesEachGraphItsOnePoint() async throws {
        let session = await PhoneTest.session(nil, transport: RoutedTransport())
        let phone = try await PhoneTest.backend(chosen: ["groceries"])
        // The made-up unknown bank's week in February 2026, read with the layout the person confirmed.
        let file = try PhoneTest.fixture("unknown-fiktivbank.csv")
        let first = PhoneTest.phoneResults(try await phone.importFiles([file], auth: none))
        try await phone.saveLayout(try #require(first.first?.readings.first?.layout))
        let added = PhoneTest.phoneResults(try await phone.importFiles([file], auth: none))
        #expect(added.first?.added ?? 0 > 0)

        let store = DashboardStore(session: session, backend: phone)
        await store.reload()
        let dashboard = try #require(store.dashboard)
        #expect(dashboard.months.map(\.key) == ["2026-02"])
        // The month once, not "Feb 2026 – Feb 2026".
        #expect(store.rangeLabel(current: false) == dashboard.months[0].title())
        #expect(!store.rangeLabel(current: false).contains("–"))

        let overview = store.startChart(side: .expenses, current: false)
        #expect(overview.count == 1 && overview.first?.value ?? 0 > 0)
        #expect(ChartAxis.singlePointDomain(overview) == -1...1)
        let category = try #require(store.rows(side: .expenses, current: false).first)
        let points = store.categoryChart(category.category.name, side: .expenses)
        #expect(points.count == 1 && ChartAxis.singlePointDomain(points) != nil)
    }
}
