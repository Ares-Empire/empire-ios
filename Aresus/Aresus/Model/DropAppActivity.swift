import UIKit

/// Application lifetime support stays in the app target; shared drop code never reaches UIApplication.shared.
@MainActor
final class DropAppActivity: DropActivity {
    private var grant = UIBackgroundTaskIdentifier.invalid
    private var observers: [NSObjectProtocol] = []
    private var expiring: (() -> Void)?

    static func environment(enabled: Bool) -> (activity: DropAppActivity?, legacyDirectory: URL?, legacyDefaults: UserDefaults?, legacyCacheURL: URL?) {
        guard enabled else { return (nil, nil, nil, nil) }
        return (DropAppActivity(), URL.applicationSupportDirectory.appendingPathComponent("Drops"), .standard,
                URL.cachesDirectory.appendingPathComponent("drop-folders.json"))
    }

    func observe(active: @escaping @MainActor () -> Void, expiring: @escaping @MainActor () -> Void) {
        self.expiring = expiring
        observers.append(NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification,
                                                               object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { active() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification,
                                                               object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.begin() }
        })
    }

    func begin() {
        guard grant == .invalid else { return }
        grant = UIApplication.shared.beginBackgroundTask(withName: "Prepare drops") { [weak self] in
            MainActor.assumeIsolated { self?.expiring?(); self?.end() }
        }
    }

    func end() {
        guard grant != .invalid else { return }
        UIApplication.shared.endBackgroundTask(grant)
        grant = .invalid
    }

    isolated deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
        if grant != .invalid { UIApplication.shared.endBackgroundTask(grant) }
    }
}
