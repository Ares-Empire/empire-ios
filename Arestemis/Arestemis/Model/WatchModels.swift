import Foundation

/// Page watches (brief 130 on the server, 131 here): a hunt of kind `watch` reads one web page every so often and tells
/// the user when the change they described in their own words has happened ("the price is under 45 €"). The server reads
/// the page, decides what can be watched and says why not; the app shows its words and never judges an address itself.

/// `WatchSearch`: the page's address, the change in the user's words (3–500 characters) and how often the server reads
/// the page, in minutes.
struct WatchSearch: Codable, Equatable, Sendable {
    var url: String
    var change: String
    var every: Int

    /// The intervals the server accepts, shortest first: 15 and 30 minutes, 1, 3, 6 and 12 hours, once a day.
    static let everyChoices = [15, 30, 60, 180, 360, 720, 1440]
    /// One hour, the server's default.
    static let defaultEvery = 60
}

/// `HuntCard.page`: what the server last read of a watch's page.
struct PageState: Codable, Equatable, Sendable {
    /// How the page reads now. A value this build does not know is kept and shown as the server's note only.
    enum Read: Equatable, Sendable {
        case waiting        // not read yet (no start judgment so far)
        case ok
        case unreadable     // the page does not show what is asked; it keeps being read
        case failing        // 24 hours of failed reads
        case blocked        // a bot wall: reading stopped until the watch is edited
        case unknown(String)

        init(rawValue: String) {
            switch rawValue {
            case "waiting": self = .waiting
            case "ok": self = .ok
            case "unreadable": self = .unreadable
            case "failing": self = .failing
            case "blocked": self = .blocked
            default: self = .unknown(rawValue)
            }
        }

        var rawValue: String {
            switch self {
            case .waiting: "waiting"
            case .ok: "ok"
            case .unreadable: "unreadable"
            case .failing: "failing"
            case .blocked: "blocked"
            case .unknown(let value): value
            }
        }
    }

    var pageTitle: String?         // the page's <title>; null before the first read
    var host: String               // "www.ikea.com"
    var now: String?               // what the page says now about the change ("KALLAX 49,99 €"); null before the start read
    var read: Read
    var checked: String?           // the last read attempt
    var changed: String?           // the last time the page's text changed
    var note: String?              // one short line from the server, in the app's language

    enum CodingKeys: String, CodingKey {
        case host, now, read, checked, changed, note
        case pageTitle = "page_title"
    }

    init(pageTitle: String? = nil, host: String, now: String? = nil, read: Read, checked: String? = nil,
         changed: String? = nil, note: String? = nil) {
        self.pageTitle = pageTitle
        self.host = host
        self.now = now
        self.read = read
        self.checked = checked
        self.changed = changed
        self.note = note
    }

    /// Lenient: a missing host is empty (the card then names the address's host), a missing `read` is `waiting`.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        pageTitle = try c.decodeIfPresent(String.self, forKey: .pageTitle)
        host = try c.decodeIfPresent(String.self, forKey: .host) ?? ""
        now = try c.decodeIfPresent(String.self, forKey: .now)
        read = try c.decodeIfPresent(String.self, forKey: .read).map(Read.init(rawValue:)) ?? .waiting
        checked = try c.decodeIfPresent(String.self, forKey: .checked)
        changed = try c.decodeIfPresent(String.self, forKey: .changed)
        note = try c.decodeIfPresent(String.self, forKey: .note)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(pageTitle, forKey: .pageTitle)
        try c.encode(host, forKey: .host)
        try c.encode(now, forKey: .now)
        try c.encode(read.rawValue, forKey: .read)
        try c.encode(checked, forKey: .checked)
        try c.encode(changed, forKey: .changed)
        try c.encode(note, forKey: .note)
    }
}

/// `Listing.page`: what changed on a watched page (a watch's match): the lines that came and went, and what the page
/// says now.
struct PageChange: Codable, Equatable, Sendable {
    var added: [String]
    var removed: [String]
    var now: String?

    init(added: [String] = [], removed: [String] = [], now: String? = nil) {
        self.added = added
        self.removed = removed
        self.now = now
    }

    /// Lenient: a missing list is empty.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        added = try c.decodeIfPresent([String].self, forKey: .added) ?? []
        removed = try c.decodeIfPresent([String].self, forKey: .removed) ?? []
        now = try c.decodeIfPresent(String.self, forKey: .now)
    }
}

extension Source {
    /// A watch's matches come from `"page"` (their `source_name` is the page's host). It is a source for listings only:
    /// never a site of a kind, a portal of the overview or a switch in a form.
    static let page = Source("page")
}

/// A watched page's address as the user gives it.
enum WatchAddress {
    /// The host of an address as written there, lowercased: "www.ikea.com". An address typed without a scheme
    /// ("ikea.com/de") is read as https, as the server does. Nil when there is no host to read.
    static func host(_ address: String) -> String? {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let withScheme = trimmed.contains("://") ? trimmed : "https://" + trimmed
        guard let host = URLComponents(string: withScheme)?.host, !host.isEmpty else { return nil }
        return host.lowercased()
    }

    /// What the address field keeps of a text pasted into it. A whole shared text ("Look at this: https://… 49,99 €")
    /// keeps only its first web link; an address on its own, or typed, stays exactly as it is (a text without spaces is
    /// never touched, so typing "ikea.com" is not turned into "http://ikea.com"). A text with spaces and no link stays as
    /// it is too: the server says what it cannot watch.
    static func fromField(_ text: String) -> String {
        guard text.rangeOfCharacter(from: .whitespacesAndNewlines) != nil,
              let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        for match in detector.matches(in: text, range: range) {
            guard let scheme = match.url?.scheme?.lowercased(), scheme == "http" || scheme == "https",
                  let found = Range(match.range, in: text) else { continue }
            return String(text[found])
        }
        return text
    }
}
