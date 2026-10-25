import SwiftUI
import WidgetKit

@main
struct AresiumWidgetBundle: WidgetBundle {
    init() { AppFont.register() }

    var body: some Widget {
        MonthlySpendingWidget()
        SpendingCategoriesWidget()
    }
}

struct MonthlySpendingWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "AresiumMonthlySpending", provider: SpendingProvider()) { entry in
            AresiumWidgetLook(red: entry.red) { theme in
                SpendingWidgetView(snapshot: entry.snapshot, theme: theme, date: entry.date)
            }
            .environment(\.locale, AppLanguage.current.locale)          // the app's language (`WidgetLanguage`)
        }
        .configurationDisplayName("Monthly spending")
        .description("This month's spending, up to your latest transaction.")
        .supportedFamilies([.systemMedium])
    }
}

struct SpendingCategoriesWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "AresiumSpendingCategories", intent: SpendingCategoriesIntent.self,
                               provider: CategoriesProvider()) { entry in
            AresiumWidgetLook(red: entry.red) { theme in
                CategoriesWidgetView(snapshot: entry.snapshot, firstCategory: entry.firstCategory,
                                     secondCategory: entry.secondCategory, theme: theme, date: entry.date)
            }
            .environment(\.locale, AppLanguage.current.locale)          // the app's language (`WidgetLanguage`)
        }
        .configurationDisplayName("Spending categories")
        .description("Two categories for this month. Long press to choose them.")
        .supportedFamilies([.systemSmall])
    }
}

/// A widget's look: red while the app is in red mode, otherwise the home screen's light or dark, like the widgets
/// around it (not the app's own Appearance choice).
struct AresiumWidgetLook<Content: View>: View {
    let red: Bool
    @ViewBuilder let content: (AppTheme) -> Content
    @Environment(\.colorScheme) private var homeScreen

    var body: some View {
        let theme: AppTheme = red ? .red : homeScreen == .light ? .light : .dark
        content(theme)
            .containerBackground(for: .widget) { Wall(palette: Palette(theme: theme)) }
            .environment(\.colorScheme, theme == .light ? .light : .dark)
    }
}

#Preview("Monthly spending", as: .systemMedium) {
    MonthlySpendingWidget()
} timeline: {
    SpendingEntry(date: .now, snapshot: .sample, red: false)
}

#Preview("Spending categories", as: .systemSmall) {
    SpendingCategoriesWidget()
} timeline: {
    CategoriesEntry(date: .now, snapshot: .sample, red: false, firstCategory: nil, secondCategory: nil)
}

#Preview("Open Aresium", as: .systemSmall) {
    SpendingCategoriesWidget()
} timeline: {
    CategoriesEntry(date: .now, snapshot: nil, red: false, firstCategory: nil, secondCategory: nil)
}
