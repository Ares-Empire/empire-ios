import Foundation
import Testing
@testable import Empire

@MainActor
struct EmpireStoreTests {
    enum Action: String, CaseIterable {
        case load, add, remove, approvals, approve, decline

        func run(_ store: EmpireStore) async {
            switch self {
            case .load: await store.reload()
            case .add: await store.ring(add: "aresium")
            case .remove: await store.ring(remove: "aresium")
            case .approvals: await store.loadApprovals()
            case .approve, .decline: await store.decide(id: "fictional-id", approve: self == .approve)
            }
        }

        func error(in store: EmpireStore) -> String? {
            switch self {
            case .load: store.error
            case .add, .remove: store.ringError
            default: store.approvalsError
            }
        }
    }

    @Test func loadDeduplicatesAndSetsState() async throws {
        let session = await empireSession()
        let transport = EmpireFakeTransport(data: try empireJSON())
        let store = EmpireStore(session: session, client: EmpireAPI(transport: transport))
        let gate = EmpireRequestGate()
        transport.nextGate = gate
        let load = Task { await store.reload() }
        await gate.waitUntilPaused()
        #expect(store.isLoading && store.data == nil && store.error == nil)
        await store.reload()
        #expect(transport.requests.count == 1)
        gate.resume()
        await load.value
        #expect(!store.isLoading && store.error == nil)
        #expect(store.data == (try EmpireSamples.load(user: false)))
        #expect(store.lastSuccessfulLoad != nil)
    }

    @Test func foregroundUsesFiveMinutesAndTwelveHours() async throws {
        let auth = EmpireFakeTransport(data: empireAuthResponse())
        let session = await empireSession(auth: auth)
        let transport = EmpireFakeTransport(data: try empireJSON())
        let store = EmpireStore(session: session, client: EmpireAPI(transport: transport))
        await store.refreshOnForeground()
        let loaded = try #require(store.lastSuccessfulLoad)
        await store.refreshOnForeground(now: loaded.addingTimeInterval(300))
        #expect(transport.requests.count == 1)
        await store.refreshOnForeground(now: loaded.addingTimeInterval(301))
        #expect(transport.requests.count == 2 && auth.requests.count == 1)
        auth.data = empireAuthResponse(token: "fictional-renewed-token")
        await store.refreshOnForeground(now: loaded.addingTimeInterval(12 * 3600 + 1))
        #expect(auth.requests.count == 2 && transport.requests.count == 3)
        #expect(auth.requests.last?.url?.path.hasSuffix("auth-refresh") == true)
        #expect(transport.requests.last?.value(forHTTPHeaderField: "Authorization") == "Bearer fictional-renewed-token")
    }

    @Test func foregroundDeduplicatesAndPreservesVisibleData() async throws {
        let session = await empireSession()
        let transport = EmpireFakeTransport(data: try empireJSON())
        let store = EmpireStore(session: session, client: EmpireAPI(transport: transport))
        await store.reload()
        let now = try #require(store.lastSuccessfulLoad).addingTimeInterval(301)
        let gate = EmpireRequestGate()
        transport.nextGate = gate
        let refresh = Task { await store.refreshOnForeground(now: now) }
        await gate.waitUntilPaused()
        await store.refreshOnForeground(now: now)
        #expect(store.data != nil && store.isLoading)
        #expect(transport.requests.count == 2)
        gate.resume()
        await refresh.value
        #expect(!store.isLoading)
    }

    @Test(arguments: [401, 403, 503])
    func failedForegroundRestoreStopsHubFetch(status: Int) async throws {
        let auth = EmpireFakeTransport(data: empireAuthResponse())
        let storage = EmpireMemoryTokens()
        let session = await empireSession(storage: storage, auth: auth)
        let transport = EmpireFakeTransport(data: try empireJSON())
        let store = EmpireStore(session: session, client: EmpireAPI(transport: transport))
        await store.reload()
        auth.status = status
        await store.refreshOnForeground(now: Date.now.addingTimeInterval(13 * 3600))
        #expect(transport.requests.count == 1)
        #expect((store.data != nil) == (status == 503))
        #expect((storage.token != nil) == (status == 503))
        #expect(session.needsRestoreRetry == (status == 503))
        if status == 503 { #expect(session.error == "Login service unavailable, try again") }
    }

    @Test(arguments: [true, false])
    func ringUsesReturnedDataAndBusyState(add: Bool) async throws {
        let session = await empireSession()
        let transport = EmpireFakeTransport(data: try empireJSON(user: true))
        let store = EmpireStore(session: session, client: EmpireAPI(transport: transport))
        await store.reload()
        let returned = try EmpireSamples.load(user: false)
        transport.data = try JSONEncoder().encode(returned)
        let gate = EmpireRequestGate()
        transport.nextGate = gate
        let action = Task {
            if add { await store.ring(add: "aresium") }
            else { await store.ring(remove: "aresium") }
        }
        await gate.waitUntilPaused()
        #expect(store.isRingBusy && store.data?.me.admin == false)
        await store.ring(add: "another-slug")
        await store.reload()
        #expect(transport.requests.count == 2)
        gate.resume()
        await action.value
        #expect(store.data == returned)
        #expect(!store.isRingBusy && store.ringError == nil)
    }

    @Test(arguments: [true, false])
    func ringErrorPersistsThroughReloadUntilNextAction(add: Bool) async throws {
        let session = await empireSession()
        let transport = EmpireFakeTransport(data: try empireJSON())
        let store = EmpireStore(session: session, client: EmpireAPI(transport: transport))
        await store.reload()
        let original = store.data
        transport.status = 409
        transport.data = Data(#"{"error":"The ring could not be changed"}"#.utf8)
        if add { await store.ring(add: "aresium") }
        else { await store.ring(remove: "aresium") }
        #expect(store.ringError == "The ring could not be changed")
        #expect(store.data == original && !store.isRingBusy)
        transport.status = 200
        transport.data = try empireJSON()
        await store.reload()
        #expect(store.ringError == "The ring could not be changed")
        await store.ring(add: "aresium")
        #expect(store.ringError == nil)
    }

    @Test(arguments: [true, false])
    func approvalsDecisionRefreshesListAndPending(approve: Bool) async throws {
        let session = await empireSession()
        let transport = EmpireFakeTransport(data: try empireJSON())
        let store = EmpireStore(session: session, client: EmpireAPI(transport: transport))
        await store.reload()
        transport.data = try JSONEncoder().encode(EmpireSamples.approvals)
        await store.loadApprovals()
        #expect(store.approvals.count == 2 && !store.isLoadingApprovals)
        let remaining = Array(EmpireSamples.approvals.dropFirst())
        transport.responses = [(204, Data()), (200, try JSONEncoder().encode(remaining)),
                               (200, try JSONEncoder().encode(empireWithPending(1)))]
        let gate = EmpireRequestGate()
        transport.nextGate = gate
        let decision = Task { await store.decide(id: "sample-pending-one", approve: approve) }
        await gate.waitUntilPaused()
        #expect(store.isDeciding)
        await store.decide(id: "sample-pending-two", approve: approve)
        await store.loadApprovals()
        #expect(transport.requests.count == 3)
        gate.resume()
        await decision.value
        #expect(!store.isDeciding && store.approvalsError == nil)
        #expect(store.approvals == remaining && store.data?.pending == 1)
        #expect(transport.requests.suffix(3).map { $0.url?.path } == [
            "/api/empire/approvals/sample-pending-one", "/api/empire/approvals", "/api/empire"
        ])
        let body = try JSONDecoder().decode([String: Bool].self, from: #require(transport.requests[2].httpBody))
        #expect(body == [approve ? "approve" : "decline": true])
    }

    @Test func decisionStillRefreshesPendingWhenListRefreshFails() async throws {
        let session = await empireSession()
        let transport = EmpireFakeTransport(data: try empireJSON())
        let store = EmpireStore(session: session, client: EmpireAPI(transport: transport))
        await store.reload()
        transport.responses = [(204, Data()), (503, Data()), (200, try JSONEncoder().encode(empireWithPending(1)))]
        await store.decide(id: "fictional-id", approve: true)
        #expect(store.data?.pending == 1)
        #expect(store.approvalsError == "Login service unavailable, try again")
        #expect(!store.isDeciding)
    }

    @Test func failedPendingRefreshRetainsVisibleDataAndUpdatedApprovals() async throws {
        let session = await empireSession()
        let transport = EmpireFakeTransport(data: try empireJSON())
        let store = EmpireStore(session: session, client: EmpireAPI(transport: transport))
        await store.reload()
        let original = store.data
        transport.responses = [(204, Data()), (200, Data("[]".utf8)), (503, Data())]
        await store.decide(id: "fictional-id", approve: false)
        #expect(store.data == original && store.approvals.isEmpty)
        #expect(store.approvalsError == "Login service unavailable, try again")
    }

    @Test(arguments: Action.allCases, [401, 403, 503])
    func authAndUnavailableStatusesAcrossActions(action: Action, status: Int) async throws {
        let storage = EmpireMemoryTokens()
        let session = await empireSession(storage: storage)
        let transport = EmpireFakeTransport(data: try empireJSON())
        let store = EmpireStore(session: session, client: EmpireAPI(transport: transport))
        await store.reload()
        let original = store.data
        transport.data = try JSONEncoder().encode(EmpireSamples.approvals)
        await store.loadApprovals()
        transport.status = status
        transport.data = Data(#"{"error":"No access to Empire"}"#.utf8)
        await action.run(store)
        #expect(!store.isLoading && !store.isRingBusy && !store.isLoadingApprovals && !store.isDeciding)
        switch status {
        case 401:
            #expect(session.token == nil && storage.token == nil && !session.isSignedIn)
            #expect(store.data == nil && store.approvals.isEmpty)
            #expect(store.lastSuccessfulLoad == nil)
        case 403:
            #expect(session.token == "fictional-empire-token" && storage.token == session.token)
            #expect(session.isDenied && !session.isSignedIn)
            #expect(session.error == "No access to Empire")
            #expect(store.data == nil && store.approvals.isEmpty)
            // The valid shared login is still usable by another Empire app.
            let other = EmpireSession(app: .aresium, storage: storage,
                                      client: EmpireAuthClient(transport: EmpireFakeTransport(data: empireAuthResponse())))
            await other.restore()
            #expect(other.isSignedIn)
        default:
            #expect(session.isSignedIn && storage.token != nil)
            #expect(store.data == original && store.approvals.count == 2)
            #expect(action.error(in: store) == "Login service unavailable, try again")
        }
    }

    @Test func appDataResetClearsAllStateAndBlocksFurtherRequests() async throws {
        let session = await empireSession()
        let transport = EmpireFakeTransport(data: try empireJSON())
        let store = EmpireStore(session: session, client: EmpireAPI(transport: transport))
        await store.reload()
        transport.data = try JSONEncoder().encode(EmpireSamples.approvals)
        await store.loadApprovals()
        transport.status = 503
        await store.ring(add: "aresium")
        await store.decide(id: "fictional-id", approve: true)
        await store.reload()
        #expect(store.ringError != nil && store.approvalsError != nil && store.error != nil)
        session.handleAuthFailure(HTTPError.server(403, "Denied"), generation: session.generation)
        #expect(store.data == nil && store.approvals.isEmpty && store.lastSuccessfulLoad == nil)
        #expect(store.error == nil && store.ringError == nil && store.approvalsError == nil)
        let count = transport.requests.count
        for action in Action.allCases { await action.run(store) }
        await store.refreshOnForeground(now: Date.now.addingTimeInterval(13 * 3600))
        #expect(transport.requests.count == count)
    }

    @Test(arguments: Action.allCases, [200, 401, 403])
    func lateResponsesCannotRestoreDataOrInvalidateNewLogin(action: Action, status: Int) async throws {
        let session = await empireSession()
        let transport = EmpireFakeTransport(data: try empireJSON())
        let store = EmpireStore(session: session, client: EmpireAPI(transport: transport))
        await store.reload()
        let original = store.data
        transport.status = status
        if action == .approvals { transport.data = try JSONEncoder().encode(EmpireSamples.approvals) }
        let gate = EmpireRequestGate()
        transport.nextGate = gate
        let pending = Task { await action.run(store) }
        await gate.waitUntilPaused()
        session.logOut()
        #expect(store.data == nil && store.approvals.isEmpty)
        await session.login(email: "new@example.invalid", password: "fictional")
        transport.status = 200
        transport.data = try empireJSON()
        await store.reload()
        gate.resume()
        await pending.value
        #expect(session.isSignedIn && !session.isDenied)
        #expect(store.data == original && store.approvals.isEmpty)
        #expect(store.error == nil && store.ringError == nil && store.approvalsError == nil)
        #expect(!store.isLoading && !store.isRingBusy && !store.isLoadingApprovals && !store.isDeciding)
    }

    @Test(arguments: [200, 401, 403])
    func ringSupersedesAnOlderHubRequest(status: Int) async throws {
        let session = await empireSession()
        let transport = EmpireFakeTransport(data: try empireJSON(user: true))
        let store = EmpireStore(session: session, client: EmpireAPI(transport: transport))
        transport.status = status
        let gate = EmpireRequestGate()
        transport.nextGate = gate
        let old = Task { await store.reload() }
        await gate.waitUntilPaused()
        transport.status = 200
        transport.data = try empireJSON()
        await store.ring(add: "aresium")
        let current = store.data
        gate.resume()
        await old.value
        #expect(session.isSignedIn && store.data == current && current?.me.admin == true)
        #expect(store.error == nil && !store.isLoading)
    }

    @Test(arguments: [false, true])
    func sampleModeStaysInMemory(user: Bool) async throws {
        let session = EmpireSession(app: .empire, storage: EmpireMemoryTokens(), restoreOnLaunch: false)
        let transport = EmpireFakeTransport()
        let store = EmpireStore(session: session, client: EmpireAPI(transport: transport), sample: true, sampleUser: user)
        await store.reload()
        #expect(store.data == (try EmpireSamples.load(user: user)))
        await store.ring(remove: "aresium")
        #expect(store.data?.projects.contains { $0.slug == "aresium" } == false)
        #expect(store.data?.addable.contains { $0.slug == "aresium" } == true)
        await store.reload()
        #expect(store.data?.addable.contains { $0.slug == "aresium" } == true)
        await store.ring(add: "aresium")
        #expect(store.data?.projects.contains { $0.slug == "aresium" } == true)
        await store.loadApprovals()
        #expect(store.approvals.count == (user ? 0 : 2))
        if !user {
            await store.decide(id: "sample-pending-one", approve: true)
            #expect(store.approvals.count == 1 && store.data?.pending == 1)
            await store.decide(id: "sample-pending-two", approve: false)
            #expect(store.approvals.isEmpty && store.data?.pending == 0)
            await store.reload()
            await store.loadApprovals()
            #expect(store.approvals.isEmpty && store.data?.pending == 0)
        }
        await store.refreshOnForeground(now: Date.now.addingTimeInterval(13 * 3600))
        #expect(transport.requests.isEmpty)
        session.logOut()
        #expect(store.data == nil && store.approvals.isEmpty && store.lastSuccessfulLoad == nil)
    }

    @Test func launchArgumentsRequireSampleData() {
        #expect(!EmpireSamples.enabled(arguments: ["Empire", "-sampleUser"]))
        #expect(EmpireSamples.enabled(arguments: ["Empire", "-sampleData"]))
        #expect(EmpireSamples.enabled(arguments: ["Empire", "-sampleData", "-sampleUser"]))
    }
}
