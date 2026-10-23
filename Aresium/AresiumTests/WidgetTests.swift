import Foundation
import SwiftUI
import UIKit
import Testing
@testable import Aresium

@MainActor
struct WidgetTests {
    private func directory() throws -> URL {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("build/WidgetTests/" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func serverDashboard() throws -> Dashboard {
        try Dashboard.decode(Data(contentsOf: URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("server-dashboard.sample.json")))
    }

    @Test func snapshotCopiesServerValuesAndUsesLastMonth() throws {
        let dashboard = try serverDashboard()
        let snapshot = try #require(WidgetSnapshot(dashboard: dashboard))
        let month = try #require(dashboard.months.last)
        let data = try #require(dashboard.byMonth[month.key])
        #expect(snapshot.monthKey == "2026-06")
        #expect(snapshot.monthKey == month.key)
        #expect(snapshot.monthLabel == month.label)
        #expect(month.days == 11)
        #expect(snapshot.daysInMonth == 30)
        #expect(snapshot.dayExpenseRunning == data.dayExpenseRunning)
        #expect(snapshot.dayExpenseRunning == [600.32, 671.92, 770.12, 832.63, 908.63, 959.28, 981.35, 1015.15, 1066.06, 1115.44, 1187.09])
        #expect(snapshot.expense == data.expense)
        #expect(snapshot.newestTransactionDate == dashboard.transactions.map(\.date).max())
        #expect(snapshot.categories.map(\.name) == dashboard.categories.filter { $0.kind == .spend }.map(\.name))
        for category in snapshot.categories {
            let meta = try #require(dashboard.categories.first { $0.name == category.name })
            #expect(category.icon == meta.icon)
            #expect(category.color == meta.color)
            #expect(category.total == data.categories.first { $0.name == category.name }?.total ?? 0)
        }
        #expect(snapshot.category(named: "Clothes")?.total == 0)
        #expect(snapshot.category(named: "Income") == nil)
        #expect(snapshot.category(named: "Transfer") == nil)
        #expect(try JSONDecoder().decode(WidgetSnapshot.self, from: JSONEncoder().encode(snapshot)) == snapshot)
    }

    @Test func fullMonthLengthIncludesLeapFebruaryAndDoesNotUsePartialDays() throws {
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(serverDashboard())) as? [String: Any])
        json["months"] = [["key": "2028-02", "label": "February 2028", "short": "Feb", "year": 2028,
                           "month": 1, "days": 3, "partial": true]]
        let original = try #require(json["byMonth"] as? [String: Any])
        json["byMonth"] = ["2028-02": original["2026-06"]!]
        let dashboard = try Dashboard.decode(JSONSerialization.data(withJSONObject: json))
        #expect(WidgetSnapshot(dashboard: dashboard)?.daysInMonth == 29)
        json["months"] = []
        #expect(WidgetSnapshot(dashboard: try Dashboard.decode(JSONSerialization.data(withJSONObject: json))) == nil)
    }

    private func snapshot(_ categories: [(String, Double)]) throws -> WidgetSnapshot {
        let json: [String: Any] = ["monthKey": "2026-10", "monthLabel": "October 2026", "daysInMonth": 31,
                                  "dayExpenseRunning": [99.25], "expense": 99.25,
                                  "categories": categories.map { ["name": $0.0, "total": $0.1, "icon": "Tag", "color": "#FFFFFF"] }]
        return try JSONDecoder().decode(WidgetSnapshot.self, from: JSONSerialization.data(withJSONObject: json))
    }

    @Test func defaultsPreferGroceriesAndDrogerieEvenAtZero() throws {
        let data = try snapshot([("Rent", 900), ("Travel", 300), ("Groceries", 0), ("Drogerie", 0)])
        #expect(data.defaultCategoryNames == ["Groceries", "Drogerie"])
    }

    @Test func missingDefaultsUseBiggestDistinctNonRentCategories() throws {
        #expect(try snapshot([("Rent", 900), ("Travel", 300), ("Groceries", 20)]).defaultCategoryNames == ["Groceries", "Travel"])
        #expect(try snapshot([("Rent", 900), ("Drogerie", 500), ("Travel", 300)]).defaultCategoryNames == ["Travel", "Drogerie"])
        #expect(try snapshot([("Rent", 900), ("Dining", 40), ("Travel", 300), ("Health", 100)]).defaultCategoryNames == ["Travel", "Health"])
        #expect(try snapshot([("Rent", 900), ("Travel", 300)]).defaultCategoryNames == ["Travel"])
        #expect(try snapshot([("Rent", 900)]).defaultCategoryNames.isEmpty)
        #expect(try snapshot([]).defaultCategoryNames.isEmpty)
    }

    @Test(arguments: ["Personal care", "Bäckerei & Café", "Food/drinks", "100% fun? #1", "日本語"])
    func categoryURLRoundTrips(name: String) {
        let destination = AresiumURL.category(name)
        #expect(AresiumURL(url: destination.url) == destination)
        #expect(destination.url.scheme == "aresium")
        #expect(destination.url.host == "category")
    }

    @Test func startURLAndFileImportsStaySeparate() {
        #expect(AresiumURL(url: AresiumURL.start.url) == .start)
        #expect(AresiumURL(url: URL(fileURLWithPath: "/fictional/import.csv")) == nil)
        for value in ["https://category/Groceries", "aresium://category/", "aresium://category/one/two",
                      "aresium://category/one?token=fictional", "aresium://unknown"] {
            #expect(AresiumURL(url: URL(string: value)!) == nil)
        }
    }

    @Test func sampleReloadPublishesSnapshotAndThemeThenLogoutDeletesIt() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let files = WidgetSnapshotStore(directory: root)
        var reloads = 0
        let publisher = WidgetSnapshotPublisher(store: files, reloadTimelines: { reloads += 1 })
        let session = EmpireSession(storage: WidgetMemoryTokens(), restoreOnLaunch: false, widgetPublisher: publisher)
        let dashboard = DashboardStore(session: session, sample: true)
        #expect(files.load() == nil)
        await dashboard.reload()
        #expect(dashboard.error == nil)
        #expect(files.load() == WidgetSnapshot.sample)
        #expect(reloads == 1)
        for theme in AppTheme.allCases {
            dashboard.setWidgetTheme(theme)
            #expect(files.theme == theme)
        }
        session.logOut()
        #expect(files.load() == nil)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent("widget-snapshot.json").path))
        #expect(files.theme == .red)
        #expect(reloads == 5)
        #expect(session.error == nil)
        // Sample logout has no token change; clearing the dashboard must also remove the file.
        await dashboard.reload()
        #expect(files.load() != nil)
        dashboard.clear()
        #expect(files.load() == nil)
        #expect(dashboard.error == nil)
    }

    @Test func absentOrCorruptSnapshotShowsEmptyStateAndDefaultsToDark() throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let files = WidgetSnapshotStore(directory: root)
        #expect(files.load() == nil)
        #expect(files.theme == .dark)
        try Data("invalid".utf8).write(to: root.appendingPathComponent("widget-snapshot.json"))
        #expect(files.load() == nil)
        try files.delete()
        try files.delete()
    }

    @Test func liveReloadPublishesButFailureAndLateResponseAfterLogoutCannotReplaceSnapshot() async throws {
        let root = try directory()
        defer { try? FileManager.default.removeItem(at: root) }
        let files = WidgetSnapshotStore(directory: root)
        var reloads = 0
        let publisher = WidgetSnapshotPublisher(store: files, reloadTimelines: { reloads += 1 })
        let transport = WidgetTestTransport(data: try JSONEncoder().encode(serverDashboard()))
        let session = EmpireSession(storage: WidgetMemoryTokens(), client: EmpireAuthClient(transport: transport),
                                    restoreOnLaunch: false, widgetPublisher: publisher)
        await session.login(email: "fictional@example.invalid", password: "fictional-password")
        #expect(session.token != nil)
        let dashboard = DashboardStore(session: session, client: APIClient(transport: transport))
        await dashboard.reload()
        let saved = try #require(files.load())
        #expect(saved == WidgetSnapshot(dashboard: try serverDashboard()))
        #expect(reloads == 1)
        transport.status = 500
        await dashboard.reload()
        #expect(dashboard.error != nil)
        #expect(files.load() == saved)
        #expect(reloads == 1)
        transport.status = 200
        transport.pause = true
        let pending = Task { await dashboard.reload() }
        await transport.waitUntilPaused()
        session.logOut()
        #expect(files.load() == nil)
        transport.resume()
        await pending.value
        #expect(files.load() == nil)
        #expect(reloads == 2)
    }

    @Test func widgetDateAndMoneyFormatting() {
        #expect(WidgetFormatting.freshness("2026-10-22") == "up to 22 Oct")
        #expect(WidgetFormatting.freshness(nil) == nil)
        #expect(WidgetFormatting.freshness("invalid") == nil)
        #expect(Money.precise(51.68) == "€51.68")
        #expect(CategorySymbol.name(for: "Trash2") == "trash")
    }

    /// simctl has no Home Screen widget-placement command. Render the same content at widget sizes.
    @Test func renderWidgetImages() throws {
        AppFont.register()
        let sample = try #require(WidgetSnapshot.sample)
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("build")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        func render<V: View>(_ view: V, name: String, width: CGFloat, theme: AppTheme = .dark) throws {
            let renderer = ImageRenderer(content: view.padding(16)
                .frame(width: width, height: 170)
                .background { Wall(palette: Palette(theme: theme)) }
                .clipShape(RoundedRectangle(cornerRadius: 22))
                .environment(\.colorScheme, theme == .light ? .light : .dark))
            renderer.scale = 3
            let data = try #require(renderer.uiImage?.pngData())
            #expect(data.count > 1000)
            try data.write(to: root.appendingPathComponent(name + ".png"))
        }
        try render(SpendingWidgetView(snapshot: sample, theme: .dark), name: "05-medium", width: 364)
        try render(CategoriesWidgetView(snapshot: sample, firstCategory: nil, secondCategory: nil, theme: .dark),
                   name: "05-small", width: 170)
        try render(CategoriesWidgetView(snapshot: nil, firstCategory: nil, secondCategory: nil, theme: .dark),
                   name: "05-empty", width: 170)
        for theme in [AppTheme.light, .red] {
            try render(SpendingWidgetView(snapshot: sample, theme: theme), name: "05-medium-" + theme.rawValue, width: 364, theme: theme)
            try render(CategoriesWidgetView(snapshot: sample, firstCategory: "Uncategorised", secondCategory: "Dining", theme: theme),
                       name: "05-small-" + theme.rawValue, width: 170, theme: theme)
        }
    }
}

@MainActor
private final class WidgetMemoryTokens: TokenStorage {
    private var token: String?
    func read() throws -> String? { token }
    func save(_ token: String) throws { self.token = token }
    func delete() throws { token = nil }
}

@MainActor
private final class WidgetTestTransport: HTTPTransport {
    let data: Data
    var status = 200
    var pause = false
    private var pending: CheckedContinuation<Void, Never>?
    private var waiter: CheckedContinuation<Void, Never>?

    init(data: Data) { self.data = data }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        if request.url?.path.contains("auth-with-password") == true {
            return (Data(#"{"token":"fictional-token","record":{"id":"fictional-user","approved":true,"services":["aresium"]}}"#.utf8), response)
        }
        if pause {
            await withCheckedContinuation {
                pending = $0
                waiter?.resume()
                waiter = nil
            }
        }
        return (data, response)
    }

    func waitUntilPaused() async {
        if pending != nil { return }
        await withCheckedContinuation { waiter = $0 }
    }

    func resume() {
        pending?.resume()
        pending = nil
    }
}
