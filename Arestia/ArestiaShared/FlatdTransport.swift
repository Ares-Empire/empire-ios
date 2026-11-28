import Foundation

/// Prepares a suspended HTTPS request pinned to flatd's key. Admission and resume belong to FlatdLaunch.
nonisolated struct FlatdTransport: PreparingTransport {
    let pin: FlatdPin
    #if DEBUG
    @TaskLocal static var fixtureTransport: (@Sendable (FlatdPin) -> any PreparingTransport)?
    var testSessions: PinnedSession? = nil
    #endif
    #if ARESTIA_UNIT_TESTS
    @TaskLocal static var loopbackFixtureHost: String?
    private var fixtureHost: String?
    #endif
    #if DEBUG && ARESTIA_GATE
    private var timing: GateAction?
    #endif

    init(pin: FlatdPin) { self.pin = pin }

    /// Task locals belong to the caller, before preparation moves to the dispatch queue.
    func capturingFixturesAndTiming(for request: URLRequest) -> any PreparingTransport {
        #if DEBUG
        if let fixture = Self.fixtureTransport { return fixture(pin) }
        #endif
        var prepared = self
        #if ARESTIA_UNIT_TESTS
        prepared.fixtureHost = Self.loopbackFixtureHost
        #endif
        #if DEBUG && ARESTIA_GATE
        if request.httpMethod == "POST" { prepared.timing = GateAction.current }
        #endif
        return prepared
    }

    func prepare(_ request: URLRequest, reply: Attempt<HTTPReply>) throws -> any SuspendedRequest {
        guard request.url?.scheme?.lowercased() == "https" else { throw URLError(.unsupportedURL) }
        #if ARESTIA_UNIT_TESTS
        var request = request
        if let fixtureHost, let url = request.url, url.host() == fixtureHost {
            var parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
            parts?.host = "127.0.0.1"
            request.url = parts?.url
        }
        #endif
        #if DEBUG
        let session = testSessions?.shared(pin: pin) ?? FlatdSession.shared(pin: pin)
        #else
        let session = FlatdSession.shared(pin: pin)
        #endif
        #if DEBUG && ARESTIA_GATE
        let stamps = timing.map { TimingStamps(action: $0) }
        #endif
        let task = session.dataTask(with: request) { data, response, error in
            let result: Result<HTTPReply, Error>
            if let error {
                // Our cancellation happens after the attempt has ended. A cancellation that wins
                // comes from the pin delegate.
                result = .failure((error as? URLError)?.code == .cancelled
                                  ? URLError(.serverCertificateUntrusted) : error)
            } else if let response = response as? HTTPURLResponse {
                result = .success((data ?? Data(), response))
            } else {
                result = .failure(HTTPError.invalidResponse)
            }
            #if DEBUG && ARESTIA_GATE
            let time = Date.now
            let first = reply.end(result)
            if first { stamps?.complete(result, at: time) }
            #else
            reply.end(result)
            #endif
        }
        #if DEBUG && ARESTIA_GATE
        return RunningTask(task: task, stamps: stamps)
        #else
        return RunningTask(task: task)
        #endif
    }
}

private nonisolated struct RunningTask: SuspendedRequest {
    let task: URLSessionDataTask
    #if DEBUG && ARESTIA_GATE
    let stamps: TimingStamps?
    #endif

    func resume() {
        #if DEBUG && ARESTIA_GATE
        if let stamps { stamps.resume(task); return }
        #endif
        task.resume()
    }

    func cancel() { task.cancel() }

    func afterResume() {
        #if DEBUG && ARESTIA_GATE
        stamps?.appendDispatch()
        #endif
    }
}

#if DEBUG && ARESTIA_GATE
private nonisolated final class TimingStamps: @unchecked Sendable {
    let action: GateAction
    private let lock = NSLock()
    private var dispatchTime: Date?
    private var dispatchFlushed = false
    private var completion: (GateOutcome, Date)?

    init(action: GateAction) { self.action = action }

    func resume(_ task: URLSessionTask) {
        let time = Date.now
        task.resume()
        if action.claimDispatch() { lock.withLock { dispatchTime = time } }
    }

    func appendDispatch() {
        guard let time = lock.withLock({ dispatchTime }) else { return }
        action.dispatch(at: time)
        let stamp = lock.withLock {
            dispatchFlushed = true
            defer { completion = nil }
            return completion
        }
        if let (outcome, time) = stamp { action.completion(outcome, at: time) }
    }

    func complete(_ reply: Result<HTTPReply, Error>, at time: Date) {
        guard !action.isFanBatch else { return }
        let outcome = GateOutcome(reply, cancelled: false)
        let flushed = lock.withLock {
            guard !dispatchFlushed else { return true }
            completion = (outcome, time)
            return false
        }
        if flushed { action.completion(outcome, at: time) }
    }
}
#endif

nonisolated enum FlatdSession {
    #if DEBUG && ARESTIA_GATE
    private static let factory = PinnedSession(requestTimeout: FlatdRequestTimeout.gate,
                                               resourceTimeout: FlatdRequestTimeout.gate)
    #else
    private static let factory = PinnedSession()
    #endif

    static func shared(pin: FlatdPin) -> URLSession {
        factory.shared(pin: pin)
    }

    static func events(pin: FlatdPin) -> URLSession {
        #if DEBUG && ARESTIA_GATE
        PinnedSession.events(pin: pin, requestTimeout: FlatdRequestTimeout.gate)
        #else
        PinnedSession.events(pin: pin, requestTimeout: 3600)
        #endif
    }
}
