import Foundation
import Observation

/// A callback that can arrive before or after its waiter. No machine-speed deadline.
@MainActor
final class TestSignal {
    private var sent = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func send() {
        sent = true
        let ready = waiters
        waiters.removeAll()
        for waiter in ready { waiter.resume() }
    }
    func wait() async {
        if sent { return }
        await withCheckedContinuation { waiters.append($0) }
    }
}

/// Waits for an Observation publication, registering before the condition can change on the main actor.
@MainActor
func waitForState(_ condition: @escaping @MainActor () -> Bool) async {
    while !condition() {
        let changed = TestSignal()
        let ready = withObservationTracking { condition() } onChange: {
            Task { @MainActor in changed.send() }
        }
        if !ready { await changed.wait() }
    }
}

