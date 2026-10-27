import Foundation
import Observation

/// Settings → Lock → Own code: setting, changing or removing the code on the code pad, one step at a time. Changing
/// and removing ask for the current code first, through the lock's own check (`AppLock.check`), so wrong codes count
/// and wait here as on the lock screen. A new code is typed twice.
@MainActor @Observable
final class LockCodeChange {
    enum Goal: String, Hashable { case set, change, remove }
    enum Step: Equatable { case current, new, again }

    let goal: Goal
    private(set) var step: Step
    private(set) var entry = CodeEntry()
    /// The last try's problem (a wrong current code, codes that differ, the wait).
    private(set) var problem: Problem?
    /// Grows with every wrong try (the dots shake).
    private(set) var shakes = 0
    private(set) var isWorking = false
    private(set) var isDone = false
    @ObservationIgnored private let lock: AppLock
    @ObservationIgnored private var first = ""

    enum Problem: Equatable { case wrongCurrent, differ, waiting, notSaved(String) }

    init(goal: Goal, lock: AppLock) {
        self.goal = goal
        self.lock = lock
        step = goal == .set ? .new : .current
    }

    func type(_ digit: Character) async {
        guard !isWorking, !isDone else { return }
        problem = nil
        entry.type(digit)
        guard entry.isComplete else { return }
        let typed = entry.digits
        entry.clear()
        switch step {
        case .current:
            isWorking = true
            let result = await lock.check(typed)
            isWorking = false
            switch result {
            case .right:
                if goal == .remove { save { try self.lock.removeCode() } } else { step = .new }
            case .wrong: fail(.wrongCurrent)
            case .waiting: fail(.waiting)
            }
        case .new:
            first = typed
            step = .again
        case .again:
            guard typed == first else {
                first = ""
                step = .new
                fail(.differ)
                return
            }
            isWorking = true
            do {
                try await lock.setCode(typed)
                isDone = true
            } catch {
                fail(.notSaved(error.localizedDescription))
            }
            isWorking = false
        }
    }

    func delete() {
        guard !isWorking else { return }
        entry.delete()
    }

    private func save(_ change: () throws -> Void) {
        do {
            try change()
            isDone = true
        } catch {
            fail(.notSaved(error.localizedDescription))
        }
    }

    private func fail(_ problem: Problem) {
        self.problem = problem
        shakes += 1
    }
}
