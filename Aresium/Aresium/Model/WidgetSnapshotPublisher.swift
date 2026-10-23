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

    func publish(_ dashboard: Dashboard) throws {
        if let snapshot = WidgetSnapshot(dashboard: dashboard) { try store.save(snapshot) }
        else { try store.delete() }
        reloadTimelines()
    }

    func clear() throws {
        try store.delete()
        reloadTimelines()
    }

    func setTheme(_ theme: AppTheme) throws {
        try store.saveTheme(theme)
        reloadTimelines()
    }
}
