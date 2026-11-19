import Foundation

/// What Patrik pastes or scans (with Arestia's own scanner) once to connect the app: flatd's key, and maybe its
/// address. Read leniently:
/// - JSON: `{"url": "http://<host>:8787", "token": "<key>"}` (the QR code's form: scanned inside the app only);
/// - flatd's own address with the key: `http://<host>:8787/?token=<key>` (also `flatd_token=`, the viewer's name);
/// - the key alone (the address then comes from Bonjour).
/// Never an `arestia://` link with the key: another app may claim the same URL scheme and would get the key when the
/// camera opens the link (Codex's review, round 3).
nonisolated struct PairingCode: Equatable, Sendable {
    let token: String
    let baseURL: URL?

    static func parse(_ text: String) -> PairingCode? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if text.hasPrefix("{") { return json(text) }
        if let url = URL(string: text), let scheme = url.scheme?.lowercased() {
            switch scheme {
            case "http", "https": return serviceLink(url)
            default: return nil
            }
        }
        return bareToken(text)
    }

    /// `http://<host>:8787/anything?token=…`
    private static func serviceLink(_ url: URL) -> PairingCode? {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard let token = (value("token", in: items) ?? value("flatd_token", in: items)).flatMap(cleanToken) else {
            return nil
        }
        return PairingCode(token: token, baseURL: serviceURL(url.absoluteString))
    }

    private static func json(_ text: String) -> PairingCode? {
        struct Body: Decodable { let token: String?; let url: String? }
        guard let body = try? JSONDecoder().decode(Body.self, from: Data(text.utf8)),
              let token = body.token.flatMap(cleanToken) else { return nil }
        return PairingCode(token: token, baseURL: body.url.flatMap(serviceURL))
    }

    private static func bareToken(_ text: String) -> PairingCode? {
        cleanToken(text).map { PairingCode(token: $0, baseURL: nil) }
    }

    /// A key: one word of URL-safe characters, long enough to be a real one (flatd's are `token_urlsafe(32)`).
    static func cleanToken(_ text: String) -> String? {
        let token = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_.~=+/"))
        guard token.count >= 16, token.count <= 512, token.unicodeScalars.allSatisfy(allowed.contains) else { return nil }
        return token
    }

    /// The service's base address from any link to it: http(s), the host and port, no path or query.
    static func serviceURL(_ text: String) -> URL? {
        guard var components = URLComponents(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
              let host = components.host, !host.isEmpty else { return nil }
        components.scheme = scheme
        components.path = ""
        components.query = nil
        components.fragment = nil
        components.user = nil
        components.password = nil
        return components.url
    }

    private static func value(_ name: String, in items: [URLQueryItem]) -> String? {
        items.first { $0.name == name }?.value
    }
}
