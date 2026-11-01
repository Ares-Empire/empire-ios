import Foundation

// A day's page (brief 77, Patrik 2026-11-01: "Lets make days clickable too and lead to a screen with that days expenses
// and income (in two tabs with swipe)"): a tap on a day of a day graph (the start screen's Current, a month's page)
// opens the day as a sheet, on the side of the graph that was tapped. The data is brief 76's (`DashboardStore.day(_:)`,
// `dayDate(atChartIndex:scope:)`); this file decides which tap opens what and how the page reads. The look is
// `Screens/DayScreen.swift`.

/// The day's page that is open (`DashboardPlace.day`): the day (`YYYY-MM-DD`) and the side it opened on.
struct DayRoute: Hashable, Identifiable {
    let date: String
    let side: DashboardSide
    var id: String { date }
}

extension DashboardStore {
    /// A short tap on a point of a page's graph: on a day graph (Current, a month's page) that day's page, opening on
    /// the page's side; nil on Overview's months (they open a month's page) and outside the graph.
    func dayRoute(atChartIndex index: Int, side: DashboardSide, scope: DashboardScope) -> DayRoute? {
        dayDate(atChartIndex: index, scope: scope).map { DayRoute(date: $0, side: side) }
    }
}

/// How a day's page reads, in the app's language (pure, so tests pin it).
enum DayPageWording {
    /// The page's title: the day written out, as a payment's page writes its date ("Wednesday, 14 October 2026" /
    /// "Mittwoch, 14. Oktober 2026").
    static func title(_ date: String, language: AppLanguage = .current) -> String {
        PaymentWording.date(date, language: language) ?? date
    }

    /// A side without payments that day: one quiet line.
    static func empty(_ side: DashboardSide, language: AppLanguage = .current) -> String {
        side == .income ? language.string("No income on this day.") : language.string("No spending on this day.")
    }

    /// A row's quiet line: its category (on a day's page nothing implies it, as a category's list does), then what
    /// the month's list says there when it says anything (the place, a receipt's state, a covered row's line).
    static func line(category: String, listLine: String, language: AppLanguage = .current) -> String {
        let category = CategoryName.shown(category, language: language)
        let rest = listLine.trimmingCharacters(in: .whitespaces)
        return rest.isEmpty || rest == category ? category : category + " · " + rest
    }
}
