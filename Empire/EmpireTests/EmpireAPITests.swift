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
                try await api.decide(id: "fictional-id", approve: self == .approve, token: "fictional-token",
                                     onUnauthorized: onUnauthorized)
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
            // A decision may return an empty 204; there is no invented response model.
            transport.status = 204
            transport.data = Data()
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
            #expect(body?.count == 1)
            if let expected = route.body {
                #expect(body as? [String: String] == expected)
            } else {
                #expect(body?[route == .approve ? "approve" : "decline"] as? Bool == true)
            }
        }
    }

    @Test(arguments: Route.allCases, [401, 403, 503])
    func everyRouteUsesSharedStatusHandling(route: Route, status: Int) async {
        let transport = EmpireFakeTransport(data: Data(#"{"error":"Service access denied"}"#.utf8))
        transport.status = status
        var unauthorized = false
        do {
            try await route.call(EmpireAPI(transport: transport)) { unauthorized = true }
            Issue.record("Expected HTTP failure")
        } catch {
            #expect(error.localizedDescription == (status == 401 ? "Your session expired. Please log in again." :
                status == 503 ? "Login service unavailable, try again" : "Service access denied"))
        }
        #expect(unauthorized == (status == 401))
    }

    @Test func decisionIDIsOnePathSegment() async throws {
        let transport = EmpireFakeTransport()
        try await EmpireAPI(transport: transport).decide(id: "made/up?value#part", approve: true, token: "fictional-token")
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
}

extension Array {
    var only: Element? { count == 1 ? first : nil }
}
