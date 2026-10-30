import Foundation
import Testing
@testable import Empire

@MainActor
struct EmpireStoreTests {
    enum Action: String, CaseIterable {
        case load, request, approvals, approve, decline

        func run(_ store: EmpireStore) async {
            switch self {
            case .load: await store.reload()
            case .request: await store.request("aresium")
            case .approvals: await store.loadApprovals()
            case .approve, .decline: await store.decide(id: "fictional-id", approve: self == .approve, requested: ["empire"])
            }
        }

        func error(in store: EmpireStore) -> String? {
            switch self {
            case .load: store.error
            case .request: store.requestError
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

    /// Asking shows which app is on its way (one at a time); the hub's answer is the new data, with that app asked for.
    @Test func aRequestShowsProgressThenTheHubsAnswer() async throws {
        let session = await empireSession()
        let transport = EmpireFakeTransport(data: Data(EmpireFixtures.catalog().utf8))
        let store = EmpireStore(session: session, client: EmpireAPI(transport: transport))
        await store.reload()
        #expect(store.data?.addable.first { $0.slug == "arestemis" }?.canRequest == true)
        let answer = Data(EmpireFixtures.catalog(arestemis: "requested").utf8)
        transport.data = answer
        let gate = EmpireRequestGate()
        transport.nextGate = gate
        let asking = Task { await store.request("arestemis") }
        await gate.waitUntilPaused()
        #expect(store.requesting == "arestemis")
        #expect(await store.request("aresolus") == false)          // one at a time
        await store.reload()                                       // and no reload over it
        #expect(transport.requests.count == 2)
        gate.resume()
        #expect(await asking.value)
        #expect(store.requesting == nil && store.requestError == nil)
        #expect(store.data == (try JSONDecoder().decode(EmpireData.self, from: answer)))
        let arestemis = try #require(store.data?.addable.first { $0.slug == "arestemis" })
        #expect(arestemis.access == .requested && !arestemis.canRequest)
        let sent = try #require(transport.requests.last)
        #expect(sent.httpMethod == "POST" && sent.url?.path == "/api/empire/request")
        #expect(try JSONDecoder().decode([String: String].self, from: #require(sent.httpBody)) == ["service": "arestemis"])
    }

    /// An app that cannot be requested (400 `bad_request`): the hub's sentence shows until the next request.
    @Test func aRefusedRequestShowsTheHubsSentence() async throws {
        let session = await empireSession()
        let transport = EmpireFakeTransport(data: Data(EmpireFixtures.catalog().utf8))
        let store = EmpireStore(session: session, client: EmpireAPI(transport: transport))
        await store.reload()
        let original = store.data
        transport.status = 400
        transport.data = Data(#"{"error":"Aresium can't be requested yet.","code":"bad_request"}"#.utf8)
        #expect(await store.request("aresium") == false)
        #expect(store.requestError == "Aresium can't be requested yet.")
        #expect(store.data == original && store.requesting == nil && session.isSignedIn)
        transport.status = 200
        transport.data = Data(EmpireFixtures.catalog().utf8)
        await store.reload()
        #expect(store.requestError == "Aresium can't be requested yet.")
        #expect(await store.request("arestemis"))
        #expect(store.requestError == nil)
    }

    @Test(arguments: [true, false])
    func approvalsDecisionRefreshesListAndPending(approve: Bool) async throws {
        let session = await empireSession()
        let transport = EmpireFakeTransport(data: try empireJSON())
        let store = EmpireStore(session: session, client: EmpireAPI(transport: transport))
        await store.reload()
        transport.data = try JSONEncoder().encode(EmpireSamples.approvals)
        await store.loadApprovals()
        #expect(store.approvals.count == EmpireSamples.approvals.count && !store.isLoadingApprovals)
        let remaining = Array(EmpireSamples.approvals.dropFirst())
        // A hub that answers only {"ok": true} (before it sent the list): the app asks for both again.
        transport.responses = [(200, Self.ok), (200, try JSONEncoder().encode(remaining)),
                               (200, try JSONEncoder().encode(empireWithPending(1)))]
        let gate = EmpireRequestGate()
        transport.nextGate = gate
        let decision = Task { await store.decide(id: "sample-pending-one", approve: approve, requested: ["empire"]) }
        await gate.waitUntilPaused()
        #expect(store.isDeciding)
        #expect(await store.decide(id: "sample-pending-two", approve: approve, requested: ["empire"]) == false)
        await store.loadApprovals()
        #expect(transport.requests.count == 3)
        gate.resume()
        #expect(await decision.value)
        #expect(!store.isDeciding && store.approvalsError == nil)
        #expect(store.approvals == remaining && store.data?.pending == 1)
        #expect(transport.requests.suffix(3).map { $0.url?.path } == [
            "/api/empire/approvals/sample-pending-one", "/api/empire/approvals", "/api/empire"
        ])
        let sent = try #require(transport.requests[2].httpBody)
        let body = try #require(try JSONSerialization.jsonObject(with: sent) as? [String: Any])
        #expect(body.count == 2 && body[approve ? "approve" : "decline"] as? Bool == true)
        #expect(body["requested"] as? [String] == ["empire"])
    }

    @Test func approvalsRetryClearsTheErrorWhileLoadingAndRefreshesTheList() async throws {
        let session = await empireSession()
        let transport = EmpireFakeTransport()
        transport.failure = URLError(.notConnectedToInternet)
        let store = EmpireStore(session: session, client: EmpireAPI(transport: transport))
        await store.loadApprovals()
        #expect(store.approvals.isEmpty && store.approvalsError != nil && !store.isLoadingApprovals)

        transport.failure = nil
        transport.data = try JSONEncoder().encode(EmpireSamples.approvals)
        let gate = EmpireRequestGate()
        transport.nextGate = gate
        let retry = Task { await store.loadApprovals() }
        await gate.waitUntilPaused()
        #expect(store.isLoadingApprovals && store.approvalsError == nil && store.approvals.isEmpty)
        await store.loadApprovals()
        #expect(transport.requests.count == 2)
        gate.resume()
        await retry.value
        #expect(!store.isLoadingApprovals && store.approvalsError == nil)
        #expect(store.approvals == EmpireSamples.approvals)

        let remaining = Array(EmpireSamples.approvals.dropFirst())
        transport.data = try JSONEncoder().encode(remaining)
        await store.loadApprovals()
        #expect(store.approvals == remaining && transport.requests.count == 3)
        #expect(transport.requests.allSatisfy { $0.url?.path == "/api/empire/approvals" })
    }

    static let ok = Data(#"{"ok": true}"#.utf8)

    static func decisionAnswer(_ approvals: [PendingAccount], pending: Int?) throws -> Data {
        var answer: [String: Any] = ["ok": true, "approvals": try JSONSerialization.jsonObject(with: JSONEncoder().encode(approvals))]
        answer["pending"] = pending ?? NSNull()
        return try JSONSerialization.data(withJSONObject: answer)
    }

    /// The hub's answer carries the list and the count after the decision: nothing more is asked.
    @Test(arguments: [true, false])
    func aDecisionUsesTheListAndCountItsAnswerCarries(approve: Bool) async throws {
        let session = await empireSession()
        let transport = EmpireFakeTransport(data: try empireJSON())
        let store = EmpireStore(session: session, client: EmpireAPI(transport: transport))
        await store.reload()
        transport.data = try JSONEncoder().encode(EmpireSamples.approvals)
        await store.loadApprovals()
        let remaining = Array(EmpireSamples.approvals.dropFirst())
        transport.responses = [(200, try Self.decisionAnswer(remaining, pending: 1))]
        let count = transport.requests.count
        #expect(await store.decide(id: "sample-pending-one", approve: approve, requested: ["empire"]))
        #expect(transport.requests.count == count + 1)
        #expect(store.approvals == remaining && store.data?.pending == 1 && store.approvalsError == nil)

        // A count the hub could not make hides the badge rather than keeping an old one.
        transport.responses = [(200, try Self.decisionAnswer([], pending: nil))]
        #expect(await store.decide(id: "sample-pending-two", approve: approve, requested: ["empire"]))
        #expect(store.approvals.isEmpty && store.data != nil && store.data?.pending == nil)
    }

    /// A decision whose answer did not come (or that the hub refused because the account was decided meanwhile): the
    /// list is asked for again, so a card for an account already decided goes, with its open confirmation.
    @Test(arguments: [(503, #"{"error":"Login service unavailable, try again in a minute.","code":"unavailable"}"#),
                      (404, #"{"error":"Account not found.","code":"not_found"}"#)])
    func aFailedDecisionRefreshesTheList(refusal: (status: Int, body: String)) async throws {
        let session = await empireSession()
        let transport = EmpireFakeTransport(data: try empireJSON())
        let store = EmpireStore(session: session, client: EmpireAPI(transport: transport))
        await store.reload()
        transport.data = try JSONEncoder().encode(EmpireSamples.approvals)
        await store.loadApprovals()
        let remaining = Array(EmpireSamples.approvals.dropFirst())
        transport.responses = [(refusal.status, Data(refusal.body.utf8)), (200, try JSONEncoder().encode(remaining)),
                               (200, try JSONEncoder().encode(empireWithPending(remaining.count)))]
        #expect(await store.decide(id: "sample-pending-one", approve: false, requested: []) == false)
        #expect(store.approvals == remaining && store.data?.pending == remaining.count)
        // The decision's own error stays the one shown.
        let sentence = try JSONDecoder().decode(ServerMessage.self, from: Data(refusal.body.utf8)).sentence
        #expect(store.approvalsError == sentence && !store.isDeciding)
        #expect(session.isSignedIn)
    }

    /// `"approvals": null`: the decision went through, the hub could not read the list again; the app asks for it.
    @Test func aDecisionAnswerWithoutTheListAsksForIt() async throws {
        let session = await empireSession()
        let transport = EmpireFakeTransport(data: try empireJSON())
        let store = EmpireStore(session: session, client: EmpireAPI(transport: transport))
        await store.reload()
        let remaining = Array(EmpireSamples.approvals.dropFirst())
        transport.responses = [(200, Data(#"{"ok": true, "approvals": null, "pending": null}"#.utf8)),
                               (200, try JSONEncoder().encode(remaining)),
                               (200, try JSONEncoder().encode(empireWithPending(remaining.count)))]
        #expect(await store.decide(id: "sample-pending-one", approve: true, requested: ["empire"]))
        #expect(store.approvals == remaining && store.data?.pending == remaining.count && store.approvalsError == nil)
        #expect(transport.requests.suffix(2).map { $0.url?.path } == ["/api/empire/approvals", "/api/empire"])
    }

    @Test func aDecisionThatWentThroughSaysSoEvenWhenTheRefreshFails() async throws {
        let session = await empireSession()
        let transport = EmpireFakeTransport(data: try empireJSON())
        let store = EmpireStore(session: session, client: EmpireAPI(transport: transport))
        await store.reload()
        transport.responses = [(200, Self.ok), (503, Data()), (503, Data())]
        #expect(await store.decide(id: "fictional-id", approve: false, requested: []))
        #expect(store.approvalsError == "Login service unavailable, try again")
    }

    /// `admin_only` (an account that lost its admin flag): the request is refused, the app stays open.
    @Test(arguments: Action.allCases)
    func aRefusalOtherThanNoAccessKeepsTheApp(action: Action) async throws {
        let storage = EmpireMemoryTokens()
        let session = await empireSession(storage: storage)
        let transport = EmpireFakeTransport(data: try empireJSON())
        let store = EmpireStore(session: session, client: EmpireAPI(transport: transport))
        await store.reload()
        let original = store.data
        transport.status = 403
        transport.data = Data(#"{"error":"Administrator access required.","code":"admin_only"}"#.utf8)
        await action.run(store)
        #expect(session.isSignedIn && !session.isDenied && storage.token != nil)
        #expect(store.data == original)
        #expect(action.error(in: store) == "Administrator access required.")
    }

    @Test func anEmptyRingLoads() async throws {
        let session = await empireSession()
        let transport = EmpireFakeTransport(data: Data(EmpireFixtures.emptyRing.utf8))
        let store = EmpireStore(session: session, client: EmpireAPI(transport: transport))
        await store.reload()
        #expect(store.error == nil && store.data?.projects.isEmpty == true && store.data?.addable.count == 1)
    }

    @Test func decisionStillRefreshesPendingWhenListRefreshFails() async throws {
        let session = await empireSession()
        let transport = EmpireFakeTransport(data: try empireJSON())
        let store = EmpireStore(session: session, client: EmpireAPI(transport: transport))
        await store.reload()
        transport.responses = [(200, Self.ok), (503, Data()), (200, try JSONEncoder().encode(empireWithPending(1)))]
        await store.decide(id: "fictional-id", approve: true, requested: [])
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
        transport.responses = [(200, Self.ok), (200, Data("[]".utf8)), (503, Data())]
        await store.decide(id: "fictional-id", approve: false, requested: [])
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
        transport.data = Data([401: #"{"error":"unauthenticated","code":"unauthorized"}"#,
                               403: #"{"error":"No access to Empire","code":"no_access"}"#,
                               503: #"{"error":"Login service unavailable, try again in a minute.","code":"unavailable"}"#][status]!.utf8)
        await action.run(store)
        #expect(!store.isLoading && store.requesting == nil && !store.isLoadingApprovals && !store.isDeciding)
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
            #expect(store.data == original && store.approvals.count == EmpireSamples.approvals.count)
            #expect(action.error(in: store) == "Login service unavailable, try again in a minute.")
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
        await store.request("aresium")
        await store.decide(id: "fictional-id", approve: true, requested: [])
        await store.reload()
        #expect(store.requestError != nil && store.approvalsError != nil && store.error != nil)
        session.handleAuthFailure(HTTPError.server(403, "Denied"), generation: session.generation, token: session.token)
        #expect(store.data == nil && store.approvals.isEmpty && store.lastSuccessfulLoad == nil)
        #expect(store.error == nil && store.requestError == nil && store.approvalsError == nil)
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
        #expect(store.error == nil && store.requestError == nil && store.approvalsError == nil)
        #expect(!store.isLoading && store.requesting == nil && !store.isLoadingApprovals && !store.isDeciding)
    }

    @Test(arguments: [200, 401, 403])
    func aRequestSupersedesAnOlderHubRequest(status: Int) async throws {
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
        await store.request("aresium")
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
        await store.loadApprovals()
        #expect(store.approvals.count == (user ? 0 : 3))
        if !user {
            await store.decide(id: "sample-pending-one", approve: true, requested: [])
            #expect(store.approvals.count == 2 && store.data?.pending == 2)
            await store.decide(id: "sample-pending-two", approve: false, requested: [])
            #expect(store.approvals.count == 1 && store.data?.pending == 1)
            await store.decide(id: "sample-member-one", approve: true, requested: [])
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
