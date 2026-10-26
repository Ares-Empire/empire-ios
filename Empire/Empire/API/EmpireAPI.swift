import Foundation

/// The per-account hub contract in ares-empire/docs/API-EMPIRE.md.
struct EmpireAPI {
    var transport: any HTTPTransport = URLSessionTransport()
    private let baseURL = URL(string: "https://www.ares-empire.de")!

    func empire(token: String, onUnauthorized: () -> Void = {}) async throws -> EmpireData {
        try await decoded("api/empire", token: token, onUnauthorized: onUnauthorized)
    }

    /// Asks for access to an app of the "+" sheet (`{"service": slug}`): it goes into the account's `requested` and
    /// Patrik is told. Answers the hub data afresh, with that app's `access` now "requested"; asking again changes
    /// nothing. 400 `bad_request` (with the hub's sentence) for an app that cannot be requested.
    func request(service slug: String, token: String, onUnauthorized: () -> Void = {}) async throws -> EmpireData {
        try await decoded("api/empire/request", body: JSONEncoder().encode(["service": slug]),
                          token: token, onUnauthorized: onUnauthorized)
    }

    func approvals(token: String, onUnauthorized: () -> Void = {}) async throws -> [PendingAccount] {
        try await decoded("api/empire/approvals", token: token, onUnauthorized: onUnauthorized)
    }

    /// Approves the account, granting `requested` (the apps its card shows, so a request made meanwhile is not granted
    /// unseen), or declines it (an approved account's `requested` only are withdrawn; a new sign-up is deleted).
    /// Returns the list and the count after the decision; nil when the answer has no list (an older hub's
    /// `{"ok": true}`, or `"approvals": null`: the hub could not read it again) or an unreadable one. The decision went
    /// through either way; the caller asks for the list again.
    @discardableResult
    func decide(id: String, approve: Bool, requested: [String], token: String,
                onUnauthorized: () -> Void = {}) async throws -> DecisionAnswer? {
        // Append the account ID as one path segment, even if it contains reserved characters.
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/%?#")
        guard !id.isEmpty, id != ".", id != "..",
              let segment = id.addingPercentEncoding(withAllowedCharacters: allowed) else {
            throw HTTPError.invalidResponse
        }
        let body = approve ? DecisionBody(approve: true, requested: requested)
                           : DecisionBody(decline: true, requested: requested)
        let data = try await request("api/empire/approvals/\(segment)", body: JSONEncoder().encode(body),
                                     token: token, onUnauthorized: onUnauthorized)
        let answer = try? decodeAnswer(DecisionWire.self, from: data, answer: "POST /api/empire/approvals/<id>")
        return answer?.approvals.map { DecisionAnswer(approvals: $0, pending: answer?.pending) }
    }

    /// `{approve: true, requested: [...]}` or `{decline: true, requested: [...]}`.
    private struct DecisionBody: Encodable {
        var approve: Bool? = nil
        var decline: Bool? = nil
        var requested: [String]? = nil
    }

    /// The decision's answer as it comes: `approvals` null when the hub could not read the list again, absent from an
    /// older hub (`{"ok": true}`).
    private struct DecisionWire: Decodable {
        let approvals: [PendingAccount]?
        let pending: Int?
    }

    private func decoded<T: Decodable>(_ path: String, body: Data? = nil, token: String,
                                       onUnauthorized: () -> Void) async throws -> T {
        let data = try await request(path, body: body, token: token, onUnauthorized: onUnauthorized)
        return try decodeAnswer(T.self, from: data, answer: (body == nil ? "GET /" : "POST /") + path)
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
