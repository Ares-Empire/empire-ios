import Foundation
import JavaScriptCore
import Testing
@testable import Aresium

/// Brief 223's proving cases through the bundle shipped on the phone, including the phone's account adapter.
@MainActor
struct EngineBalanceTests {
    private let categories = [
        SourceCategory(name: "Shopping", icon: "Tag", color: "#123456", excludeFromTotals: false),
        SourceCategory(name: "Transfer", icon: "Tag", color: "#123456", excludeFromTotals: true)
    ]

    private func payment(_ id: String, _ day: String, _ amount: Double, _ balance: Double?,
                         account: String? = "current", category: String = "Shopping",
                         raw: JSONValue? = nil, order: Int? = nil) -> SourcePayment {
        SourcePayment(id: id, externalId: id, accountId: account, statementOrder: order, date: day,
                      amount: amount, currency: "EUR", balance: balance, description: "Fictional shop",
                      raw: raw, category: category, tags: [])
    }

    private func input(_ rows: [SourcePayment], today: String = "2026-02-10") -> DashboardSourceInput {
        DashboardSourceInput(transactions: rows, categories: categories, today: today)
    }

    private func permutations<T>(_ rows: [T]) -> [[T]] {
        guard !rows.isEmpty else { return [[]] }
        return rows.indices.flatMap { index in
            permutations(rows.enumerated().filter { $0.offset != index }.map(\.element)).map { [rows[index]] + $0 }
        }
    }

    @Test func shuffledBookingsCloseAt850AndCarryAcrossMonths() async throws {
        let engine = try PhoneTest.engine()
        let rows = [payment("opening", "2026-01-30", 1000, 1000),
                    payment("debit100", "2026-01-31", -100, 900),
                    payment("debit50", "2026-01-31", -50, 850),
                    payment("purchase", "2026-02-04", -2, nil, account: "paypal")]
        for shuffled in permutations(rows) {
            let dashboard = try await engine.dashboard(input(shuffled, today: "2026-02-05"))
            #expect(dashboard.byMonth["2026-01"]?.dayBalance[28] == nil)
            #expect(dashboard.byMonth["2026-01"]?.dayBalance[29] == 1000)
            #expect(dashboard.byMonth["2026-01"]?.dayBalance[30] == 850)
            #expect(dashboard.byMonth["2026-02"]?.dayBalance == [850, 850, 850, 850, 850])
            #expect(dashboard.overview.balance == [850, 850])
        }
    }

    @Test func excludedTransfersFundingAndSecondAccountKeepTheirBalances() async throws {
        let engine = try PhoneTest.engine()
        let rows = [payment("funding", "2026-02-03", -50, 850,
                            raw: .object(["Type": .string("General Card Deposit")])),
                    payment("opening", "2026-02-02", 1000, 1000),
                    payment("transfer", "2026-02-03", -100, 900, category: "Transfer"),
                    payment("second", "2026-02-04", 250, 250, account: "savings", category: "Transfer")]
        let dashboard = try await engine.dashboard(input(rows))
        #expect(dashboard.byMonth["2026-02"]?.dayBalance == [nil, 1000, 850, 1100, 1100, 1100, 1100, 1100, 1100, 1100])
        #expect(dashboard.transactions.map(\.id) == ["opening", "transfer", "second"])
        #expect(dashboard.total.expense == 0 && dashboard.total.income == 1000)
    }

    @Test func unknownAccountsJoinOnlyAtTheirFirstBalanceIncludingZero() async throws {
        let engine = try PhoneTest.engine()
        let rows = [payment("unknown", "2026-02-01", -5, nil), payment("a", "2026-02-03", -10, 0),
                    payment("bUnknown", "2026-02-03", -1, nil, account: "savings"),
                    payment("b", "2026-02-05", 500, 500, account: "savings"), payment("a2", "2026-02-06", -5, -5)]
        let dashboard = try await engine.dashboard(input(rows))
        #expect(dashboard.byMonth["2026-02"]?.dayBalance == [nil, nil, 0, 0, 500, 495, 495, 495, 495, 495])
        let unknown = try await engine.dashboard(input([rows[0]]))
        #expect(unknown.byMonth["2026-02"]?.endBalance == nil)
        #expect(unknown.byMonth["2026-02"]?.dayBalance == Array(repeating: nil, count: 10))
        #expect(unknown.overview.balance == [nil])
        let encoded = try JSONEncoder().encode(unknown)
        #expect(try Dashboard.decode(encoded).overview.balance == [nil])
    }

    @Test func sourceNullsAndOpeningFromAFilteredBookingDecode() throws {
        // The source's balance fields are JSON too; no unknown value may be decoded as zero.
        struct Balances: Decodable {
            let openingBalance: Double?
            let balanceByDay: [String: Double?]
        }
        let context = try #require(JSContext())
        let url = try #require(AresiumEngine.bundledScriptURL())
        context.evaluateScript(try String(contentsOf: url, encoding: .utf8))
        let call = try #require(context.evaluateScript(
            "(json) => JSON.stringify(AresiumEngine.buildDashboardSource(JSON.parse(json)))"))
        func balances(_ rows: [SourcePayment]) throws -> Balances {
            let json = String(decoding: try JSONEncoder().encode(input(rows)), as: UTF8.self)
            let answer = try #require(call.call(withArguments: [json])?.toString())
            #expect(context.exception == nil)
            return try JSONDecoder().decode(Balances.self, from: Data(answer.utf8))
        }
        let unknown = try balances([payment("unknown", "2026-02-04", -2, nil)])
        #expect(unknown.openingBalance == nil && unknown.balanceByDay.values.allSatisfy { $0 == nil })
        #expect(unknown.balanceByDay.keys.contains("2026-02-01"))
        let opening = try balances([
            payment("funding", "2026-01-31", 100, 100, raw: .object(["Type": .string("General Card Deposit")])),
            payment("purchase", "2026-02-04", -2, nil, account: "paypal")
        ])
        #expect(opening.openingBalance == 100 && opening.balanceByDay.values.allSatisfy { $0 == 100 })
    }

    @Test func genuineStatementOrderResolvesACircuitAndMissingOrderKeepsTheFallback() async throws {
        let engine = try PhoneTest.engine()
        let a = payment("a", "2026-02-03", -100, 900, order: 1)
        let b = payment("b", "2026-02-03", 100, 1000, order: 2)
        for rows in [[a, b], [b, a]] {
            #expect(try await engine.dashboard(input(rows)).byMonth["2026-02"]?.endBalance == 1000)
        }
        var unorderedA = a, unorderedB = b
        unorderedA.statementOrder = nil
        unorderedB.statementOrder = nil
        #expect(try await engine.dashboard(input([unorderedB, unorderedA])).byMonth["2026-02"]?.endBalance == 900)
        #expect(try await engine.dashboard(input([unorderedA, unorderedB])).byMonth["2026-02"]?.endBalance == 1000)
    }

    @Test func phoneAdapterPassesStableAccountIDsAndNeverInventsStatementOrder() async throws {
        let engine = try PhoneTest.engine()
        let catalog = try await engine.catalog()
        let list = PhoneCategoryList(catalog: catalog, chosen: [ChosenCategory(id: "groceries", order: 0)])
        let rows = [
            LedgerPayment(id: "a", account: "fictional-current", source: "bank", externalId: "a", bookingDate: "2026-02-03",
                          amount: "-10.00", currency: "EUR", text: "Fictional shop", balance: "90.00",
                          category: "groceries", categorySource: .manual, extraCategories: [], sequence: 17),
            LedgerPayment(id: "b", account: "fictional-savings", source: "bank", externalId: "b", bookingDate: "2026-02-03",
                          amount: "-5.00", currency: "EUR", text: "Fictional shop", balance: "45.00",
                          category: "groceries", categorySource: .manual, extraCategories: [], sequence: 18)
        ]
        let source = PhoneDashboard.input(payments: rows, list: list, today: "2026-02-10")
        #expect(source.transactions.map(\.accountId) == rows.map(\.account))
        #expect(source.transactions.allSatisfy { $0.statementOrder == nil })
        #expect(try await engine.dashboard(source).byMonth["2026-02"]?.endBalance == 135)
    }

    @Test func chartGapsKeepIndicesAndSeparateKnownStretches() {
        let points = ChartBalances.points([nil, 0, 10, nil, -5, nil]) { index, value, segment in
            ChartPoint(index: index, label: String(index), value: value, segment: segment)
        }
        #expect(points.map(\.index) == [1, 2, 4])
        #expect(points.map(\.value) == [0, 10, -5])
        #expect(points[0].segment == points[1].segment && points[1].segment != points[2].segment)
        #expect(ChartBalances.points([nil, nil]) { index, value, segment in
            ChartPoint(index: index, label: "", value: value, segment: segment)
        }.isEmpty)
    }
}
