import Foundation

/// How the app writes the API's values: English labels, € in front, mono-friendly numbers. Pure functions with the
/// clock and calendar passed in, so the tests pin them.
enum Format {
    private static let posix = Locale(identifier: "en_US_POSIX")
    private static let grouping = Locale(identifier: "en_US")

    /// "€980", "€1,150" (whole euros).
    static func money(_ euros: Double) -> String {
        "€" + Int(euros.rounded()).formatted(.number.locale(grouping))
    }

    /// "42", "42.5": whole numbers without a decimal point.
    static func number(_ value: Double) -> String {
        if value == value.rounded() { return String(Int(value)) }
        return String(format: "%.1f", locale: posix, value)
    }

    /// "42 m²"
    static func size(_ sqm: Double) -> String { number(sqm) + " m²" }

    /// "1 room", "2 rooms", "1.5 rooms"
    static func rooms(_ rooms: Double) -> String { number(rooms) + (rooms == 1 ? " room" : " rooms") }

    /// "1 flatmate", "2 flatmates"
    static func flatmates(_ count: Int) -> String { "\(count) flatmate" + (count == 1 ? "" : "s") }

    /// How long ago: "just now", "40 s ago", "4 min ago", "3 h ago" (same day), "yesterday 18:05", "Mon 18:05"
    /// (this week), then the day ("12 Oct").
    static func relative(_ date: Date, now: Date = .now, calendar: Calendar = .app) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 10 { return "just now" }
        if seconds < 60 { return "\(Int(seconds)) s ago" }
        if seconds < 3600 { return "\(Int(seconds / 60)) min ago" }
        if calendar.isDate(date, inSameDayAs: now) { return "\(Int(seconds / 3600)) h ago" }
        let time = formatted(date, "HH:mm", calendar: calendar)
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "yesterday " + time
        }
        if seconds < 6 * 86_400 { return formatted(date, "EEE", calendar: calendar) + " " + time }
        return day(date, now: now, calendar: calendar)
    }

    /// An API timestamp, relative; nil if it cannot be read.
    static func relative(_ timestamp: String?, now: Date = .now, calendar: Calendar = .app) -> String? {
        timestamp.flatMap(Timestamp.parse).map { relative($0, now: now, calendar: calendar) }
    }

    /// "1 Dec"; with the year when the day is far from now ("1 Dec 2027").
    static func day(_ date: Date, now: Date = .now, calendar: Calendar = .app) -> String {
        let far = abs(date.timeIntervalSince(now)) > 330 * 86_400
        return formatted(date, far ? "d MMM yyyy" : "d MMM", calendar: calendar)
    }

    /// An API date ("2026-12-01") as "1 Dec"; nil if it cannot be read.
    static func day(_ string: String?, now: Date = .now, calendar: Calendar = .app) -> String? {
        string.flatMap { DateOnly.parse($0, calendar: calendar) }.map { day($0, now: now, calendar: calendar) }
    }

    private static func formatted(_ date: Date, _ pattern: String, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = posix
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = pattern
        return formatter.string(from: date)
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
    /// "Flat", "WG room" (the server's labels too: the push subtitle).
    var title: String {
        switch self {
        case .flat: "Flat"
        case .wg: "WG room"
        }
    }

    /// Inside a sentence, after the first kind: "WG room".
    var inSentence: String { title }

    /// On a listing row.
    var short: String { title }
}

extension Source {
    /// The portal's name when the server's (`SourceStatus.name`, `Listing.source_name`) is not at hand.
    var name: String {
        switch self {
        case .wgGesucht: "WG-Gesucht"
        case .kleinanzeigen: "Kleinanzeigen"
        case .immowelt: "Immowelt"
        }
    }
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
    var kinds: String { Self.sentence(kindPhrases) }
    /// Places, rent, move-in: each part a unit that should not be broken across lines.
    let parts: [String]
    var details: String { parts.joined(separator: " · ") }

    /// For display: lines break only between kinds and between parts, never inside "WG room" or "1 Dec – 1 Feb".
    var wrappingKinds: String { Self.sentence(kindPhrases.map(Self.unbreakable)) }
    var wrappingDetails: String { parts.map(Self.unbreakable).joined(separator: " · ") }

    private static func unbreakable(_ phrase: String) -> String {
        phrase.replacingOccurrences(of: " ", with: "\u{00A0}")
            .replacingOccurrences(of: "-", with: "-\u{2060}")
            .replacingOccurrences(of: "–", with: "\u{2060}–\u{2060}")
    }

    init(_ search: Search, now: Date = .now, calendar: Calendar = .app) {
        let kinds = Kind.allCases.filter(search.kinds.contains)
        kindPhrases = kinds.enumerated().map { $0.offset == 0 ? $0.element.title : $0.element.inSentence }
        var parts: [String] = []
        if let places = Self.places(search.places) { parts.append(places) }
        if search.people > 1 { parts.append("\(search.people) people") }
        if let rent = Self.rent(min: search.rentWarmMin, max: search.rentWarmMax, label: "warm")
            ?? Self.rent(min: search.rentColdMin, max: search.rentColdMax, label: "cold") {
            parts.append(rent)
        }
        if let moveIn = Self.moveIn(search, now: now, calendar: calendar) { parts.append(moveIn) }
        self.parts = parts
    }

    /// "€400–1,000 warm", "up to €1,000 warm", "from €400 warm"
    private static func rent(min: Double?, max: Double?, label: String) -> String? {
        switch (min, max) {
        case let (min?, max?): "\(Format.money(min))–\(Format.money(max).dropFirst()) \(label)"
        case let (nil, max?): "up to \(Format.money(max)) \(label)"
        case let (min?, nil): "from \(Format.money(min)) \(label)"
        case (nil, nil): nil
        }
    }

    /// "a", "a or b", "a, b or c"
    private static func sentence(_ items: [String]) -> String {
        guard items.count > 1 else { return items.first ?? "" }
        return items.dropLast().joined(separator: ", ") + " or " + items[items.count - 1]
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

    private static func moveIn(_ search: Search, now: Date, calendar: Calendar) -> String? {
        let from = Format.day(search.moveInFrom, now: now, calendar: calendar)
        let until = Format.day(search.moveInUntil, now: now, calendar: calendar)
        switch (from, until) {
        case let (from?, until?): return "\(from) – \(until)"
        case let (from?, nil): return "from \(from)"
        case let (nil, until?): return "until \(until)"
        case (nil, nil): return nil
        }
    }
}

// MARK: - a listing's lines

extension Listing {
    /// The rent to show big and what it is: warm if known, else cold.
    var shownRent: (amount: String, label: String)? {
        if let rentWarm { return (Format.money(rentWarm), "warm") }
        if let rentCold { return (Format.money(rentCold), "cold") }
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

/// One label/value pair of a match's facts grid; `numeric` values are set in the number font.
struct ListingFact: Equatable, Identifiable {
    let label: String
    let value: String
    var unit: String? = nil        // "m²", set apart from the number
    var numeric = false            // a plain number (mono); dates and times read as words
    var id: String { label }
}

extension Listing {
    /// The match page's grid: Size, Rooms (a flat) or Flatmates (a WG), Kind, Move-in, Until, Furnished, District
    /// (or City), Posted; only the known ones.
    func detailFacts(now: Date = .now, calendar: Calendar = .app) -> [ListingFact] {
        var facts: [ListingFact] = []
        if let sqm { facts.append(ListingFact(label: "Size", value: Format.number(sqm), unit: "m²", numeric: true)) }
        if let kind, kind.isWG {
            if let flatmates { facts.append(ListingFact(label: "Flatmates", value: String(flatmates), numeric: true)) }
        } else if let rooms {
            facts.append(ListingFact(label: "Rooms", value: Format.number(rooms), numeric: true))
        }
        if let kind { facts.append(ListingFact(label: "Kind", value: kind.title)) }
        if let from = Format.day(availableFrom, now: now, calendar: calendar) {
            facts.append(ListingFact(label: "Move-in", value: from))
        }
        if let until = Format.day(availableUntil, now: now, calendar: calendar) {
            facts.append(ListingFact(label: "Until", value: until))
        }
        if let furnished { facts.append(ListingFact(label: "Furnished", value: furnished ? "Yes" : "No")) }
        if let district {
            facts.append(ListingFact(label: "District", value: district))
        } else if let city {
            facts.append(ListingFact(label: "City", value: city))
        }
        if let posted = Format.relative(posted, now: now, calendar: calendar) {
            facts.append(ListingFact(label: "Posted", value: posted))
        }
        return facts
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
