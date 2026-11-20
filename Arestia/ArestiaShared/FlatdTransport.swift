import Foundation
import os

/// flatd's HTTP transport: HTTPS only, to a server that proved it holds flatd's key (`FlatdPin`), in an ephemeral
/// session that never follows a redirect. So the key and every request go only to flatd itself, encrypted: never in
/// the clear, never to whatever answers at flatd's address, never on to another address.
struct FlatdTransport: GatedTransport {
    let pin: FlatdPin

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await send(request, starting: { start in start() })
    }

    /// Starts the request inside the gate: the task is made and resumed in the same step that checked its pairing is
    /// still the saved one, under the lock Forget takes (`FlatdDispatchLock`). A gate that refuses starts nothing.
    func send(_ request: URLRequest, gate: FlatdGate) async throws -> (Data, HTTPURLResponse) {
        try await send(request, starting: { start in try gate.start(start) })
    }

    private func send(_ request: URLRequest, starting: (() -> Void) throws -> Void) async throws
        -> (Data, HTTPURLResponse) {
        // Checked here too, not only by iOS: nothing for flatd ever leaves without TLS.
        guard request.url?.scheme?.lowercased() == "https" else { throw URLError(.unsupportedURL) }
        let session = FlatdSession.shared(pin: pin)
        let running = RunningTask()
        do {
            return try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (done: CheckedContinuation<(Data, HTTPURLResponse), Error>) in
                    running.finish = { result in done.resume(with: result) }
                    do {
                        try starting {
                            let task = session.dataTask(with: request.withLanguage()) { data, response, error in
                                if let error {
                                    running.end(.failure(error))
                                } else if let response = response as? HTTPURLResponse {
                                    running.end(.success((data ?? Data(), response)))
                                } else {
                                    running.end(.failure(HTTPError.invalidResponse))
                                }
                            }
                            running.start(task)
                        }
                    } catch {
                        running.end(.failure(error))      // the gate refused: nothing was started
                    }
                }
            } onCancel: {
                running.cancel()
            }
        } catch let error as URLError where error.code == .cancelled && !Task.isCancelled {
            // Nobody cancelled this request (and its session is never invalidated): the session's delegate did,
            // because the server is not flatd (`PinnedServer`).
            throw URLError(.serverCertificateUntrusted)
        }
    }
}

/// A request's task and its one ending. Cancelling and starting are decided under one lock: a request cancelled
/// before its task started is never resumed (round 7), and the caller hears exactly one ending, whichever comes first.
private nonisolated final class RunningTask: @unchecked Sendable {
    private let lock = NSLock()
    private var task: URLSessionDataTask?
    private var cancelled = false
    private var ended = false
    /// The caller's continuation; set before anything can end it.
    var finish: (@Sendable (Result<(Data, HTTPURLResponse), Error>) -> Void)?

    /// Resumes the task unless the request was cancelled first (then it ends as cancelled, never started).
    func start(_ task: URLSessionDataTask) {
        let resume: Bool = lock.withLock {
            guard !cancelled else { return false }
            self.task = task
            return true
        }
        if resume { task.resume() } else { end(.failure(CancellationError())) }
    }

    func cancel() {
        let task: URLSessionDataTask? = lock.withLock {
            cancelled = true
            return self.task
        }
        task?.cancel()
    }

    func end(_ result: Result<(Data, HTTPURLResponse), Error>) {
        let first: Bool = lock.withLock {
            guard !ended else { return false }
            ended = true
            return true
        }
        if first { finish?(result) }
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
            let session = URLSession(configuration: configuration(), delegate: PinnedServer(pin: pin),
                                     delegateQueue: nil)
            sessions[pin] = session
            return session
        }
    }

    /// Nothing kept (no cookies, cache or credentials), and straight to flatd: a proxy set up on the iPhone is not
    /// used, so not even the address flatd has is told to anyone on the way.
    private static func configuration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = [:]
        return configuration
    }

    /// A session for the event stream: idle for long stretches (its liveness comes from pings); the same rules.
    static func events(pin: FlatdPin) -> URLSession {
        let configuration = configuration()
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
