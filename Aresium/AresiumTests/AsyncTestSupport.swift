import Foundation
import Observation
import CoreFoundation
@testable import Aresium

extension ImportStore {
    /// receive() may already have started the automatic batch. The explicit trigger then returns early;
    /// wait for that existing import too before asserting its results.
    func importAndWait() async {
        await importPendingFiles()
        await pendingImportsFinished()
    }
}

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

/// A cancellable suspension, released by the test rather than a wall clock.
@MainActor
final class TestSuspension {
    private var pending: [UUID: CheckedContinuation<Void, Error>] = [:]
    private var arrivals: [CheckedContinuation<Void, Never>] = []
    func sleep() async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation { continuation in
                pending[id] = continuation
                let ready = arrivals
                arrivals.removeAll()
                for arrival in ready { arrival.resume() }
            }
        } onCancel: {
            Task { @MainActor in self.pending.removeValue(forKey: id)?.resume(throwing: CancellationError()) }
        }
    }
    func entered() async {
        if !pending.isEmpty { return }
        await withCheckedContinuation { arrivals.append($0) }
    }
    func release() {
        let ready = pending.values
        pending.removeAll()
        for continuation in ready { continuation.resume() }
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

/// UIKit is not Observable. Recheck its published view state after a run-loop turn, never after a guessed delay.
@MainActor
func waitForViewState(_ condition: @escaping @MainActor () -> Bool) async {
    while !condition() {
        await withCheckedContinuation { continuation in
            let observer = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.beforeWaiting.rawValue,
                                                             false, 0) { _, _ in continuation.resume() }
            CFRunLoopAddObserver(CFRunLoopGetMain(), observer, .commonModes)
        }
    }
}

/// The banner's real 4.5-second schedule, advanced explicitly by the test. Cancellation works like Task.sleep.
@MainActor
final class ImportTestTimer {
    private var now: Duration = .zero
    private var entries: [(due: Duration, task: Task<Void, Never>, action: @MainActor () -> Void)] = []
    private(set) var delays: [Duration] = []
    func schedule(_ delay: Duration, action: @escaping @MainActor () -> Void) -> Task<Void, Never> {
        delays.append(delay)
        let task = Task {}
        entries.append((now + delay, task, action))
        return task
    }
    func advance(by duration: Duration) {
        now += duration
        let ready = entries.filter { $0.due <= now }
        entries.removeAll { $0.due <= now }
        for entry in ready where !entry.task.isCancelled { entry.action() }
    }
}
