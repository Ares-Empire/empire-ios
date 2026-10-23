import WidgetKit
import Foundation

nonisolated struct SpendingEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
    let theme: AppTheme
}

nonisolated struct SpendingProvider: TimelineProvider {
    func placeholder(in context: Context) -> SpendingEntry {
        SpendingEntry(date: .now, snapshot: .sample, theme: .dark)
    }

    func getSnapshot(in context: Context, completion: @escaping (SpendingEntry) -> Void) {
        let store = WidgetSnapshotStore()
        completion(SpendingEntry(date: .now, snapshot: context.isPreview ? .sample : store.load(), theme: store.theme))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SpendingEntry>) -> Void) {
        let store = WidgetSnapshotStore()
        completion(Timeline(entries: [SpendingEntry(date: .now, snapshot: store.load(), theme: store.theme)], policy: .never))
    }
}

nonisolated struct CategoriesEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
    let theme: AppTheme
    let firstCategory: String?
    let secondCategory: String?
}

nonisolated struct CategoriesProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> CategoriesEntry {
        CategoriesEntry(date: .now, snapshot: .sample, theme: .dark, firstCategory: nil, secondCategory: nil)
    }

    func snapshot(for configuration: SpendingCategoriesIntent, in context: Context) async -> CategoriesEntry {
        let store = WidgetSnapshotStore()
        return CategoriesEntry(date: .now, snapshot: context.isPreview ? .sample : store.load(), theme: store.theme,
                               firstCategory: configuration.firstCategory?.id, secondCategory: configuration.secondCategory?.id)
    }

    func timeline(for configuration: SpendingCategoriesIntent, in context: Context) async -> Timeline<CategoriesEntry> {
        let store = WidgetSnapshotStore()
        let entry = CategoriesEntry(date: .now, snapshot: store.load(), theme: store.theme,
                                    firstCategory: configuration.firstCategory?.id, secondCategory: configuration.secondCategory?.id)
        return Timeline(entries: [entry], policy: .never)
    }
}
