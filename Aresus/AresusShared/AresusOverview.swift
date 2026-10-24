import Foundation

/// The Aresus API's overview (aresus/docs/API.md → `GET /overview`), compiled into the app and the widget. The rest of
/// the contract's types are the app's (`Aresus/Model/AresusModels.swift`). Field names follow the contract; timestamps
/// decode to `Date` (`AresusJSON`).

nonisolated enum AresusState: String, Codable, Sendable {
    case issue, active, inactive
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
