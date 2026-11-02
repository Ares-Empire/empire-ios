import Foundation

/// Everything the app asks of Arestemis. `ArestemisAPI` talks to the server; `SampleBackend` (DEBUG, `-sampleData`)
/// answers from the bundled samples in memory. The store only knows this protocol.
protocol ArestemisBackend {
    func overview() async throws -> Overview
    func kinds() async throws -> [OfferedKind]
    func hunts() async throws -> [Hunt]
    func createHunt(kind: HuntKind, name: String?, search: HuntSearch) async throws -> Hunt
    func updateHunt(id: Int, search: HuntSearch, name: String?) async throws -> Hunt
    /// The name alone (`PATCH /hunts/{id}`): unlike `updateHunt` the server does not start the search again.
    func renameHunt(id: Int, name: String?) async throws -> Hunt
    func setActive(id: Int, active: Bool) async throws -> Hunt
    func deleteHunt(id: Int) async throws
    func parse(text: String, kind: HuntKind) async throws -> HuntParseResult
    func places(query: String) async throws -> [Place]
    func matches(hunt: Int?, state: [MatchState]?, limit: Int, before: Int?) async throws -> MatchPage
    /// `GET /matches?q=`: every state but dismissed, best match first (brief 132).
    func findMatches(_ words: String, hunt: Int?, limit: Int) async throws -> MatchPage
    func match(id: Int) async throws -> Match
    func setState(_ state: MatchState, match id: Int) async throws -> Match
    func application(match id: Int, regenerate: Bool) async throws -> Application
    func rejected(hunt: Int?, limit: Int) async throws -> RejectedPage
    func settings() async throws -> Settings
    func saveSettings(_ settings: Settings) async throws -> Settings
}

/// The Arestemis API (Arestemis/docs/API.md), with the Empire login's Bearer token. Statuses go through the shared
/// `checkResponse`; the store hands failures to `EmpireSession.handleAuthFailure` (401 logs out, 403 closes this app).
struct ArestemisAPI: ArestemisBackend {
    static let baseURL = URL(string: "https://www.ares-empire.de/api/arestemis")!
    /// `DELETE /me`: the account's own data on the server (settings, hunts, matches, applications). Settings → Account →
    /// Leave Arestemis calls it before the access goes (`LeaveAppFlow`); deleting the account reaches it on the server.
    static let accountDataURL = baseURL.appendingPathComponent("me")
    /// Routes where the server asks the AI (parse, application) may take longer than a plain read.
    static let aiTimeout: TimeInterval = 60

    var transport: any HTTPTransport = URLSessionTransport()
    /// The current Empire token, read when a request starts; nil = not signed in.
    let token: () -> String?

    func overview() async throws -> Overview { try await send(.get, "overview") }

    /// `GET /kinds`: each kind of search and the sites it can use, set up or not, with or without auctions.
    func kinds() async throws -> [OfferedKind] { try await send(.get, "kinds") }

    func hunts() async throws -> [Hunt] { try await send(.get, "hunts") }

    func createHunt(kind: HuntKind, name: String?, search: HuntSearch) async throws -> Hunt {
        try await send(.post, "hunts", body: CreateBody(kind: kind, name: name, search: search))
    }

    func updateHunt(id: Int, search: HuntSearch, name: String?) async throws -> Hunt {
        try await send(.put, "hunts/\(id)", body: UpdateBody(search: search, name: name))
    }

    func renameHunt(id: Int, name: String?) async throws -> Hunt {
        try await send(.patch, "hunts/\(id)", body: NameBody(name: name))
    }

    func setActive(id: Int, active: Bool) async throws -> Hunt {
        try await send(.post, "hunts/\(id)/active", body: ["active": active])
    }

    func deleteHunt(id: Int) async throws {
        _ = try await data(.delete, "hunts/\(id)")
    }

    func parse(text: String, kind: HuntKind) async throws -> HuntParseResult {
        let body = ["text": text, "kind": kind.rawValue]
        switch kind {
        case .flat: return .flat(try await send(.post, "search/parse", body: body, timeout: Self.aiTimeout))
        case .item: return .item(try await send(.post, "search/parse", body: body, timeout: Self.aiTimeout))
        case .watch, .unknown: throw HTTPError.server(400, "This hunt needs a newer app.")
        }
    }

    func places(query: String) async throws -> [Place] {
        try await send(.get, "places", query: [URLQueryItem(name: "q", value: query)])
    }

    func matches(hunt: Int?, state states: [MatchState]?, limit: Int, before: Int?) async throws -> MatchPage {
        var query: [URLQueryItem] = []
        if let hunt { query.append(URLQueryItem(name: "hunt", value: String(hunt))) }
        if let states, !states.isEmpty {
            query.append(URLQueryItem(name: "state", value: states.map(\.rawValue).joined(separator: ",")))
        }
        query.append(URLQueryItem(name: "limit", value: String(limit)))
        if let before { query.append(URLQueryItem(name: "before", value: String(before))) }
        return try await send(.get, "matches", query: query)
    }

    /// The found listings that match the words, best match first (the server's order; no `before`, no `state`: all but
    /// dismissed). The words are the app's (`ListingSearch.words`): trimmed, 2–100 characters.
    func findMatches(_ words: String, hunt: Int?, limit: Int) async throws -> MatchPage {
        var query = [URLQueryItem(name: "q", value: words)]
        if let hunt { query.append(URLQueryItem(name: "hunt", value: String(hunt))) }
        query.append(URLQueryItem(name: "limit", value: String(limit)))
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

    func rejected(hunt: Int?, limit: Int) async throws -> RejectedPage {
        var query = [URLQueryItem(name: "limit", value: String(limit))]
        if let hunt { query.append(URLQueryItem(name: "hunt", value: String(hunt))) }
        return try await send(.get, "rejected", query: query)
    }

    func settings() async throws -> Settings { try await send(.get, "settings") }

    func saveSettings(_ settings: Settings) async throws -> Settings {
        try await send(.put, "settings", body: settings)
    }

    // MARK: - requests

    enum Method: String { case get = "GET", post = "POST", put = "PUT", patch = "PATCH", delete = "DELETE" }

    private struct CreateBody: Encodable {
        let kind: HuntKind
        let name: String?
        let search: HuntSearch
        enum CodingKeys: CodingKey { case kind, name, search }
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(kind, forKey: .kind)
            try c.encode(name, forKey: .name)
            try c.encode(search, forKey: .search)
        }
    }
    private struct UpdateBody: Encodable {
        let search: HuntSearch
        let name: String?
        enum CodingKeys: CodingKey { case search, name }
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(search, forKey: .search)
            try c.encode(name, forKey: .name)
        }
    }
    /// `{"name": null}` clears the name, so the null is sent rather than left out.
    private struct NameBody: Encodable {
        let name: String?
        enum CodingKeys: CodingKey { case name }
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(name, forKey: .name)
        }
    }
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
        if !query.isEmpty {
            components?.queryItems = query
            // A typed "+" stays a plus: servers read a bare one in a query as a space.
            let encoded = components?.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
            components?.percentEncodedQuery = encoded
        }
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
        if let refusal = FieldRefusal(status: response.statusCode, data: data) { throw refusal }
        try checkResponse(response, data: data, onUnauthorized: {})
        return data
    }
}

/// A `400` that names the field it is about (`{"error": "…", "field": "search.url"}`, Arestemis/docs/API.md), so a
/// form can show the server's sentence at that field. Its description is the sentence, as any refusal's.
struct FieldRefusal: LocalizedError, Equatable {
    let field: String
    let message: String

    var errorDescription: String? { message }

    /// Nil for any other answer: another status, no field or no sentence (those go on as `HTTPError`).
    init?(status: Int, data: Data) {
        struct Body: Decodable { let error: String?; let message: String?; let field: String? }
        guard status == 400, let body = try? JSONDecoder().decode(Body.self, from: data),
              let field = body.field?.trimmingCharacters(in: .whitespaces), !field.isEmpty,
              let sentence = [body.error, body.message].compactMap({ $0?.trimmingCharacters(in: .whitespacesAndNewlines) })
                .first(where: { !$0.isEmpty }) else { return nil }
        self.field = field
        message = sentence
    }

    init(field: String, message: String) {
        self.field = field
        self.message = message
    }
}

// brief 114 replaces: compatibility calls for the current flat screens and callers.
extension ArestemisBackend {
    func createHunt(_ search: Search) async throws -> Hunt {
        try await createHunt(kind: .flat, name: nil, search: .flat(search))
    }
    func updateHunt(id: Int, search: Search) async throws -> Hunt {
        // Preserve an existing name for callers that only edit the flat search.
        let current = try await hunts().first { $0.id == id }
        return try await updateHunt(id: id, search: .flat(search), name: current?.name)
    }
    func setHunt(id: Int, active: Bool) async throws -> Hunt { try await setActive(id: id, active: active) }
    func parse(_ text: String) async throws -> ParsedSearch {
        guard case .flat(let parsed) = try await parse(text: text, kind: .flat) else { throw HTTPError.invalidResponse }
        return parsed
    }
    func matches(states: [MatchState]?, limit: Int, before: Int?) async throws -> MatchPage {
        try await matches(hunt: nil, state: states, limit: limit, before: before)
    }
    func rejected(limit: Int) async throws -> RejectedPage { try await rejected(hunt: nil, limit: limit) }
}
