import Foundation

/// A link to a note, optionally to one of its headings: `arestoteles://note/<id>#<anchor>`, id and anchor
/// percent-encoded (the contract's Text links). The one parser for links tapped in a note, deep links from outside
/// and Spotlight results, so all three open notes the same way.
nonisolated struct NoteLink: Hashable, Sendable {
    static let scheme = "arestoteles"

    let note: String
    var anchor: String?

    init(note: String, anchor: String? = nil) {
        self.note = note
        self.anchor = anchor.flatMap { $0.isEmpty ? nil : $0 }
    }

    /// `arestoteles://note/Printing%20press#My%20position`. Nil for anything else (a web link, the bare
    /// `arestoteles://` the Empire app opens the app with, a note link without an id).
    init?(url: URL) {
        guard url.scheme?.lowercased() == Self.scheme,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.host?.lowercased() == "note" else { return nil }
        // The path is "/<id>" with the id percent-encoded; ids never contain "/", so everything after the first
        // slash is the id.
        var path = components.percentEncodedPath
        guard path.hasPrefix("/") else { return nil }
        path.removeFirst()
        guard let note = path.removingPercentEncoding, !note.isEmpty else { return nil }
        self.init(note: note, anchor: components.percentEncodedFragment.flatMap { $0.removingPercentEncoding })
    }

    /// A link written as text: Spotlight's identifier for a note, a launch argument.
    init?(string: String) {
        guard let url = URL(string: string) else { return nil }
        self.init(url: url)
    }

    var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = "note"
        components.percentEncodedPath = "/" + Self.encode(note)
        if let anchor { components.percentEncodedFragment = Self.encode(anchor) }
        return components.url!
    }

    /// Percent-encodes everything but RFC 3986's unreserved characters, so an id is always one path segment (and an
    /// anchor one fragment), whatever it contains.
    static func encode(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: .unreserved) ?? text
    }
}

nonisolated extension CharacterSet {
    /// RFC 3986 unreserved: ALPHA / DIGIT / "-" / "." / "_" / "~".
    static let unreserved = CharacterSet(charactersIn:
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
}
