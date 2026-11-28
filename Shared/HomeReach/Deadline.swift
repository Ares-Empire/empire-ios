import Foundation
import os

/// An absolute limit on a monotonic clock that advances while the device sleeps or the process is suspended.
nonisolated struct Deadline: Sendable {
    struct Clock: Sendable {
        let now: @Sendable () -> ContinuousClock.Instant
        let sleepUntil: @Sendable (ContinuousClock.Instant) async throws -> Void

        static let continuous = Clock(now: { ContinuousClock().now }, sleepUntil: {
            try await ContinuousClock().sleep(until: $0)
        })
    }

    struct Expired: Error {}

    let instant: ContinuousClock.Instant
    let clock: Clock

    init(after duration: Duration, clock: Clock = .continuous) {
        self.init(at: clock.now() + duration, clock: clock)
    }

    private init(at instant: ContinuousClock.Instant, clock: Clock) {
        self.instant = instant
        self.clock = clock
    }

    var remaining: Duration { clock.now().duration(to: instant) }
    var remainingSeconds: TimeInterval {
        let parts = remaining.components
        return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
    }

    func capped(at instant: ContinuousClock.Instant) -> Deadline {
        Deadline(at: min(self.instant, instant), clock: clock)
    }

    func capped(by duration: Duration) -> Deadline {
        capped(at: clock.now() + duration)
    }

    func check() throws {
        try Task.checkCancellation()
        guard remaining > .zero else { throw Expired() }
    }

    struct Abandoned: Error {}

    func wait<V>(for attempt: Attempt<V>, starting start: () -> Void = {}) async -> Attempt<V>.Outcome {
        await withTaskCancellationHandler {
            if remaining <= .zero { attempt.interrupt(with: Expired()) }
            let timer = Task {
                do {
                    try await clock.sleepUntil(instant)
                    attempt.interrupt(with: Expired())
                } catch {}
            }
            defer { timer.cancel() }
            if attempt.isLive { start() }
            return await attempt.outcome
        } onCancel: {
            attempt.interrupt(with: CancellationError())
        }
    }

    func run<T: Sendable>(_ operation: @escaping @Sendable () async throws -> T) async throws -> T {
        let attempt = Attempt<T>(until: self)
        let outcome = await wait(for: attempt) {
            let task = Task {
                guard attempt.isLive else { return }
                do { attempt.end(.success(try await operation())) }
                catch { attempt.end(.failure(error)) }
            }
            attempt.onFailure { task.cancel() }
        }
        return try outcome.result.get()
    }

    /// The caller can leave while a system call on the worker is stalled.
    func blockingOutcome<T: Sendable>(
        finishAdmittedWork: Bool = false, _ body: @escaping @Sendable (Hold) throws -> T
    ) async -> Attempt<T>.Outcome {
        let attempt = Attempt<T>(until: self, finishAdmittedWork: finishAdmittedWork)
        return await wait(for: attempt) {
            DispatchQueue.global(qos: .userInitiated).async {
                guard attempt.isLive else { return }
                attempt.end(Result { try body(attempt) })
            }
        }
    }

    func blocking<T: Sendable>(_ body: @escaping @Sendable (Hold) throws -> T) async throws -> T {
        try await blockingOutcome(body).result.get()
    }

    func bestEffort<T: Sendable>(
        within duration: Duration = .seconds(1), default fallback: T,
        _ body: @escaping @Sendable (Hold) throws -> T
    ) async -> T {
        (try? await capped(by: duration).blocking(body)) ?? fallback
    }
}

/// The non-generic view of an attempt used by synchronous workers.
nonisolated class Hold: @unchecked Sendable {
    let deadline: Deadline

    fileprivate init(until deadline: Deadline) { self.deadline = deadline }

    var isLive: Bool { fatalError("Implemented by Attempt") }
    func commit<T>(_ step: () throws -> T) throws -> T { fatalError("Implemented by Attempt") }

    func check() throws {
        guard isLive else {
            try deadline.check()
            throw Deadline.Abandoned()
        }
    }
}

nonisolated final class Attempt<Value: Sendable>: Hold, @unchecked Sendable {
    struct Outcome: Sendable {
        let result: Result<Value, Error>
        let committed: Bool
    }

    private struct State: Sendable {
        var outcome: Outcome?
        var committed = false
        var waiter: CheckedContinuation<Outcome, Never>?
        var cleanups: [@Sendable () -> Void] = []
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    private let finishAdmittedWork: Bool

    init(until deadline: Deadline, finishAdmittedWork: Bool = false) {
        self.finishAdmittedWork = finishAdmittedWork
        super.init(until: deadline)
    }

    override var isLive: Bool {
        state.withLock { $0.outcome == nil && deadline.remaining > .zero }
    }

    /// Only short, synchronous operations belong here. A rejected step has no effect.
    override func commit<T>(_ step: () throws -> T) throws -> T {
        try state.withLockUnchecked { state in
            guard state.outcome == nil else { throw Deadline.Abandoned() }
            try deadline.check()
            let value = try step()
            state.committed = true
            return value
        }
    }

    @discardableResult func end(_ result: Result<Value, Error>) -> Bool {
        finish(result, beforeCommit: false)
    }

    /// Forget keeps its waiter until the worker reports the result of an admitted deletion.
    func interrupt(with error: Error) {
        finish(.failure(error), beforeCommit: finishAdmittedWork)
    }

    /// An admission timer can deny a pending request but cannot replace an admitted request's reply.
    func endBeforeCommit(with error: Error) {
        finish(.failure(error), beforeCommit: true)
    }

    @discardableResult
    private func finish(_ result: Result<Value, Error>, beforeCommit: Bool) -> Bool {
        let ending = state.withLock { state -> (Outcome, CheckedContinuation<Outcome, Never>?, [@Sendable () -> Void])? in
            guard state.outcome == nil, !(beforeCommit && state.committed) else { return nil }
            let result = if case .failure(let error) = result, error is CancellationError {
                result
            } else if !(finishAdmittedWork && state.committed), deadline.remaining <= .zero {
                Result<Value, Error>.failure(Deadline.Expired())
            } else {
                result
            }
            let outcome = Outcome(result: result, committed: state.committed)
            state.outcome = outcome
            let waiter = state.waiter
            state.waiter = nil
            let cleanups = state.cleanups
            state.cleanups = []
            return (outcome, waiter, cleanups)
        }
        guard let (outcome, waiter, cleanups) = ending else { return false }
        waiter?.resume(returning: outcome)
        if case .failure = outcome.result { cleanups.forEach { $0() } }
        return true
    }

    func onFailure(_ cleanup: @escaping @Sendable () -> Void) {
        let failed = state.withLock { state in
            switch state.outcome?.result {
            case nil:
                state.cleanups.append(cleanup)
                return false
            case .success: return false
            case .failure: return true
            }
        }
        if failed { cleanup() }
    }

    fileprivate var outcome: Outcome {
        get async {
            await withCheckedContinuation { waiter in
                let outcome = state.withLock { state in
                    if state.outcome == nil {
                        precondition(state.waiter == nil)
                        state.waiter = waiter
                    }
                    return state.outcome
                }
                if let outcome { waiter.resume(returning: outcome) }
            }
        }
    }
}
