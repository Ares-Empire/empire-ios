import Foundation

/// How the app writes the vault's values in the app's language (ares-empire/docs/LANGUAGES.md). Pure functions with the
/// language passed in, so the tests pin both. The vault's own words (titles, text) are never translated.
enum Format {
    /// "Topic", "Mechanism", … (an unknown type shows its own word).
    static func type(_ type: NoteType, language: AppLanguage = .current) -> String {
        switch type {
        case .topic: language.string("Topic")
        case .mechanism: language.string("Mechanism")
        case .event: language.string("Event")
        case .actor: language.string("Actor")
        case .question: language.string("Question")
        case .session: language.string("Session")
        case .inbox: language.string("Inbox")
        case .home: language.string("Home")
        case .positions: language.string("Positions")
        case .glossary: language.string("Glossary")
        default: type.rawValue.capitalized
        }
    }

    /// "Topics", "Mechanisms", … for the search filter.
    static func types(_ type: NoteType, language: AppLanguage = .current) -> String {
        switch type {
        case .topic: language.string("Topics")
        case .mechanism: language.string("Mechanisms")
        case .event: language.string("Events")
        case .actor: language.string("Actors")
        case .question: language.string("Questions")
        case .session: language.string("Sessions")
        case .inbox: language.string("Inbox")
        case .home: language.string("Home")
        case .positions: language.string("Positions")
        case .glossary: language.string("Glossary")
        default: type.rawValue.capitalized
        }
    }

    /// "Solid", "My read", "Shaky".
    static func confidence(_ confidence: Confidence, language: AppLanguage = .current) -> String {
        switch confidence {
        case .solid: language.string("Solid")
        case .myRead: language.string("My read")
        case .shaky: language.string("Shaky")
        }
    }

    /// A year: "1517"; before Christ "44 BCE" (German "44 v. Chr.").
    static func year(_ year: Int, language: AppLanguage = .current) -> String {
        year < 0 ? language.string("\(String(-year)) BCE") : String(year)
    }

    /// An event's years: "1517–1648", "1454", "490–479 BCE", "44 BCE – 14 CE"; nil when the event has no years.
    static func years(from: Int?, to: Int?, language: AppLanguage = .current) -> String? {
        switch (from, to) {
        case (nil, nil): return nil
        case let (year?, nil), let (nil, year?): return self.year(year, language: language)
        case let (from?, to?) where from == to: return year(from, language: language)
        case let (from?, to?) where from < 0 && to < 0:
            return language.string("\(String(-from))–\(String(-to)) BCE")
        case let (from?, to?) where from < 0:
            return language.string("\(String(-from)) BCE – \(String(to)) CE")
        case let (from?, to?):
            return "\(from)–\(to)"
        }
    }

    /// A contract date ("2026-10-20") as "20 Oct 2026" (German "20. Okt. 2026"); the text itself if it cannot be read.
    static func day(_ date: String, language: AppLanguage = .current) -> String {
        guard let parsed = parseDay(date) else { return date }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = berlin
        return parsed.formatted(Date.FormatStyle(date: .omitted, time: .omitted, locale: language.locale,
                                                 calendar: calendar, timeZone: berlin).day().month(.abbreviated).year())
    }

    /// How old a moment is, for "Updated …" lines: "just now", "4 min ago", "3 h ago", then the day.
    static func age(_ date: Date, now: Date = .now, language: AppLanguage = .current) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return language.string("just now") }
        if seconds < 3600 { return language.string("\(Int(seconds / 60)) min ago") }
        if seconds < 86_400 { return language.string("\(Int(seconds / 3600)) h ago") }
        return date.formatted(Date.FormatStyle(date: .omitted, time: .omitted, locale: language.locale, timeZone: berlin)
            .day().month(.abbreviated))
    }

    /// An ISO 8601 timestamp of the contract ("2026-10-24T18:00:00Z").
    static func timestamp(_ text: String) -> Date? {
        try? Date(text, strategy: .iso8601)
    }

    /// The vault's dates are Berlin dates.
    static let berlin = TimeZone(identifier: "Europe/Berlin")!

    private static func parseDay(_ text: String) -> Date? {
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = berlin
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
    }
}
