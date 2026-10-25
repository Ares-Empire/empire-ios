import SwiftUI
import WidgetKit

@main
struct AresusWidgetBundle: WidgetBundle {
    init() { AppFont.register() }

    var body: some Widget {
        AresusStatusWidget()
    }
}

/// The empire's status light: "All running" or the issues, always with how old the check is. Home screen (small,
/// medium) and lock screen (rectangular, circular). Views in `AresusShared/AresusWidgetViews.swift`. Light or dark as
/// the home screen is (like the widgets around it), not as the app's own Appearance setting.
struct AresusStatusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: AresusWidgetKind.status, provider: StatusProvider()) { entry in
            StatusEntryView(entry: entry)
                .containerBackground(for: .widget) { ProvinceWall(accent: .aresus) }
                .environment(\.locale, AppLanguage.current.locale)      // the app's language (`WidgetLanguage`)
        }
        .configurationDisplayName("Aresus")
        .description("Whether every province is running, and how fresh the check is.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular])
    }
}

private struct StatusEntryView: View {
    let entry: StatusEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        AresusWidgetView(content: entry.content, date: entry.date, family: family)
    }
}

#Preview("All running", as: .systemSmall) {
    AresusStatusWidget()
} timeline: {
    StatusEntry(date: .now, content: .status(.example(checked: .now.addingTimeInterval(-240))))
}

#Preview("Logged out", as: .systemMedium) {
    AresusStatusWidget()
} timeline: {
    StatusEntry(date: .now, content: .loggedOut)
}
