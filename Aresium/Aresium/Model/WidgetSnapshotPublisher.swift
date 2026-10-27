import WidgetKit
import Foundation

@MainActor
struct WidgetSnapshotPublisher {
    let store: WidgetSnapshotStore
    var reloadTimelines: () -> Void

    init(store: WidgetSnapshotStore = WidgetSnapshotStore(),
         reloadTimelines: @escaping () -> Void = { WidgetCenter.shared.reloadAllTimelines() }) {
        self.store = store
        self.reloadTimelines = reloadTimelines
    }

    static func temporary() -> Self {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("widget-" + UUID().uuidString)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return Self(store: WidgetSnapshotStore(directory: directory), reloadTimelines: {})
    }

    /// Saves the dashboard's numbers for the widgets: phone mode's as the iPhone's own (`phone`), server mode's with
    /// the account they belong to. While Aresium's lock is on, none are kept (`setLocked`).
    func publish(_ dashboard: Dashboard, account: String? = nil, phone: Bool = false) throws {
        if store.isLocked {
            if store.load() != nil { try clear() }
            return
        }
        if let snapshot = WidgetSnapshot(dashboard: dashboard, account: account, phone: phone) { try store.save(snapshot) }
        else { try store.delete() }
        reloadTimelines()
    }

    /// Aresium's lock turned on or off: on, the numbers go and the widgets show only that Aresium is locked; off, the
    /// next `publish` brings them back. Reloads the widgets only when it changed.
    func setLocked(_ locked: Bool) throws {
        guard store.isLocked != locked else { return }
        try store.saveLocked(locked)
        if locked { try store.delete() }
        reloadTimelines()
    }

    func clear() throws {
        try store.delete()
        reloadTimelines()
    }

    /// Saves red mode for the widgets; reloads them only when it changed.
    func setRedMode(_ red: Bool) throws {
        guard store.redMode != red else { return }
        try store.saveRedMode(red)
        reloadTimelines()
    }
}
