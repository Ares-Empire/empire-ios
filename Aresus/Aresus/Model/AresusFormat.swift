import Foundation

/// How times, durations and shares read in the app: English words, 24-hour times, the phone's time zone.
/// Every function takes `now` and a calendar, so tests pin both.
nonisolated enum AresusFormat {
    static let locale = Locale(identifier: "en_GB")

    // MARK: times

    /// "just now", "12 s ago", "4 min ago", "3 h ago" (same day), "yesterday 23:57", "Mon 19 Oct 11:00",
    /// "19 Oct 2025" (another year).
    static func relative(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 1 { return "just now" }
        if seconds < 60 { return "\(Int(seconds)) s ago" }
        if seconds < 3600 { return "\(Int(seconds / 60)) min ago" }
        if calendar.isDate(date, inSameDayAs: now) { return "\(Int(seconds / 3600)) h ago" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "yesterday \(time(date, calendar: calendar))"
        }
        if calendar.component(.year, from: date) != calendar.component(.year, from: now) {
            return format(date, "\(day: .defaultDigits) \(month: .abbreviated) \(year: .defaultDigits)", calendar: calendar)
        }
        return "\(day(date, calendar: calendar)) \(time(date, calendar: calendar))"
    }

    /// "14:09"
    static func time(_ date: Date, calendar: Calendar = .current) -> String {
        format(date, "\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits)",
               calendar: calendar)
    }

    /// "Sat 24 Oct"
    static func day(_ date: Date, calendar: Calendar = .current) -> String {
        format(date, "\(weekday: .abbreviated) \(day: .defaultDigits) \(month: .abbreviated)", calendar: calendar)
    }

    /// "Today 14:09", "Yesterday 23:57", "Mon 19 Oct 11:00": a moment in a list where the day matters.
    static func moment(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        "\(dayHeading(date, now: now, calendar: calendar)) \(time(date, calendar: calendar))"
    }

    /// The overview's heading: "Sat 24 Oct · 14:09" (shown in capitals).
    static func checkedHeading(_ date: Date, calendar: Calendar = .current) -> String {
        "\(day(date, calendar: calendar)) · \(time(date, calendar: calendar))"
    }

    // MARK: days

    /// "Today", "Yesterday", "Sat 19 Oct", "Sat 19 Oct 2025" (another year).
    static func dayHeading(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        if calendar.component(.year, from: date) != calendar.component(.year, from: now) {
            return format(date, "\(weekday: .abbreviated) \(day: .defaultDigits) \(month: .abbreviated) \(year: .defaultDigits)",
                          calendar: calendar)
        }
        return day(date, calendar: calendar)
    }

    /// A calendar day from the contract ("2026-10-24") as noon of that day in `calendar`'s time zone.
    static func date(day text: String, calendar: Calendar = .current) -> Date? {
        let parts = text.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]) else { return nil }
        let components = DateComponents(year: year, month: month, day: day, hour: 12)
        guard let date = calendar.date(from: components),
              calendar.dateComponents([.year, .month, .day], from: date) == DateComponents(year: year, month: month, day: day)
        else { return nil }
        return date
    }

    /// The contract's day key ("2026-10-24") of a moment, in `calendar`'s time zone.
    static func dayKey(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    /// The weekday's initial ("S" for Saturday).
    static func weekdayInitial(_ date: Date, calendar: Calendar = .current) -> String {
        format(date, "\(weekday: .narrow)", calendar: calendar)
    }

    // MARK: durations and shares

    /// "45 s", "6 min", "2 h", "2 h 10 min", "3 d 4 h".
    static func duration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        if total < 60 { return "\(total) s" }
        let minutes = total / 60
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        if hours < 24 { return minutes % 60 == 0 ? "\(hours) h" : "\(hours) h \(minutes % 60) min" }
        let days = hours / 24
        return hours % 24 == 0 ? "\(days) d" : "\(days) d \(hours % 24) h"
    }

    /// The server's uptime as one short figure: "5 d", "15 h", "40 min".
    static func upFor(_ seconds: Int) -> String {
        let total = max(0, seconds)
        if total >= 86_400 { return "\(total / 86_400) d" }
        if total >= 3600 { return "\(total / 3600) h" }
        return "\(total / 60) min"
    }

    /// A share 0…1 as a whole percentage: "35 %". Values just under 100 % never round up to it.
    static func percent(_ fraction: Double) -> String {
        let value = max(0, min(1, fraction)) * 100
        let rounded = value.rounded()
        return "\(Int(rounded == 100 && value < 100 ? 99 : rounded)) %"
    }

    /// A day's or a period's uptime: "100 %", "99.6 %", "97 %"; nil = "not watched".
    static func uptime(_ ratio: Double?) -> String {
        guard let ratio else { return "not watched" }
        let clamped = max(0, min(1, ratio))
        var permille = Int((clamped * 1000).rounded())
        if permille == 1000 && clamped < 1 { permille = 999 }      // any downtime never reads as 100 %
        return permille % 10 == 0 ? "\(permille / 10) %" : "\(permille / 10).\(permille % 10) %"
    }

    /// The load average: "0.04", "1.20".
    static func load(_ value: Double) -> String {
        String(format: "%.2f", max(0, value))
    }

    private static func format(_ date: Date, _ format: Date.FormatString, calendar: Calendar) -> String {
        date.formatted(Date.VerbatimFormatStyle(format: format, locale: locale, timeZone: calendar.timeZone,
                                                calendar: calendar))
    }
}
