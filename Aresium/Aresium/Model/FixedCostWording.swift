import Foundation

nonisolated enum FixedCostWording {
    private static var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(secondsFromGMT: 0)!
        return result
    }

    private static func date(_ day: String) -> Date? {
        guard LedgerExport.isDay(day) else { return nil }
        let parts = day.split(separator: "-").compactMap { Int($0) }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
    }

    static func cadence(_ cadence: FixedCostCadence, language: AppLanguage = .current) -> String {
        switch cadence {
        case .monthly: language.string("monthly")
        case .quarterly: language.string("quarterly")
        case .halfYearly: language.string("every 6 months")
        case .yearly: language.string("yearly")
        }
    }
    /// `referenceDay` is explicit so the year and both languages are testable without a wall clock.
    static func nextDue(_ day: String, referenceDay: String = ReceiptDay.day(.now), language: AppLanguage = .current) -> String {
        guard let formatted = shortDay(day, referenceDay: referenceDay, language: language) else { return day }
        return language.string("next \(formatted)")
    }
    /// An ended entry's newest payment (brief 209): "last 3 Aug" / "zuletzt am 3. Aug.", the year as in `nextDue`.
    static func last(_ day: String, referenceDay: String = ReceiptDay.day(.now), language: AppLanguage = .current) -> String {
        guard let formatted = shortDay(day, referenceDay: referenceDay, language: language) else { return day }
        return language.string("last \(formatted)")
    }
    /// "3 Dec" / "3. Dez.", with the year only when it is not the reference day's.
    private static func shortDay(_ day: String, referenceDay: String, language: AppLanguage) -> String? {
        guard let date = date(day) else { return nil }
        var style = Date.FormatStyle(date: .omitted, time: .omitted, locale: language.locale,
                                     calendar: calendar, timeZone: calendar.timeZone).day().month(.abbreviated)
        if day.prefix(4) != referenceDay.prefix(4) { style = style.year() }
        return date.formatted(style)
    }
}
