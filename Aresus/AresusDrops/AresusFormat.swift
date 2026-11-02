import Foundation

/// How times, durations and shares read in the app, in its language (ares-empire/docs/LANGUAGES.md): 24-hour times, the
/// phone's time zone. Every function takes `now`, a calendar and the language, so tests pin all three.
nonisolated enum AresusFormat {
    // MARK: times

    /// "just now", "12 s ago", "4 min ago", "3 h ago" (same day), "yesterday 23:57", "Mon 19 Oct 11:00",
    /// "19 Oct 2025" (another year). German: "gerade eben", "vor 4 Min.", "gestern 23:57", "Mo. 19. Okt. 11:00".
    static func relative(_ date: Date, now: Date, calendar: Calendar = .current, language: AppLanguage = .current) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 1 { return language.string(LocalizedStringResource("just now", table: "AresusDrops")) }
        if seconds < 60 { return language.string(LocalizedStringResource("\(Int(seconds)) s ago", table: "AresusDrops")) }
        if seconds < 3600 { return language.string(LocalizedStringResource("\(Int(seconds / 60)) min ago", table: "AresusDrops")) }
        if calendar.isDate(date, inSameDayAs: now) { return language.string(LocalizedStringResource("\(Int(seconds / 3600)) h ago", table: "AresusDrops")) }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return language.string(LocalizedStringResource("yesterday \(time(date, calendar: calendar, language: language))", table: "AresusDrops"))
        }
        if calendar.component(.year, from: date) != calendar.component(.year, from: now) {
            return date.formatted(style(calendar, language).day().month(.abbreviated).year())
        }
        return "\(day(date, calendar: calendar, language: language)) \(time(date, calendar: calendar, language: language))"
    }

    /// "14:09"
    static func time(_ date: Date, calendar: Calendar = .current, language: AppLanguage = .current) -> String {
        date.formatted(style(calendar, language).hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
    }

    /// "Sat 24 Oct" (German "Sa. 24. Okt.")
    static func day(_ date: Date, calendar: Calendar = .current, language: AppLanguage = .current) -> String {
        date.formatted(style(calendar, language).weekday(.abbreviated).day().month(.abbreviated))
    }

    /// "Today 14:09", "Yesterday 23:57", "Mon 19 Oct 11:00": a moment in a list where the day matters.
    static func moment(_ date: Date, now: Date, calendar: Calendar = .current, language: AppLanguage = .current) -> String {
        "\(dayHeading(date, now: now, calendar: calendar, language: language)) \(time(date, calendar: calendar, language: language))"
    }

    /// The overview's heading: "Sat 24 Oct · 14:09" (shown in capitals).
    static func checkedHeading(_ date: Date, calendar: Calendar = .current, language: AppLanguage = .current) -> String {
        "\(day(date, calendar: calendar, language: language)) · \(time(date, calendar: calendar, language: language))"
    }

    // MARK: days

    /// "Today", "Yesterday", "Sat 19 Oct", "Sat 19 Oct 2025" (another year).
    static func dayHeading(_ date: Date, now: Date, calendar: Calendar = .current, language: AppLanguage = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return language.string(LocalizedStringResource("Today", table: "AresusDrops")) }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return language.string(LocalizedStringResource("Yesterday", table: "AresusDrops"))
        }
        if calendar.component(.year, from: date) != calendar.component(.year, from: now) {
            return day(date, calendar: calendar, language: language) + " " + date.formatted(style(calendar, language).year())
        }
        return day(date, calendar: calendar, language: language)
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
    static func weekdayInitial(_ date: Date, calendar: Calendar = .current, language: AppLanguage = .current) -> String {
        date.formatted(style(calendar, language).weekday(.narrow))
    }

    // MARK: durations and shares

    /// "45 s", "6 min", "2 h", "2 h 10 min", "3 d 4 h" (German "6 Min.", "2 Std. 10 Min.", "3 Tg. 4 Std.").
    static func duration(_ seconds: TimeInterval, language: AppLanguage = .current) -> String {
        let total = max(0, Int(seconds))
        if total < 60 { return language.string(LocalizedStringResource("\(total) s", table: "AresusDrops")) }
        let minutes = total / 60
        if minutes < 60 { return language.string(LocalizedStringResource("\(minutes) min", table: "AresusDrops")) }
        let hours = minutes / 60
        if hours < 24 {
            return minutes % 60 == 0 ? language.string(LocalizedStringResource("\(hours) h", table: "AresusDrops")) : language.string(LocalizedStringResource("\(hours) h \(minutes % 60) min", table: "AresusDrops"))
        }
        let days = hours / 24
        return hours % 24 == 0 ? language.string(LocalizedStringResource("\(days) d", table: "AresusDrops")) : language.string(LocalizedStringResource("\(days) d \(hours % 24) h", table: "AresusDrops"))
    }

    /// The server's uptime as one short figure: "5 d", "15 h", "40 min".
    static func upFor(_ seconds: Int, language: AppLanguage = .current) -> String {
        let total = max(0, seconds)
        if total >= 86_400 { return language.string(LocalizedStringResource("\(total / 86_400) d", table: "AresusDrops")) }
        if total >= 3600 { return language.string(LocalizedStringResource("\(total / 3600) h", table: "AresusDrops")) }
        return language.string(LocalizedStringResource("\(total / 60) min", table: "AresusDrops"))
    }

    /// A share 0…1 as a whole percentage: "35 %". Values just under 100 % never round up to it.
    static func percent(_ fraction: Double) -> String {
        let value = max(0, min(1, fraction)) * 100
        let rounded = value.rounded()
        return "\(Int(rounded == 100 && value < 100 ? 99 : rounded)) %"
    }

    /// A day's or a period's uptime: "100 %", "99.6 %" (German "99,6 %"), "97 %"; nil = "not watched".
    static func uptime(_ ratio: Double?, language: AppLanguage = .current) -> String {
        guard let ratio else { return language.string(LocalizedStringResource("not watched", table: "AresusDrops")) }
        let clamped = max(0, min(1, ratio))
        var permille = Int((clamped * 1000).rounded())
        if permille == 1000 && clamped < 1 { permille = 999 }      // any downtime never reads as 100 %
        let shown = (Double(permille) / 10).formatted(.number.precision(.fractionLength(0...1)).locale(language.locale))
        return shown + " %"
    }

    /// The load average: "0.04", "1.20" (German "0,04").
    static func load(_ value: Double, language: AppLanguage = .current) -> String {
        max(0, value).formatted(.number.precision(.fractionLength(2)).grouping(.never).locale(language.locale))
    }

    private static func style(_ calendar: Calendar, _ language: AppLanguage) -> Date.FormatStyle {
        Date.FormatStyle(date: .omitted, time: .omitted, locale: language.locale, calendar: calendar,
                         timeZone: calendar.timeZone)
    }
}
