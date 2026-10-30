import Dispatch
import SwiftData

/// A context and its actor jobs on the same private serial queue. On iOS 27 the default SwiftData executor runs
/// this ledger's jobs on the main thread even when the actor is created in a detached task (picker timing tests).
/// Keep the context confined here, so fetching, sorting snapshots and applying results cannot block scrolling.
nonisolated final class PhoneLedgerExecutor: SerialModelExecutor, @unchecked Sendable {
    private let container: ModelContainer
    private var context: ModelContext?
    private let queue = DispatchQueue(label: "de.ares-empire.aresium.ledger", qos: .userInitiated)

    init(container: ModelContainer) {
        self.container = container
    }

    var modelContext: ModelContext {
        // Create on the first actor job, including when someone constructs the ledger on the main actor.
        // DispatchQueue.sync in init can run its block on the calling thread and create a main context.
        dispatchPrecondition(condition: .onQueue(queue))
        if let context { return context }
        let context = ModelContext(container)
        self.context = context
        return context
    }

    func enqueue(_ job: consuming ExecutorJob) {
        let job = UnownedJob(job)
        let executor = asUnownedSerialExecutor()
        queue.async { job.runSynchronously(on: executor) }
    }
}
