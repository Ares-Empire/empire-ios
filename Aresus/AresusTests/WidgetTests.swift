import Foundation
import Security
import SwiftUI
import Testing
import WidgetKit
@testable import Aresus

/// The widget's status from an overview (aresus/docs/API.md samples), how it is saved, and how the widget chooses
/// between the server and the saved status.
struct WidgetStatusTests {
    @Test func oneIssueFromTheSample() throws {
        let overview: Overview = try sample("overview")
        let status = WidgetStatus(overview: overview)
        #expect(status.summary == "1 issue")
        #expect(status.state == .issue)
        #expect(status.issues == [.init(slug: "aresium", name: "Aresium", line: "Website down since 14:02 (502)")])
        #expect(status.counts == .init(issue: 1, active: 3, inactive: 4))      // the two planned ones are inactive
        #expect(status.serverIssue == nil)
        #expect(status.syncLine == "3 machines · last sync 4 min ago")
        #expect(status.checked == at("2026-10-24T12:09:00Z"))
        #expect(status.rows.map(\.name) == ["Aresium"])
        #expect(status.lockLines == ["1 issue · Aresium", "1 issue"])
        #expect(status.runningShare == 0.8)                                     // 3 active + the server of 5
    }

    @Test func allGood() throws {
        let status = WidgetStatus(overview: try AresusSamples(allGood: true).overview())
        #expect(status.summary == "All running")
        #expect(status.state == .active)
        #expect(status.issues.isEmpty && status.rows.isEmpty && status.issueCount == 0)
        #expect(status.counts == .init(issue: 0, active: 4, inactive: 4))
        #expect(status.lockLines == ["All running"])
        #expect(status.runningShare == 1)
    }

    @Test func aServerIssueCountsAndComesLast() throws {
        let status = WidgetStatus(overview: try overview(issues: ["aresium", "arestemis"], serverIssue: "Disk 92 % full"))
        #expect(status.summary == "3 issues")                                   // as the server counts: provinces + server
        #expect(status.state == .issue)
        #expect(status.serverIssue == "Disk 92 % full")
        #expect(status.counts.issue == 2)
        #expect(status.rows.map(\.id) == ["province-aresium", "province-arestemis", "server"])
        #expect(status.rows.last?.line == "Disk 92 % full")
        #expect(status.lockLines == ["3 issues · Aresium, Arestemis, Server", "3 issues · Aresium, Arestemis +1",
                                     "3 issues · Aresium +2", "3 issues"])
    }

    @Test func onlyTheServer() throws {
        let status = WidgetStatus(overview: try overview(issues: [], serverIssue: "Memory 95 % full"))
        #expect(status.summary == "1 issue" && status.state == .issue && status.issues.isEmpty)
        #expect(status.rows.map(\.name) == ["Server"])
        #expect(status.runningShare == 0.8)                                     // 4 active, the server not
    }

    @Test func issuesKeepTheServersOrder() throws {
        // The server sorts issues by name; the widget keeps whatever order it sends.
        let status = WidgetStatus(overview: try overview(issues: ["arestemis", "aresium"], serverIssue: nil))
        #expect(status.issues.map(\.slug) == ["arestemis", "aresium"])
        #expect(status.summary == "2 issues")
    }

    @Test @MainActor func rowsOpenTheirScreens() throws {
        let status = WidgetStatus(overview: try overview(issues: ["aresium"], serverIssue: "Disk 92 % full"))
        #expect(status.rows.map { AresusLink(url: $0.url) } == [.province("aresium"), .server])
        #expect(AresusLink(url: WidgetLink.home) == .home)
    }

    @Test func turnsStaleAfterAnHour() throws {
        let status = WidgetStatus(overview: try sample("overview"))
        #expect(!status.isStale(at: status.checked.addingTimeInterval(59 * 60)))
        #expect(status.isStale(at: status.checked.addingTimeInterval(60 * 60)))
        #expect(status.staleAt == status.checked.addingTimeInterval(3600))
    }

    /// The sample's provinces with `issues` (slugs) as issues, in that order first, and the server's issue.
    private func overview(issues: [String], serverIssue: String?) throws -> Overview {
        let base: Overview = try AresusSamples(allGood: true).overview()
        let lines = ["aresium": "Website down since 14:02 (502)", "arestemis": "Bot not answering since 13:51"]
        let issueProvinces = issues.compactMap { slug in base.provinces.first { $0.slug == slug } }.map {
            Province(slug: $0.slug, name: $0.name, logo: $0.logo, state: .issue, word: "Issue",
                     line: lines[$0.slug] ?? "Down", since: $0.since)
        }
        let server = base.server
        return Overview(version: 1, checked: base.checked, summary: "",
                        server: Server(host: server.host, diskUsed: server.diskUsed, memoryUsed: server.memoryUsed,
                                       load: server.load, uptimeSeconds: server.uptimeSeconds, issue: serverIssue),
                        provinces: issueProvinces + base.provinces.filter { !issues.contains($0.slug) })
    }
}

struct WidgetStatusStoreTests {
    @Test func savesReadsAndDeletes() throws {
        let store = temporaryStore()
        #expect(store.read() == .missing)
        let status = WidgetStatus.example(checked: Date(timeIntervalSince1970: 1_792_000_000.25))
        try store.save(status)
        #expect(store.read() == .status(status))                                // exact, fractions of a second too
        try store.delete()
        #expect(store.read() == .missing)
        try store.delete()                                                      // deleting nothing is fine
    }

    @Test func aCorruptFileReadsAsFailed() throws {
        let directory = temporaryDirectory()
        try Data("{\"summary\": 3".utf8).write(to: directory.appendingPathComponent(WidgetStatusStore.fileName))
        let store = WidgetStatusStore(directory: directory)
        #expect(store.read() == .failed)
        #expect(store.read().status == nil)
        try store.save(.example(checked: .now))                                 // and is replaced by the next save
        #expect(store.read().status != nil)
    }

    @Test func withoutTheAppGroupNothingIsSaved() {
        let store = WidgetStatusStore(directory: nil)
        #expect(store.read() == .missing)
        #expect(throws: (any Error).self) { try store.save(.example(checked: .now)) }
    }
}

/// The widget's choice between the server and the saved status, with a fake Keychain and a fake fetch.
@MainActor
struct WidgetStatusLoaderTests {
    let now = at("2026-10-24T12:30:00Z")

    @Test func noLoginMeansLoggedOutAndForgetsTheSavedStatus() async throws {
        let store = temporaryStore()
        try store.save(.example(checked: now.addingTimeInterval(-60), account: "account-a"))
        var fetched = false
        let loader = WidgetStatusLoader(readToken: { nil }, fetch: { _ in fetched = true; return try sample("overview") },
                                        store: store)
        #expect(await loader.load(now: now) == .loggedOut)
        #expect(!fetched && store.read() == .missing)
    }

    @Test func aStatusTheAppJustSavedIsUsedWithoutAsking() async throws {
        let store = temporaryStore()
        let saved = WidgetStatus.example(checked: now.addingTimeInterval(-90), account: "account-a")
        try store.save(saved)
        var fetched = false
        let loader = WidgetStatusLoader(readToken: { widgetLoginToken() },
                                        fetch: { _ in fetched = true; return try sample("overview") }, store: store)
        #expect(await loader.load(now: now) == .status(saved))
        #expect(!fetched)
    }

    @Test func otherwiseItAsksTheServerAndSavesTheAnswer() async throws {
        let store = temporaryStore()
        try store.save(.example(checked: now.addingTimeInterval(-20 * 60), account: "account-a"))
        let transport = FakeTransport(data: try sampleData("overview"))
        let loader = WidgetStatusLoader(readToken: { widgetLoginToken() },
                                        fetch: { try await AresusAPI(transport: transport).overview(token: $0) }, store: store)
        let expected = WidgetStatus(overview: try sample("overview"), account: "account-a")
        #expect(await loader.load(now: now) == .status(expected))
        #expect(store.read() == .status(expected))
        #expect(transport.requests.map { $0.url?.path } == ["/api/aresus/overview"])
        #expect(transport.requests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer \(widgetLoginToken())")
    }

    @Test func aSavedStatusFromTheFutureIsNotTrusted() async throws {
        // A phone clock behind the server's must not make an old status look fresh forever.
        let store = temporaryStore()
        try store.save(.example(checked: now.addingTimeInterval(10 * 60), account: "account-a"))
        var fetched = false
        let loader = WidgetStatusLoader(readToken: { widgetLoginToken() },
                                        fetch: { _ in fetched = true; return try sample("overview") }, store: store)
        _ = await loader.load(now: now)
        #expect(fetched)
    }

    @Test(arguments: [401, 403])
    func aRefusedLoginMeansLoggedOut(status: Int) async throws {
        let store = temporaryStore()
        try store.save(.example(checked: now.addingTimeInterval(-20 * 60), account: "account-a"))
        let transport = FakeTransport(data: Data("{\"error\":\"No access.\"}".utf8))
        transport.status = status
        let loader = WidgetStatusLoader(readToken: { widgetLoginToken() },
                                        fetch: { try await AresusAPI(transport: transport).overview(token: $0) }, store: store)
        #expect(await loader.load(now: now) == .loggedOut)
        #expect(store.read() == .missing)
    }

    @Test(arguments: [500, 503])
    func theServerDownShowsTheSavedStatus(status: Int) async throws {
        let store = temporaryStore()
        let saved = WidgetStatus.example(checked: now.addingTimeInterval(-3 * 3600), account: "account-a")
        try store.save(saved)
        let transport = FakeTransport(data: Data("{\"error\":\"Aresus has not finished its first check yet.\"}".utf8))
        transport.status = status
        let loader = WidgetStatusLoader(readToken: { widgetLoginToken() },
                                        fetch: { try await AresusAPI(transport: transport).overview(token: $0) }, store: store)
        #expect(await loader.load(now: now) == .status(saved))                 // its age tells it is old
        #expect(store.read() == .status(saved))
    }

    @Test func offlineShowsTheSavedStatusOrNothingLoaded() async throws {
        let store = temporaryStore()
        let loader = WidgetStatusLoader(readToken: { widgetLoginToken() },
                                        fetch: { _ in throw URLError(.notConnectedToInternet) }, store: store)
        #expect(await loader.load(now: now) == .notLoaded)
        let saved = WidgetStatus.example(checked: now.addingTimeInterval(-40 * 60), account: "account-a")
        try store.save(saved)
        #expect(await loader.load(now: now) == .status(saved))
    }

    @Test func aLockedKeychainShowsTheSavedStatusWithoutAsking() async throws {
        // The token is readable only while the phone is unlocked; the lock screen widget refreshes anyway.
        let store = temporaryStore()
        var fetched = false
        let loader = WidgetStatusLoader(readToken: { throw KeychainError(status: errSecInteractionNotAllowed) },
                                        fetch: { _ in fetched = true; return try sample("overview") }, store: store,
                                        readAccount: { "account-a" })
        #expect(await loader.load(now: now) == .notLoaded)
        let saved = WidgetStatus.example(checked: now.addingTimeInterval(-2 * 3600), account: "account-a")
        try store.save(saved)
        #expect(await loader.load(now: now) == .status(saved))
        #expect(!fetched && store.read() == .status(saved))                     // kept: the login may well be fine
    }

    @Test func theQuickSnapshotNeverFetches() async throws {
        let store = temporaryStore()
        var fetched = false
        let loader = WidgetStatusLoader(readToken: { widgetLoginToken() },
                                        fetch: { _ in fetched = true; return try sample("overview") }, store: store)
        #expect(await loader.load(now: now, fetching: false) == .notLoaded)
        let saved = WidgetStatus.example(checked: now.addingTimeInterval(-50 * 60), account: "account-a")
        try store.save(saved)
        #expect(await loader.load(now: now, fetching: false) == .status(saved))
        #expect(!fetched)
    }

    @Test(arguments: ["account-a", "account-b", nil] as [String?])
    func lockedKeychainChecksTheMarkerAndDeletesOtherAccounts(account: String?) async throws {
        let store = temporaryStore()
        let saved = WidgetStatus.example(checked: now, account: "account-a")
        try store.save(saved)
        var fetched = false
        let loader = WidgetStatusLoader(readToken: { throw KeychainError(status: errSecInteractionNotAllowed) },
                                        fetch: { _ in fetched = true; return try sample("overview") }, store: store,
                                        readAccount: { account })
        #expect(await loader.load(now: now) == (account == "account-a" ? .status(saved) : .loggedOut))
        #expect(store.read() == (account == "account-a" ? .status(saved) : .missing))
        #expect(!fetched)
    }

    @Test func lockedLegacyStatusIsDeletedEvenWithNoMarker() async throws {
        let store = temporaryStore()
        try store.save(.example(checked: now))
        let loader = WidgetStatusLoader(readToken: { throw KeychainError(status: errSecInteractionNotAllowed) },
                                        fetch: { _ in throw URLError(.notConnectedToInternet) }, store: store,
                                        readAccount: { nil })
        #expect(await loader.load(now: now) == .loggedOut)
        #expect(store.read() == .missing)
    }

    @Test(arguments: [false, true])
    func anotherAccountsUnlockedTokenNeverShowsTheSavedStatus(fetching: Bool) async throws {
        let store = temporaryStore()
        try store.save(.example(checked: now, account: "account-a"))
        let loader = WidgetStatusLoader(readToken: { widgetLoginToken(account: "account-b") },
                                        fetch: { _ in throw URLError(.notConnectedToInternet) }, store: store)
        #expect(await loader.load(now: now, fetching: fetching) == .notLoaded)
        #expect(store.read() == .missing)
    }

    @Test func anotherAccountsTokenFetchesAndSavesItsOwnStatus() async throws {
        let store = temporaryStore()
        try store.save(.example(checked: now, account: "account-a"))
        let loader = WidgetStatusLoader(readToken: { widgetLoginToken(account: "account-b") },
                                        fetch: { _ in try sample("overview") }, store: store)
        let expected = WidgetStatus(overview: try sample("overview"), account: "account-b")
        #expect(await loader.load(now: now) == .status(expected))
        #expect(store.read() == .status(expected))
    }
}

struct WidgetTimelineTests {
    @Test func aFreshStatusGetsAnEntryWhenItTurnsStale() throws {
        let status = WidgetStatus(overview: try sample("overview"))
        let now = status.checked.addingTimeInterval(30)
        let timeline = StatusTimeline.timeline(.status(status), now: now)
        #expect(timeline.entries.map(\.date) == [now, status.staleAt])
        #expect(timeline.entries.allSatisfy { $0.content == .status(status) })
        #expect(timeline.policy == .after(now.addingTimeInterval(15 * 60)))
    }

    @Test func aStaleStatusOrNoStatusIsOneEntry() throws {
        let status = WidgetStatus(overview: try sample("overview"))
        let late = status.checked.addingTimeInterval(2 * 3600)
        #expect(StatusTimeline.entries(.status(status), now: late).map(\.date) == [late])
        #expect(StatusTimeline.entries(.loggedOut, now: late).map(\.date) == [late])
        #expect(StatusTimeline.entries(.notLoaded, now: late).map(\.date) == [late])
    }
}

struct WidgetAgeTests {
    let checked = at("2026-10-24T12:09:00Z")

    nonisolated static let ages: [(TimeInterval, String)] = [
        (10, "checked now"), (61, "checked 1 minute ago"), (240, "checked 4 minutes ago"),
        (59 * 60, "checked 59 minutes ago"), (2 * 3600 + 300, "checked 2 hours ago")]

    @Test(arguments: ages)
    func readsAsTheWidgetShowsIt(age: TimeInterval, text: String) {
        #expect(WidgetAge.text(since: checked, now: checked.addingTimeInterval(age)) == text)
    }

    @Test func daysForAnOldStatus() {
        #expect(WidgetAge.text(since: checked, now: checked.addingTimeInterval(3 * 86_400)) == "checked 3 days ago")
    }

    @Test func itCountsOnByItself() throws {
        // A live format (Text(.currentDate, format:)): it names the next moment its text changes, so the widget's age
        // keeps counting between refreshes.
        let now = checked.addingTimeInterval(240)
        let next = try #require(WidgetAge.style(since: checked).discreteInput(after: now))
        #expect(next > now && next <= now.addingTimeInterval(60))
        #expect(WidgetAge.text(since: checked, now: next.addingTimeInterval(1)) == "checked 5 minutes ago")
    }
}

/// The app saves the status after each overview and deletes it with the data.
@MainActor
struct WidgetStatusPublisherTests {
    @Test func publishesAndClears() throws {
        let store = temporaryStore()
        var reloads = 0
        let publisher = WidgetStatusPublisher(store: store, reloadTimelines: { reloads += 1 })
        let overview: Overview = try sample("overview")
        publisher.publish(overview, account: "fictional-account")
        #expect(store.read() == .status(WidgetStatus(overview: overview, account: "fictional-account")) && reloads == 1)
        publisher.clear()
        #expect(store.read() == .missing && reloads == 2)
    }

    @Test func theStoreSavesEachOverviewAndForgetsItOnLogout() async throws {
        let store = temporaryStore()
        var reloads = 0
        let session = await signedInSession()
        let transport = FakeTransport(data: try sampleData("overview"))
        let aresus = AresusStore(session: session, client: AresusAPI(transport: transport),
                                 widget: WidgetStatusPublisher(store: store, reloadTimelines: { reloads += 1 }))
        await aresus.load(.overview)
        #expect(store.read() == .status(WidgetStatus(overview: try sample("overview"), account: session.accountID)) && reloads == 1)
        session.logOut()
        #expect(store.read() == .missing && reloads == 2)
    }

    @Test func samplesNeverWriteTheWidget() async throws {
        let store = temporaryStore()
        let session = EmpireSession(app: .aresus, storage: MemoryTokens(), restoreOnLaunch: false)
        let aresus = AresusStore(session: session, samples: AresusSamples(allGood: false),
                                 widget: WidgetStatusPublisher(store: store, reloadTimelines: {}))
        await aresus.load(.overview)
        #expect(aresus.overview != nil && store.read() == .missing)
    }
}

func temporaryDirectory() -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("aresus-widget-" + UUID().uuidString)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

func temporaryStore() -> WidgetStatusStore { WidgetStatusStore(directory: temporaryDirectory()) }

/// An unsigned fictional JWT; only the account payload is read by the widget.
nonisolated private func widgetLoginToken(account: String = "account-a") -> String {
    let payload = Data("{\"id\":\"\(account)\"}".utf8).base64EncodedString()
        .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
    return "fictional.\(payload).unsigned"
}
