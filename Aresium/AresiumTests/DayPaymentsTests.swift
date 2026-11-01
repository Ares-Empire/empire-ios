import Foundation
import Testing
@testable import Aresium

@MainActor
struct DayPaymentsTests {
    private func store(phone: PhoneBackend? = nil) async -> DashboardStore {
        let session = EmpireSession(app: .aresium, storage: PhoneTokens(), restoreOnLaunch: false)
        let store = phone.map { DashboardStore(session: session, backend: $0) } ?? DashboardStore(session: session, sample: true)
        await store.reload()
        return store
    }

    /// Compare every day with the graph and every category's month list, including days with no activity.
    private func checkEveryDay(_ store: DashboardStore) throws {
        let dashboard = try #require(store.dashboard)
        for month in dashboard.months {
            for number in 1...month.days {
                let date = month.key + String(format: "-%02d", number)
                let day = store.day(date)
                #expect(day.date == date)
                for side in DashboardSide.allCases {
                    let result = day[side]
                    let values = side == .expenses ? dashboard.byMonth[month.key]?.dayExpense : dashboard.byMonth[month.key]?.dayIncome
                    #expect(result.total == values?[number - 1], "\(date) \(side)")
                    let categories = side == .expenses ? dashboard.categories : dashboard.incomeBuckets
                    var ids = Set<String>()
                    for category in categories {
                        let list = store.transactions(category: category.name, month: month.key, side: side).filter { $0.transaction.date == date }
                        ids.formUnion(list.map(\.id))
                        let actual = result.rows.filter { list.map(\.id).contains($0.id) }
                        #expect(actual.map(\.id) == list.map(\.id), "same category list order on \(date)")
                        #expect(actual.map(\.transaction.coveredBy) == list.map(\.transaction.coveredBy))
                        #expect(actual.map(\.transaction.amount) == list.map(\.transaction.amount))
                    }
                    #expect(result.rows.count == ids.count && Set(result.rows.map(\.id)) == ids, "extra categories only once")
                    let expected = dashboard.transactions.filter { $0.date == date && ids.contains($0.id) }.sorted(by: Transaction.listOrder)
                    #expect(result.rows.map(\.id) == expected.map(\.id), "stable store order across categories")
                    for row in result.rows {
                        let meta = try #require(categories.first { $0.name == row.category.name })
                        #expect(row.category.icon == meta.icon && row.category.color == meta.color && row.category.kind == meta.kind)
                        let listRow = try #require(store.transactions(category: row.category.name, month: month.key, side: side).first { $0.id == row.id })
                        #expect(row.row.tagged == listRow.tagged)
                        let names = side == .expenses ? row.transaction.categoriesIn : row.transaction.incomeBuckets
                        #expect(names.contains(row.category.name))
                    }
                }
            }
        }
    }

    @Test func everyServerSampleDayMatchesItsGraphAndLists() async throws {
        let store = await store()
        #expect(store.dashboard?.nameGroups == nil)
        try checkEveryDay(store)
        #expect(!store.builtDays.days.isEmpty && store.builtDays.revision == store.revision)
        let revision = store.revision
        await store.reload()
        _ = store.day("2026-10-01")
        #expect(store.revision > revision && store.builtDays.revision == store.revision && store.builtDays.days.count == 1)
        store.clear()
        #expect(store.day("2026-10-01").expenses.rows.isEmpty && store.day("2026-10-01").expenses.total == 0)
    }

    @Test func everyPhoneSampleDayMatchesItsGraphAndListsWithCash() async throws {
        let phone = try await PhoneSample.backend(empty: false, storage: PhoneTest.storage()).backend
        try await PhoneSample.addCash(phone, now: #require(ReceiptDay.date("2026-10-30")))
        let store = await store(phone: phone)
        try checkEveryDay(store)
        #expect(store.dashboard?.transactions.contains { $0.coveredBy != nil } == true)
    }

    @Test func coveredRowsExtraCategoriesTransfersAndBothDirections() async throws {
        let auth = BackendAuth(token: nil)
        let phone = try await PhoneCountingTests.backend(chosen: ["groceries", "hobbies", "cash", "salary", "selling-things"])
        _ = try await phone.importFiles([PhoneTest.vrBank([
            ("01.10.2026", "Fictional Shop", "Purchase", -2000),
            ("01.10.2026", "Fictional Shop", "Refund", 500),
            ("01.10.2026", "Geldautomat Fiktivbank", "Bargeldauszahlung", -10000),
            ("01.10.2026", "Fictional Transfer", "Transfer", -4000),
            ("02.10.2026", "Fictional Buyer", "Money returned", -800)])], auth: auth)
        let payments = try await phone.ledger.payments()
        let purchase = try #require(payments.first { $0.amountValue == -20 })
        let refund = try #require(payments.first { $0.amountValue == 5 })
        let transfer = try #require(payments.first { $0.amountValue == -40 })
        let returned = try #require(payments.first { $0.amountValue == -8 })
        for payment in [purchase, refund] { try await phone.ledger.setCategory(payment.id, category: "groceries", source: .manual) }
        try await phone.ledger.setCategory(transfer.id, category: CategoryCatalog.ownTransfers, source: .structural)
        try await phone.ledger.setCategory(returned.id, category: "selling-things", source: .manual)
        _ = try await phone.setTags(id: purchase.id, categories: ["Hobbies"], dropCurrent: false, auth: auth)
        _ = try await phone.setTags(id: refund.id, categories: ["Hobbies"], dropCurrent: false, auth: auth)
        _ = try await phone.addCashEntry(CashEntryDraft(direction: .out, amount: 25, date: "2026-10-03", what: "Fictional stall", category: "groceries"))
        let store = await store(phone: phone)
        try checkEveryDay(store)
        let first = store.day("2026-10-01")
        #expect(first.expenses.rows.filter { $0.id == purchase.id }.count == 1)
        #expect(first.income.rows.filter { $0.id == refund.id }.count == 1)
        #expect(!first.expenses.rows.contains { $0.id == transfer.id })
        let covered = try #require(first.expenses.rows.first { $0.transaction.coveredBy != nil })
        #expect(covered.transaction.amount == 25 && first.expenses.total == 95)
        #expect(first.income.total == 5 && store.day("2026-10-03").expenses.total == 25)
        #expect(store.day("2026-10-02").expenses.rows.first?.category.name == "Selling things")
        // The graph's amount includes the positive covered row as a reduction on the withdrawal day.
        for date in ["2026-10-01", "2026-10-02", "2026-10-03"] {
            let day = store.day(date)
            #expect(abs(day.expenses.total + day.expenses.rows.reduce(0) { $0 + $1.transaction.amount }) < 0.000001)
            #expect(abs(day.income.total - day.income.rows.reduce(0) { $0 + $1.transaction.amount }) < 0.000001)
        }
    }

    @Test func dayDatesFollowCurrentReviewAndMonthScopesAndRejectMonthPoints() async throws {
        let store = await store()
        let month = try #require(store.currentMonth)
        #expect(store.dayDate(atChartIndex: 0, scope: .current) == month.key + "-01")
        #expect(store.dayDate(atChartIndex: month.days - 1, scope: .current) == month.key + String(format: "-%02d", month.days))
        #expect(store.dayDate(atChartIndex: 0, scope: .overview) == nil)
        #expect(store.dayDate(atChartIndex: -1, scope: .current) == nil)
        #expect(store.dayDate(atChartIndex: month.days, scope: .current) == nil)
        #expect(store.dayDate(atChartIndex: 0, scope: .month("missing")) == nil)
        #expect(store.dayDate(atChartIndex: 29, scope: .month("2026-09")) == "2026-09-30")
        #expect(store.dayDate(atChartIndex: 30, scope: .month("2026-09")) == nil)
        store.showReview(month: "2026-09")
        #expect(store.dayDate(atChartIndex: 0, scope: .current) == "2026-09-01")
        store.clear()
        #expect(store.dayDate(atChartIndex: 0, scope: .current) == nil)
    }

    @Test func invalidAndAbsentDaysHaveEmptyListsAndZeroTotals() async {
        let store = await store()
        for date in ["", "2026-02-30", "2026-10-00", "2026-10-32", "2026-10-01-extra", "2026-1-01", "2025-01-01"] {
            let day = store.day(date)
            #expect(day.expenses.rows.isEmpty && day.income.rows.isEmpty)
            #expect(day.expenses.total == 0 && day.income.total == 0)
        }
    }
}
