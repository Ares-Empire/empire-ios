import Testing
import os
@testable import Arestia

struct AttemptTests {
    @Test func firstEndingWinsAndCommitAfterEndIsRefused() async throws {
        let cap = Deadline(after: .seconds(5))
        let attempt = Attempt<Int>(until: cap)
        try attempt.commit {}
        #expect(attempt.end(.failure(CancellationError())))
        let outcome = await cap.wait(for: attempt)
        #expect(outcome.committed)
        #expect(throws: CancellationError.self) { try outcome.result.get() }
        #expect(!attempt.end(.success(1)))
        #expect(throws: Deadline.Abandoned.self) {
            try attempt.commit { Issue.record("A finished attempt committed") }
        }
    }

    @Test func failureCleanupsRunOnceAndSuccessDiscardsThem() async {
        let cap = Deadline(after: .seconds(5))
        let failed = Attempt<Int>(until: cap)
        let succeeded = Attempt<Int>(until: cap)
        let count = OSAllocatedUnfairLock(initialState: 0)
        let cleanup: @Sendable () -> Void = { count.withLock { $0 += 1 } }
        failed.onFailure(cleanup)
        failed.end(.failure(CancellationError()))
        failed.end(.failure(CancellationError()))
        failed.onFailure(cleanup)
        succeeded.onFailure(cleanup)
        succeeded.end(.success(1))
        succeeded.onFailure(cleanup)
        #expect(count.withLock { $0 } == 2)
    }
}
