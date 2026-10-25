import Foundation

/// Only the display data needed by the widgets. Never contains credentials or transaction records.
nonisolated struct WidgetSnapshot: Codable, Equatable {
    struct SpendCategory: Codable, Equatable, Identifiable {
        let name: String
        let icon: String
        let color: String
        let total: Double
        var id: String { name }
    }

    let monthKey: String
    let monthLabel: String
    let daysInMonth: Int
    let dayExpenseRunning: [Double]
    let expense: Double
    let newestTransactionDate: String?
    let categories: [SpendCategory]

    init?(dashboard: Dashboard) {
        guard let month = dashboard.months.last, let data = dashboard.byMonth[month.key],
              let date = WidgetFormatting.monthDate(month.key),
              let days = WidgetFormatting.calendar.range(of: .day, in: .month, for: date)?.count else { return nil }
        monthKey = month.key
        monthLabel = month.title()
        daysInMonth = days
        dayExpenseRunning = data.dayExpenseRunning
        expense = data.expense
        newestTransactionDate = dashboard.transactions.map(\.date).max()
        categories = dashboard.categories.filter { $0.kind == .spend }.map { category in
            SpendCategory(name: category.name, icon: category.icon, color: category.color,
                          total: data.categories.first { $0.name == category.name }?.total ?? 0)
        }
    }

    /// Reserve an available named default before filling missing slots. Never default to Rent.
    var defaultCategoryNames: [String] {
        let preferred = ["Groceries", "Drogerie"]
        let available = Set(categories.map(\.name))
        let reserved = Set(preferred.filter { available.contains($0) })
        let fallback = categories.filter { $0.name != "Rent" && !reserved.contains($0.name) }
            .sorted { $0.total == $1.total ? $0.name < $1.name : $0.total > $1.total }
        var remaining = fallback.map(\.name)
        return preferred.compactMap { name in
            if available.contains(name) { return name }
            return remaining.isEmpty ? nil : remaining.removeFirst()
        }
    }

    func category(named name: String?) -> SpendCategory? {
        categories.first { $0.name == name }
    }

    static var sample: WidgetSnapshot? { try? WidgetSnapshot(dashboard: Dashboard.sample()) }
}

/// A note replaces saved amounts only when the device's calendar month is newer.
nonisolated struct WidgetMonthNote: Equatable {
    let monthLabel: String
    let message: String
    let lastData: String?

    init?(snapshot: WidgetSnapshot, now: Date, calendar: Calendar) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM"
        guard snapshot.monthKey < formatter.string(from: now) else { return nil }
        formatter.locale = AppLanguage.current.locale
        formatter.setLocalizedDateFormatFromTemplate("MMMMyyyy")
        monthLabel = formatter.string(from: now)
        formatter.setLocalizedDateFormatFromTemplate("MMMM")
        message = String(localized: "Nothing imported for \(formatter.string(from: now)) yet", table: "AresiumShared",
                         bundle: .appLanguage, locale: .appLanguage)
        lastData = WidgetFormatting.lastData(snapshot.newestTransactionDate)
    }
}

nonisolated enum WidgetFormatting {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    static func monthDate(_ key: String) -> Date? { date(key + "-01") }

    static func date(_ value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter.date(from: value)
    }

    static func freshness(_ value: String?) -> String? {
        transactionDateLabel(value).map { String(localized: "up to \($0)", table: "AresiumShared",
                                                 bundle: .appLanguage, locale: .appLanguage) }
    }

    static func lastData(_ value: String?) -> String? {
        transactionDateLabel(value).map { String(localized: "last data \($0)", table: "AresiumShared",
                                                 bundle: .appLanguage, locale: .appLanguage) }
    }

    private static func transactionDateLabel(_ value: String?) -> String? {
        guard let value, let date = date(value) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = AppLanguage.current.locale
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("dMMM")
        return formatter.string(from: date)
    }
}
