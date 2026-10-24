import Foundation

/// What the screens show, derived from the contract's answers: sections, flags, groupings. Kept out of the views so it
/// is tested, and kept to presentation: what is wrong and in which order is the server's call.

/// One of the overview's sections (Issues, Active, Inactive), in the server's order.
nonisolated struct ProvinceSection: Equatable, Identifiable, Sendable {
    let state: AresusState
    let provinces: [Province]
    var id: AresusState { state }

    var title: String {
        switch state {
        case .issue: String(localized: "Issues")
        case .active: String(localized: "Active")
        case .inactive: String(localized: "Inactive")
        }
    }
}

extension Overview {
    /// Issues (only if any), Active, Inactive; the provinces keep the server's order within each.
    nonisolated var sections: [ProvinceSection] {
        [AresusState.issue, .active, .inactive].compactMap { state in
            let provinces = provinces.filter { $0.state == state }
            return provinces.isEmpty ? nil : ProvinceSection(state: state, provinces: provinces)
        }
    }

    /// The summary reads in the issue red when a province or the server has an issue.
    nonisolated var hasIssue: Bool { server.issue != nil || provinces.contains { $0.state == .issue } }
}

/// The server's limits as the contract states them (aresus/docs/API.md → Server): above them the server reports an
/// issue, and the card's bar turns red.
nonisolated enum ServerLimits {
    static let disk = 0.85
    static let memory = 0.92
}

extension Server {
    nonisolated var diskOverLimit: Bool { diskUsed > ServerLimits.disk }
    nonisolated var memoryOverLimit: Bool { memoryUsed > ServerLimits.memory }
}

extension Machine {
    /// The SF Symbol for the machine's system.
    nonisolated var symbol: String {
        switch os {
        case "macOS": "laptopcomputer"
        case "Windows": "pc"
        case "Linux": "server.rack"
        default: "desktopcomputer"
        }
    }
}

extension AresusState {
    /// A machine's status word (provinces bring their own `word`).
    nonisolated var word: String {
        switch self {
        case .issue: String(localized: "Issue")
        case .active: String(localized: "Active")
        case .inactive: String(localized: "Inactive")
        }
    }
}

extension RunCounts {
    /// The counts worth showing, zeros left out: what came in, what went out, then what went wrong. `key` is the
    /// contract's name, `label` the word shown.
    nonisolated var shown: [(key: String, label: String, value: Int)] {
        [("pulled", String(localized: "pulled"), pulled), ("pushed", String(localized: "pushed"), pushed),
         ("committed", String(localized: "committed"), committed), ("cloned", String(localized: "cloned"), cloned),
         ("skipped", String(localized: "skipped"), skipped), ("failed", String(localized: "failed"), failed)]
            .filter { $0.2 > 0 }
    }
}

/// How a log line reads: failures in the issue red, skips and warnings muted, the rest in ink.
nonisolated enum LogTone: Equatable, Sendable {
    case fail, quiet, normal

    init(line: String) {
        let word = line.prefix { !$0.isWhitespace }.uppercased()
        switch word {
        case "FAIL", "FAILED", "ERROR": self = .fail
        case "SKIP", "WARN", "WARNING": self = .quiet
        default: self = .normal
        }
    }
}

/// One day of sync runs under its heading ("Today", "Yesterday", "Sat 19 Oct").
nonisolated struct RunDay: Equatable, Identifiable, Sendable {
    let key: String                // "2026-10-24"
    let title: String
    let items: [SyncItem]
    var id: String { key }

    /// Groups the server's list (newest first) by day: a run by the day it finished on this phone, a quiet day by its
    /// own `day`. Days come newest first; within a day the server's order stays.
    static func group(_ items: [SyncItem], now: Date, calendar: Calendar = .current) -> [RunDay] {
        var keys: [String] = []
        var byKey: [String: [SyncItem]] = [:]
        for item in items {
            let key: String
            switch item {
            case .run(let run): key = AresusFormat.dayKey(run.finished, calendar: calendar)
            case .quiet(let day): key = AresusFormat.date(day: day.day, calendar: calendar) == nil
                ? AresusFormat.dayKey(day.last, calendar: calendar) : day.day
            }
            if byKey[key] == nil { keys.append(key) }
            byKey[key, default: []].append(item)
        }
        return keys.sorted(by: >).map { key in
            let title = AresusFormat.date(day: key, calendar: calendar)
                .map { AresusFormat.dayHeading($0, now: now, calendar: calendar) } ?? key
            return RunDay(key: key, title: title, items: byKey[key] ?? [])
        }
    }
}

extension ProvinceDetail {
    /// The average of the watched days, nil when none was watched.
    nonisolated var averageUptime: Double? {
        let watched = uptime.compactMap(\.ratio)
        return watched.isEmpty ? nil : watched.reduce(0, +) / Double(watched.count)
    }
}

/// A day's bar in the 14-day strip: the up share and the down share of its height, nil when not watched. Any
/// downtime keeps a visible sliver (`minimumDown`), so a six-minute outage is not lost in a 99.6 % day.
nonisolated struct UptimeShare: Equatable, Sendable {
    let up: Double
    let down: Double

    init?(ratio: Double?, minimumDown: Double = 0.08) {
        guard let ratio else { return nil }
        let clamped = max(0, min(1, ratio))
        down = clamped < 1 ? max(1 - clamped, minimumDown) : 0
        up = 1 - down
    }
}
