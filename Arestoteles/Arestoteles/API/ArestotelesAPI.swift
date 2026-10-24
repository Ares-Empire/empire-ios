import Foundation

/// The answer to `GET /vault`.
nonisolated enum VaultFetch: Equatable, Sendable {
    case notModified                                // 304: the vault the app has is current
    case fresh(Vault, etag: String?)                // 200, with the `ETag` to send next time
}

/// The edit answers that are not a plain failure (API.md → Edits).
nonisolated enum VaultAPIError: LocalizedError, Equatable {
    /// 409: the note changed since the app loaded it, or the position no longer exists. `current` is the note as it is
    /// now, when the server sent it.
    case conflict(message: String?, current: Note?)
    /// 422: the edit cannot apply (the vault's check refused it); the server's message says why.
    case invalid(message: String)

    var errorDescription: String? {
        switch self {
        case let .conflict(message, _): message ?? String(localized: "This changed elsewhere.")
        case let .invalid(message): message
        }
    }
}

/// Everything the app asks of the Arestoteles server. `ArestotelesAPI` talks to it; `SampleBackend` (DEBUG,
/// `-sampleData`) answers from the bundled samples. The store only knows this protocol.
protocol VaultBackend {
    func vault(ifNoneMatch etag: String?) async throws -> VaultFetch
    func source(note id: String) async throws -> NoteSource
    func send(_ edit: Edit) async throws -> EditResult
    func search(_ query: String, limit: Int) async throws -> SearchAnswer
}

/// The Arestoteles API (Arestoteles/docs/API.md, version 1), with the Empire login's Bearer token. Statuses go through
/// the shared `checkResponse` (401, 403, 503); 304 is a current vault, 409 and 422 are `VaultAPIError`s.
struct ArestotelesAPI: VaultBackend {
    static let baseURL = URL(string: "https://www.ares-empire.de/api/arestoteles")!

    var transport: any HTTPTransport = URLSessionTransport()
    /// The current Empire token, read when a request starts; nil = not signed in.
    let token: () -> String?

    func vault(ifNoneMatch etag: String?) async throws -> VaultFetch {
        var request = try request("GET", path: "/vault", timeout: 60)
        // The ETag is the server's to format (the vault commit): it is sent back exactly as it came.
        if let etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        let (data, response) = try await transport.send(request)
        if response.statusCode == 304 { return .notModified }
        try check(response, data: data)
        return .fresh(try JSONDecoder().decode(Vault.self, from: data), etag: response.value(forHTTPHeaderField: "ETag"))
    }

    func source(note id: String) async throws -> NoteSource {
        let request = try request("GET", path: "/notes/" + NoteLink.encode(id) + "/source")
        let (data, response) = try await transport.send(request)
        try check(response, data: data)
        return try JSONDecoder().decode(NoteSource.self, from: data)
    }

    /// The passages that answer a query, by words and meaning. Short timeout: the search waits for nobody, and the
    /// device's own results stand alone when this fails.
    func search(_ query: String, limit: Int) async throws -> SearchAnswer {
        let request = try request("GET", path: "/search", query: "q=\(NoteLink.encode(query))&limit=\(limit)",
                                  timeout: 5)
        let (data, response) = try await transport.send(request)
        try check(response, data: data)
        return try JSONDecoder().decode(SearchAnswer.self, from: data)
    }

    func send(_ edit: Edit) async throws -> EditResult {
        var request = try request("POST", path: "/edits", timeout: 60)
        request.httpBody = try JSONEncoder().encode(edit)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await transport.send(request)
        switch response.statusCode {
        case 409:
            let body = try? JSONDecoder().decode(ConflictBody.self, from: data)
            throw VaultAPIError.conflict(message: body?.error, current: body?.current)
        case 422:
            let body = try? JSONDecoder().decode(ServerMessage.self, from: data)
            throw VaultAPIError.invalid(message: body?.error ?? body?.message
                                        ?? String(localized: "The vault's check refused this edit."))
        default:
            try check(response, data: data)
        }
        return try JSONDecoder().decode(EditResult.self, from: data)
    }

    // MARK: - requests

    /// The shared statuses (`checkResponse`), except that a 503 keeps the server's own sentence when it sends one: the
    /// shared message speaks of the account server, while this server also answers 503 before its first index is
    /// built ("still loading", API.md).
    private func check(_ response: HTTPURLResponse, data: Data) throws {
        if response.statusCode == 503, let message = try? JSONDecoder().decode(ServerMessage.self, from: data).error {
            throw HTTPError.server(503, message)
        }
        try checkResponse(response, data: data, onUnauthorized: {})
    }

    /// `{"error": "…", "current": Note}` of a 409.
    private struct ConflictBody: Decodable {
        let error: String?
        let current: Note?
    }

    /// `query`: already percent-encoded (every character but the unreserved ones, so "+" and "&" in a query stay text).
    private func request(_ method: String, path: String, query: String? = nil, timeout: TimeInterval = 30) throws
        -> URLRequest {
        guard let token = token(), !token.isEmpty else { throw HTTPError.unauthorized }
        // The path is set percent-encoded, so a note id stays one segment whatever it contains.
        guard var components = URLComponents(url: Self.baseURL, resolvingAgainstBaseURL: false) else {
            throw HTTPError.invalidResponse
        }
        components.percentEncodedPath += path
        components.percentEncodedQuery = query
        guard let url = components.url else { throw HTTPError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = timeout
        // The app does its own revalidation (If-None-Match); a local cache must not answer for the server.
        request.cachePolicy = .reloadIgnoringLocalCacheData
        return request
    }
}
