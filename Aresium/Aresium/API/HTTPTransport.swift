import Foundation

protocol HTTPTransport {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

struct URLSessionTransport: HTTPTransport {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw HTTPError.invalidResponse }
        return (data, response)
    }
}

struct ServerMessage: Decodable { let message: String }

enum HTTPError: LocalizedError {
    case invalidResponse, unauthorized, server(Int, String?)
    var errorDescription: String? {
        switch self {
        case .invalidResponse: "The server returned an invalid response."
        case .unauthorized: "Your session expired. Please log in again."
        case let .server(status, message): message ?? "The request failed (HTTP \(status)). Please try again."
        }
    }
}

struct APIClient {
    var transport: any HTTPTransport = URLSessionTransport()
    var baseURL = URL(string: "https://aresium.de")!

    func dashboard(token: String, onUnauthorized: () -> Void) async throws -> Dashboard {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/data"))
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30
        let (data, response) = try await transport.send(request)
        if response.statusCode == 401 {
            onUnauthorized()
            throw HTTPError.unauthorized
        }
        guard (200..<300).contains(response.statusCode) else {
            throw HTTPError.server(response.statusCode, try? JSONDecoder().decode(ServerMessage.self, from: data).message)
        }
        return try Dashboard.decode(data)
    }
}
