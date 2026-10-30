import Foundation

nonisolated enum MessageInterval: String, Codable, CaseIterable, Sendable {
    case week, fortnight, month

    func adding(to date: Date, calendar: Calendar) -> Date? {
        calendar.date(byAdding: self == .month ? .month : .day,
                      value: self == .week ? 7 : self == .fortnight ? 14 : 1, to: date)
    }
}

nonisolated struct MessagePreferences: Codable, Equatable, Sendable {
    var enabled = false
    var importReminder = true
    var interval = MessageInterval.fortnight
    var monthReview = true
    var hour = 18
    var minute = 0
}

nonisolated enum MessageAuthorization: Sendable {
    case notAsked, allowed, denied
}

/// Only metadata is persisted, never the dashboard's amounts or account names.
nonisolated struct MessageHistory: Codable, Sendable {
    var lastImport: Date?
    var reminderStarted: Date?
    var accountImports: [String: Date] = [:]
    var offerReady = false
    var offered = false
}

nonisolated struct MessageContext: Sendable {
    var phone = false
    var sample = false
    var tour = false
    var testing = false
    var locked = false
    var language = AppLanguage.current
    var permitsMessages: Bool { phone && !sample && !tour && !testing }
}

nonisolated struct PlannedMessage: Equatable, Sendable {
    let identifier: String
    let date: Date
    let title: String
    let body: String
    let url: URL
}

/// Remember which of the three slots already elapsed, even if interval/time changes or delivered banners are cleared.
nonisolated struct MessageProgress: Codable, Sendable {
    var anchor: Date?
    var consumed = 0
    var scheduled: [Int: Date] = [:]
}

/// Pure planning on the scheduler's actor; absolute, one-shot requests keep the three-reminder limit across launches.
nonisolated enum MessagePlan {
    static func owns(_ identifier: String) -> Bool {
        identifier.hasPrefix("aresium.reminder.") || identifier.hasPrefix("aresium.review.")
    }

    static func requests(preferences: MessagePreferences, history: MessageHistory, context: MessageContext,
                         dashboard: Dashboard?, accountsByMonth: [String: Set<String>],
                         now: Date, calendar: Calendar, remindersConsumed: Int = 0) -> [PlannedMessage] {
        guard preferences.enabled, context.permitsMessages else { return [] }
        var requests: [PlannedMessage] = []
        let language = context.language
        if preferences.importReminder, let anchor = history.lastImport ?? history.reminderStarted {
            var day = anchor
            for index in 1...3 {
                guard let next = preferences.interval.adding(to: day, calendar: calendar) else { break }
                day = next
                guard index > remindersConsumed else { continue }
                guard let date = atTime(day, preferences, calendar), date > now else { continue }
                let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: anchor),
                                                    to: calendar.startOfDay(for: date)).day ?? 0
                let body = context.locked || history.lastImport == nil
                    ? language.string("Import your statements to keep your dashboard up to date.")
                    : language.string("Your last import was \(days) days ago.")
                requests.append(PlannedMessage(identifier: "aresium.reminder.\(index)", date: date,
                                              title: language.string("Time for new statements"), body: body,
                                              url: AresiumURL.importData.url))
            }
        }
        if preferences.monthReview, let dashboard,
           let review = review(preferences: preferences, history: history, context: context, dashboard: dashboard,
                               accountsByMonth: accountsByMonth, now: now, calendar: calendar) {
            requests.append(review)
        }
        return requests
    }

    private static func atTime(_ day: Date, _ preferences: MessagePreferences, _ calendar: Calendar) -> Date? {
        calendar.date(bySettingHour: preferences.hour, minute: preferences.minute, second: 0, of: day,
                      matchingPolicy: .nextTime, repeatedTimePolicy: .first)
    }

    private static func review(preferences: MessagePreferences, history: MessageHistory, context: MessageContext,
                               dashboard: Dashboard, accountsByMonth: [String: Set<String>], now: Date,
                               calendar: Calendar) -> PlannedMessage? {
        guard var start = calendar.dateInterval(of: .month, for: now)?.start else { return nil }
        func third(_ start: Date) -> Date? {
            calendar.date(byAdding: .day, value: 2, to: start).flatMap { atTime($0, preferences, calendar) }
        }
        guard var date = third(start) else { return nil }
        if date <= now {
            guard let next = calendar.date(byAdding: .month, value: 1, to: start), let nextDate = third(next) else { return nil }
            start = next
            date = nextDate
        }
        guard let previous = calendar.date(byAdding: .month, value: -1, to: start) else { return nil }
        let components = calendar.dateComponents([.year, .month], from: previous)
        let key = String(format: "%04d-%02d", components.year!, components.month!)
        guard dashboard.transactions.contains(where: { $0.month == key }), let totals = dashboard.byMonth[key] else {
            return nil
        }
        let language = context.language
        let month = previous.formatted(Date.FormatStyle(date: .omitted, time: .omitted, locale: language.locale,
                                                        calendar: calendar, timeZone: calendar.timeZone).month(.wide))
        let complete = (accountsByMonth[key] ?? []).allSatisfy { account in
            history.accountImports[account].map { $0 >= start } ?? false
        }
        let body: String
        if context.locked {
            body = language.string("Your \(month) review is ready.")
        } else if !complete {
            body = language.string("Import your statements to complete \(month).")
        } else {
            let spent = money(totals.expense, language: language)
            let received = money(totals.income, language: language)
            if let top = totals.categories.filter({ $0.total > 0 }).sorted(by: {
                $0.total == $1.total ? $0.name < $1.name : $0.total > $1.total
            }).first {
                let category = CategoryName.shown(top.name, language: language)
                let amount = money(top.total, language: language)
                body = language.string("\(month): \(spent) spent, \(received) in. Most on \(category): \(amount).")
            } else {
                body = language.string("\(month): \(spent) spent, \(received) in.")
            }
        }
        return PlannedMessage(identifier: "aresium.review.\(key)", date: date,
                              title: language.string("Month review"), body: body, url: AresiumURL.review(key).url)
    }

    private static func money(_ amount: Double, language: AppLanguage) -> String {
        amount.formatted(.number.locale(language.locale).precision(.fractionLength(0...2))) + " €"
    }
}
