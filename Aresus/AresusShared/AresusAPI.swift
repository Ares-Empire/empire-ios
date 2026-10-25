import Foundation

/// The Aresus API (aresus/docs/API.md): Bearer = the Empire token, statuses as every Empire service (401 token
/// rejected, 403 no `aresus` service, 503 account server unreachable, 404 unknown slug or run).
/// Compiled into the app and the widget; the widget uses only `overview`. The app's other routes are in
/// `Aresus/API/AresusAPI+Details.swift`.
struct AresusAPI {
    var transport: any HTTPTransport = URLSessionTransport()
    static let baseURL = URL(string: "https://www.ares-empire.de/api/aresus")!

    func overview(token: String, onUnauthorized: () -> Void = {}) async throws -> Overview {
        try await get(["overview"], token: token, onUnauthorized: onUnauthorized)
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

    /// One GET of the API, decoded with the contract's dates.
    func get<T: Decodable>(_ segments: [String], token: String, onUnauthorized: () -> Void) async throws -> T {
        guard let url = Self.url(segments) else { throw HTTPError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30
        let (data, response) = try await transport.send(request)
        // A 503 says which of its two reasons it is (account server unreachable, or the first check round not finished
        // yet, aresus/docs/API.md → CONTRACT ADDITION): `checkResponse` keeps the server's sentence.
        try checkResponse(response, data: data, onUnauthorized: onUnauthorized)
        return try AresusJSON.decoder().decode(T.self, from: data)
    }
}
