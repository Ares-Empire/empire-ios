import Foundation

/// Accepts a server only when its certificate holds the pinned key. Refuses redirects.
nonisolated final class PinnedServer: NSObject, URLSessionTaskDelegate, Sendable {
    let pin: SPKIPin

    init(pin: SPKIPin) { self.pin = pin }

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
