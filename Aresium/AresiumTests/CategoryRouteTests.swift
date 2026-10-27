import Foundation
import Testing
@testable import Aresium

/// Brief 22: in the Current view a category opens this month's payments directly; Overview keeps its months first. The
/// same in both modes (the start screen and the widget's category links go through `DashboardStore.route`).
@MainActor
struct CategoryRouteTests {
    @Test func currentOpensThisMonthsPaymentsAndOverviewTheMonths() {
        #expect(CategoryRoute.route(category: "Groceries", side: .expenses, current: true, currentMonth: "2026-10")
                == DashboardRoute(category: "Groceries", side: .expenses, month: "2026-10"))
        #expect(CategoryRoute.route(category: "Groceries", side: .expenses, current: false, currentMonth: "2026-10")
                == DashboardRoute(category: "Groceries", side: .expenses))
        // Before the dashboard has a month (still loading): the months, never an empty list.
        #expect(CategoryRoute.route(category: "Salary", side: .income, current: true, currentMonth: nil)
                == DashboardRoute(category: "Salary", side: .income))
    }

    @Test func theStoreRoutesWithItsCurrentMonthInBothModes() async throws {
        let server = DashboardStore(session: EmpireSession(app: .aresium, storage: PhoneTokens(), restoreOnLaunch: false),
                                    sample: true)
        await server.reload()
        let route = server.route(category: "Groceries", side: .expenses, current: true)
        #expect(route.month == "2026-10")
        #expect(!server.transactions(category: route.category, month: route.month ?? "", side: .expenses).isEmpty)

        let phone = try await PhoneTest.backend(chosen: ["groceries"])
        _ = try await phone.importFiles([PhoneTest.vrBank([("03.10.2026", "REWE Markt GmbH", "REWE", -2000)])],
                                        auth: BackendAuth(token: nil))
        let store = DashboardStore(session: EmpireSession(app: .aresium, storage: PhoneTokens(), restoreOnLaunch: false),
                                   backend: phone)
        await store.reload()
        let name = try #require(store.rows(side: .expenses, current: true).first?.category.name)
        let phoneRoute = store.route(category: name, side: .expenses, current: true)
        #expect(phoneRoute.month == "2026-10")
        #expect(store.transactions(category: name, month: "2026-10", side: .expenses).count == 1)
        #expect(store.route(category: name, side: .expenses, current: false).month == nil)
    }
}
