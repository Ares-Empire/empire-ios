import Foundation
import os

/// flatd's HTTP transport: HTTPS only, to a server that proved it holds flatd's key (`FlatdPin`), in an ephemeral
/// session that never follows a redirect. So the key and every request go only to flatd itself, encrypted: never in
/// the clear, never to whatever answers at flatd's address, never on to another address.
struct FlatdTransport: GatedTransport {
    let pin: FlatdPin

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await send(request, gate: nil, dispatch: nil)
    }

    /// Starts the request inside the gate: the task is made and resumed in the same step that checked its pairing is
    /// still the saved one, under the lock Forget takes (`FlatdDispatchLock`). A gate that refuses starts nothing.
    func send(_ request: URLRequest, gate: FlatdGate?, dispatch: FlatdRequestDispatch?) async throws
        -> (Data, HTTPURLResponse) {
        // Checked here too, not only by iOS: nothing for flatd ever leaves without TLS.
        guard request.url?.scheme?.lowercased() == "https" else { throw URLError(.unsupportedURL) }
        if let gate, gate.pin != pin { throw FlatdError.unreachable }
        let session = FlatdSession.shared(pin: pin)
        let running = RunningTask()
        #if DEBUG && ARESTIA_GATE
        if request.httpMethod == "POST" { running.timing = GateAction.current }
        #endif
        do {
            return try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { (done: CheckedContinuation<(Data, HTTPURLResponse), Error>) in
                    running.finish = { result in done.resume(with: result) }
                    do {
                        let start = {
                            let task = session.dataTask(with: request.withLanguage()) { data, response, error in
                                if let error {
                                    running.end(.failure(error))
                                } else if let response = response as? HTTPURLResponse {
                                    running.end(.success((data ?? Data(), response)))
                                } else {
                                    running.end(.failure(HTTPError.invalidResponse))
                                }
                            }
                            do { try running.start(task, dispatch: dispatch) }
                            catch {
                                running.end(.failure(error))
                                task.cancel()
                                return
                            }
                        }
                        if let gate { try gate.start(start) } else { try start() }
                        #if DEBUG && ARESTIA_GATE
                        // Both the pairing lock and the task's start lock have been released.
                        running.appendDispatch()
                        #endif
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
    #if DEBUG && ARESTIA_GATE
    /// Set before starting the task, only for a command made by a traced action.
    var timing: GateAction?
    private typealias CompletionStamp = (time: Date, outcome: GateOutcome)
    private var dispatchTime: Date?
    private var dispatchFlushed = false
    private var pendingCompletion: CompletionStamp?

    /// If the reply beat dispatch to the log, write both from the continuation's setup closure.
    /// The awaiting task cannot resume until that closure returns.
    func appendDispatch() {
        guard let timing, let time = lock.withLock({ dispatchTime }) else { return }
        timing.dispatch(at: time)
        let pending = lock.withLock {
            dispatchFlushed = true
            defer { pendingCompletion = nil }
            return pendingCompletion
        }
        if let pending { timing.completion(pending.outcome, at: pending.time) }
    }
    #endif

    /// Resumes the task unless the request was cancelled first (then it ends as cancelled, never started). The check
    /// and the resume are one step under the lock, so a cancellation either comes before (nothing starts) or finds the
    /// task to cancel (round 8). `resume()` only hands the task to the session's own queue, which reports its ending on
    /// another thread, so holding the lock across it never waits on `end`.
    func start(_ task: URLSessionDataTask, dispatch: FlatdRequestDispatch?) throws {
        try lock.withLock {
            guard !cancelled else { throw CancellationError() }
            let resume = {
                self.task = task
                #if DEBUG && ARESTIA_GATE
                if let timing = self.timing {
                    self.dispatchTime = timing.resume(task)
                } else {
                    task.resume()
                }
                #else
                task.resume()
                #endif
            }
            if let dispatch { try dispatch.start(resume) } else { resume() }
        }
    }

    func cancel() {
        let task: URLSessionDataTask? = lock.withLock {
            cancelled = true
            return self.task
        }
        task?.cancel()
    }

    func end(_ result: Result<(Data, HTTPURLResponse), Error>) {
        #if DEBUG && ARESTIA_GATE
        var completion: CompletionStamp?
        #endif
        let first: Bool = lock.withLock {
            guard !ended else { return false }
            ended = true
            #if DEBUG && ARESTIA_GATE
            if let timing, !timing.isFanBatch, dispatchTime != nil {
                let stamp = (Date.now, GateOutcome(result, cancelled: cancelled))
                if dispatchFlushed {
                    completion = stamp
                } else {
                    pendingCompletion = stamp
                }
            }
            #endif
            return true
        }
        #if DEBUG && ARESTIA_GATE
        if let completion { timing?.completion(completion.outcome, at: completion.time) }
        #endif
        if first { finish?(result) }
    }
}

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
