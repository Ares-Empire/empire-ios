import Foundation

enum Vote: String, Codable, CaseIterable, Sendable { case up, down }

/// The server's photo judgment (brief 267). New categories keep the verdict readable.
struct LookVerdict: Codable, Equatable, Sendable {
    enum Length: String, Codable, Sendable {
        case long, mid, short, unknown
        init(from decoder: Decoder) throws {
            self = Self(rawValue: (try? decoder.singleValueContainer().decode(String.self)) ?? "") ?? .unknown
        }
    }
    enum Cut: String, Codable, Sendable {
        case men, unisex, women, unknown
        init(from decoder: Decoder) throws {
            self = Self(rawValue: (try? decoder.singleValueContainer().decode(String.self)) ?? "") ?? .unknown
        }
    }
    enum Fur: String, Codable, Sendable {
        case real, faux, unknown
        init(from decoder: Decoder) throws {
            self = Self(rawValue: (try? decoder.singleValueContainer().decode(String.self)) ?? "") ?? .unknown
        }
    }

    let score: Int
    let length: Length
    let cut: Cut
    let fur: Fur
    let reason: String
    let reasonDE: String

    enum CodingKeys: String, CodingKey {
        case score, length, cut, fur, reason
        case reasonDE = "reason_de"
    }

    func reason(language: AppLanguage = .current) -> String {
        LocalizedText(en: reason, de: reasonDE).text(language)
    }
}
