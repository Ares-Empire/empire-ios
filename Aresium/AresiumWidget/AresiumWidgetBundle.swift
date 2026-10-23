import SwiftUI
import WidgetKit

/// Placeholder until brief 05 builds the real widgets (prompts/05-aresium-widgets.md).
@main
struct AresiumWidgetBundle: WidgetBundle {
    var body: some Widget {
        PlaceholderWidget()
    }
}

struct PlaceholderWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AresiumPlaceholder", provider: PlaceholderProvider()) { _ in
            Text("Aresium").containerBackground(.black, for: .widget)
        }
        .supportedFamilies([.systemSmall])
    }
}

struct PlaceholderProvider: TimelineProvider {
    struct Entry: TimelineEntry { let date: Date }
    func placeholder(in context: Context) -> Entry { Entry(date: .now) }
    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) { completion(Entry(date: .now)) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        completion(Timeline(entries: [Entry(date: .now)], policy: .never))
    }
}
