import Foundation

/// A manual, cancellation-aware clock for debounce, pacing and timeout tests.
@MainActor
final class TestClock {
    private(set) var now = ContinuousClock.now
    private struct Wait {
        let due: ContinuousClock.Instant
        let duration: Duration
        let continuation: CheckedContinuation<Void, Error>
    }
    private var waits: [UUID: Wait] = [:]
    private var arrivals: [(Duration, CheckedContinuation<Void, Never>)] = []

    func sleep(for duration: Duration) async throws {
        try Task.checkCancellation()
        if duration <= .zero { return }
        let id = UUID()
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { continuation in
                waits[id] = Wait(due: now + duration, duration: duration, continuation: continuation)
                let ready = arrivals.filter { $0.0 == duration }
                arrivals.removeAll { $0.0 == duration }
                for (_, arrival) in ready { arrival.resume() }
            }
        } onCancel: {
            Task { @MainActor in self.waits.removeValue(forKey: id)?.continuation.resume(throwing: CancellationError()) }
        }
    }

    func sleeping(for duration: Duration) async {
        if waits.values.contains(where: { $0.duration == duration }) { return }
        await withCheckedContinuation { arrivals.append((duration, $0)) }
    }

    func advance(by duration: Duration) {
        now += duration
        let ready = waits.filter { $0.value.due <= now }
        for (id, wait) in ready { waits.removeValue(forKey: id); wait.continuation.resume() }
    }
}
