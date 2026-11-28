import Foundation

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

    /// Waits for synchronous work on a dispatch queue. The caller can leave while a system call is stalled.
    func work<T: Sendable>(_ operation: @escaping @Sendable (Work) throws -> T) async throws -> T {
        let work = Work(deadline: self)
        return try await run {
            try await withTaskCancellationHandler {
                let (values, result) = AsyncStream<Result<T, Error>>.makeStream(bufferingPolicy: .bufferingNewest(1))
                DispatchQueue.global(qos: .userInitiated).async {
                    result.yield(Result {
                        try work.check()
                        return try operation(work)
                    })
                    result.finish()
                }
                for await value in values { return try value.get() }
                throw CancellationError()
            } onCancel: {
                work.abandon()
            }
        }
    }

    func read<T: Sendable>(_ lookup: @escaping @Sendable () throws -> T) async throws -> T {
        try await work { _ in try lookup() }
    }

    final class Work: @unchecked Sendable {
        let deadline: Deadline
        private let lock = NSLock()
        private var abandoned = false
        private var writing = false

        fileprivate init(deadline: Deadline) { self.deadline = deadline }

        fileprivate func abandon() { lock.withLock { abandoned = true } }

        func check() throws { try perform {} }

        /// A synchronous write can finish after abandonment. Its caller can tell whether it is safe to retry.
        var writeAdmitted: Bool { lock.withLock { writing } }

        func admitWrite() throws { try perform { writing = true } }

        /// Linearizes request start with abandonment. Only use this for a short, nonblocking step.
        func perform<T>(_ step: () throws -> T) throws -> T {
            try lock.withLock {
                guard !abandoned else { throw CancellationError() }
                try deadline.check()
                return try step()
            }
        }
    }

    /// Cancel the losing task. Operations must cooperate with cancellation.
    func run<T: Sendable>(_ operation: @escaping @Sendable () async throws -> T) async throws -> T {
        try check()
        let value = try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                let value = try await operation()
                try check()
                return value
            }
            group.addTask {
                try await clock.sleepUntil(instant)
                throw Expired()
            }
            defer { group.cancelAll() }
            do {
                return try await group.next()!
            } catch {
                try Task.checkCancellation()
                if remaining <= .zero { throw Expired() }
                throw error
            }
        }
        try check()
        return value
    }
}
