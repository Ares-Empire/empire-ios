import WidgetKit
import Foundation

nonisolated struct SpendingEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
    let red: Bool                       // the app's red mode; otherwise the home screen's look
    var locked = false                  // Aresium's lock is on: no numbers, only that it is locked
}

/// What a widget shows now: nothing while Aresium's lock is on, else the snapshot it may show (`readShown`).
nonisolated private func shown(_ store: WidgetSnapshotStore) -> (result: WidgetSnapshotStore.ReadResult, locked: Bool) {
    store.isLocked ? (.missing, true) : (store.readShown(), false)
}

nonisolated struct SpendingProvider: TimelineProvider {
    func placeholder(in context: Context) -> SpendingEntry {
        WidgetLanguage.aresium.follow()
        return SpendingEntry(date: .now, snapshot: .sample, red: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (SpendingEntry) -> Void) {
        WidgetLanguage.aresium.follow()         // the app's language, also when it differs from the iPhone's
        let store = WidgetSnapshotStore()
        if context.isPreview { return completion(SpendingEntry(date: .now, snapshot: .sample, red: store.redMode)) }
        let now = shown(store)
        completion(SpendingEntry(date: .now, snapshot: now.result.snapshot, red: store.redMode, locked: now.locked))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SpendingEntry>) -> Void) {
        WidgetLanguage.aresium.follow()
        let store = WidgetSnapshotStore()
        let date = Date.now
        let now = shown(store)
        completion(Timeline(entries: [SpendingEntry(date: date, snapshot: now.result.snapshot, red: store.redMode,
                                                    locked: now.locked)],
                            policy: .after(now.result.nextRefresh(after: date))))
    }
}

nonisolated struct CategoriesEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
    let red: Bool                       // the app's red mode; otherwise the home screen's look
    let firstCategory: String?
    let secondCategory: String?
    var locked = false                  // Aresium's lock is on: no numbers, only that it is locked
}

nonisolated struct CategoriesProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> CategoriesEntry {
        WidgetLanguage.aresium.follow()
        return CategoriesEntry(date: .now, snapshot: .sample, red: false, firstCategory: nil, secondCategory: nil)
    }

    func snapshot(for configuration: SpendingCategoriesIntent, in context: Context) async -> CategoriesEntry {
        WidgetLanguage.aresium.follow()
        let store = WidgetSnapshotStore()
        let now = context.isPreview ? (result: WidgetSnapshotStore.ReadResult.missing, locked: false) : shown(store)
        return CategoriesEntry(date: .now, snapshot: context.isPreview ? .sample : now.result.snapshot, red: store.redMode,
                               firstCategory: configuration.firstCategory?.id, secondCategory: configuration.secondCategory?.id,
                               locked: now.locked)
    }

    func timeline(for configuration: SpendingCategoriesIntent, in context: Context) async -> Timeline<CategoriesEntry> {
        WidgetLanguage.aresium.follow()
        let store = WidgetSnapshotStore()
        let date = Date.now
        let now = shown(store)
        let entry = CategoriesEntry(date: date, snapshot: now.result.snapshot, red: store.redMode,
                                    firstCategory: configuration.firstCategory?.id, secondCategory: configuration.secondCategory?.id,
                                    locked: now.locked)
        return Timeline(entries: [entry], policy: .after(now.result.nextRefresh(after: date)))
    }
}
