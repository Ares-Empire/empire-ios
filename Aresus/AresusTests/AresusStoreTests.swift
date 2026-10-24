import Foundation
import Testing
@testable import Aresus

@MainActor
struct AresusStoreTests {
    @Test func loadsEachPartAndCachesProvincesBySlug() async throws {
        let session = await signedInSession()
        let transport = FakeTransport()
        transport.responses = [(200, try sampleData("overview")), (200, try sampleData("province")),
                               (200, try sampleData("sync")), (200, try sampleData("run"))]
        let store = AresusStore(session: session, client: AresusAPI(transport: transport))
        await store.load(.overview)
        await store.load(.province("aresium"))
        await store.load(.sync)
        await store.load(.run(612))
        #expect(store.overview == (try sample("overview")))
        #expect(store.provinces["aresium"] == (try sample("province")))
        #expect(store.sync == (try sample("sync")))
        #expect(store.runs[612] == (try sample("run")))
        #expect(store.loading.isEmpty && store.errors.isEmpty)
        #expect(Set(store.loadedAt.keys) == [.overview, .province("aresium"), .sync, .run(612)])
        #expect(transport.requests.map { $0.url?.path } == ["/api/aresus/overview", "/api/aresus/provinces/aresium",
                                                            "/api/aresus/sync", "/api/aresus/sync/runs/612"])
        #expect(transport.requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer fictional-empire-token" })
    }

    @Test func onePartLoadsOnceAtATime() async throws {
        let session = await signedInSession()
        let transport = FakeTransport(data: try sampleData("overview"))
        let store = AresusStore(session: session, client: AresusAPI(transport: transport))
        let gate = RequestGate()
        transport.nextGate = gate
        let load = Task { await store.load(.overview) }
        await gate.waitUntilPaused()
        #expect(store.isLoading(.overview) && store.overview == nil)
        await store.load(.overview)
        await store.refresh([.overview])
        #expect(transport.requests.count == 1)
        gate.resume()
        await load.value
        #expect(!store.isLoading(.overview) && store.overview != nil)
    }

    @Test func refreshLoadsOnlyWhatIsMissingOrOld() async throws {
        let session = await signedInSession()
        let transport = FakeTransport(data: try sampleData("sync"))
        let store = AresusStore(session: session, client: AresusAPI(transport: transport))
        await store.refresh([.sync], olderThan: AresusStore.interval)
        let loaded = try #require(store.loadedAt[.sync])
        await store.refresh([.sync], olderThan: AresusStore.interval, now: loaded.addingTimeInterval(59))
        #expect(transport.requests.count == 1)
        await store.refresh([.sync], olderThan: AresusStore.interval, now: loaded.addingTimeInterval(60))
        #expect(transport.requests.count == 2)
        await store.refresh([.sync])                                  // the minute's tick: always
        #expect(transport.requests.count == 3)
    }

    @Test func foregroundRefreshesUnlessJustLoadedAndRenewsOldLogins() async throws {
        let auth = FakeTransport(data: authResponse())
        let session = await signedInSession(auth: auth)
        let transport = FakeTransport(data: try sampleData("overview"))
        let store = AresusStore(session: session, client: AresusAPI(transport: transport))
        await store.refreshOnForeground(visible: [.overview])
        let loaded = try #require(store.loadedAt[.overview])
        await store.refreshOnForeground(visible: [.overview], now: loaded.addingTimeInterval(5))
        #expect(transport.requests.count == 1)
        await store.refreshOnForeground(visible: [.overview], now: loaded.addingTimeInterval(10))
        #expect(transport.requests.count == 2 && auth.requests.count == 1)
        auth.data = authResponse(token: "fictional-renewed-token")
        await store.refreshOnForeground(visible: [.overview], now: loaded.addingTimeInterval(12 * 3600 + 1))
        #expect(auth.requests.count == 2 && auth.requests.last?.url?.path.hasSuffix("auth-refresh") == true)
        #expect(transport.requests.last?.value(forHTTPHeaderField: "Authorization") == "Bearer fictional-renewed-token")
    }

    @Test func aRejectedTokenLogsOutEverywhereAndForgetsTheData() async throws {
        let storage = MemoryTokens()
        let session = await signedInSession(storage: storage)
        let transport = FakeTransport(data: try sampleData("overview"))
        let store = AresusStore(session: session, client: AresusAPI(transport: transport))
        await store.load(.overview)
        transport.status = 401
        await store.load(.sync)
        #expect(session.token == nil && storage.token == nil && !session.isSignedIn)
        #expect(store.overview == nil && store.errors.isEmpty && store.loadedAt.isEmpty && store.loading.isEmpty)
        await store.load(.overview)
        #expect(transport.requests.count == 2)                        // nothing is asked without a login
    }

    @Test func noAresusServiceClosesOnlyThisApp() async throws {
        let storage = MemoryTokens()
        let session = await signedInSession(storage: storage)
        let transport = FakeTransport(data: try sampleData("overview"))
        let store = AresusStore(session: session, client: AresusAPI(transport: transport))
        await store.load(.overview)
        transport.status = 403
        transport.data = Data(#"{"error":"This account has no access to Aresus."}"#.utf8)
        await store.load(.overview)
        #expect(session.isDenied && !session.isSignedIn)
        #expect(session.error == "This account has no access to Aresus.")
        #expect(storage.token == "fictional-empire-token")            // the shared login stays for the other apps
        #expect(store.overview == nil && store.errors.isEmpty)
    }

    @Test func anAccountWithoutAresusIsDeniedAtLogin() async {
        let session = EmpireSession(app: .aresus, storage: MemoryTokens(),
                                    client: EmpireAuthClient(transport: FakeTransport(data: authResponse(services: ["aresium"]))),
                                    restoreOnLaunch: false)
        await session.login(email: "member@example.invalid", password: "fictional-password")
        #expect(session.isDenied && !session.isSignedIn)
    }

    @Test func failuresKeepTheLastGoodAnswer() async throws {
        let session = await signedInSession()
        let transport = FakeTransport(data: try sampleData("overview"))
        let store = AresusStore(session: session, client: AresusAPI(transport: transport))
        await store.load(.overview)
        let shown = store.overview
        transport.status = 503
        transport.data = Data(#"{"error":"Login service unavailable, try again in a minute."}"#.utf8)
        await store.load(.overview)
        #expect(store.overview == shown && session.isSignedIn)
        #expect(store.error(.overview) == "Login service unavailable, try again in a minute.")
        transport.data = try sampleData("overview")
        transport.status = 200
        await store.load(.overview)
        #expect(store.error(.overview) == nil)
    }

    @Test func plainMessagesForUnknownProvincesRunsAndBadAnswers() async throws {
        let session = await signedInSession()
        let transport = FakeTransport(data: Data(#"{"error":"not found"}"#.utf8))
        transport.status = 404
        let store = AresusStore(session: session, client: AresusAPI(transport: transport))
        await store.load(.province("atlantis"))
        await store.load(.run(1))
        #expect(store.error(.province("atlantis")) == "Aresus does not watch this province.")
        #expect(store.error(.run(1)) == "This run is no longer kept.")
        transport.status = 200
        transport.data = Data(#"{"version": 1}"#.utf8)
        await store.load(.overview)
        #expect(store.error(.overview) == "The server's answer could not be read.")
        transport.failure = URLError(.notConnectedToInternet)
        await store.load(.sync)
        #expect(store.error(.sync) == "No connection.")
    }

    @Test(arguments: [200, 401, 403])
    func lateAnswersCannotComeBackAfterALogout(status: Int) async throws {
        let session = await signedInSession()
        let transport = FakeTransport(data: try sampleData("overview"))
        transport.status = status
        let store = AresusStore(session: session, client: AresusAPI(transport: transport))
        let gate = RequestGate()
        transport.nextGate = gate
        let pending = Task { await store.load(.overview) }
        await gate.waitUntilPaused()
        session.logOut()
        await session.login(email: "new@example.invalid", password: "fictional-password")
        gate.resume()
        await pending.value
        #expect(session.isSignedIn)                                   // the old answer did not end the new login
        #expect(store.overview == nil && store.errors.isEmpty && store.loading.isEmpty)
    }

    @Test func notSignedInAsksNothing() async {
        let session = EmpireSession(app: .aresus, storage: MemoryTokens(), restoreOnLaunch: false)
        let transport = FakeTransport()
        let store = AresusStore(session: session, client: AresusAPI(transport: transport))
        await store.refresh([.overview, .sync])
        await store.refreshOnForeground(visible: [.overview])
        #expect(transport.requests.isEmpty && store.overview == nil)
    }

    @Test func sampleModeStaysOffTheNetwork() async throws {
        let session = EmpireSession(app: .aresus, storage: MemoryTokens(), restoreOnLaunch: false)
        let transport = FakeTransport()
        let launched = Date.now
        let store = AresusStore(session: session, client: AresusAPI(transport: transport),
                                samples: AresusSamples(allGood: false), launched: launched)
        await store.refresh([.overview, .province("aresium"), .province("arestoteles"), .sync, .run(612), .run(880)])
        #expect(store.overview?.summary == "1 issue")
        #expect(store.provinces["aresium"]?.checks.count == 5)
        #expect(store.provinces["arestoteles"]?.state == .inactive)
        #expect(store.sync?.machines.count == 3)
        #expect(store.runs[612]?.result == .failed && store.runs[880]?.machine == "Aresium")
        await store.load(.province("atlantis"))
        #expect(store.error(.province("atlantis")) == "Aresus does not watch this province.")
        await store.refreshOnForeground(visible: [.overview])
        #expect(transport.requests.isEmpty)
        // The samples read as if just checked: their moment is 12 s after the check.
        #expect(store.clock.now(launched) == at("2026-10-24T12:09:12Z"))
    }

    @Test func allGoodSampleTurnsTheIssueIntoARunningProvince() throws {
        let overview = try AresusSamples(allGood: true).overview()
        #expect(overview.summary == "Everything running")
        #expect(overview.provinces.map(\.slug) == ["empire", "aresium", "arestemis", "aresync",
                                                   "arestoteles", "aresis", "arescrypt", "aresolus"])
        #expect(overview.provinces.allSatisfy { $0.state != .issue })
        let detail = try AresusSamples(allGood: true).province("aresium")
        #expect(detail.state == .active && detail.checks.allSatisfy(\.ok))
        #expect(detail.incidents.allSatisfy { $0.resolved != nil })
    }

    @Test func samplesNeedTheLaunchArgument() {
        #expect(AresusSamples.launched(arguments: ["Aresus", "-sampleAllGood"]) == nil)
        #expect(AresusSamples.launched(arguments: ["Aresus", "-sampleData"])?.allGood == false)
        #expect(AresusSamples.launched(arguments: ["Aresus", "-sampleData", "-sampleAllGood"])?.allGood == true)
    }
}
