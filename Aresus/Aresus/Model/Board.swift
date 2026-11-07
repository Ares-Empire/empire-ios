import Foundation

/// Board v1. Unknown kinds and states decode as unknown and never enter either ask list.
nonisolated struct BoardItem: Codable, Equatable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable { case ask, work, unknown }
    enum State: String, Codable, Sendable { case open, answered, done, dropped, unknown }

    var id: Int
    var kind: Kind
    var topic: String
    var text: String
    var why: String?
    var options: [String]
    var due: String?
    var source: String
    var session: String?
    /// The session cannot go on until Patrik answers (since 2026-11-07; absent from an older server: false).
    var blocking: Bool
    var key: String?
    var since: Date?
    var state: State
    var answer: String?
    var sentTo: String?
    var sent: Date?
    var created: Date
    var updated: Date

    enum CodingKeys: String, CodingKey {
        case id, kind, topic, text, why, options, due, source, session, blocking, key, since, state, answer, sent, created
        case updated
        case sentTo = "sent_to"
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        kind = (try? c.decode(Kind.self, forKey: .kind)) ?? .unknown
        state = (try? c.decode(State.self, forKey: .state)) ?? .unknown
        topic = try c.decode(String.self, forKey: .topic)
        text = try c.decode(String.self, forKey: .text)
        why = try? c.decodeIfPresent(String.self, forKey: .why)
        options = (try? c.decode([String].self, forKey: .options)) ?? []
        due = try? c.decodeIfPresent(String.self, forKey: .due)
        source = try c.decode(String.self, forKey: .source)
        session = try? c.decodeIfPresent(String.self, forKey: .session)
        blocking = (try? c.decodeIfPresent(Bool.self, forKey: .blocking)) ?? false
        key = try? c.decodeIfPresent(String.self, forKey: .key)
        since = try? c.decodeIfPresent(Date.self, forKey: .since)
        answer = try? c.decodeIfPresent(String.self, forKey: .answer)
        sentTo = try? c.decodeIfPresent(String.self, forKey: .sentTo)
        sent = try? c.decodeIfPresent(Date.self, forKey: .sent)
        created = try c.decode(Date.self, forKey: .created)
        updated = try c.decode(Date.self, forKey: .updated)
    }

    var claudeURL: URL? {
        guard let session, (8...80).contains(session.count),
              session.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }) else { return nil }
        return URL(string: "https://claude.ai/code/\(session)")
    }
}

nonisolated struct BoardUnowned: Codable, Equatable, Sendable {
    var count: Int
    var oldest: Date?
    var topics: [String]

    func line(language: AppLanguage = .current) -> String {
        let words = language.string("\(count) open items have no session")
        return topics.isEmpty ? words : words + " · " + topics.joined(separator: ", ")
    }
}

nonisolated struct BoardWaiting: Codable, Equatable, Sendable {
    var asks: [BoardItem]
    var answered: [BoardItem]
    var unowned: BoardUnowned

    init(asks: [BoardItem], answered: [BoardItem], unowned: BoardUnowned) {
        self.asks = asks.filter { $0.kind == .ask && $0.state == .open }
        self.answered = answered.filter { $0.kind == .ask && $0.state == .answered }.sorted { $0.updated > $1.updated }
        self.unowned = unowned
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(asks: try c.decode([BoardItem].self, forKey: .asks),
                  answered: try c.decode([BoardItem].self, forKey: .answered),
                  unowned: try c.decode(BoardUnowned.self, forKey: .unowned))
    }

    static var empty: Self { Self(asks: [], answered: [], unowned: BoardUnowned(count: 0, oldest: nil, topics: [])) }
}

nonisolated enum BoardWords {
    /// One complete unit, without "ago". Foundation supplies the unit's English/German plural forms.
    static func age(_ created: Date, now: Date, language: AppLanguage = .current) -> String {
        let seconds = max(60, now.timeIntervalSince(created))
        let formatter = DateComponentsFormatter()
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = language.locale
        formatter.calendar = calendar
        formatter.unitsStyle = .full
        formatter.allowedUnits = seconds >= 86_400 ? [.day] : seconds >= 3_600 ? [.hour] : [.minute]
        formatter.maximumUnitCount = 1
        return formatter.string(from: floor(seconds / 60) * 60) ?? ""
    }

    /// Due dates are calendar days in Berlin, independently of the phone's time zone.
    static func dueDate(_ day: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Europe/Berlin")!
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard let date = formatter.date(from: day), formatter.string(from: date) == day else { return nil }
        return date
    }

    static func due(_ day: String, language: AppLanguage = .current) -> String? {
        guard let date = dueDate(day) else { return nil }
        let formatter = DateFormatter()
        formatter.locale = language.locale
        formatter.timeZone = TimeZone(identifier: "Europe/Berlin")!
        formatter.setLocalizedDateFormatFromTemplate("EEE d MMM")
        let dateText = formatter.string(from: date)
        return language.string("due \(dateText)")
    }

    static func isDue(_ day: String, now: Date) -> Bool {
        guard let date = dueDate(day) else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
        return date <= calendar.startOfDay(for: now)
    }

    /// The server takes 1–1000 characters of Patrik's own words.
    static let ownAnswerLimit = 1000
    /// From here the field shows how many characters are left.
    static let ownAnswerWarning = 900

    static func ownAnswer(_ text: String) -> String? {
        let answer = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return (1...ownAnswerLimit).contains(answer.count) ? answer : nil
    }

    static func ownAnswerLength(_ text: String) -> Int {
        text.trimmingCharacters(in: .whitespacesAndNewlines).count
    }

    /// "950 / 1000": the count the server checks, written the language's way.
    static func ownAnswerCount(_ length: Int, language: AppLanguage = .current) -> String {
        let format = IntegerFormatStyle<Int>().locale(language.locale)
        return length.formatted(format) + " / " + ownAnswerLimit.formatted(format)
    }
}
