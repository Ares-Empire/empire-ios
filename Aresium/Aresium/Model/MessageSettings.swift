import Foundation

// Settings → Messages and the offer after the first import (brief 46): the words and choices the screens show, kept
// out of the views. The scheduling is brief 45's (`AresiumMessages`, `MessagePlan`, `MessageScheduler`); this file only
// reads its state and calls its API.

/// The words of Settings → Messages, its row on the Settings list and the offer.
nonisolated enum MessageWording {
    /// The row's state on its right: Off, or what is on, short; "Off in iOS" while iOS has Aresium's notifications off,
    /// since then nothing comes whatever is chosen.
    static func state(_ preferences: MessagePreferences, authorization: MessageAuthorization,
                      language: AppLanguage = .current) -> String {
        guard preferences.enabled else { return language.string("Off") }
        if authorization == .denied { return language.string("Off in iOS") }
        switch (preferences.importReminder, preferences.monthReview) {
        case (true, true): return language.string("On")
        case (true, false): return language.string("Reminder only")
        case (false, true): return language.string("Review only")
        case (false, false): return language.string("None chosen")
        }
    }

    /// How often the import reminder comes, as the page's picker names it.
    static func interval(_ interval: MessageInterval, language: AppLanguage = .current) -> String {
        switch interval {
        case .week: language.string("Every week")
        case .fortnight: language.string("Every 2 weeks")
        case .month: language.string("Every month")
        }
    }

    /// The offer's line: the reminder at the interval it would use, and the month review.
    static func offerLine(_ interval: MessageInterval, language: AppLanguage = .current) -> String {
        switch interval {
        case .week:
            language.string("A reminder every week after your last import, and a review of last month on the 3rd.")
        case .fortnight:
            language.string("A reminder every 2 weeks after your last import, and a review of last month on the 3rd.")
        case .month:
            language.string("A reminder every month after your last import, and a review of last month on the 3rd.")
        }
    }

    /// The page's quiet note: made on this iPhone, nothing sent; with the lock on, also that they show no numbers.
    static func note(lockOn: Bool, language: AppLanguage = .current) -> String {
        let made = language.string("These messages are made on this iPhone. Nothing is sent anywhere.")
        guard lockOn else { return made }
        return made + " " + language.string("While the lock is on, they show no numbers.")
    }
}

/// The page's time picker shows a `Date`; the preferences keep the hour and the minute (wall-clock time, every day).
nonisolated enum MessageTime {
    /// Today (or `day`) at the chosen time, for the picker to show.
    static func date(of preferences: MessagePreferences, on day: Date = .now, calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: day)
        return calendar.date(bySettingHour: preferences.hour, minute: preferences.minute, second: 0, of: start,
                             matchingPolicy: .nextTime, repeatedTimePolicy: .first)
            ?? start.addingTimeInterval(TimeInterval(preferences.hour * 3600 + preferences.minute * 60))
    }

    /// The preferences with the picked time's hour and minute (the rest as it was).
    static func setting(_ date: Date, in preferences: MessagePreferences,
                        calendar: Calendar = .current) -> MessagePreferences {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        var value = preferences
        value.hour = parts.hour ?? preferences.hour
        value.minute = parts.minute ?? preferences.minute
        return value
    }
}

/// The one-time offer after the first import that added payments (brief 46): when it shows, and what Turn on does.
nonisolated enum ReminderOffer {
    /// What else is on screen at the moment the offer could show.
    nonisolated struct Moment: Equatable {
        /// `AresiumMessages.shouldOfferReminder`: an import added payments, Messages is off, never answered.
        var ready = false
        var tour = false
        var locked = false
        /// Files are read, imported or waiting (`ImportStore.isBusy`).
        var importing = false
        /// The category picker after an import (`ImportStore.asksForCategories`).
        var picker = false
        /// The import's result shows in the offer's place, with or without its send card ("Help Aresium learn your
        /// bank"), or another line of the app's.
        var result = false
        /// Another window of the app is open: Settings, the guide, the file check, a receipt or its question, a picker.
        var window = false
    }

    /// In the import result's place once the result (with its send card) and the category picker are done: never with
    /// them, never in the tour or behind the lock or another window.
    static func shows(_ moment: Moment) -> Bool {
        moment.ready && !moment.tour && !moment.locked && !moment.importing && !moment.picker && !moment.result
            && !moment.window
    }

    /// Turn on: Messages on with both messages; how often and the time stay as they are (every 2 weeks and 18:00
    /// unless changed before).
    static func turnedOn(_ preferences: MessagePreferences) -> MessagePreferences {
        var value = preferences
        value.enabled = true
        value.importReminder = true
        value.monthReview = true
        return value
    }
}

extension ReminderOffer.Moment {
    /// The moment as the app's state has it: the messages' readiness and the import's own state (its work, the category
    /// picker, the result with or without its send card); the screen adds the tour, the lock and its other windows.
    @MainActor init(messages: AresiumMessages, imports: ImportStore, tour: Bool, locked: Bool, window: Bool) {
        self.init(ready: messages.shouldOfferReminder, tour: tour, locked: locked, importing: imports.isBusy,
                  picker: imports.asksForCategories, result: imports.banner != nil, window: window)
    }
}

extension AresiumMessages {
    /// The offer's Turn on: both messages on (iOS asks for permission now, the first time), then the offer is answered
    /// for good.
    func acceptReminderOffer() {
        setPreferences(ReminderOffer.turnedOn(preferences))
        finishReminderOffer()
    }

    /// The offer's Not now (and a swipe down): answered for good, nothing turned on.
    func declineReminderOffer() {
        finishReminderOffer()
    }
}
