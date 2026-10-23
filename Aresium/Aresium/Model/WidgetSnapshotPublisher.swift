import WidgetKit

@MainActor
struct WidgetSnapshotPublisher {
    let store: WidgetSnapshotStore
    var reloadTimelines: () -> Void

    init(store: WidgetSnapshotStore = WidgetSnapshotStore(),
         reloadTimelines: @escaping () -> Void = { WidgetCenter.shared.reloadAllTimelines() }) {
        self.store = store
        self.reloadTimelines = reloadTimelines
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
