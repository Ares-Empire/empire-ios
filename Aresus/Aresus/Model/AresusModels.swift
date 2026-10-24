import Foundation

/// The Aresus API, version 1 (aresus/docs/API.md). The server checks, decides and sorts; the app only displays.
/// Field names follow the contract; timestamps decode to `Date` (`AresusJSON`), calendar days ("2026-10-24") stay text.

nonisolated enum AresusState: String, Codable, Sendable {
    case issue, active, inactive
}

nonisolated enum RunResult: String, Codable, Sendable {
    case ok, failed
}

nonisolated struct Province: Codable, Equatable, Identifiable, Sendable {
    let slug: String               // "aresium"; "empire" for the hub itself
    let name: String
    let logo: String?              // hub brand path, e.g. "brand/hermes.webp"
    let state: AresusState
    let word: String               // "Issue" | "Active" | "Inactive" | "Planned"
    let line: String               // "Website 182 ms" · "Website down since 14:02" · "Off on purpose"
    let since: Date?
    var id: String { slug }
}

nonisolated struct Server: Codable, Equatable, Sendable {
    let host: String
    let diskUsed: Double           // 0…1
    let memoryUsed: Double         // 0…1
    let load: Double               // 1-minute load average
    let uptimeSeconds: Int
    let issue: String?             // "Disk 92 % full" when over a limit

    enum CodingKeys: String, CodingKey {
        case host, load, issue
        case diskUsed = "disk_used", memoryUsed = "memory_used", uptimeSeconds = "uptime_s"
    }
}

nonisolated struct Overview: Codable, Equatable, Sendable {
    let version: Int
    let checked: Date              // last completed check round
    let summary: String            // "Everything running" · "1 issue" · "2 issues"
    let server: Server
    let provinces: [Province]      // sorted by the server: issue, active, inactive (planned last), then by name
}

nonisolated struct Check: Codable, Equatable, Identifiable, Sendable {
    let name: String
    let ok: Bool
    let detail: String
    let checked: Date
    var id: String { name }
}

nonisolated struct Deploy: Codable, Equatable, Sendable {
    let commit: String
    let subject: String
    let date: Date
    let behind: Int?               // commits on GitHub not deployed; nil = unknown
}

nonisolated struct Incident: Codable, Equatable, Identifiable, Sendable {
    let opened: Date
    let resolved: Date?
    let summary: String
    var id: String { "\(opened.timeIntervalSince1970)-\(summary)" }
}

nonisolated struct UptimeDay: Codable, Equatable, Identifiable, Sendable {
    let day: String                // "2026-10-24"
    let ratio: Double?             // nil = not watched that day
    var id: String { day }
}

/// `ProvinceDetail extends Province` in the contract.
nonisolated struct ProvinceDetail: Codable, Equatable, Sendable {
    let slug: String
    let name: String
    let logo: String?
    let state: AresusState
    let word: String
    let line: String
    let since: Date?
    let about: String?
    let checks: [Check]
    let deploy: Deploy?
    let incidents: [Incident]      // last 30 days, newest first
    let uptime: [UptimeDay]        // last 14 days, oldest first

    var province: Province {
        Province(slug: slug, name: name, logo: logo, state: state, word: word, line: line, since: since)
    }
}

nonisolated struct Machine: Codable, Equatable, Identifiable, Sendable {
    let name: String               // "Aresium" (the MacBook's host name), "Notebook-Patrik", "Server"
    let os: String                 // "macOS" | "Windows" | "Linux"
    let lastRun: Date?
    let lastResult: RunResult?
    let lastOK: Date?
    let openProblems: [String]
    let state: AresusState         // issue = an open problem; inactive = no run for a while
    var id: String { name }

    enum CodingKeys: String, CodingKey {
        case name, os, state
        case lastRun = "last_run", lastResult = "last_result", lastOK = "last_ok", openProblems = "open_problems"
    }
}

nonisolated struct RunSummary: Codable, Equatable, Sendable {
    let id: Int
    let machine: String
    let finished: Date
    let result: RunResult
    let summary: String            // "pulled 2 · pushed 1" · "rebase conflict in aresium" · "nothing to do"
}

/// Runs that changed nothing and had no problem, folded per machine and day.
nonisolated struct QuietDay: Codable, Equatable, Sendable {
    let machine: String
    let day: String                // "2026-10-24"
    let count: Int
    let last: Date
}

/// `RunSummary | QuietDay`, told apart by the contract's `quiet` key.
nonisolated enum SyncItem: Codable, Equatable, Identifiable, Sendable {
    case run(RunSummary)
    case quiet(QuietDay)

    private enum Key: String, CodingKey { case quiet }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: Key.self)
        if try container.decode(Bool.self, forKey: .quiet) {
            self = .quiet(try QuietDay(from: decoder))
        } else {
            self = .run(try RunSummary(from: decoder))
        }
    }

    func encode(to encoder: any Encoder) throws {
        switch self {
        case .run(let run): try run.encode(to: encoder)
        case .quiet(let day): try day.encode(to: encoder)
        }
        var container = encoder.container(keyedBy: Key.self)
        try container.encode(isQuiet, forKey: .quiet)
    }

    var isQuiet: Bool { if case .quiet = self { true } else { false } }

    var id: String {
        switch self {
        case .run(let run): "run-\(run.id)"
        case .quiet(let day): "quiet-\(day.machine)-\(day.day)"
        }
    }
}

nonisolated struct SyncOverview: Codable, Equatable, Sendable {
    let machines: [Machine]
    let runs: [SyncItem]           // newest first, last 14 days, max 200 items
}

nonisolated struct RunCounts: Codable, Equatable, Sendable {
    let cloned: Int
    let committed: Int
    let pushed: Int
    let pulled: Int
    let skipped: Int
    let failed: Int
}

nonisolated struct RunProblem: Codable, Equatable, Sendable {
    let key: String
    let immediate: Bool
    let message: String
}

/// `RunDetail extends RunSummary` in the contract.
nonisolated struct RunDetail: Codable, Equatable, Sendable {
    let id: Int
    let machine: String
    let finished: Date
    let result: RunResult
    let summary: String
    let started: Date
    let counts: RunCounts
    let lines: [String]            // the run's log lines without timestamps
    let problems: [RunProblem]
}

/// Timestamps are ISO 8601 with `Z`; fractional seconds and numeric offsets are accepted too.
nonisolated enum AresusJSON {
    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            guard let date = date(text) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not an ISO 8601 timestamp: \(text)")
            }
            return date
        }
        return decoder
    }

    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static func date(_ text: String) -> Date? {
        if let date = try? Date(text, strategy: Date.ISO8601FormatStyle()) { return date }
        return try? Date(text, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true))
    }
}
