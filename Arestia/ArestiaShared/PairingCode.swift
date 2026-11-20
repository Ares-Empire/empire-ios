import Foundation

/// What Patrik scans (with Arestia's own scanner) or pastes once to connect the app: flatd's pairing code, as
/// `flatd pair` shows it on flatd's own machine. One JSON object:
///
///     {"url": "https://<address>:8788", "token": "<key>", "spki_sha256": "<64 hex digits>"}
///
/// - `token`: flatd's key. `spki_sha256`: flatd's identity (`FlatdPin`), without which the app talks to nobody.
/// - `url`: where flatd is right now, only a hint (the app also looks over Bonjour); HTTPS or the code is refused.
///
/// Nothing else is read: a key alone or an address with `?token=` carries no identity, so the app could not tell flatd
/// from a device posing as it. And never an `arestia://` link with the key: another app may claim the same URL scheme
/// and would get the key when the camera opens the link (Codex's review, round 3).
nonisolated struct PairingCode: Equatable, Sendable {
    let token: String
    let pin: FlatdPin
    let baseURL: URL?

    static func parse(_ text: String) -> PairingCode? {
        struct Body: Decodable {
            let token: String
            let spki_sha256: String
            let url: String?
        }
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.hasPrefix("{"), text.utf8.count <= 4096,
              let body = try? JSONDecoder().decode(Body.self, from: Data(text.utf8)),
              let token = cleanToken(body.token), let pin = FlatdPin(body.spki_sha256) else { return nil }
        var baseURL: URL?
        if let url = body.url {
            guard let service = serviceURL(url) else { return nil }      // an address that is not HTTPS: not flatd's code
            baseURL = service
        }
        return PairingCode(token: token, pin: pin, baseURL: baseURL)
    }

    /// A key: one word of URL-safe characters, long enough to be a real one (flatd's are `token_urlsafe(32)`).
    static func cleanToken(_ text: String) -> String? {
        let token = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_.~=+/"))
        guard token.count >= 16, token.count <= 512, token.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
        return token
    }

    /// The service's base address: `https`, the host and port, no path, query or login. Nil for anything else (plain
    /// HTTP above all: on the home network flatd speaks HTTPS only).
    static func serviceURL(_ text: String) -> URL? {
        guard var components = URLComponents(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              components.scheme?.lowercased() == "https",
              let host = components.host, !host.isEmpty else { return nil }
        components.scheme = "https"
        components.path = ""
        components.query = nil
        components.fragment = nil
        components.user = nil
        components.password = nil
        return components.url
    }
}
