import WidgetKit
import Foundation

/// Hands WidgetKit the widget's timeline. The decisions (live or saved, logged out) are `WidgetStatusLoader`'s, in
/// AresusShared where the app's tests reach them.
nonisolated struct StatusProvider: TimelineProvider {
    func placeholder(in context: Context) -> StatusEntry {
        WidgetLanguage.aresus.follow()
        return StatusEntry(date: .now, content: .status(.example(checked: .now)))
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (StatusEntry) -> Void) {
        WidgetLanguage.aresus.follow()          // the app's language, also when it differs from the iPhone's
        // The widget gallery: a made-up status, so the preview never shows real data or waits for the network.
        if context.isPreview {
            completion(StatusEntry(date: .now, content: .status(.example(checked: .now.addingTimeInterval(-240)))))
            return
        }
        Task { @MainActor in
            let now = Date.now
            completion(StatusEntry(date: now, content: await WidgetStatusLoader.live().load(now: now, fetching: false)))
        }
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<StatusEntry>) -> Void) {
        WidgetLanguage.aresus.follow()
        Task { @MainActor in
            let now = Date.now
            let content = await WidgetStatusLoader.live().load(now: now)
            completion(StatusTimeline.timeline(content, now: now))
        }
    }
}
