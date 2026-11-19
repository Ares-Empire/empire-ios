import Foundation

/// flatd's HTTP transport: an ephemeral session that never follows a redirect, so neither the key nor a keyless health
/// check is ever carried to another address (Codex's review, round 2). A redirect comes back as its own 3xx answer,
/// which the client reads as "not flatd" or a failure.
struct FlatdTransport: HTTPTransport {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await FlatdSession.shared.data(for: request.withLanguage())
        guard let response = response as? HTTPURLResponse else { throw HTTPError.invalidResponse }
        return (data, response)
    }
}

nonisolated enum FlatdSession {
    /// One session for the app (or the extension): no cookies or cache kept, no redirects followed.
    static let shared = URLSession(configuration: .ephemeral, delegate: NoRedirects(), delegateQueue: nil)

    /// A session for the event stream: idle for long stretches (its liveness comes from pings), no redirects.
    static func events() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 3600
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
    }
}

nonisolated final class NoRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
