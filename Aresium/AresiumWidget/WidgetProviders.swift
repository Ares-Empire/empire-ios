import WidgetKit
import Foundation

nonisolated struct SpendingEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
    let red: Bool                       // the app's red mode; otherwise the home screen's look
}

nonisolated struct SpendingProvider: TimelineProvider {
    func placeholder(in context: Context) -> SpendingEntry {
        WidgetLanguage.aresium.follow()
        return SpendingEntry(date: .now, snapshot: .sample, red: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (SpendingEntry) -> Void) {
        WidgetLanguage.aresium.follow()         // the app's language, also when it differs from the iPhone's
        let store = WidgetSnapshotStore()
        completion(SpendingEntry(date: .now, snapshot: context.isPreview ? .sample : store.readForCurrentLogin().snapshot, red: store.redMode))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SpendingEntry>) -> Void) {
        WidgetLanguage.aresium.follow()
        let store = WidgetSnapshotStore()
        let now = Date.now
        let result = store.readForCurrentLogin()
        completion(Timeline(entries: [SpendingEntry(date: now, snapshot: result.snapshot, red: store.redMode)],
                            policy: .after(result.nextRefresh(after: now))))
    }
}

nonisolated struct CategoriesEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
    let red: Bool                       // the app's red mode; otherwise the home screen's look
    let firstCategory: String?
    let secondCategory: String?
}

nonisolated struct CategoriesProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> CategoriesEntry {
        WidgetLanguage.aresium.follow()
        return CategoriesEntry(date: .now, snapshot: .sample, red: false, firstCategory: nil, secondCategory: nil)
    }

    func snapshot(for configuration: SpendingCategoriesIntent, in context: Context) async -> CategoriesEntry {
        WidgetLanguage.aresium.follow()
        let store = WidgetSnapshotStore()
        return CategoriesEntry(date: .now, snapshot: context.isPreview ? .sample : store.readForCurrentLogin().snapshot, red: store.redMode,
                               firstCategory: configuration.firstCategory?.id, secondCategory: configuration.secondCategory?.id)
    }

    func timeline(for configuration: SpendingCategoriesIntent, in context: Context) async -> Timeline<CategoriesEntry> {
        WidgetLanguage.aresium.follow()
        let store = WidgetSnapshotStore()
        let now = Date.now
        let result = store.readForCurrentLogin()
        let entry = CategoriesEntry(date: now, snapshot: result.snapshot, red: store.redMode,
                                    firstCategory: configuration.firstCategory?.id, secondCategory: configuration.secondCategory?.id)
        return Timeline(entries: [entry], policy: .after(result.nextRefresh(after: now)))
    }
}
