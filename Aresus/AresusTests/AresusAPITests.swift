import Foundation
import Testing
@testable import Aresus

/// The app's four routes as the contract writes them, with the Empire token and the shared status handling.
@MainActor
struct AresusAPITests {
    enum Route: String, CaseIterable {
        case overview, province, sync, run

        var path: String {
            switch self {
            case .overview: "/api/aresus/overview"
            case .province: "/api/aresus/provinces/aresium"
            case .sync: "/api/aresus/sync"
            case .run: "/api/aresus/sync/runs/612"
            }
        }

        var sampleName: String {
            switch self {
            case .overview: "overview"
            case .province: "province"
            case .sync: "sync"
            case .run: "run"
            }
        }

        func call(_ api: AresusAPI, onUnauthorized: () -> Void = {}) async throws {
            switch self {
            case .overview: _ = try await api.overview(token: "fictional-token", onUnauthorized: onUnauthorized)
            case .province: _ = try await api.province("aresium", token: "fictional-token", onUnauthorized: onUnauthorized)
            case .sync: _ = try await api.sync(token: "fictional-token", onUnauthorized: onUnauthorized)
            case .run: _ = try await api.run(612, token: "fictional-token", onUnauthorized: onUnauthorized)
            }
        }
    }

    @Test(arguments: Route.allCases)
    func requestsFollowContract(route: Route) async throws {
        let transport = FakeTransport(data: try sampleData(route.sampleName))
        let api = AresusAPI(transport: transport)
        switch route {
        case .overview: #expect(try await api.overview(token: "fictional-token") == sample("overview"))
        case .province: #expect(try await api.province("aresium", token: "fictional-token") == sample("province"))
        case .sync: #expect(try await api.sync(token: "fictional-token") == sample("sync"))
        case .run: #expect(try await api.run(612, token: "fictional-token") == sample("run"))
        }
        let request = try #require(transport.requests.only)
        #expect(request.url?.absoluteString == "https://www.ares-empire.de\(route.path)")
        #expect(request.httpMethod == "GET")
        #expect(request.httpBody == nil)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fictional-token")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(request.timeoutInterval == 30)
    }

    @Test(arguments: Route.allCases, [401, 403, 404, 503])
    func everyRouteUsesSharedStatusHandling(route: Route, status: Int) async {
        let transport = FakeTransport(data: Data(#"{"error":"No aresus service"}"#.utf8))
        transport.status = status
        var unauthorized = false
        do {
            try await route.call(AresusAPI(transport: transport)) { unauthorized = true }
            Issue.record("Expected HTTP \(status) to fail")
        } catch {
            switch status {
            case 401: #expect(error.localizedDescription == "Your session expired. Please log in again.")
            case 503: #expect(error.localizedDescription == "Login service unavailable, try again")
            default: #expect(error.localizedDescription == "No aresus service")
            }
        }
        #expect(unauthorized == (status == 401))
    }

    @Test func aSlugIsOnePathSegment() async throws {
        let transport = FakeTransport(data: try sampleData("province"))
        _ = try await AresusAPI(transport: transport).province("made/up?slug#part", token: "fictional-token")
        let url = try #require(transport.requests.first?.url)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.percentEncodedPath == "/api/aresus/provinces/made%2Fup%3Fslug%23part")
        #expect(components.query == nil && components.fragment == nil)
    }

    @Test(arguments: ["", ".", ".."])
    func unusableSlugsSendNothing(slug: String) async {
        let transport = FakeTransport()
        await #expect(throws: HTTPError.self) {
            _ = try await AresusAPI(transport: transport).province(slug, token: "fictional-token")
        }
        #expect(transport.requests.isEmpty)
    }

    @Test func malformedAnswersAndTransportErrorsPropagate() async {
        let transport = FakeTransport(data: Data("not JSON".utf8))
        await #expect(throws: DecodingError.self) { _ = try await AresusAPI(transport: transport).overview(token: "fictional") }
        transport.failure = URLError(.notConnectedToInternet)
        await #expect(throws: URLError.self) { _ = try await AresusAPI(transport: transport).sync(token: "fictional") }
    }
}
