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
        try await Task.sleep(for: .milliseconds(4700))
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
    private var requestWaiter: CheckedContinuation<Void, Never>?
    init(status: Int = 200, data: Data = Data()) { self.status = status; self.data = data }
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        requestWaiter?.resume()
        requestWaiter = nil
        if let failure { throw failure }
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
