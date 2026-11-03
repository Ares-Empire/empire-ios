import Foundation

/// How the app writes the API's values, in the app's language (ares-empire/docs/LANGUAGES.md): "€980" or "980 €",
/// "1 Dec" or "1. Dez.". Pure functions with the clock, calendar and language passed in, so the tests pin them.
enum Format {
    /// "€980", "€1,150"; German "980 €", "1.150 €" (whole euros).
    static func money(_ euros: Double, language: AppLanguage = .current) -> String {
        let amount = whole(euros, language: language)
        return language == .german ? amount + "\u{a0}€" : "€" + amount
    }

    /// "€400–1,000"; German "400–1.000 €".
    static func moneyRange(_ low: Double, _ high: Double, language: AppLanguage = .current) -> String {
        let range = whole(low, language: language) + "–" + whole(high, language: language)
        return language == .german ? range + "\u{a0}€" : "€" + range
    }

    /// "€6.19"; German "6,19 €" (shipping costs, to the cent).
    static func cents(_ euros: Double, language: AppLanguage = .current) -> String {
        let amount = euros.formatted(.number.precision(.fractionLength(2)).locale(language.locale))
        return language == .german ? amount + "\u{a0}€" : "€" + amount
    }

    private static func whole(_ euros: Double, language: AppLanguage) -> String {
        Int(euros.rounded()).formatted(.number.locale(language.locale))
    }

    /// "42", "42.5" (German "42,5"): whole numbers without a decimal point, no grouping.
    static func number(_ value: Double, language: AppLanguage = .current) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)).grouping(.never).locale(language.locale))
    }

    /// "42 m²"
    static func size(_ sqm: Double, language: AppLanguage = .current) -> String { number(sqm, language: language) + " m²" }

    /// "1 room", "2 rooms", "1.5 rooms" (German "1 Zimmer", "1,5 Zimmer")
    static func rooms(_ rooms: Double, language: AppLanguage = .current) -> String {
        let count = number(rooms, language: language)
        return rooms == 1 ? language.string("\(count) room") : language.string("\(count) rooms")
    }

    /// "1 flatmate", "2 flatmates"
    static func flatmates(_ count: Int, language: AppLanguage = .current) -> String {
        language.string("\(count) flatmates")
    }

    /// How long ago: "just now", "40 s ago", "4 min ago", "3 h ago" (same day), "yesterday 18:05", "Mon 18:05"
    /// (this week), then the day ("12 Oct").
    static func relative(_ date: Date, now: Date = .now, calendar: Calendar = .app,
                         language: AppLanguage = .current) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 10 { return language.string("just now") }
        if seconds < 60 { return language.string("\(Int(seconds)) s ago") }
        if seconds < 3600 { return language.string("\(Int(seconds / 60)) min ago") }
        if calendar.isDate(date, inSameDayAs: now) { return language.string("\(Int(seconds / 3600)) h ago") }
        let time = date.formatted(style(calendar, language).hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return language.string("yesterday \(time)")
        }
        if seconds < 6 * 86_400 { return date.formatted(style(calendar, language).weekday(.abbreviated)) + " " + time }
        return day(date, now: now, calendar: calendar, language: language)
    }

    /// A moment with its time, before or after now (an auction's end): "today 14:00", "tomorrow 09:30", "yesterday
    /// 18:05", "Thu 14:00" (within six days), else the day ("12 Nov 14:00"); German "heute 14:00", "morgen 09:30",
    /// "Do 14:00", "12. Nov. 14:00".
    static func moment(_ date: Date, now: Date = .now, calendar: Calendar = .app,
                       language: AppLanguage = .current) -> String {
        let time = date.formatted(style(calendar, language).hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
        func isDay(_ offset: Int) -> Bool {
            calendar.date(byAdding: .day, value: offset, to: now).map { calendar.isDate(date, inSameDayAs: $0) } ?? false
        }
        if isDay(0) { return language.string("today \(time)") }
        if isDay(1) { return language.string("tomorrow \(time)") }
        if isDay(-1) { return language.string("yesterday \(time)") }
        if abs(date.timeIntervalSince(now)) < 6 * 86_400 {
            return date.formatted(style(calendar, language).weekday(.abbreviated)) + " " + time
        }
        return day(date, now: now, calendar: calendar, language: language) + " " + time
    }

    /// An API timestamp, relative; nil if it cannot be read.
    static func relative(_ timestamp: String?, now: Date = .now, calendar: Calendar = .app,
                         language: AppLanguage = .current) -> String? {
        timestamp.flatMap(Timestamp.parse).map { relative($0, now: now, calendar: calendar, language: language) }
    }

    /// "1 Dec" (German "1. Dez."); with the year when the day is far from now ("1 Dec 2027").
    static func day(_ date: Date, now: Date = .now, calendar: Calendar = .app, language: AppLanguage = .current) -> String {
        let far = abs(date.timeIntervalSince(now)) > 330 * 86_400
        let style = style(calendar, language).day().month(.abbreviated)
        return date.formatted(far ? style.year() : style)
    }

    /// An API date ("2026-12-01") as "1 Dec"; nil if it cannot be read.
    static func day(_ string: String?, now: Date = .now, calendar: Calendar = .app,
                    language: AppLanguage = .current) -> String? {
        string.flatMap { DateOnly.parse($0, calendar: calendar) }.map { day($0, now: now, calendar: calendar, language: language) }
    }

    private static func style(_ calendar: Calendar, _ language: AppLanguage) -> Date.FormatStyle {
        Date.FormatStyle(date: .omitted, time: .omitted, locale: language.locale, calendar: calendar,
                         timeZone: calendar.timeZone)
    }
}

extension Calendar {
    /// Gregorian in the phone's time zone: what "today" and "yesterday" mean to the user.
    static var app: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }
}

/// API timestamps: ISO 8601 with `Z` or an offset, with or without fractional seconds.
enum Timestamp {
    static func parse(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }
}

/// API dates without a time ("2026-12-01"), as the start of that day in the given calendar (and back).
enum DateOnly {
    static func parse(_ string: String, calendar: Calendar = .app) -> Date? {
        let parts = string.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, string.count == 10 else { return nil }
        let components = DateComponents(year: parts[0], month: parts[1], day: parts[2])
        guard let date = calendar.date(from: components),
              calendar.dateComponents([.year, .month, .day], from: date) == components else { return nil }
        return date
    }

    static func string(_ date: Date, calendar: Calendar = .app) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

// MARK: - names

extension Kind {
    /// "Flat", "WG room" (German "Wohnung", "WG-Zimmer"; the server's labels too: the push subtitle).
    func title(in language: AppLanguage = .current) -> String {
        switch self {
        case .flat: language.string("Flat")
        case .wg: language.string("WG room")
        }
    }

    var title: String { title() }

    /// On a listing row.
    var short: String { title }
}

extension Place {
    /// "Garching bei München" → "Garching": the town without its "bei …", "an der …", "am …" part.
    var shortName: String {
        let cuts = [" bei ", " an der ", " am ", " im ", " in der ", " in ", " ob der ", " (", ", "]
        let end = cuts.compactMap { name.range(of: $0)?.lowerBound }.min()
        return end.map { String(name[..<$0]) } ?? name
    }
}

// MARK: - the search in two lines

/// The hunt's search as the Hunt tab shows it: what ("Flat or WG room") and where, for whom, how much, when
/// ("München, Garching · 2 people · up to €1,000 warm · from 1 Dec"). The warm rent stands for the rent when both are
/// set; sizes are left to the Search tab.
struct SearchSummary: Equatable {
    /// The kinds as phrases ("Flat", "WG room") and as one sentence.
    let kindPhrases: [String]
    var kinds: String { sentence(kindPhrases) }
    /// Places, rent, move-in: each part a unit that should not be broken across lines.
    let parts: [String]
    var details: String { parts.joined(separator: " · ") }

    /// For display: lines break only between kinds and between parts, never inside "WG room" or "1 Dec – 1 Feb".
    var wrappingKinds: String { sentence(kindPhrases.map(Self.unbreakable)) }
    var wrappingDetails: String { parts.map(Self.unbreakable).joined(separator: " · ") }

    static func unbreakable(_ phrase: String) -> String {
        phrase.replacingOccurrences(of: " ", with: "\u{00A0}")
            .replacingOccurrences(of: "-", with: "-\u{2060}")
            .replacingOccurrences(of: "–", with: "\u{2060}–\u{2060}")
    }

    private let language: AppLanguage

    init(_ search: Search, now: Date = .now, calendar: Calendar = .app, language: AppLanguage = .current) {
        self.language = language
        let kinds = Kind.allCases.filter(search.kinds.contains)
        kindPhrases = kinds.map { $0.title(in: language) }
        var parts: [String] = []
        if let places = Self.places(search.places) { parts.append(places) }
        if search.people > 1 { parts.append(language.string("\(search.people) people")) }
        if let rent = Self.rent(min: search.rentWarmMin, max: search.rentWarmMax, warm: true, language: language)
            ?? Self.rent(min: search.rentColdMin, max: search.rentColdMax, warm: false, language: language) {
            parts.append(rent)
        }
        if let moveIn = Self.moveIn(search, now: now, calendar: calendar, language: language) { parts.append(moveIn) }
        self.parts = parts
    }

    /// "€400–1,000 warm", "up to €1,000 warm", "from €400 warm" (German "400–1.000 € warm", "bis 1.000 € warm", …)
    private static func rent(min: Double?, max: Double?, warm: Bool, language: AppLanguage) -> String? {
        let label = warm ? language.string("warm") : language.string("cold")
        switch (min, max) {
        case let (min?, max?): return "\(Format.moneyRange(min, max, language: language)) \(label)"
        case let (nil, max?): return language.string("up to \(Format.money(max, language: language)) \(label)")
        case let (min?, nil): return language.string("from \(Format.money(min, language: language)) \(label)")
        case (nil, nil): return nil
        }
    }

    /// "a", "a or b", "a, b or c" (German "a, b oder c")
    private func sentence(_ items: [String]) -> String {
        items.formatted(.list(type: .or).locale(language.locale))
    }

    /// Short town names (full ones where two would read the same), at most three, then "+2".
    private static func places(_ places: [Place]) -> String? {
        guard !places.isEmpty else { return nil }
        let short = places.map(\.shortName)
        let names = places.enumerated().map { index, place in
            short.filter { $0 == short[index] }.count > 1 ? place.name : short[index]
        }
        let shown = names.prefix(3).joined(separator: ", ")
        return names.count > 3 ? "\(shown) +\(names.count - 3)" : shown
    }

    private static func moveIn(_ search: Search, now: Date, calendar: Calendar, language: AppLanguage) -> String? {
        let from = Format.day(search.moveInFrom, now: now, calendar: calendar, language: language)
        let until = Format.day(search.moveInUntil, now: now, calendar: calendar, language: language)
        switch (from, until) {
        case let (from?, until?): return "\(from) – \(until)"
        case let (from?, nil): return language.string("from \(from)")
        case let (nil, until?): return language.string("until \(until)")
        case (nil, nil): return nil
        }
    }
}

// MARK: - a listing's lines

extension Listing {
    /// The rent to show big and what it is: warm if known, else cold.
    var shownRent: (amount: String, label: String)? { shownRent() }

    func shownRent(language: AppLanguage = .current) -> (amount: String, label: String)? {
        if let rentWarm { return (Format.money(rentWarm, language: language), language.string("warm")) }
        if let rentCold { return (Format.money(rentCold, language: language), language.string("cold")) }
        return nil
    }

    /// "42 m² · 2 rooms · Schwabing" (a WG: "19 m² · WG room · Hochbrück"); unknown parts left out.
    var facts: String {
        var parts: [String] = []
        if let sqm { parts.append(Format.size(sqm)) }
        if let kind, kind.isWG {
            parts.append(kind.short)
        } else if let rooms {
            parts.append(Format.rooms(rooms))
        }
        if let place = district ?? city { parts.append(place) }
        return parts.joined(separator: " · ")
    }
}

/// One label/value pair of a listing page's facts; `numeric` values are set in the number font. A fact the listing does
/// not state has no value: the page shows a quiet "–" (`ListingFact.dash`) and VoiceOver says "not stated", so an
/// unknown never reads like a value (brief 142).
struct ListingFact: Equatable, Identifiable {
    let label: String
    /// nil: the listing does not state it.
    let value: String?
    var unit: String? = nil        // "m²", set apart from the number
    var numeric = false            // a plain number (mono); dates and times read as words
    var id: String { label }

    var isStated: Bool { value != nil }

    /// What the page shows for a fact the listing does not state.
    static let dash = "–"

    /// What VoiceOver says for it.
    static func notStated(language: AppLanguage = .current) -> String { language.string("not stated") }
}

extension Listing {
    /// A flat's page, its facts as a portal lists them (brief 142, Patrik 2026-11-03: "make it look like a normal listing
    /// with our metrics and just fill them in or have a '-' … if empty"): the rent the big figure does not show (cold
    /// beside a warm figure, warm beside a cold one; none when the listing gives no rent, which the big figure says),
    /// Size (the room's for a WG room), Rooms (a flat) or Flatmates (a WG room), Move-in, Until, Furnished, Location (the
    /// address with the district, else the district or the city), Kind, Posted.
    ///
    /// The facts every flat search asks about are always there, unknown ones without a value: the rents, the size,
    /// rooms or flatmates, move-in and the place, and Furnished, which every flat listing is judged by. Until shows
    /// when the listing gives an end or the search wants only sublets (`search`; for any other flat an end that is not
    /// given means none). Kind and Posted only when known: the title and the time found say them anyway.
    func detailFacts(search: Search? = nil, now: Date = .now, calendar: Calendar = .app,
                     language: AppLanguage = .current) -> [ListingFact] {
        let l = language
        var facts: [ListingFact] = []
        func money(_ label: String, _ euros: Double?) {
            facts.append(ListingFact(label: label, value: euros.map { Format.money($0, language: l) }, numeric: true))
        }
        if rentWarm != nil {
            money(l.string("Cold rent"), rentCold)
        } else if rentCold != nil {
            money(l.string("Warm rent"), nil)
        }
        let wg = kind?.isWG == true
        facts.append(ListingFact(label: wg ? l.string("Room size") : l.string("Size"),
                                 value: sqm.map { Format.number($0, language: l) }, unit: "m²", numeric: true))
        if wg {
            facts.append(ListingFact(label: l.string("Flatmates"), value: flatmates.map(String.init), numeric: true))
        } else {
            facts.append(ListingFact(label: l.string("Rooms"), value: rooms.map { Format.number($0, language: l) },
                                     numeric: true))
        }
        facts.append(ListingFact(label: l.string("Move-in"),
                                 value: Format.day(availableFrom, now: now, calendar: calendar, language: l)))
        let until = Format.day(availableUntil, now: now, calendar: calendar, language: l)
        if until != nil || search?.sublet == .only {
            facts.append(ListingFact(label: l.string("Until"), value: until))
        }
        facts.append(ListingFact(label: l.string("Furnished"),
                                 value: furnished.map { $0 ? l.string("Yes") : l.string("No") }))
        facts.append(ListingFact(label: l.string("Location"), value: location))
        if let kind { facts.append(ListingFact(label: l.string("Kind"), value: kind.title(in: l))) }
        if let posted = Format.relative(posted, now: now, calendar: calendar, language: l) {
            facts.append(ListingFact(label: l.string("Posted"), value: posted))
        }
        return facts
    }

    /// Where the flat is, as precisely as the listing says: "Hohenzollernstraße, Schwabing", "Schwabing", "München";
    /// nil when it does not say.
    var location: String? {
        let near = [address, district].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if !near.isEmpty { return near.joined(separator: ", ") }
        return city.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
    }

    /// The portal page, only if it is a web address (never another app's scheme from a listing).
    var portalURL: URL? {
        guard let url = URL(string: url), let scheme = url.scheme?.lowercased(), ["https", "http"].contains(scheme),
              url.host() != nil else { return nil }
        return url
    }

    /// "€950 warm · 30 m² · 1 room · Maxvorstadt" (filtered-out rows, which have no big rent).
    var factsWithRent: String {
        ([shownRent.map { "\($0.amount) \($0.label)" }] + [facts.isEmpty ? nil : facts]).compactMap { $0 }
            .joined(separator: " · ")
    }
}

extension Match {
    /// "WG-Gesucht · 4 min ago"
    func sourceLine(now: Date = .now, calendar: Calendar = .app) -> String {
        [listing.sourceName, Format.relative(found, now: now, calendar: calendar)].compactMap { $0 }.joined(separator: " · ")
    }
}
