import Foundation
import os

/// flatd's HTTP transport: HTTPS only, to a server that proved it holds flatd's key (`FlatdPin`), in an ephemeral
/// session that never follows a redirect. So the key and every request go only to flatd itself, encrypted: never in
/// the clear, never to whatever answers at flatd's address, never on to another address.
struct FlatdTransport: HTTPTransport {
    let pin: FlatdPin

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        // Checked here too, not only by iOS: nothing for flatd ever leaves without TLS.
        guard request.url?.scheme?.lowercased() == "https" else { throw URLError(.unsupportedURL) }
        do {
            let (data, response) = try await FlatdSession.shared(pin: pin).data(for: request.withLanguage())
            guard let response = response as? HTTPURLResponse else { throw HTTPError.invalidResponse }
            return (data, response)
        } catch let error as URLError where error.code == .cancelled && !Task.isCancelled {
            // Nobody cancelled this request (and its session is never invalidated): the session's delegate did,
            // because the server is not flatd (`PinnedServer`).
            throw URLError(.serverCertificateUntrusted)
        }
    }
}

nonisolated enum FlatdSession {
    private static let sessions = OSAllocatedUnfairLock<[FlatdPin: URLSession]>(initialState: [:])

    /// The session for this pin: no cookies or cache kept, no redirects followed, only flatd's key accepted. One
    /// session per pin, because a session reuses its connections: a connection checked against one pin must never
    /// carry a request meant for another. A session is never invalidated: a caller may still be about to start a
    /// request on it (pairing again while the old pairing is in use), and a task on an invalidated session is a crash.
    /// There are only ever as many as pairing codes were tried since the app (or the extension) started.
    static func shared(pin: FlatdPin) -> URLSession {
        sessions.withLock { sessions in
            if let session = sessions[pin] { return session }
            let session = URLSession(configuration: .ephemeral, delegate: PinnedServer(pin: pin), delegateQueue: nil)
            sessions[pin] = session
            return session
        }
    }

    /// A session for the event stream: idle for long stretches (its liveness comes from pings); the same rules.
    static func events(pin: FlatdPin) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 3600
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration, delegate: PinnedServer(pin: pin), delegateQueue: nil)
    }
}

/// The session's delegate: a server is accepted only when its certificate holds flatd's key, and no redirect is
/// followed. iOS's own verdict on the certificate (a CA, the name, the dates) is not asked: flatd's certificate is
/// self-signed and names no address, and the pin is stricter than any of that.
nonisolated final class PinnedServer: NSObject, URLSessionTaskDelegate, Sendable {
    let pin: FlatdPin

    init(pin: FlatdPin) { self.pin = pin }

    /// What to answer a challenge with; separate from the delegate call so the tests can ask it.
    func verdict(method: String, trust: SecTrust?) -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        guard method == NSURLAuthenticationMethodServerTrust else { return (.performDefaultHandling, nil) }
        guard let trust, pin.matches(trust) else { return (.cancelAuthenticationChallenge, nil) }
        return (.useCredential, URLCredential(trust: trust))
    }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping @Sendable (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        let (disposition, credential) = verdict(method: challenge.protectionSpace.authenticationMethod,
                                                trust: challenge.protectionSpace.serverTrust)
        completionHandler(disposition, credential)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
