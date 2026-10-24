import Foundation

/// Everything the app asks of Arestemis. `ArestemisAPI` talks to the server; `SampleBackend` (DEBUG, `-sampleData`)
/// answers from the bundled samples in memory. The store only knows this protocol.
protocol ArestemisBackend {
    func overview() async throws -> Overview
    func createHunt(_ search: Search) async throws -> Hunt
    func updateHunt(id: Int, search: Search) async throws -> Hunt
    func setHunt(id: Int, active: Bool) async throws -> Hunt
    func deleteHunt(id: Int) async throws
    func parse(_ text: String) async throws -> ParsedSearch
    func places(query: String) async throws -> [Place]
    func matches(states: [MatchState]?, limit: Int, before: Int?) async throws -> MatchPage
    func match(id: Int) async throws -> Match
    func setState(_ state: MatchState, match id: Int) async throws -> Match
    func application(match id: Int, regenerate: Bool) async throws -> Application
    func rejected(limit: Int) async throws -> RejectedPage
    func settings() async throws -> Settings
    func saveSettings(_ settings: Settings) async throws -> Settings
}

/// The Arestemis API (Arestemis/docs/API.md), with the Empire login's Bearer token. Statuses go through the shared
/// `checkResponse`; the store hands failures to `EmpireSession.handleAuthFailure` (401 logs out, 403 closes this app).
struct ArestemisAPI: ArestemisBackend {
    static let baseURL = URL(string: "https://www.ares-empire.de/api/arestemis")!
    /// Routes where the server asks the AI (parse, application) may take longer than a plain read.
    static let aiTimeout: TimeInterval = 60

    var transport: any HTTPTransport = URLSessionTransport()
    /// The current Empire token, read when a request starts; nil = not signed in.
    let token: () -> String?

    func overview() async throws -> Overview { try await send(.get, "overview") }

    func createHunt(_ search: Search) async throws -> Hunt {
        try await send(.post, "hunts", body: SearchBody(search: search))
    }

    func updateHunt(id: Int, search: Search) async throws -> Hunt {
        try await send(.put, "hunts/\(id)", body: SearchBody(search: search))
    }

    func setHunt(id: Int, active: Bool) async throws -> Hunt {
        try await send(.post, "hunts/\(id)/active", body: ["active": active])
    }

    func deleteHunt(id: Int) async throws {
        _ = try await data(.delete, "hunts/\(id)")
    }

    func parse(_ text: String) async throws -> ParsedSearch {
        try await send(.post, "search/parse", body: ["text": text], timeout: Self.aiTimeout)
    }

    func places(query: String) async throws -> [Place] {
        try await send(.get, "places", query: [URLQueryItem(name: "q", value: query)])
    }

    func matches(states: [MatchState]?, limit: Int, before: Int?) async throws -> MatchPage {
        var query: [URLQueryItem] = []
        if let states, !states.isEmpty {
            query.append(URLQueryItem(name: "state", value: states.map(\.rawValue).joined(separator: ",")))
        }
        query.append(URLQueryItem(name: "limit", value: String(limit)))
        if let before { query.append(URLQueryItem(name: "before", value: String(before))) }
        return try await send(.get, "matches", query: query)
    }

    func match(id: Int) async throws -> Match { try await send(.get, "matches/\(id)") }

    func setState(_ state: MatchState, match id: Int) async throws -> Match {
        try await send(.post, "matches/\(id)/state", body: ["state": state.rawValue])
    }

    func application(match id: Int, regenerate: Bool) async throws -> Application {
        try await send(.post, "matches/\(id)/application", body: regenerate ? ["regenerate": true] : [String: Bool](),
                       timeout: Self.aiTimeout)
    }

    func rejected(limit: Int) async throws -> RejectedPage {
        try await send(.get, "rejected", query: [URLQueryItem(name: "limit", value: String(limit))])
    }

    func settings() async throws -> Settings { try await send(.get, "settings") }

    func saveSettings(_ settings: Settings) async throws -> Settings {
        try await send(.put, "settings", body: settings)
    }

    // MARK: - requests

    enum Method: String { case get = "GET", post = "POST", put = "PUT", delete = "DELETE" }

    private struct SearchBody: Encodable { let search: Search }
    private struct NoBody: Encodable {}

    private func send<Response: Decodable>(_ method: Method, _ path: String, query: [URLQueryItem] = []) async throws -> Response {
        try await send(method, path, query: query, body: Optional<NoBody>.none)
    }

    private func send<Response: Decodable, Body: Encodable>(_ method: Method, _ path: String, query: [URLQueryItem] = [],
                                                            body: Body?, timeout: TimeInterval = 30) async throws -> Response {
        let data = try await data(method, path, query: query, body: body, timeout: timeout)
        return try JSONDecoder().decode(Response.self, from: data)
    }

    private func data(_ method: Method, _ path: String, query: [URLQueryItem] = []) async throws -> Data {
        try await data(method, path, query: query, body: Optional<NoBody>.none)
    }

    private func data<Body: Encodable>(_ method: Method, _ path: String, query: [URLQueryItem],
                                       body: Body?, timeout: TimeInterval = 30) async throws -> Data {
        guard let token = token(), !token.isEmpty else { throw HTTPError.unauthorized }
        var components = URLComponents(url: Self.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        if !query.isEmpty { components?.queryItems = query }
        guard let url = components?.url else { throw HTTPError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        if let body {
            request.httpBody = try JSONEncoder().encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = timeout
        let (data, response) = try await transport.send(request)
        try checkResponse(response, data: data, onUnauthorized: {})
        return data
    }
}
