import Foundation
import Testing
@testable import Empire

@MainActor
struct EmpireAPITests {
    enum Route: String, CaseIterable {
        case empire, add, remove, approvals, approve, decline

        var path: String {
            switch self {
            case .empire: "/api/empire"
            case .add, .remove: "/api/empire/ring"
            case .approvals: "/api/empire/approvals"
            case .approve, .decline: "/api/empire/approvals/fictional-id"
            }
        }
        var body: [String: String]? {
            switch self {
            case .add: ["add": "aresium"]
            case .remove: ["remove": "aresium"]
            default: nil
            }
        }

        func call(_ api: EmpireAPI, onUnauthorized: () -> Void = {}) async throws {
            switch self {
            case .empire: _ = try await api.empire(token: "fictional-token", onUnauthorized: onUnauthorized)
            case .add: _ = try await api.ring(add: "aresium", token: "fictional-token", onUnauthorized: onUnauthorized)
            case .remove: _ = try await api.ring(remove: "aresium", token: "fictional-token", onUnauthorized: onUnauthorized)
            case .approvals: _ = try await api.approvals(token: "fictional-token", onUnauthorized: onUnauthorized)
            case .approve, .decline:
                try await api.decide(id: "fictional-id", approve: self == .approve, requested: ["arestemis"],
                                     token: "fictional-token", onUnauthorized: onUnauthorized)
            }
        }
    }

    @Test(arguments: [false, true])
    func bundledSamplesDecode(user: Bool) throws {
        let sample = try EmpireSamples.load(user: user)
        #expect(sample.version == 2)
        #expect(sample.me.admin == !user)
        #expect(sample.me.id == (user ? "sample-user" : "sample-admin"))
        let aresium = try #require(sample.projects.first { $0.slug == "aresium" })
        #expect(aresium.logo == "brand/hermes.webp")
        #expect(aresium.app == "aresium://")
        #expect(aresium.isComingSoon == user)
        #expect(aresium.detail.features.count == 3)
        #expect(user ? aresium.live == nil : aresium.live != nil)
        #expect(sample.pending == (user ? 0 : 2))
        #expect(user ? sample.ideas.isEmpty : !sample.ideas.isEmpty)
        #expect(!sample.chronicle.isEmpty)
        #expect(try JSONDecoder().decode(EmpireData.self, from: JSONEncoder().encode(sample)) == sample)
    }

    @Test(arguments: Route.allCases)
    func requestsFollowContract(route: Route) async throws {
        let sample = try EmpireSamples.load(user: false)
        let pending = EmpireSamples.approvals
        let transport = EmpireFakeTransport(data: route == .approvals ? try JSONEncoder().encode(pending) : try empireJSON())
        let api = EmpireAPI(transport: transport)
        switch route {
        case .empire: #expect(try await api.empire(token: "fictional-token") == sample)
        case .add: #expect(try await api.ring(add: "aresium", token: "fictional-token") == sample)
        case .remove: #expect(try await api.ring(remove: "aresium", token: "fictional-token") == sample)
        case .approvals: #expect(try await api.approvals(token: "fictional-token") == pending)
        default:
            // The hub's answer before it sent the list: `{"ok": true}` (webauth/server.py decide_approval).
            transport.data = Data(#"{"ok": true}"#.utf8)
            try await route.call(api)
        }
        let request = try #require(transport.requests.only)
        #expect(request.url?.absoluteString == "https://www.ares-empire.de\(route.path)")
        let isGet = route == .empire || route == .approvals
        #expect(request.httpMethod == (isGet ? "GET" : "POST"))
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fictional-token")
        #expect(request.timeoutInterval == 30)
        if isGet {
            #expect(request.httpBody == nil)
        } else {
            #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
            let body = try JSONSerialization.jsonObject(with: #require(request.httpBody)) as? [String: Any]
            switch route {
            case .approve:
                // The apps the card showed, so the hub grants nothing asked for meanwhile.
                #expect(body?.count == 2 && body?["approve"] as? Bool == true)
                #expect(body?["requested"] as? [String] == ["arestemis"])
            case .decline:
                // Withdraws only these requests of an approved account (a new sign-up is deleted).
                #expect(body?.count == 2 && body?["decline"] as? Bool == true)
                #expect(body?["requested"] as? [String] == ["arestemis"])
            default:
                #expect(body as? [String: String] == route.body)
            }
        }
    }

    /// The hub's refusals as webauth/server.py sends them: `{"error": "<sentence>", "code": "<code>"}`.
    @Test(arguments: Route.allCases, [401, 403, 503])
    func everyRouteUsesSharedStatusHandling(route: Route, status: Int) async {
        let code = [401: "unauthorized", 403: "no_access", 503: "unavailable"][status]!
        let transport = EmpireFakeTransport(data: Data(#"{"error":"Fictional sentence","code":"\#(code)"}"#.utf8))
        transport.status = status
        var unauthorized = false
        do {
            try await route.call(EmpireAPI(transport: transport)) { unauthorized = true }
            Issue.record("Expected HTTP failure")
        } catch HTTPError.unauthorized {
            #expect(status == 401)
        } catch HTTPError.server(let refused, let message) {
            // A 403 `no_access` is "no access" (the app closes); a 503 keeps the server's own sentence.
            #expect(refused == status && message == "Fictional sentence")
        } catch {
            Issue.record("Unexpected \(error)")
        }
        #expect(unauthorized == (status == 401))
    }

    private func refusal(_ status: Int, _ body: String = "") -> Error? {
        let response = HTTPURLResponse(url: URL(string: "https://www.ares-empire.de/api/empire")!, statusCode: status,
                                       httpVersion: nil, headerFields: nil)!
        do {
            try checkResponse(response, data: Data(body.utf8), onUnauthorized: {})
            return nil
        } catch {
            return error
        }
    }

    @Test func refusalsWithoutASentenceUseTheAppsOwn() {
        #expect(refusal(503)?.localizedDescription == "Login service unavailable, try again")
        #expect(refusal(503, #"{"error":"  "}"#)?.localizedDescription == "Login service unavailable, try again")
        #expect(refusal(503, "<html>Bad gateway</html>")?.localizedDescription == "Login service unavailable, try again")
        #expect(refusal(403)?.localizedDescription == "This account has no access.")
        #expect(refusal(500, #"{"error":"Fictional failure","code":"server_error"}"#)?.localizedDescription == "Fictional failure")
        // PocketBase's shape: a numeric status beside the sentence does not hide it.
        #expect(refusal(400, #"{"status":400,"message":"Fictional refusal.","data":{}}"#)?.localizedDescription
                == "Fictional refusal.")
        #expect(refusal(200) == nil)
    }

    /// A 403 means "no access to this app" only with `no_access` or no code (servers that send none yet); any other
    /// code (`admin_only`) refuses that request alone.
    @Test func onlyNoAccessOrNoCodeMeansNoAccess() {
        guard case HTTPError.server(403, "No access to Empire")? = refusal(403, #"{"error":"No access to Empire","code":"no_access"}"#),
              case HTTPError.server(403, "No access to Empire")? = refusal(403, #"{"error":"No access to Empire"}"#),
              case HTTPError.forbidden("admin_only", "Administrator access required.")?
                = refusal(403, #"{"error":"Administrator access required.","code":"admin_only"}"#),
              case HTTPError.forbidden("admin_only", nil)? = refusal(403, #"{"code":"admin_only"}"#)
        else {
            Issue.record("A 403 was read wrongly")
            return
        }
        #expect(refusal(403, #"{"code":"admin_only"}"#)?.localizedDescription == "This isn't allowed for this account.")
    }

    @Test func aDecisionAnswerCarriesTheListAndTheCount() async throws {
        let transport = EmpireFakeTransport(data: Data(#"""
            {"ok": true, "approvals": [{"id": "fictional00002", "email": "two@example.invalid", "name": "",
             "created": "2026-10-25 08:00:00.000Z", "requested": ["empire"], "approved": false, "verified": false}],
             "pending": 1}
            """#.utf8))
        let api = EmpireAPI(transport: transport)
        let answer = try await api.decide(id: "fictional00001", approve: true, requested: ["empire"], token: "fictional")
        #expect(answer?.pending == 1 && answer?.approvals.map(\.id) == ["fictional00002"])
        #expect(answer?.approvals.first?.awaitsEmailConfirmation == true)

        transport.data = Data(#"{"ok": true, "approvals": [], "pending": null}"#.utf8)   // the hub could not count
        let uncounted = try await api.decide(id: "fictional00001", approve: false, requested: [], token: "fictional")
        #expect(uncounted == DecisionAnswer(approvals: [], pending: nil))

        transport.data = Data(#"{"ok": true}"#.utf8)                                     // an older hub
        #expect(try await api.decide(id: "fictional00001", approve: true, requested: [], token: "fictional") == nil)
        transport.data = Data(#"{"ok": true, "approvals": null, "pending": 1}"#.utf8)    // done; the list not read again
        #expect(try await api.decide(id: "fictional00001", approve: true, requested: [], token: "fictional") == nil)
        transport.data = Data(#"{"ok": true, "approvals": [{"id": 7}]}"#.utf8)          // unreadable: asked again
        #expect(try await api.decide(id: "fictional00001", approve: true, requested: [], token: "fictional") == nil)
    }

    @Test func verifiedIsOptionalOnAnApproval() throws {
        let decoded = try JSONDecoder().decode([PendingAccount].self, from: Data(#"""
            [{"id": "a", "email": "a@example.invalid", "name": "", "created": "", "verified": true},
             {"id": "b", "email": "b@example.invalid", "name": "", "created": "", "verified": false},
             {"id": "c", "email": "c@example.invalid", "name": "", "created": ""}]
            """#.utf8))
        #expect(decoded.map(\.verified) == [true, false, nil])
        #expect(decoded.map(\.awaitsEmailConfirmation) == [false, true, false])     // an older hub: nothing shown
    }

    @Test func decisionIDIsOnePathSegment() async throws {
        let transport = EmpireFakeTransport()
        try await EmpireAPI(transport: transport).decide(id: "made/up?value#part", approve: true, requested: [],
                                                         token: "fictional-token")
        let components = try #require(transport.requests.first?.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) })
        #expect(components.percentEncodedPath == "/api/empire/approvals/made%2Fup%3Fvalue%23part")
        #expect(components.query == nil && components.fragment == nil)
    }

    @Test func malformedDataAndTransportErrorsPropagate() async {
        let transport = EmpireFakeTransport(data: Data("invalid JSON".utf8))
        await #expect(throws: DecodingError.self) { _ = try await EmpireAPI(transport: transport).empire(token: "fictional") }
        transport.failure = URLError(.notConnectedToInternet)
        await #expect(throws: URLError.self) { _ = try await EmpireAPI(transport: transport).approvals(token: "fictional") }
    }

    private func decodingError(_ object: Any) throws -> DecodingError {
        do {
            _ = try JSONDecoder().decode(EmpireData.self, from: JSONSerialization.data(withJSONObject: object))
        } catch let error as DecodingError {
            return error
        }
        throw HTTPError.invalidResponse
    }

    /// The device log gets where the hub's answer did not fit, never a value from it.
    @Test func aDecodingFailureIsDescribedByItsPathOnly() throws {
        var hub = try #require(try JSONSerialization.jsonObject(with: empireJSON()) as? [String: Any])
        var projects = try #require(hub["projects"] as? [[String: Any]])
        #expect(AnswerDecoding.describe(try decodingError(["version": 2])) == "keyNotFound me")

        projects[0]["name"] = 42
        hub["projects"] = projects
        #expect(AnswerDecoding.describe(try decodingError(hub)) == "typeMismatch projects[0].name (expected String)")

        projects[0]["name"] = "Fictional"
        var detail = try #require(projects[1]["detail"] as? [String: Any])
        detail.removeValue(forKey: "about")
        projects[1]["detail"] = detail
        hub["projects"] = projects
        #expect(AnswerDecoding.describe(try decodingError(hub)) == "keyNotFound projects[1].detail.about")

        do {
            _ = try JSONDecoder().decode(EmpireData.self, from: Data(#"{"secret-value"#.utf8))
            Issue.record("Broken JSON decoded")
        } catch let error as DecodingError {
            #expect(AnswerDecoding.describe(error) == "dataCorrupted <root>")
        }
    }

    /// `pending` is null when the hub could not count the accounts waiting.
    @Test func pendingMayBeNull() throws {
        var hub = try #require(try JSONSerialization.jsonObject(with: empireJSON()) as? [String: Any])
        hub["pending"] = NSNull()
        #expect(try JSONDecoder().decode(EmpireData.self, from: JSONSerialization.data(withJSONObject: hub)).pending == nil)
        hub.removeValue(forKey: "pending")
        #expect(try JSONDecoder().decode(EmpireData.self, from: JSONSerialization.data(withJSONObject: hub)).pending == nil)
    }

    /// A member just approved: nothing in the ring yet, one province to add (coming soon), no news.
    @Test func anEmptyRingDecodes() async throws {
        let transport = EmpireFakeTransport(data: Data(EmpireFixtures.emptyRing.utf8))
        let data = try await EmpireAPI(transport: transport).empire(token: "fictional")
        #expect(data.projects.isEmpty && data.chronicle.isEmpty && data.ideas.isEmpty && data.pending == 0)
        #expect(data.me.admin == false && data.me.name.isEmpty)
        let addable = try #require(data.addable.only)
        #expect(addable.isComingSoon && !addable.canOpen && addable.live == nil && addable.app == "aresium://")
    }
}

extension Array {
    var only: Element? { count == 1 ? first : nil }
}
