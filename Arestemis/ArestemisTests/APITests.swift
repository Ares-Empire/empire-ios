import Foundation
import Testing
@testable import Arestemis

/// Every route of Arestemis/docs/API.md: path, method, query, body and the Bearer token; statuses through the shared
/// `checkResponse`.
@MainActor
struct APITests {
    enum Route: String, CaseIterable {
        case overview, createHunt, updateHunt, startHunt, deleteHunt, parse, places, matches, match, state
        case application, regenerate, rejected, settings, saveSettings

        var method: String {
            switch self {
            case .overview, .places, .matches, .match, .rejected, .settings: "GET"
            case .updateHunt, .saveSettings: "PUT"
            case .deleteHunt: "DELETE"
            default: "POST"
            }
        }

        var path: String {
            switch self {
            case .overview: "/overview"
            case .createHunt: "/hunts"
            case .updateHunt, .deleteHunt: "/hunts/1"
            case .startHunt: "/hunts/1/active"
            case .parse: "/search/parse"
            case .places: "/places"
            case .matches: "/matches"
            case .match: "/matches/41"
            case .state: "/matches/41/state"
            case .application, .regenerate: "/matches/41/application"
            case .rejected: "/rejected"
            case .settings, .saveSettings: "/settings"
            }
        }

        /// The answer the fake server gives (a sample, or a made-up one in the contract's shape).
        func answer() throws -> (Int, Data) {
            let hunt = try #require(try sample(Overview.self, "overview").hunt)
            switch self {
            case .overview: return (200, try ArestemisSamples.data("overview"))
            case .createHunt, .updateHunt, .startHunt: return (200, try JSONEncoder().encode(hunt))
            case .deleteHunt: return (204, Data())
            case .parse: return (200, Data(#"{"search":{"kinds":["flat"]},"unclear":[]}"#.utf8))
            case .places: return (200, try ArestemisSamples.data("places"))
            case .matches: return (200, try ArestemisSamples.data("matches"))
            case .match, .state: return (200, try ArestemisSamples.data("match"))
            case .application, .regenerate:
                return (200, Data(#"{"text":"Hallo","mode":"own","created":"2026-10-24T10:00:00Z"}"#.utf8))
            case .rejected: return (200, try ArestemisSamples.data("rejected"))
            case .settings, .saveSettings: return (200, try ArestemisSamples.data("settings"))
            }
        }

        func call(_ api: ArestemisAPI) async throws {
            let search = try #require(try sample(Overview.self, "overview").hunt?.search.flat)
            switch self {
            case .overview: _ = try await api.overview()
            case .createHunt: _ = try await api.createHunt(search)
            case .updateHunt: _ = try await api.updateHunt(id: 1, search: .flat(search), name: nil)
            case .startHunt: _ = try await api.setHunt(id: 1, active: true)
            case .deleteHunt: try await api.deleteHunt(id: 1)
            case .parse: _ = try await api.parse("2 rooms in Schwabing")
            case .places: _ = try await api.places(query: "garch")
            case .matches: _ = try await api.matches(states: [.new, .saved], limit: 50, before: 40)
            case .match: _ = try await api.match(id: 41)
            case .state: _ = try await api.setState(.saved, match: 41)
            case .application: _ = try await api.application(match: 41, regenerate: false)
            case .regenerate: _ = try await api.application(match: 41, regenerate: true)
            case .rejected: _ = try await api.rejected(limit: 50)
            case .settings: _ = try await api.settings()
            case .saveSettings: _ = try await api.saveSettings(sample(Settings.self, "settings"))
            }
        }
    }

    private func api(_ transport: FakeTransport, token: String? = "fictional-token") -> ArestemisAPI {
        ArestemisAPI(transport: transport, token: { token })
    }

    @Test(arguments: Route.allCases)
    func requestsFollowTheContract(route: Route) async throws {
        let transport = FakeTransport(fallback: try route.answer())
        try await route.call(api(transport))
        let request = try #require(transport.requests.only)
        let url = try #require(request.url)
        #expect(url.scheme == "https" && url.host() == "www.ares-empire.de")
        #expect(url.path(percentEncoded: false) == "/api/arestemis" + route.path)
        #expect(request.httpMethod == route.method)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fictional-token")
        let hasBody = route.method == "POST" || route.method == "PUT"
        #expect((request.httpBody != nil) == hasBody)
        #expect((request.value(forHTTPHeaderField: "Content-Type") == "application/json") == hasBody)
        let json = try body(request)
        switch route {
        case .createHunt, .updateHunt:
            let search = try #require(json?["search"] as? [String: Any])
            #expect(json?.count == (route == .createHunt ? 3 : 2) && json?["name"] is NSNull && search["kinds"] as? [String] == ["flat", "wg"])
        case .startHunt: #expect(json?["active"] as? Bool == true && json?.count == 1)
        case .parse: #expect(json?["text"] as? String == "2 rooms in Schwabing" && json?["kind"] as? String == "flat" && json?.count == 2)
        case .state: #expect(json?["state"] as? String == "saved" && json?.count == 1)
        case .application: #expect(json?.isEmpty == true)
        case .regenerate: #expect(json?["regenerate"] as? Bool == true && json?.count == 1)
        case .saveSettings: #expect(json?["application_mode"] as? String == "ai")
        default: break
        }
        #expect(request.timeoutInterval == ([.parse, .application, .regenerate].contains(route) ? 60 : 30))
    }

    @Test func queries() async throws {
        let transport = FakeTransport(fallback: (200, try ArestemisSamples.data("matches")))
        _ = try await api(transport).matches(states: [.new, .saved], limit: 50, before: 40)
        _ = try await api(transport).matches(states: nil, limit: 20, before: nil)
        transport.fallback = (200, try ArestemisSamples.data("places"))
        _ = try await api(transport).places(query: "München Nord")
        transport.fallback = (200, try ArestemisSamples.data("rejected"))
        _ = try await api(transport).rejected(limit: 50)
        let queries = transport.requests.map { URLComponents(url: $0.url!, resolvingAgainstBaseURL: false)?.queryItems ?? [] }
        #expect(queries[0] == [.init(name: "state", value: "new,saved"), .init(name: "limit", value: "50"),
                               .init(name: "before", value: "40")])
        #expect(queries[1] == [.init(name: "limit", value: "20")])
        #expect(queries[2] == [.init(name: "q", value: "München Nord")])
        #expect(transport.requests[2].url?.query(percentEncoded: true) == "q=M%C3%BCnchen%20Nord")
        #expect(queries[3] == [.init(name: "limit", value: "50")])
    }

    @Test(arguments: [401, 403, 404, 409, 503])
    func statusesBecomeErrors(status: Int) async throws {
        let transport = FakeTransport(fallback: (status, Data(#"{"error":"Made-up refusal","field":"kinds"}"#.utf8)))
        do {
            _ = try await api(transport).overview()
            Issue.record("Expected a failure")
        } catch HTTPError.unauthorized {
            #expect(status == 401)
        } catch HTTPError.server(let code, let message) {
            #expect(code == status)
            #expect(message == "Made-up refusal")          // a 503 too keeps the server's own sentence
        }
    }

    @Test func noTokenSendsNothing() async {
        let transport = FakeTransport()
        await #expect(throws: HTTPError.self) { _ = try await api(transport, token: nil).overview() }
        await #expect(throws: HTTPError.self) { _ = try await api(transport, token: "").settings() }
        #expect(transport.requests.isEmpty)
    }

    @Test func brokenAnswersAndTransportErrorsPropagate() async {
        let transport = FakeTransport(fallback: (200, Data("not JSON".utf8)))
        await #expect(throws: DecodingError.self) { _ = try await api(transport).overview() }
        transport.failure = URLError(.notConnectedToInternet)
        await #expect(throws: URLError.self) { _ = try await api(transport).settings() }
    }
}
