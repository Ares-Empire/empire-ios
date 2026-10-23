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

    @Test func detailDecodesAndFormatsWebsiteRows() throws {
        let detail = try TransactionDetail.bundledSample()
        #expect(detail.id == "fictional-detail" && detail.currency == "EUR")
        #expect(detail.valueDate == "2026-10-03" && detail.balance == 1420.75)
        #expect(detail.category == "Groceries" && detail.categoryColor == "#E8B85C")
        #expect(detail.tags == ["Dining"] && detail.categorySource == "rule" && detail.categorized)
        #expect(detail.counterparty == "Sample Market" && detail.accountLabel == "Sample current account")
        #expect(detail.iban == nil && detail.source == "bank")
        #expect(detail.city == "Sample City" && detail.country == "DE")
        #expect(detail.trip == nil && detail.tripKind == nil && !detail.recurring)
        #expect(detail.placeType == "supermarket" && detail.externalId == "fictional-export-001")
        #expect(detail.signedAmount == "−42.50")
        #expect(detail.originalRows?.first { $0.label == "Amount" }?.value == "-42.5")
        #expect(detail.originalRows?.first { $0.label == "Note" }?.value == "—")
        #expect(!detail.rows.contains { ["Trip", "Recurring"].contains($0.label) })
        #expect(detail.rows.first { $0.label == "Balance after" }?.value == "€1,420.75")
        #expect(detail.rows.first { $0.label == "Location" }?.value == "Sample City, DE")
        let roundTrip = try JSONDecoder().decode(TransactionDetail.self, from: JSONEncoder().encode(detail))
        #expect(roundTrip.raw == detail.raw)
    }

    @Test func emptyDetailRowsAreHiddenAndZeroBalanceIsShown() throws {
        var json = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(TransactionDetail.bundledSample())) as? [String: Any])
        for field in ["valueDate", "counterparty", "city", "country", "categorySource", "account", "iban"] { json[field] = NSNull() }
        json["balance"] = 0
        json["description"] = ""
        json["placeType"] = "unknown"
        json["recurring"] = true
        json["trip"] = "Sample trip"
        json["tripKind"] = "travel"
        json["currency"] = "USD"
        json["raw"] = ["nested": ["sample": true], "list": [1, 2], "empty": ""]
        let detail = try JSONDecoder().decode(TransactionDetail.self, from: JSONSerialization.data(withJSONObject: json))
        #expect(detail.accountLabel == nil && detail.signedAmount == "−42.50 USD")
        #expect(detail.rows.map(\.label) == ["Source", "Booking date", "Balance after", "Trip", "Recurring", "External ID"])
        #expect(detail.rows.first { $0.label == "Balance after" }?.value == "€0.00")
        #expect(detail.rows.first { $0.label == "Trip" }?.value == "Sample trip (travel)")
        #expect(detail.originalRows?.first { $0.label == "empty" }?.value == "—")
    }

    @Test(arguments: ["detail", "category", "tags"])
    func transactionRequestsEncodeIDMethodBodyAndBearer(action: String) async throws {
        let transport = FakeTransport(data: try JSONEncoder().encode(TransactionDetail.bundledSample()))
        let client = APIClient(transport: transport)
        let id = "sample/id ?#%ä"
        var unauthorized = false
        let result: TransactionDetail
        switch action {
        case "category":
            result = try await client.switchCategory(id: id, category: "Dining", token: "fictional-token") { unauthorized = true }
        case "tags":
            result = try await client.setTransactionTags(id: id, categories: ["Dining", "Transport"], dropCurrent: true,
                                                         token: "fictional-token") { unauthorized = true }
        default:
            result = try await client.transactionDetail(id: id, token: "fictional-token") { unauthorized = true }
        }
        let request = try #require(transport.requests.first)
        let suffix = action == "detail" ? "" : "/" + action
        #expect(request.url?.absoluteString == "https://aresium.de/api/transaction/sample%2Fid%20%3F%23%25%C3%A4" + suffix)
        #expect(request.httpMethod == (action == "detail" ? "GET" : "POST"))
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fictional-token")
        #expect(request.timeoutInterval == 30 && result.category == "Groceries" && !unauthorized)
        if action == "detail" { #expect(request.httpBody == nil) }
        else {
            #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
            let bodyData = try #require(request.httpBody)
            let body = try #require(try JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
            if action == "category" {
                #expect(body.count == 1 && body["category"] as? String == "Dining")
            } else {
                #expect(body.count == 2)
                #expect(body["categories"] as? [String] == ["Dining", "Transport"])
                #expect(body["dropCurrent"] as? Bool == true)
            }
        }
    }

    @Test(arguments: ["detail", "category", "tags"])
    func transactionUnauthorizedUsesSameSessionHandling(action: String) async {
        let client = APIClient(transport: FakeTransport(status: 401))
        var unauthorized = false
        do {
            switch action {
            case "category": _ = try await client.switchCategory(id: "fictional", category: "Dining", token: "fictional-token") { unauthorized = true }
            case "tags": _ = try await client.setTransactionTags(id: "fictional", categories: [], dropCurrent: false, token: "fictional-token") { unauthorized = true }
            default: _ = try await client.transactionDetail(id: "fictional", token: "fictional-token") { unauthorized = true }
            }
            Issue.record("Expected unauthorized")
        } catch { #expect(error.localizedDescription == HTTPError.unauthorized.localizedDescription) }
        #expect(unauthorized)
    }

    @Test func choicesUseServerPickOrderForEachSign() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("server-dashboard.sample.json")
        let dashboard = try Dashboard.decode(Data(contentsOf: url))
        #expect(dashboard.recategorisationChoices(amount: -1).map(\.name) == dashboard.pick.spend)
        #expect(dashboard.recategorisationChoices(amount: 0).map(\.name) == dashboard.pick.spend)
        #expect(dashboard.recategorisationChoices(amount: 1).map(\.name) == dashboard.pick.income)
        #expect(dashboard.pick.spend.first == "Rent" && dashboard.categories.first?.name == "Groceries")
        #expect(!dashboard.recategorisationChoices(amount: 1).contains { $0.name == "Refunds" || $0.name == "Other" })
    }

    @Test(arguments: ["switch", "add", "drop"])
    func successfulChangeShowsReturnedDetailAndReloadsDashboard(action: String) async throws {
        let (dashboard, transport, store) = try await liveDetailStore()
        store.beginRecategorisation()
        #expect(store.extras == ["Dining"])
        if action == "switch" { store.select("Home") }
        else {
            store.mode = .add
            store.select("Transport")
            store.select("Groceries")
            #expect(store.extras == ["Dining", "Transport"])
        }
        var updated = try #require(try JSONSerialization.jsonObject(with: transport.data) as? [String: Any])
        updated["category"] = action == "add" ? "Groceries" : "Home"
        updated["categorySource"] = "manual"
        var nextDashboard = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(Dashboard.sample())) as? [String: Any])
        nextDashboard["transactions"] = []
        transport.responses = [(200, try JSONSerialization.data(withJSONObject: updated)),
                               (200, try JSONSerialization.data(withJSONObject: nextDashboard))]
        let before = transport.requests.count
        await store.save(dropCurrent: action == "drop")
        #expect(store.detail?.category == updated["category"] as? String)
        #expect(store.detail?.categorySource == "manual")
        #expect(!store.showsRecategorisation && !store.isSaving && store.saveError == nil)
        #expect(transport.requests.count == before + 2)
        #expect(transport.requests.last?.url?.path == "/api/data")
        #expect(dashboard.dashboard?.transactions.isEmpty == true)
        if action != "switch" {
            let bodyData = try #require(transport.requests[before].httpBody)
            let body = try #require(try JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
            #expect(body["categories"] as? [String] == ["Dining", "Transport"])
            #expect(body["dropCurrent"] as? Bool == (action == "drop"))
        }
    }

    @Test(arguments: ["switch", "add"])
    func failedChangeKeepsSheetSelectionsAndError(action: String) async throws {
        let (dashboard, transport, store) = try await liveDetailStore()
        store.beginRecategorisation()
        if action == "switch" { store.select("Home") }
        else { store.mode = .add; store.select("Transport") }
        transport.status = 400
        transport.data = Data(#"{"error":"unknown category"}"#.utf8)
        let before = transport.requests.count
        await store.save()
        #expect(store.showsRecategorisation && store.saveError == "unknown category" && !store.isSaving)
        #expect(store.detail?.category == "Groceries")
        #expect(store.target == (action == "switch" ? "Home" : nil))
        #expect(store.extras == (action == "switch" ? ["Dining"] : ["Dining", "Transport"]))
        #expect(transport.requests.count == before + 1 && dashboard.session.token != nil)
    }

    @Test func savingDisablesSelectionsAndDuplicateSubmissions() async throws {
        let (_, transport, store) = try await liveDetailStore()
        store.beginRecategorisation()
        store.select("Home")
        transport.responses = [(200, transport.data), (200, try JSONEncoder().encode(Dashboard.sample()))]
        let gate = RequestGate()
        transport.nextGate = gate
        let saving = Task { await store.save() }
        await gate.waitUntilPaused()
        #expect(store.isSaving && !store.canSave && !store.canRemoveCurrent)
        store.select("Transport")
        #expect(store.target == "Home")
        let before = transport.requests.count
        await store.save()
        #expect(transport.requests.count == before)
        gate.resume()
        await saving.value
        #expect(!store.isSaving && !store.showsRecategorisation)
    }

    @Test func successfulSaveSupersedesDashboardRefreshThatPredatesIt() async throws {
        let (dashboard, transport, store) = try await liveDetailStore()
        store.beginRecategorisation()
        store.select("Home")
        let gate = RequestGate()
        transport.nextGate = gate
        transport.responses = [(401, Data()), (200, transport.data), (200, try JSONEncoder().encode(Dashboard.sample()))]
        let oldReload = Task { await dashboard.reload() }
        await gate.waitUntilPaused()
        let before = transport.requests.count
        await store.save()
        #expect(transport.requests.count == before + 2 && dashboard.error == nil && !dashboard.isLoading)
        gate.resume()
        await oldReload.value
        #expect(dashboard.session.token != nil && dashboard.error == nil)
        #expect(dashboard.dashboard?.transactions.count == 25)
    }

    @Test func sampleDetailUsesSelectedRowAndCannotMutate() async throws {
        let dashboard = sampleStore()
        await dashboard.reload()
        for transaction in try #require(dashboard.dashboard).transactions {
            let store = dashboard.transactionDetailStore(for: transaction)
            await store.load()
            #expect(store.detail?.id == transaction.id && store.detail?.place == transaction.place)
            #expect(store.detail?.amount == transaction.amount && store.detail?.bookingDate == transaction.date)
            store.beginRecategorisation()
            store.select(try #require(store.choices.first { $0.name != store.detail?.category }).name)
            await store.save()
            #expect(store.showsRecategorisation && store.saveError == "Not available with sample data")
            store.mode = .add
            await store.save()
            #expect(store.saveError == "Not available with sample data")
        }
    }

    private func liveDetailStore() async throws -> (DashboardStore, FakeTransport, TransactionDetailStore) {
        let transport = FakeTransport(data: try JSONEncoder().encode(Dashboard.sample()))
        let session = EmpireSession(storage: MemoryTokenStorage(), client: EmpireAuthClient(transport: FakeTransport(data: authResponse())))
        await session.login(email: "fictional@example.invalid", password: "fictional-password")
        let dashboard = DashboardStore(session: session, client: APIClient(transport: transport))
        await dashboard.reload()
        let store = dashboard.transactionDetailStore(for: try #require(dashboard.dashboard?.transactions.first))
        transport.data = try JSONEncoder().encode(TransactionDetail.bundledSample())
        await store.load()
        return (dashboard, transport, store)
    }

    private func sampleStore() -> DashboardStore {
        DashboardStore(session: EmpireSession(storage: MemoryTokenStorage()), sample: true)
    }

    @Test func importRequestSendsTwoFilesAndBearer() async throws {
        let transport = FakeTransport(data: importResponse())
        let files = [ImportFile(name: "bank.csv", content: "fictional,bank\n1,2"),
                     ImportFile(name: "paypal.xml", content: "<fictional />")]
        var unauthorized = false
        let response = try await APIClient(transport: transport).importFiles(files, token: "fictional-token") { unauthorized = true }
        let request = try #require(transport.requests.first)
        #expect(transport.requests.count == 1)
        #expect(request.url?.absoluteString == "https://aresium.de/api/import")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fictional-token")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let body = try JSONDecoder().decode([String: [ImportFile]].self, from: #require(request.httpBody))
        #expect(body == ["files": files])
        #expect(response.results.first?.account == "Fictional bank")
        #expect(response.results.first?.total == 12)
        #expect(!unauthorized)
    }

    @Test func importReaderSkipsOtherExtensionsAndAcceptsUppercase() throws {
        let directory = try importDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let csv = directory.appendingPathComponent("bank.CSV")
        let xml = directory.appendingPathComponent("paypal.XmL")
        try Data("fictional csv".utf8).write(to: csv)
        try Data("<fictional />".utf8).write(to: xml)
        let ignored = directory.appendingPathComponent("missing.pdf")
        #expect(try ImportFileReader.read([ignored, csv, xml]).map(\.name) == ["bank.CSV", "paypal.XmL"])
        #expect(throws: ImportFileError.self) { try ImportFileReader.read([ignored]) }
    }

    @Test func importReaderAllowsExactly20MBAndNamesOversizeFile() throws {
        let directory = try importDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("large.csv")
        try Data(repeating: 65, count: ImportFileReader.maximumBytes).write(to: url)
        #expect(try ImportFileReader.read([url]).first?.content.utf8.count == ImportFileReader.maximumBytes)
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data([65]))
        try handle.close()
        do {
            _ = try ImportFileReader.read([url])
            Issue.record("Expected the 20 MB guard")
        } catch { #expect(error.localizedDescription == "large.csv is too large (max 20 MB)") }
    }

    @Test func importReaderReplacesInvalidUTF8LikeWebsiteFileText() throws {
        let directory = try importDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("latin1.csv")
        try Data([0x61, 0x3B, 0xE4, 0x0A]).write(to: url) // Latin-1 ä is invalid UTF-8.
        #expect(try ImportFileReader.read([url]).first?.content == "a;\u{FFFD}\n")
    }

    @Test func importSummariesMatchWebsite() throws {
        func summary(_ results: String) throws -> String {
            try JSONDecoder().decode(ImportResponse.self, from: Data("{\"results\":[\(results)]}".utf8)).summary
        }
        let one = #"{"name":"one.csv","added":1,"total":1,"account":"Fictional bank","skipped":false}"#
        let eleven = #"{"name":"eleven.xml","added":11,"total":11,"account":"Fictional bank","skipped":false}"#
        let skipped = #"{"name":"duplicate.csv","added":0,"total":1,"account":null,"skipped":true}"#
        let failed = #"{"name":"bad.csv","added":0,"total":0,"account":null,"skipped":false,"error":"Unknown format"}"#
        #expect(try summary("") == "0 new transactions imported")
        #expect(try summary(one) == "1 new transaction imported")
        #expect(try summary(one + "," + eleven) == "12 new transactions imported")
        #expect(try summary(one + "," + eleven + "," + skipped) == "12 new transactions imported · 1 skipped")
        #expect(try summary(skipped + "," + skipped) == "0 new transactions imported · 2 skipped")
        #expect(try summary(one + "," + one + "," + one + "," + failed) == "3 added · 1 file(s) failed")
        #expect(try summary(failed + "," + failed) == "0 added · 2 file(s) failed")
    }

    @Test(arguments: [400, 409]) func importFailureShowsServerError(status: Int) async throws {
        let session = await importSession()
        let dashboardTransport = FakeTransport()
        let store = DashboardStore(session: session, client: APIClient(transport: dashboardTransport))
        let text = status == 409 ? "an import is already running" : "no .csv/.xml files in request"
        let transport = FakeTransport(status: status, data: try JSONEncoder().encode(["error": text]))
        let imports = ImportStore(dashboard: store, client: APIClient(transport: transport))
        let directory = try importDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("bank.csv")
        try Data("fictional".utf8).write(to: url)
        await imports.receive([url])
        await imports.importPendingFiles()
        #expect(imports.banner?.message == text)
        #expect(imports.banner?.success == false)
        #expect(session.token != nil)
        #expect(dashboardTransport.requests.isEmpty)
        #expect(!imports.isBusy)
    }

    @Test func importUnauthorizedLogsOut() async {
        let session = await importSession()
        var unauthorized = false
        do {
            _ = try await APIClient(transport: FakeTransport(status: 401)).importFiles(
                [ImportFile(name: "bank.csv", content: "fictional")], token: "fictional-token") {
                    unauthorized = true
                    session.logOut()
                }
            Issue.record("Expected unauthorized")
        } catch { #expect(error.localizedDescription == "Your session expired. Please log in again.") }
        #expect(unauthorized)
        #expect(session.token == nil)
    }

    @Test func successfulImportReloadsDashboardEvenWithFailedFiles() async throws {
        let session = await importSession()
        let dashboardTransport = FakeTransport(data: try JSONEncoder().encode(Dashboard.sample()))
        let store = DashboardStore(session: session, client: APIClient(transport: dashboardTransport))
        let response = Data(#"{"results":[{"name":"bank.csv","added":3,"total":3,"account":"Fictional bank","skipped":false},{"name":"bad.xml","added":0,"total":0,"account":null,"skipped":false,"error":"Unknown format"}]}"#.utf8)
        let imports = ImportStore(dashboard: store, client: APIClient(transport: FakeTransport(data: response)))
        let directory = try importDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("bank.csv")
        try Data("fictional".utf8).write(to: url)
        await imports.receive([url])
        await imports.importPendingFiles()
        #expect(dashboardTransport.requests.map { $0.url?.path } == ["/api/data"])
        #expect(store.dashboard?.transactions.count == 25)
        #expect(imports.banner?.message == "3 added · 1 file(s) failed")
        #expect(imports.banner?.success == false)
        #expect(!imports.isBusy)
    }

    @Test func filesReceivedBeforeLoginAreRetainedAndImportedTogetherAfterLogin() async throws {
        let session = EmpireSession(storage: MemoryTokenStorage(), client: EmpireAuthClient(transport: FakeTransport(data: authResponse())), restoreOnLaunch: false)
        let dashboardTransport = FakeTransport(data: try JSONEncoder().encode(Dashboard.sample()))
        let store = DashboardStore(session: session, client: APIClient(transport: dashboardTransport))
        let transport = FakeTransport(data: importResponse())
        let imports = ImportStore(dashboard: store, client: APIClient(transport: transport))
        let directory = try importDirectory()
        let csv = directory.appendingPathComponent("bank.csv")
        let xml = directory.appendingPathComponent("paypal.xml")
        try Data("fictional bank".utf8).write(to: csv)
        try Data("<fictional />".utf8).write(to: xml)
        await imports.receive([csv])
        await imports.receive([xml])
        #expect(transport.requests.isEmpty)
        #expect(!imports.isBusy)
        try FileManager.default.removeItem(at: directory)
        await session.login(email: "fictional@example.invalid", password: "fictional-password")
        await imports.sessionChanged()
        #expect(transport.requests.count == 1)
        let body = try JSONDecoder().decode([String: [ImportFile]].self, from: #require(transport.requests.first?.httpBody))
        #expect(body["files"] == [ImportFile(name: "bank.csv", content: "fictional bank"), ImportFile(name: "paypal.xml", content: "<fictional />")])
        #expect(dashboardTransport.requests.count == 1)
        #expect(imports.banner?.message == "12 new transactions imported")
        #expect(imports.banner?.success == true)
        await imports.sessionChanged()
        #expect(transport.requests.count == 1)
    }

    @Test func importRefreshSupersedesAnOlderDashboardRequest() async throws {
        let session = await importSession()
        let dashboardTransport = PendingAPITransport(data: try JSONEncoder().encode(Dashboard.sample()))
        let store = DashboardStore(session: session, client: APIClient(transport: dashboardTransport))
        let oldReload = Task { await store.reload() }
        await dashboardTransport.waitForFirstRequest()
        let imports = ImportStore(dashboard: store, client: APIClient(transport: FakeTransport(data: importResponse())))
        let directory = try importDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("bank.csv")
        try Data("fictional".utf8).write(to: url)
        await imports.receive([url])
        await imports.importPendingFiles()
        #expect(store.dashboard?.transactions.count == 25)
        dashboardTransport.finishFirstRequest(status: 401)
        await oldReload.value
        #expect(session.token != nil)
        #expect(store.error == nil)
        #expect(store.dashboard?.transactions.count == 25)
    }

    @Test func incomingURLsAreAutomaticallyBatchedWhenLoggedIn() async throws {
        let session = await importSession()
        let dashboardTransport = FakeTransport(data: try JSONEncoder().encode(Dashboard.sample()))
        let store = DashboardStore(session: session, client: APIClient(transport: dashboardTransport))
        let transport = FakeTransport(data: importResponse())
        let imports = ImportStore(dashboard: store, client: APIClient(transport: transport))
        let directory = try importDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let csv = directory.appendingPathComponent("bank.csv")
        let xml = directory.appendingPathComponent("paypal.xml")
        try Data("fictional bank".utf8).write(to: csv)
        try Data("<fictional />".utf8).write(to: xml)
        await imports.receive([csv])
        await imports.receive([xml])
        #expect(imports.isBusy)
        #expect(transport.requests.isEmpty)
        await transport.waitForRequest()
        #expect(transport.requests.count == 1)
        let body = try JSONDecoder().decode([String: [ImportFile]].self, from: #require(transport.requests.first?.httpBody))
        #expect(body["files"]?.map(\.name) == ["bank.csv", "paypal.xml"])
        #expect(dashboardTransport.requests.count == 1)
        #expect(!imports.isBusy)
    }

    @Test func sampleImportButtonAndSharedFilesShowUnavailableWithoutReading() async {
        let transport = FakeTransport()
        let imports = ImportStore(dashboard: sampleStore(), client: APIClient(transport: transport))
        imports.showSampleUnavailable()
        #expect(imports.banner?.message == "Not available with sample data")
        await imports.receive([URL(fileURLWithPath: "/nonexistent/bank.csv")])
        #expect(imports.banner?.message == "Not available with sample data")
        #expect(transport.requests.isEmpty)
        #expect(!imports.isBusy)
    }

    @Test func importBannerDismissesAutomatically() async throws {
        let imports = ImportStore(dashboard: sampleStore())
        imports.showSampleUnavailable()
        #expect(imports.banner != nil)
        // Rendering tests can delay the dismissal task's initial scheduling on the main actor.
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(7))
        while imports.banner != nil, clock.now < deadline {
            try await clock.sleep(for: .milliseconds(50))
        }
        #expect(imports.banner == nil)
    }

    private func importSession() async -> EmpireSession {
        let session = EmpireSession(storage: MemoryTokenStorage(), client: EmpireAuthClient(transport: FakeTransport(data: authResponse())))
        await session.login(email: "fictional@example.invalid", password: "fictional-password")
        return session
    }

    private func importDirectory() throws -> URL {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let directory = root.appendingPathComponent("build/03-test-files/\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func importResponse() -> Data {
        Data(#"{"results":[{"name":"bank.csv","added":12,"total":12,"account":"Fictional bank","skipped":false}]}"#.utf8)
    }
}

@MainActor
private final class FakeTransport: HTTPTransport {
    var requests: [URLRequest] = []
    var status: Int
    var data: Data
    var failure: (any Error)?
    var responses: [(Int, Data)] = []
    var nextGate: RequestGate?
    private var requestWaiter: CheckedContinuation<Void, Never>?
    init(status: Int = 200, data: Data = Data()) { self.status = status; self.data = data }
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        requestWaiter?.resume()
        requestWaiter = nil
        if let failure { throw failure }
        let (status, data) = responses.isEmpty ? (status, data) : responses.removeFirst()
        if let gate = nextGate {
            nextGate = nil
            await gate.pause()
        }
        return (data, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
    func waitForRequest() async {
        if !requests.isEmpty { return }
        await withCheckedContinuation { requestWaiter = $0 }
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

@MainActor
private final class RequestGate {
    private var pending: CheckedContinuation<Void, Never>?
    private var waiter: CheckedContinuation<Void, Never>?
    func pause() async {
        await withCheckedContinuation {
            pending = $0
            waiter?.resume()
            waiter = nil
        }
    }
    func waitUntilPaused() async {
        if pending != nil { return }
        await withCheckedContinuation { waiter = $0 }
    }
    func resume() { pending?.resume(); pending = nil }
}
