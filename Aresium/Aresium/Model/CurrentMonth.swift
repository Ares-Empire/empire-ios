import Foundation

/// Which month the start screen's Current shows (brief 215, the first-run review's finding 2: on 2 November a fresh
/// import of three months showed a month of two days, "Rent" and a two-point graph, right after "74 new").
///
/// One rule, read with the day the person opened the app (`DashboardStore.openedOn`: at launch and on coming back from
/// the background, never while the app is open, so Current never changes its month under them):
/// - in a month's first seven days, while the newest month of the data is that running month and the month before it is
///   in the data, Current opens on the month before. It is the month the month review is about (brief 46's message on
///   the 3rd opens it the same way, `DashboardStore.showReview`), so the first look is a full month;
/// - otherwise on the newest month, as before.
///
/// A month chosen for Current wins until the app goes to the background (`DashboardStore.CurrentChoice`): a review
/// message's, the one the range line's other month leads to (one tap, both ways), or the newest from a widget's link.
nonisolated enum CurrentMonth {
    /// Up to this day of a month, Current opens on the month before.
    static let earlyDays = 7

    /// The month Current opens on (`YYYY-MM`), from the data's months (oldest first, `YYYY-MM`) and the day the app was
    /// opened (`YYYY-MM-DD`); nil without months.
    static func opening(months: [String], openedOn day: String) -> String? {
        guard let newest = months.last else { return nil }
        guard LedgerExport.isDay(day), let dayOfMonth = Int(day.suffix(2)), dayOfMonth <= earlyDays,
              newest == String(day.prefix(7)), let before = monthBefore(newest), months.contains(before)
        else { return newest }
        return before
    }

    /// The range line's other month on Current, one tap away: the newest while Current shows an older one; in a month's
    /// first days, while Current shows the running month (chosen by the person), the month it opens on. nil: none.
    static func other(months: [String], shown: String, openedOn day: String?) -> String? {
        guard let newest = months.last else { return nil }
        if shown != newest { return newest }
        guard let day, let opening = opening(months: months, openedOn: day), opening != newest else { return nil }
        return opening
    }

    /// The calendar month before `YYYY-MM`.
    static func monthBefore(_ key: String) -> String? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 2, (1...12).contains(parts[1]) else { return nil }
        let (year, month) = parts[1] == 1 ? (parts[0] - 1, 12) : (parts[0], parts[1] - 1)
        return String(format: "%04d-%02d", year, month)
    }
}

/// The range line's other month in the app's language (brief 215): the running month "November so far" / "November
/// bisher", any other month by its name, "October" / "Oktober".
nonisolated enum CurrentMonthWording {
    static func other(_ month: Month, language: AppLanguage = .current) -> String {
        let name = monthName(month.key, language: language)
        return month.partial ? language.string("\(name) so far") : name
    }

    /// The month's full name ("November"), in the app's language.
    static func monthName(_ key: String, language: AppLanguage = .current) -> String {
        guard let date = WidgetFormatting.monthDate(key) else { return key }
        let calendar = WidgetFormatting.calendar
        return date.formatted(Date.FormatStyle(date: .omitted, time: .omitted, locale: language.locale,
                                               calendar: calendar, timeZone: calendar.timeZone).month(.wide))
    }
}
