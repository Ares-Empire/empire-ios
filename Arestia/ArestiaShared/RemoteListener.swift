import Foundation

nonisolated struct RemoteListener: Equatable, Sendable, Encodable {
    let url: URL
    let pin: FlatdPin

    let generation: UUID

    private init(url: URL, pin: FlatdPin, generation: UUID) {
        self.url = url
        self.pin = pin
        self.generation = generation
    }

    static func parse(url text: String?, pin hex: String?, homePin: FlatdPin, generation: UUID = UUID()) -> RemoteListener? {
        let endpoint = /https:\/\/([a-zA-Z0-9-]+(?:\.[a-zA-Z0-9-]+)+):([0-9]+)/
        let label = /[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?/
        guard let text, let match = text.wholeMatch(of: endpoint),
              match.1.utf8.count <= 253,
              match.1.split(separator: ".").allSatisfy({ $0.wholeMatch(of: label) != nil }),
              let suffix = match.1.split(separator: ".").last,
              suffix.lowercased().hasPrefix("xn--") || suffix.allSatisfy(\.isLetter),
              let port = UInt16(match.2.drop(while: { $0 == "0" })), port > 0,
              let url = URL(string: "https://\(match.1):\(port)"),
              let hex, let pin = FlatdPin(hex), pin.hex == hex, pin != homePin else { return nil }
        return RemoteListener(url: url, pin: pin, generation: generation)
    }

    struct Saved: Decodable {
        let url: String?
        let pin: String?
        let generation: UUID?
    }
}
