import UIKit

/// One grant per flush, ended exactly once on completion or expiration. Expiration leaves unsent notes on disk.
@MainActor
final class QuickNoteBackgroundTask {
    private var identifier: UIBackgroundTaskIdentifier = .invalid

    init() {
        identifier = UIApplication.shared.beginBackgroundTask(withName: "Send quick notes") { [weak self] in
            MainActor.assumeIsolated { self?.end() }
        }
    }

    func end() {
        guard identifier != .invalid else { return }
        let identifier = identifier
        self.identifier = .invalid
        UIApplication.shared.endBackgroundTask(identifier)
    }
}
