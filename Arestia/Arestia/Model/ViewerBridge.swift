import Foundation

// The bridge between the 3D page (flatd's `GET /viewer`, phone mode) and the app, as the viewer's BRIDGE.md v1 defines
// it: the page posts messages to the handler `flat3d`; the app answers through `flat3d.receive(message)`. The page
// never talks to the network itself: the app is flatd's only client here. Pure parts, so the tests pin them.

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
    /// An uncaught error in the page.
    case log(String)
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
            return .log(message["message"] as? String ?? "")
        default:
            return .other
        }
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
        case .unreachable: "offline"
        case .deviceDidNotAnswer, .noAnswer: "timeout"
        case .refused: "unauthorized"
        case .unknown: "unknown"
        case .notPossible: "refused"
        case let .failed(status, _) where status == 400: "refused"
        case .failed, .invalidAnswer: "failed"
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

    /// Settings → 3D flat → Always daylight (Patrik, 2026-11-19: the real time of day and season, "but with a setting
    /// toggle to always day"); off by default.
    static let alwaysDaylightKey = "arestia.alwaysDaylight"

    /// The accent as the page takes it ("#FF9A62": the bright one; the page deepens it on the light wall itself).
    static let accentHex = "#FF9A62"
}
