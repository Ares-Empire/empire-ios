import Foundation

/// What a watch's card and a found change show (brief 131), decided here so the screens only lay it out: the card's main
/// fact or its quiet line per state, when the page was last checked and changed, the intervals' words, a change's lines.

/// A watch's lines on its card (the Hunts list and the watch's page), under its name and host.
struct WatchCardText: Equatable {
    /// What the page says now about the change ("KALLAX 49,99 €"): the card's main fact, while the page reads well.
    let fact: String?
    /// A quiet line instead: "Reading the page…" until the first read, or the server's note when the page cannot be read
    /// (for a page that refuses the server, with the hint that editing tries again). No alarm: the greyed sites' style.
    let note: String?
    /// "Checked 4 min ago · Changed yesterday 18:05"; nil before the first read.
    let times: String?

    /// `page`: the card's page state; nil for a watch the overview has not sent yet (just made), read as waiting.
    init(_ page: PageState?, now: Date = .now, calendar: Calendar = .app, language: AppLanguage = .current) {
        let l = language
        let note = page?.note.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 }
        switch page?.read ?? .waiting {
        case .waiting:
            fact = nil
            self.note = l.string("Reading the page…")
        case .ok:
            fact = page?.now.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 }
                .map(WatchText.keepingAmounts)
            self.note = nil
        case .unreadable:
            fact = nil
            self.note = note ?? l.string("This page doesn't show it.")
        case .failing:
            fact = nil
            self.note = note ?? l.string("The page can't be read right now.")
        case .blocked:
            fact = nil
            self.note = (note ?? l.string("The page can't be read right now.")) + " " + l.string("Editing the watch tries again.")
        case .unknown:
            // A state this build does not know: the server's note says it.
            fact = nil
            self.note = note
        }
        let checked = Format.relative(page?.checked, now: now, calendar: calendar, language: l).map { l.string("Checked \($0)") }
        let changed = Format.relative(page?.changed, now: now, calendar: calendar, language: l).map { l.string("Changed \($0)") }
        let times = [checked, changed].compactMap { $0 }
        self.times = times.isEmpty ? nil : times.joined(separator: " · ")
    }
}

/// The server's lines about a page as the app sets them.
enum WatchText {
    /// A number and its currency kept on one line ("49,99 €", "€ 45", "45 EUR"), so a wrapped line never leaves the sign
    /// alone at the start of the next one. Nothing else in the server's words changes.
    static func keepingAmounts(_ text: String) -> String {
        text.replacing(/(\d) +(€|EUR|\$|£|CHF)/) { "\($0.1)\u{00A0}\($0.2)" }
            .replacing(/(€|\$|£) +(\d)/) { "\($0.1)\u{00A0}\($0.2)" }
    }
}

/// How often a watch's page is read: the form's menu.
enum WatchInterval {
    /// "Every 15 min", "Every hour", "Once a day" (German "Alle 15 Min.", "Jede Stunde", "Einmal am Tag"). A value the
    /// choices do not have (a newer server's) in minutes.
    static func title(_ minutes: Int, language: AppLanguage = .current) -> String {
        let l = language
        switch minutes {
        case 15: return l.string("Every 15 min")
        case 30: return l.string("Every 30 min")
        case 60: return l.string("Every hour")
        case 180: return l.string("Every 3 hours")
        case 360: return l.string("Every 6 hours")
        case 720: return l.string("Every 12 hours")
        case 1440: return l.string("Once a day")
        default: return l.string("Every \(minutes) min")
        }
    }

    /// The menu's choices: the server's (or those offered, `from`), and the watch's own value when it is none of them,
    /// so it can stay as it is.
    static func choices(keeping value: Int, from offered: [Int] = WatchSearch.everyChoices) -> [Int] {
        offered.contains(value) ? offered : (offered + [value]).sorted()
    }
}

extension Match {
    /// A found change's small line: "www.ikea.com · 4 min ago", or "… · Already true when the watch started" for a match
    /// the start read found (its time says nothing about when the page changed).
    func watchSourceLine(now: Date = .now, calendar: Calendar = .app, language: AppLanguage = .current) -> String {
        let when = atStart ? language.string("Already true when the watch started")
            : Format.relative(found, now: now, calendar: calendar, language: language)
        return [listing.sourceName, when].compactMap { $0 }.joined(separator: " · ")
    }

    /// A found change's title: the server's summary ("KALLAX now 44,99 € instead of 49,99 €"), else the page's title.
    var watchTitle: String {
        let summary = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        return WatchText.keepingAmounts(summary.isEmpty ? listing.title : summary)
    }

    /// "Now: KALLAX 44,99 €" on a found change's page; nil when the server sent no line.
    func watchNowLine(language: AppLanguage = .current) -> String? {
        let now = listing.page?.now?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return now.isEmpty ? nil : language.string("Now: \(WatchText.keepingAmounts(now))")
    }
}
