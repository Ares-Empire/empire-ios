import Foundation
import os

/// The network layer every Empire app shares: transport, status handling and errors.
/// Statuses follow the Empire contract (aresium/docs/API-DATA.md → Auth): 401 the token is rejected,
/// 403 the account may not use this service, 503 the account server could not be asked. Servers say more in
/// `{"error": "<sentence>", "code": "<code>"}` (codes: `unauthorized`, `no_access`, `admin_only`, `bad_request`,
/// `not_found`, `rate_limited`, `unavailable`, `server_error`); a server that sends no `code` is read by its status
/// alone, as before.
protocol HTTPTransport {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
    func upload(_ request: URLRequest, fromFile fileURL: URL) async throws -> (Data, HTTPURLResponse)
}

extension HTTPTransport {
    // Existing fakes that never upload need not implement it. Never fall back to reading a file into Data.
    func upload(_ request: URLRequest, fromFile fileURL: URL) async throws -> (Data, HTTPURLResponse) {
        throw HTTPError.invalidResponse
    }
}

struct URLSessionTransport: HTTPTransport {
    let session = URLSession(configuration: .ephemeral)
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request.withLanguage())
        guard let response = response as? HTTPURLResponse else { throw HTTPError.invalidResponse }
        return (data, response)
    }

    func upload(_ request: URLRequest, fromFile fileURL: URL) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.upload(for: request.withLanguage(), fromFile: fileURL)
        guard let response = response as? HTTPURLResponse else { throw HTTPError.invalidResponse }
        return (data, response)
    }
}

/// A refused request's body. Each field is read on its own, so one of an unexpected type (PocketBase's numeric
/// `status`, say) never hides the others.
nonisolated struct ServerMessage: Decodable, Sendable {
    let message: String?
    let error: String?
    let code: String?

    private enum CodingKeys: String, CodingKey { case message, error, code }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        message = try? container.decodeIfPresent(String.self, forKey: .message)
        error = try? container.decodeIfPresent(String.self, forKey: .error)
        code = try? container.decodeIfPresent(String.self, forKey: .code)
    }

    /// The server's sentence for the person (`error`, else `message`), if it sent one that is not blank.
    var sentence: String? {
        [error, message].lazy.compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.first { !$0.isEmpty }
    }

    /// The code that means "this account may not use this service" (contract above).
    static let noAccessCode = "no_access"
}

func checkResponse(_ response: HTTPURLResponse, data: Data, onUnauthorized: () -> Void) throws {
    let body = try? JSONDecoder().decode(ServerMessage.self, from: data)
    switch response.statusCode {
    case 200..<300: return
    case 401: onUnauthorized(); throw HTTPError.unauthorized
    case 403:
        // "No access to this app" only when the server says so (`no_access`) or says nothing (servers without codes).
        if let code = body?.code, code != ServerMessage.noAccessCode {
            throw HTTPError.forbidden(code: code, message: body?.sentence)
        }
        let noAccess = String(localized: LocalizedStringResource("This account has no access.", table: "Shared",
                                                                 locale: .appLanguage))
        throw HTTPError.server(403, body?.sentence ?? noAccess)
    case 503:
        // A server that is up but not ready yet (Aresus's first check round, Arestoteles's index) says why.
        throw HTTPError.server(503, body?.sentence ?? String(localized: LocalizedStringResource(
            "Login service unavailable, try again", table: "Shared", locale: .appLanguage)))
    default: throw HTTPError.server(response.statusCode, body?.sentence)
    }
}

enum HTTPError: LocalizedError {
    case invalidResponse, unauthorized
    /// A refused request: its status and the server's sentence. A 403 here means the account may not use this service
    /// (the server's code is `no_access`, or it sent none): the app closes for this account
    /// (`EmpireSession.handleAuthFailure`).
    case server(Int, String?)
    /// A 403 for another reason than access to this service (its code, e.g. `admin_only`): only this request is
    /// refused; the app stays open and shows the sentence.
    case forbidden(code: String, message: String?)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            String(localized: LocalizedStringResource("The server returned an invalid response.", table: "Shared",
                                                      locale: .appLanguage))
        case .unauthorized:
            String(localized: LocalizedStringResource("Your session expired. Please log in again.", table: "Shared",
                                                      locale: .appLanguage))
        case let .server(status, message):
            message ?? String(localized: LocalizedStringResource(
                "The request failed (HTTP \(status)). Please try again.", table: "Shared", locale: .appLanguage))
        case let .forbidden(_, message):
            message ?? String(localized: LocalizedStringResource("This isn't allowed for this account.", table: "Shared",
                                                                 locale: .appLanguage))
        }
    }
}

/// Decodes a server's answer. When it does not fit the model, the device log says where (the key path and what was
/// expected, never a value: `log show --predicate 'subsystem == "de.ares-empire.shared" && category == "decoding"'`)
/// and the decoding error goes on to the caller as before.
func decodeAnswer<T: Decodable>(_ type: T.Type, from data: Data, decoder: JSONDecoder = JSONDecoder(),
                                answer: String) throws -> T {
    do {
        return try decoder.decode(type, from: data)
    } catch let error as DecodingError {
        AnswerDecoding.log.error("\(answer, privacy: .public) did not decode: \(AnswerDecoding.describe(error), privacy: .public)")
        throw error
    }
}

enum AnswerDecoding {
    static let log = Logger(subsystem: "de.ares-empire.shared", category: "decoding")

    /// Where an answer did not fit, without any of its values: "keyNotFound projects[2].detail.about",
    /// "typeMismatch pending (expected Int)". `DecodingError`'s own description is left out: for broken JSON it
    /// quotes the data.
    static func describe(_ error: DecodingError) -> String {
        switch error {
        case let .keyNotFound(key, context):
            "keyNotFound \(path(context.codingPath + [key]))"
        case let .typeMismatch(type, context):
            "typeMismatch \(path(context.codingPath)) (expected \(type))"
        case let .valueNotFound(type, context):
            "valueNotFound \(path(context.codingPath)) (expected \(type))"
        case let .dataCorrupted(context):
            "dataCorrupted \(path(context.codingPath))"
        @unknown default:
            "unknown decoding error"
        }
    }

    /// `projects[2].detail.features`; `<root>` for the answer itself.
    static func path(_ keys: [any CodingKey]) -> String {
        var text = ""
        for key in keys {
            if let index = key.intValue { text += "[\(index)]" }
            else { text += text.isEmpty ? key.stringValue : "." + key.stringValue }
        }
        return text.isEmpty ? "<root>" : text
    }
}
