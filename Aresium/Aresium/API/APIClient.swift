import Foundation

/// Aresium's server (aresium/docs/API-DATA.md). Transport and statuses: Shared/API/HTTP.swift.
struct APIClient {
    var transport: any HTTPTransport = URLSessionTransport()
    var baseURL = URL(string: "https://aresium.de")!

    func dashboard(token: String, onUnauthorized: () -> Void) async throws -> Dashboard {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/data"))
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30
        let (data, response) = try await transport.send(request)
        try checkResponse(response, data: data, onUnauthorized: onUnauthorized)
        return try Dashboard.decode(data)
    }
}
