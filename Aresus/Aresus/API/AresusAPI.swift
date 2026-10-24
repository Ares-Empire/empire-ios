import Foundation

/// The app's routes of the Aresus API (aresus/docs/API.md): Bearer = the Empire token, statuses as every Empire service
/// (401 token rejected, 403 no `aresus` service, 503 account server unreachable, 404 unknown slug or run).
struct AresusAPI {
    var transport: any HTTPTransport = URLSessionTransport()
    static let baseURL = URL(string: "https://www.ares-empire.de/api/aresus")!

    func overview(token: String, onUnauthorized: () -> Void = {}) async throws -> Overview {
        try await get(["overview"], token: token, onUnauthorized: onUnauthorized)
    }

    func province(_ slug: String, token: String, onUnauthorized: () -> Void = {}) async throws -> ProvinceDetail {
        try await get(["provinces", slug], token: token, onUnauthorized: onUnauthorized)
    }

    func sync(token: String, onUnauthorized: () -> Void = {}) async throws -> SyncOverview {
        try await get(["sync"], token: token, onUnauthorized: onUnauthorized)
    }

    func run(_ id: Int, token: String, onUnauthorized: () -> Void = {}) async throws -> RunDetail {
        try await get(["sync", "runs", String(id)], token: token, onUnauthorized: onUnauthorized)
    }

    /// Each segment goes into the path as exactly one segment, whatever characters it holds.
    static func url(_ segments: [String]) -> URL? {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/%?#;")
        var encoded: [String] = []
        for segment in segments {
            guard !segment.isEmpty, segment != ".", segment != "..",
                  let part = segment.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
            encoded.append(part)
        }
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.percentEncodedPath = baseURL.path + "/" + encoded.joined(separator: "/")
        return components?.url
    }

    private func get<T: Decodable>(_ segments: [String], token: String, onUnauthorized: () -> Void) async throws -> T {
        guard let url = Self.url(segments) else { throw HTTPError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30
        let (data, response) = try await transport.send(request)
        // Aresus answers 503 for two reasons (account server unreachable, or its first check round not finished yet,
        // aresus/docs/API.md → CONTRACT ADDITION) and says which in `error`; keep its sentence over the shared one.
        if response.statusCode == 503, let message = try? JSONDecoder().decode(ServerMessage.self, from: data).error,
           !message.isEmpty {
            throw HTTPError.server(503, message)
        }
        try checkResponse(response, data: data, onUnauthorized: onUnauthorized)
        return try AresusJSON.decoder().decode(T.self, from: data)
    }
}
