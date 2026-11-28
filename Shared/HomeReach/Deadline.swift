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

    /// A synchronous system lookup can outlive its caller. Its queue only returns a value and owns no further work.
    func read<T: Sendable>(_ lookup: @escaping @Sendable () -> T) async throws -> T {
        try await run {
            let (values, result) = AsyncStream<T>.makeStream(bufferingPolicy: .bufferingNewest(1))
            DispatchQueue.global(qos: .userInitiated).async {
                result.yield(lookup())
                result.finish()
            }
            for await value in values { return value }
            throw CancellationError()
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
