import CoreFoundation
import Foundation

// The bridge between the 3D page (flatd's `GET /viewer`, phone mode) and the app, as the viewer's BRIDGE.md v1 defines
// it: the page posts messages to the handler `flat3d`; the app answers through `flat3d.receive(message)`. The page
// never talks to the network itself: the app is flatd's only client here. Pure parts, so the tests pin them.

enum PageLogLevel: String {
    case error, warn, info
}

/// A message from the page (`window.webkit.messageHandlers.flat3d.postMessage(…)`). Unknown types are ignored.
enum PageMessage: Equatable {
    /// The page can take state now (after every load): answer with `config` and a `snapshot`.
    case ready
    /// The user acted on a device: forward `body` unchanged to `POST /api/devices/{id}`, then one `result`.
    case request(reqId: String, id: String, body: Data)
    /// The user ended a mode in the model: `POST /api/modes/{id}` with `body`, then one `result`.
    case mode(reqId: String, id: String, body: Data)
    /// A tap the page would like felt: `light`, `medium`, `success`, `error`.
    case haptic(String)
    /// A diagnostic from the page, optionally with elapsed times in milliseconds.
    case log(level: PageLogLevel, text: String, timing: [String: Int])
    /// A request or mode change that names its `reqId` but nothing usable: answered with one failed result.
    case invalid(reqId: String)
    case other

    /// Reads WebKit's message body (a dictionary of Foundation objects).
    static func parse(_ body: Any) -> PageMessage? {
        guard let message = body as? [String: Any], let type = message["type"] as? String else { return nil }
        switch type {
        case "ready":
            return .ready
        case "request", "mode":
            guard let reqId = message["reqId"] as? String else { return nil }
            guard let id = message["id"] as? String, !id.isEmpty,
                  let payload = message["body"] as? [String: Any], JSONSerialization.isValidJSONObject(payload),
                  let body = try? JSONSerialization.data(withJSONObject: payload) else { return .invalid(reqId: reqId) }
            return type == "request" ? .request(reqId: reqId, id: id, body: body) : .mode(reqId: reqId, id: id, body: body)
        case "haptic":
            return .haptic(message["style"] as? String ?? "light")
        case "log":
            let level = (message["level"] as? String).flatMap(PageLogLevel.init(rawValue:)) ?? .error
            return .log(level: level, text: message["message"] as? String ?? "", timing: parseTiming(message))
        default:
            return .other
        }
    }

    private static func parseTiming(_ message: [String: Any]) -> [String: Int] {
        guard let values = message["timing"] as? [String: Any] else { return [:] }
        var timing: [String: Int] = [:]
        for name in values.keys.sorted() {
            guard !name.isEmpty, name.utf8.count <= 24,
                  name.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0)
                      || (97...122).contains($0) || $0 == 95 }),
                  let number = values[name] as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                  let ms = Int(exactly: number.doubleValue.rounded(.towardZero)) else { continue }
            timing[name] = ms
            if timing.count == 24 { break }
        }
        return timing
    }

    /// One line for the log: the steps in the order they happened (they are times since the page started; WebKit hands
    /// the object over without its key order), a tie by name.
    static func timingLine(_ timing: [String: Int]) -> String {
        timing.sorted { ($0.value, $0.key) < ($1.value, $1.key) }.map { "\($0.key) \($0.value)" }.joined(separator: ", ")
    }
}

/// What the app sends the page: JSON objects handed to `flat3d.receive`.
enum PageScript {
    /// `flat3d.receive(<json>)`, guarded so a page that is not ready yet ignores it.
    static func receive(_ json: Data) -> String {
        var text = String(decoding: json, as: UTF8.self)
        // JSON allows these two inside strings, older JavaScript did not.
        text = text.replacingOccurrences(of: "\u{2028}", with: "\\u2028").replacingOccurrences(of: "\u{2029}", with: "\\u2029")
        return "window.flat3d && flat3d.receive && flat3d.receive(\(text));"
    }

    /// One `result` per request: ok, or the bridge's error word and the app's line.
    static func result(reqId: String, error: FlatdError?, language: AppLanguage = .current) -> Data {
        var message: [String: Any] = ["type": "result", "reqId": reqId, "ok": error == nil]
        if let error {
            message["error"] = errorWord(error)
            message["message"] = error.message(language: language)
        }
        return (try? JSONSerialization.data(withJSONObject: message, options: [.sortedKeys])) ?? Data()
    }

    /// BRIDGE.md's words: `offline`, `timeout`, `unauthorized`, `unknown`, `refused` (400, or 409: `favourite` on a
    /// blind without one), `failed`.
    static func errorWord(_ error: FlatdError) -> String {
        switch error {
        case .unreachable, .awayNeedsUnlock: "offline"
        case .deviceDidNotAnswer, .noAnswer: "timeout"
        case .refused, .notPaired: "unauthorized"
        case .unknown: "unknown"
        case .notPossible, .anotherFlat: "refused"
        case let .failed(status, _) where status == 400: "refused"
        case .failed, .invalidAnswer, .pairingUnreadable, .renameNotSupported: "failed"
        }
    }

    /// `connected`, `connecting` or `offline`, from the store's link.
    static func connection(_ link: FlatStore.Link) -> Data {
        let status = switch link {
        case .live: "connected"
        case .connecting: "connecting"
        case .offline, .refused, .notSetUp: "offline"
        }
        return (try? JSONSerialization.data(withJSONObject: ["type": "connection", "status": status],
                                            options: [.sortedKeys])) ?? Data()
    }

    /// The app's look and language, the 3D flat's light (`real`: the sun where it really is now; `day`: always
    /// daylight, Settings → 3D flat), and how much of the page's bottom its tab bar covers.
    static func config(dark: Bool, language: AppLanguage, accent: String, alwaysDaylight: Bool,
                       bottomBar: Double) -> Data {
        let message: [String: Any] = [
            "type": "config",
            "theme": dark ? "dark" : "light",
            "language": language.code,
            "accent": accent,
            "lighting": alwaysDaylight ? "day" : "real",
            "insets": ["top": 0, "right": 0, "bottom": max(0, bottomBar.rounded()), "left": 0],
        ]
        return (try? JSONSerialization.data(withJSONObject: message, options: [.sortedKeys])) ?? Data()
    }

    /// Settings → 3D flat → Always daylight (owner, 2026-11-19) (the real time of day and season, "but with a setting
    /// toggle to always day"); off by default.
    static let alwaysDaylightKey = "arestia.alwaysDaylight"

    /// The accent as the page takes it ("#FF9A62": the bright one; the page deepens it on the light wall itself).
    static let accentHex = "#FF9A62"
}

/// Which document in the 3D tab's web view may speak to the app: only the page the app handed over, and only once
/// WebKit put *that* load in place. Each load is a new document (`begin`); its navigation, as `WKWebView.load` returned
/// it, is the one whose commit counts (`committed`), so a late commit of an earlier load (overlapping loads, round 4)
/// never lets the next document speak while the previous one is still shown. Kept apart from WebKit, so the tests pin
/// it with stand-in navigations.
struct PageHandover {
    /// Counts the documents loaded: a request's result goes only to the document that asked.
    private(set) var document = 0
    /// The load on its way: its document and the navigation WebKit gave for it (held, so its identity stays unique).
    private var arriving: (document: Int, navigation: AnyObject)?
    /// The document WebKit put in place, and its navigation; only it may speak.
    private var handedOver: Int?
    private var shown: AnyObject?

    /// A new page is fetched for the web view: from now on no document speaks until it is in place (the old one is no
    /// longer the one, the new one is not there yet). Returns the new document's count.
    mutating func begin() -> Int {
        document += 1
        arriving = nil
        handedOver = nil
        shown = nil
        return document
    }

    /// The web view started loading `document`'s page as `navigation`; false (nothing awaited) when it is not the newest
    /// document or WebKit did not start a load.
    mutating func loading(_ document: Int, as navigation: AnyObject?) -> Bool {
        guard document == self.document, let navigation else { return false }
        arriving = (document, navigation)
        return true
    }

    /// Whether this navigation is the load awaited now (its failures count; others are an earlier load's).
    func awaits(_ navigation: AnyObject?) -> Bool {
        guard let arriving, let navigation else { return false }
        return arriving.navigation === navigation && arriving.document == document
    }

    /// WebKit put a navigation in place: when it is the awaited load, its document may speak from now on.
    mutating func committed(_ navigation: AnyObject?) {
        guard awaits(navigation) else { return }
        handedOver = document
        shown = navigation
        arriving = nil
    }

    /// Whether a navigation's failure concerns the page of now (the load awaited, or the one in place), not an
    /// earlier load's.
    func concerns(_ navigation: AnyObject?) -> Bool {
        guard let navigation else { return false }
        return awaits(navigation) || (maySpeak && shown === navigation)
    }

    var maySpeak: Bool { handedOver == document }
}
