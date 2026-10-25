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
            SpendingWidgetView(snapshot: entry.snapshot, theme: entry.theme, date: entry.date)
                .containerBackground(for: .widget) { Wall(palette: Palette(theme: entry.theme)) }
                .environment(\.colorScheme, entry.theme == .light ? .light : .dark)
                .environment(\.locale, AppLanguage.current.locale)      // the app's language (`WidgetLanguage`)
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
            CategoriesWidgetView(snapshot: entry.snapshot, firstCategory: entry.firstCategory,
                                 secondCategory: entry.secondCategory, theme: entry.theme, date: entry.date)
                .containerBackground(for: .widget) { Wall(palette: Palette(theme: entry.theme)) }
                .environment(\.colorScheme, entry.theme == .light ? .light : .dark)
                .environment(\.locale, AppLanguage.current.locale)      // the app's language (`WidgetLanguage`)
        }
        .configurationDisplayName("Spending categories")
        .description("Two categories for this month. Long press to choose them.")
        .supportedFamilies([.systemSmall])
    }
}

#Preview("Monthly spending", as: .systemMedium) {
    MonthlySpendingWidget()
} timeline: {
    SpendingEntry(date: .now, snapshot: .sample, theme: .dark)
}

#Preview("Spending categories", as: .systemSmall) {
    SpendingCategoriesWidget()
} timeline: {
    CategoriesEntry(date: .now, snapshot: .sample, theme: .dark, firstCategory: nil, secondCategory: nil)
}

#Preview("Open Aresium", as: .systemSmall) {
    SpendingCategoriesWidget()
} timeline: {
    CategoriesEntry(date: .now, snapshot: nil, theme: .dark, firstCategory: nil, secondCategory: nil)
}
