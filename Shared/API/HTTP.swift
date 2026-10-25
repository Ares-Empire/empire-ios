import Foundation

/// The network layer every Empire app shares: transport, status handling and errors.
/// Statuses follow the Empire contract (aresium/docs/API-DATA.md → Auth): 401 the token is rejected,
/// 403 the account may not use this service, 503 the account server could not be asked.
protocol HTTPTransport {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

struct URLSessionTransport: HTTPTransport {
    let session = URLSession(configuration: .ephemeral)
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request.withLanguage())
        guard let response = response as? HTTPURLResponse else { throw HTTPError.invalidResponse }
        return (data, response)
    }
}

struct ServerMessage: Decodable { let message: String?; let error: String? }

func checkResponse(_ response: HTTPURLResponse, data: Data, onUnauthorized: () -> Void) throws {
    let body = try? JSONDecoder().decode(ServerMessage.self, from: data)
    switch response.statusCode {
    case 200..<300: return
    case 401: onUnauthorized(); throw HTTPError.unauthorized
    case 403:
        let noAccess = String(localized: LocalizedStringResource("This account has no access.", table: "Shared",
                                                                 locale: .appLanguage))
        throw HTTPError.server(403, body?.error ?? body?.message ?? noAccess)
    case 503:
        throw HTTPError.server(503, String(localized: LocalizedStringResource("Login service unavailable, try again",
                                                                              table: "Shared", locale: .appLanguage)))
    default: throw HTTPError.server(response.statusCode, body?.error ?? body?.message)
    }
}

enum HTTPError: LocalizedError {
    case invalidResponse, unauthorized, server(Int, String?)
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
        }
    }
}
