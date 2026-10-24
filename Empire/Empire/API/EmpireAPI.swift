import Foundation

/// The per-account hub contract in ares-empire/docs/API-EMPIRE.md.
struct EmpireAPI {
    var transport: any HTTPTransport = URLSessionTransport()
    private let baseURL = URL(string: "https://www.ares-empire.de")!

    func empire(token: String, onUnauthorized: () -> Void = {}) async throws -> EmpireData {
        try await decoded("api/empire", token: token, onUnauthorized: onUnauthorized)
    }

    func ring(add slug: String, token: String, onUnauthorized: () -> Void = {}) async throws -> EmpireData {
        try await decoded("api/empire/ring", body: JSONEncoder().encode(["add": slug]),
                          token: token, onUnauthorized: onUnauthorized)
    }

    func ring(remove slug: String, token: String, onUnauthorized: () -> Void = {}) async throws -> EmpireData {
        try await decoded("api/empire/ring", body: JSONEncoder().encode(["remove": slug]),
                          token: token, onUnauthorized: onUnauthorized)
    }

    func approvals(token: String, onUnauthorized: () -> Void = {}) async throws -> [PendingAccount] {
        try await decoded("api/empire/approvals", token: token, onUnauthorized: onUnauthorized)
    }

    func decide(id: String, approve: Bool, token: String, onUnauthorized: () -> Void = {}) async throws {
        // Append the account ID as one path segment, even if it contains reserved characters.
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/%?#")
        guard !id.isEmpty, id != ".", id != "..",
              let segment = id.addingPercentEncoding(withAllowedCharacters: allowed) else {
            throw HTTPError.invalidResponse
        }
        _ = try await request("api/empire/approvals/\(segment)",
                              body: JSONEncoder().encode([approve ? "approve" : "decline": true]),
                              token: token, onUnauthorized: onUnauthorized)
    }

    private func decoded<T: Decodable>(_ path: String, body: Data? = nil, token: String,
                                       onUnauthorized: () -> Void) async throws -> T {
        let data = try await request(path, body: body, token: token, onUnauthorized: onUnauthorized)
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func request(_ path: String, body: Data? = nil, token: String,
                         onUnauthorized: () -> Void) async throws -> Data {
        guard let url = URL(string: "/\(path)", relativeTo: baseURL)?.absoluteURL else {
            throw HTTPError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = body == nil ? "GET" : "POST"
        request.httpBody = body
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30
        let (data, response) = try await transport.send(request)
        try checkResponse(response, data: data, onUnauthorized: onUnauthorized)
        return data
    }
}
