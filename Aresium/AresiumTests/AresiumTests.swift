import Foundation
import Security
import CoreText
import UIKit
import Testing
@testable import Aresium

@MainActor
struct AresiumTests {
    @Test func sampleDecodesAndRoundTrips() throws {
        let dashboard = try Dashboard.sample()
        #expect(dashboard.version == 2)
        #expect(dashboard.months.map(\.key) == ["2026-08", "2026-09", "2026-10"])
        #expect(dashboard.months.map(\.partial) == [false, false, true])
        #expect(dashboard.transactions.count == 25)
        #expect(dashboard.categories.contains { $0.kind == .income })
        #expect(dashboard.categories.contains { $0.kind == .transfer })
        #expect(dashboard.transactions.first { $0.id == "sample-21" }?.incomeBuckets == ["Refunds"])
        #expect(dashboard.transactions.first { $0.id == "sample-24" }?.incomeBuckets == ["Other"])
        let roundTrip = try Dashboard.decode(JSONEncoder().encode(dashboard))
        #expect(roundTrip.total.expense == dashboard.total.expense)
        #expect(roundTrip.transactions.map(\.id) == dashboard.transactions.map(\.id))
        for month in dashboard.months {
            let data = try #require(dashboard.byMonth[month.key])
            #expect(data.dayExpense.count == month.days)
            #expect(data.dayIncome.count == month.days)
            #expect(data.dayBalance.count == month.days)
        }
        for series in Array(dashboard.spend.values) + Array(dashboard.income.values) {
            #expect(series.months.count == dashboard.months.count)
            for month in dashboard.months { #expect(series.days[month.key]?.count == month.days) }
        }
    }

    @Test func rejectsDifferentAPIVersion() throws {
        let data = try JSONEncoder().encode(Dashboard.sample())
        let json = String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\"version\":2", with: "\"version\":1")
        #expect(throws: DashboardError.self) { try Dashboard.decode(Data(json.utf8)) }
    }

    @Test func categoryMonthsKeepWebsiteOrderAndFilterZeroValues() async throws {
        let store = sampleStore()
        await store.reload()
        #expect(store.months(category: "Groceries", side: .expenses).map(\.month.key) == ["2026-08", "2026-09", "2026-10"])
        #expect(store.months(category: "Groceries", side: .expenses).map(\.total) == [107, 162.5, 147.1])
        #expect(store.months(category: "Savings", side: .income).map(\.month.key) == ["2026-09", "2026-10"])
        #expect(store.months(category: "Savings", side: .income).map(\.total) == [100, 2500])
        #expect(store.months(category: "Uncategorised", side: .expenses).isEmpty)
        #expect(store.months(category: "Missing", side: .income).isEmpty)
        #expect(store.error == nil)
        #expect(!store.isLoading)
    }

    @Test func spendTransactionsFilterSortAndMarkAddedTags() async {
        let store = sampleStore()
        await store.reload()
        let rows = store.transactions(category: "Groceries", month: "2026-10", side: .expenses)
        #expect(rows.map(\.id) == ["sample-19", "sample-21", "sample-22", "sample-23"])
        #expect(rows.map(\.transaction.day) == [3, 8, 12, 15])
        #expect(rows.map(\.tagged) == [false, false, true, false])
        #expect(rows[1].transaction.amount == 12.4)
        #expect(store.transactions(category: "Groceries", month: "2026-07", side: .expenses).isEmpty)
    }

    @Test func incomeTransactionsUseServerBucketMembershipAndPrimaryBucket() async {
        let store = sampleStore()
        await store.reload()
        let added = store.transactions(category: "Savings", month: "2026-10", side: .income)
        #expect(added.map(\.id) == ["sample-17"])
        #expect(added.map(\.tagged) == [true])
        #expect(store.transactions(category: "Salary", month: "2026-10", side: .income).map(\.tagged) == [false])
        let refunds = store.transactions(category: "Refunds", month: "2026-10", side: .income)
        #expect(refunds.map(\.id) == ["sample-21"])
        #expect(refunds.map(\.tagged) == [false])
        #expect(store.transactions(category: "Other", month: "2026-10", side: .income).map(\.id) == ["sample-24"])
    }

    @Test func totalsAndChartsAreReadFromContract() async throws {
        let store = sampleStore()
        await store.reload()
        let dashboard = try #require(store.dashboard)
        #expect(store.currentMonth?.key == "2026-10")
        #expect(store.rangeLabel(current: true) == "October 2026")
        #expect(store.rangeLabel(current: false) == "August 2026 – October 2026")
        #expect(store.totals(current: true)?.expense == 935.1)
        #expect(store.totals(current: true)?.income == 2537.4)
        #expect(store.totals(current: false)?.income == dashboard.total.income)
        // These overlapping rows must never become the headline income total.
        #expect(store.rows(side: .income, current: true).map(\.total) == [2500, 2500, 25, 12.4])
        #expect(store.startChart(side: .expenses, current: true).map(\.value) == dashboard.byMonth["2026-10"]?.dayExpense)
        #expect(store.startChart(side: .income, current: false).map(\.value) == dashboard.overview.income)
        #expect(store.categoryChart("Groceries", side: .expenses).map(\.value) == dashboard.spend["Groceries"]?.months)
        #expect(store.category("Refunds", side: .income)?.icon == "RotateCcw")
    }

    @Test func APIClientSendsBearerAndDecodes() async throws {
        let transport = FakeTransport(data: try JSONEncoder().encode(Dashboard.sample()))
        var unauthorized = false
        let dashboard = try await APIClient(transport: transport).dashboard(token: "fictional-token") { unauthorized = true }
        let request = try #require(transport.requests.first)
        #expect(request.url?.absoluteString == "https://aresium.de/api/data")
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fictional-token")
        #expect(dashboard.version == 2)
        #expect(!unauthorized)
    }

    @Test func APIUnauthorizedLogsOutAndDeletesStoredToken() async throws {
        let storage = MemoryTokenStorage()
        let session = EmpireSession(storage: storage, client: EmpireAuthClient(transport: FakeTransport(data: authResponse())))
        await session.login(email: "fictional@example.invalid", password: "fictional-password")
        #expect(session.token != nil)
        var unauthorized = false
        do {
            _ = try await APIClient(transport: FakeTransport(status: 401)).dashboard(token: "fictional-token") {
                unauthorized = true
                session.logOut()
            }
            Issue.record("Expected unauthorized")
        } catch {
            #expect(error is HTTPError)
        }
        #expect(unauthorized)
        #expect(session.token == nil)
        #expect(storage.token == nil)
    }

    @Test func serverFailureDoesNotLogOut() async {
        var unauthorized = false
        do {
            _ = try await APIClient(transport: FakeTransport(status: 503, data: Data(#"{"message":"Temporarily unavailable"}"#.utf8)))
                .dashboard(token: "fictional-token") { unauthorized = true }
            Issue.record("Expected server failure")
        } catch { #expect(error.localizedDescription == "Temporarily unavailable") }
        #expect(!unauthorized)
    }

    @Test func loginUsesPocketBaseBodyAndSecureStorage() async throws {
        let storage = MemoryTokenStorage()
        let transport = FakeTransport(data: authResponse())
        let session = EmpireSession(storage: storage, client: EmpireAuthClient(transport: transport))
        await session.login(email: "fictional@example.invalid", password: "fictional-password")
        let request = try #require(transport.requests.first)
        #expect(request.url?.path == "/api/collections/users/auth-with-password")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let body = try JSONDecoder().decode([String: String].self, from: #require(request.httpBody))
        #expect(body == ["identity": "fictional@example.invalid", "password": "fictional-password"])
        #expect(session.token == "fictional-token")
        #expect(storage.token == "fictional-token")
        #expect(session.error == nil)
    }

    @Test func restoreRenewsWithRawAuthorizationHeader() async throws {
        let storage = MemoryTokenStorage(token: "old-fictional-token")
        let transport = FakeTransport(data: authResponse())
        let session = EmpireSession(storage: storage, client: EmpireAuthClient(transport: transport))
        await session.restore()
        let request = try #require(transport.requests.first)
        #expect(request.url?.path == "/api/collections/users/auth-refresh")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "old-fictional-token")
        #expect(storage.token == "fictional-token")
        #expect(session.token == "fictional-token")
        #expect(!session.isRestoring)
    }

    @Test(arguments: [400, 401]) func expiredRefreshDeletesToken(status: Int) async {
        let storage = MemoryTokenStorage(token: "old-fictional-token")
        let session = EmpireSession(storage: storage, client: EmpireAuthClient(transport: FakeTransport(status: status)))
        await session.restore()
        #expect(storage.token == nil)
        #expect(session.token == nil)
        #expect(!session.isRestoring)
        #expect(!session.needsRestoreRetry)
    }

    @Test func refreshNetworkFailureKeepsSavedTokenForRetry() async {
        let storage = MemoryTokenStorage(token: "old-fictional-token")
        let transport = FakeTransport()
        transport.failure = URLError(.notConnectedToInternet)
        let session = EmpireSession(storage: storage, client: EmpireAuthClient(transport: transport))
        await session.restore()
        #expect(storage.token == "old-fictional-token")
        #expect(session.token == nil)
        #expect(session.error != nil)
        #expect(session.needsRestoreRetry)
        #expect(!session.isRestoring)
    }

    @Test func loginShowsPocketBaseMessage() async {
        let session = EmpireSession(storage: MemoryTokenStorage(), client: EmpireAuthClient(transport:
            FakeTransport(status: 403, data: Data(#"{"message":"Confirm your email first."}"#.utf8))))
        await session.login(email: "fictional@example.invalid", password: "fictional-password")
        #expect(session.error == "Confirm your email first.")
        #expect(session.token == nil)
    }

    @Test func accountWithoutAresiumAccessIsNotStored() async {
        let storage = MemoryTokenStorage()
        let response = Data(#"{"token":"fictional-token","record":{"id":"fictional-user","approved":true,"services":["empire"]}}"#.utf8)
        let session = EmpireSession(storage: storage, client: EmpireAuthClient(transport: FakeTransport(data: response)))
        await session.login(email: "fictional@example.invalid", password: "fictional-password")
        #expect(session.token == nil)
        #expect(storage.token == nil)
        #expect(session.error == "This account has no access to Aresium.")
    }

    @Test func failedReloadPreservesStaleDashboard() async throws {
        let transport = FakeTransport(data: try JSONEncoder().encode(Dashboard.sample()))
        let session = EmpireSession(storage: MemoryTokenStorage(), client: EmpireAuthClient(transport: FakeTransport(data: authResponse())))
        await session.login(email: "fictional@example.invalid", password: "fictional-password")
        let store = DashboardStore(session: session, client: APIClient(transport: transport))
        await store.reload()
        #expect(store.dashboard?.transactions.count == 25)
        transport.failure = URLError(.notConnectedToInternet)
        await store.reload()
        #expect(store.dashboard?.transactions.count == 25)
        #expect(store.error != nil)
        #expect(!store.isLoading)
        store.clear()
        #expect(store.dashboard == nil)
        #expect(store.error == nil)
    }

    @Test func keychainSavesReadsUpdatesAndDeletesOnSimulator() throws {
        let keychain = TokenKeychain(service: "de.ares-empire.aresium.tests.\(UUID().uuidString)")
        defer { try? keychain.delete() }
        #expect(try keychain.read() == nil)
        try keychain.save("fictional-token-one")
        #expect(try keychain.read() == "fictional-token-one")
        try keychain.save("fictional-token-two")
        #expect(try keychain.read() == "fictional-token-two")
        try keychain.delete()
        #expect(try keychain.read() == nil)
        try keychain.delete()
    }

    @Test func lateUnauthorizedResponseCannotLogOutANewerSession() async throws {
        let session = EmpireSession(storage: MemoryTokenStorage(), client: EmpireAuthClient(transport: FakeTransport(data: authResponse())))
        await session.login(email: "fictional@example.invalid", password: "fictional-password")
        let transport = PendingAPITransport(data: try JSONEncoder().encode(Dashboard.sample()))
        let store = DashboardStore(session: session, client: APIClient(transport: transport))
        let oldReload = Task { await store.reload() }
        await transport.waitForFirstRequest()
        #expect(store.isLoading)
        session.logOut()
        store.clear()
        #expect(!store.isLoading)
        await session.login(email: "fictional@example.invalid", password: "fictional-password")
        await store.reload()
        #expect(store.dashboard?.transactions.count == 25)
        transport.finishFirstRequest(status: 401)
        await oldReload.value
        #expect(session.token == "fictional-token")
        #expect(store.dashboard?.transactions.count == 25)
        #expect(store.error == nil)
        #expect(!store.isLoading)
    }

    @Test func formattingMatchesWebsite() {
        #expect(Money.total(1234.56) == "€1,235")
        #expect(Money.total(12.5) == "€13")
        #expect(Money.total(0) == "€0")
        #expect(Money.transaction(-1234.5) == "−1,234.50")
        #expect(Money.transaction(12.4) == "+12.40")
        #expect(CategorySymbol.name(for: "ShoppingCart") == "cart")
        #expect(CategorySymbol.name(for: "NewIcon") == "tag")
        let days = (0..<23).map { ChartPoint(index: $0, label: String($0 + 1), value: 0) }
        #expect(ChartAxis.ticks(days) == [0, 5, 10, 15, 20, 22])
        #expect(ChartAxis.ticks(Array(days.prefix(3))) == [0, 1, 2])
        #expect(ChartAxis.ticks([]).isEmpty)
    }

    @Test func bundledFontsAndCategorySymbolsResolve() {
        AppFont.register()
        for name in [AppFont.textName, AppFont.numberName] {
            let font = CTFontCreateWithName(name as CFString, 16, nil)
            #expect(CTFontCopyPostScriptName(font) as String == name)
        }
        for icon in ["Beer", "CircleHelp", "Code", "Dumbbell", "GraduationCap", "Handshake", "House",
                     "Laptop", "Palmtree", "Pill", "Receipt", "Repeat", "RotateCcw", "Scissors", "Shirt",
                     "ShoppingBag", "ShoppingCart", "SprayCan", "Tag", "TrainFront", "TrendingUp", "Tv",
                     "Users", "Utensils", "Wallet"] {
            #expect(UIImage(systemName: CategorySymbol.name(for: icon)) != nil)
        }
    }

    private func sampleStore() -> DashboardStore {
        DashboardStore(session: EmpireSession(storage: MemoryTokenStorage()), sample: true)
    }
}

@MainActor
private final class FakeTransport: HTTPTransport {
    var requests: [URLRequest] = []
    var status: Int
    var data: Data
    var failure: (any Error)?
    init(status: Int = 200, data: Data = Data()) { self.status = status; self.data = data }
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        if let failure { throw failure }
        return (data, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

@MainActor
private final class MemoryTokenStorage: TokenStorage {
    var token: String?
    init(token: String? = nil) { self.token = token }
    func read() throws -> String? { token }
    func save(_ token: String) throws { self.token = token }
    func delete() throws { token = nil }
}

@MainActor
private final class PendingAPITransport: HTTPTransport {
    let data: Data
    private var requests = 0
    private var pending: CheckedContinuation<(Data, HTTPURLResponse), Error>?
    private var waiter: CheckedContinuation<Void, Never>?
    init(data: Data) { self.data = data }
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests += 1
        if requests == 1 {
            return try await withCheckedThrowingContinuation {
                pending = $0
                waiter?.resume()
                waiter = nil
            }
        }
        return (data, response(status: 200))
    }
    func waitForFirstRequest() async {
        if requests > 0 { return }
        await withCheckedContinuation { waiter = $0 }
    }
    func finishFirstRequest(status: Int) {
        pending?.resume(returning: (Data(), response(status: status)))
        pending = nil
    }
    private func response(status: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: URL(string: "https://aresium.de/api/data")!, statusCode: status, httpVersion: nil, headerFields: nil)!
    }
}

@MainActor
private func authResponse() -> Data {
    Data(#"{"token":"fictional-token","record":{"id":"fictional-user","approved":true,"services":["aresium"]}}"#.utf8)
}

/// The app must list exactly what the website lists. `server-dashboard.sample.json` is generated by the
/// Aresium server (`npm run sample`), and `server-dashboard.expected.json` holds the website's own answers
/// (web/public/app/data.js) for every category, income bucket and month of that sample. Regenerate both
/// with `node scripts/aresium-fixtures.mjs` when the contract changes.
@MainActor
struct ServerSampleMatchesWebsiteTests {
    private func fixture(_ name: String) throws -> Data {
        try Data(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent(name))
    }

    @Test func listsMatchTheWebsiteForEveryCategoryBucketAndMonth() async throws {
        let session = EmpireSession(storage: MemoryTokenStorage(), client: EmpireAuthClient(transport: FakeTransport(data: authResponse())))
        await session.login(email: "fictional@example.invalid", password: "fictional-password")
        let store = DashboardStore(session: session, client: APIClient(transport: FakeTransport(data: try fixture("server-dashboard.sample.json"))))
        await store.reload()
        let dashboard = try #require(store.dashboard)
        #expect(dashboard.overview.expense.count == dashboard.months.count)
        for month in dashboard.months { #expect(dashboard.byMonth[month.key]?.dayExpense.count == month.days) }

        let expected = try #require(try JSONSerialization.jsonObject(with: try fixture("server-dashboard.expected.json")) as? [String: Any])
        var compared = 0
        for (sideKey, side) in [("spend", DashboardSide.expenses), ("income", DashboardSide.income)] {
            for (name, entry) in try #require(expected[sideKey] as? [String: [String: Any]]) {
                let months = try #require(entry["months"] as? [[Any]])
                let rows = store.months(category: name, side: side)
                #expect(rows.map(\.month.key) == months.map { $0[0] as? String }, "\(sideKey) \(name) months")
                #expect(rows.map(\.total) == months.map { ($0[1] as? NSNumber)?.doubleValue }, "\(sideKey) \(name) totals")
                compared += months.count
                for (key, list) in try #require(entry["txns"] as? [String: [[Any]]]) {
                    let txns = store.transactions(category: name, month: key, side: side)
                    #expect(txns.map(\.id) == list.map { $0[0] as? String }, "\(sideKey) \(name) \(key) ids")
                    #expect(txns.map(\.tagged) == list.map { $0[1] as? Bool }, "\(sideKey) \(name) \(key) tagged")
                    compared += list.count
                }
            }
        }
        #expect(compared == 511)
    }
}
