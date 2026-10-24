import Foundation
import UIKit

/// What a support message is about: the account server's `feedback.kind` (ares-empire/docs/ACCOUNTS.md → Contact &
/// support).
enum SupportKind: String, CaseIterable, Identifiable, Sendable {
    case problem, idea, question, other

    var id: String { rawValue }

    /// The picker's words.
    var title: String {
        switch self {
        case .problem: String(localized: "Problem", table: "Shared", comment: "Contact form: the kind of message")
        case .idea: String(localized: "Idea or wish", table: "Shared", comment: "Contact form: the kind of message")
        case .question: String(localized: "Question", table: "Shared", comment: "Contact form: the kind of message")
        case .other: String(localized: "Something else", table: "Shared", comment: "Contact form: the kind of message")
        }
    }

    var symbol: String {
        switch self {
        case .problem: "exclamationmark.bubble"
        case .idea: "lightbulb"
        case .question: "questionmark.bubble"
        case .other: "ellipsis.bubble"
        }
    }

    /// The text box's placeholder: a short prompt that fits the kind.
    var placeholder: String {
        switch self {
        case .problem: String(localized: "What happened, and what did you expect?", table: "Shared")
        case .idea: String(localized: "What would make the app better for you?", table: "Shared")
        case .question: String(localized: "What would you like to know?", table: "Shared")
        case .other: String(localized: "What is it about?", table: "Shared")
        }
    }
}

/// One message for "Contact & support", as the account server's `feedback` collection takes it
/// (`POST /api/collections/feedback/records`). Built only from a valid form: see `init`.
struct SupportMessage: Encodable, Equatable, Sendable {
    let user: String            // the account's id; the server accepts only the sender's own
    let app: String             // the app's service: empire, aresium, arestemis, aresus, arestoteles
    let kind: String
    let message: String
    let appVersion: String      // "1.0 (12)"
    let system: String          // "iOS 27.0 · iPhone"
    let language: String        // "en" or "de"

    enum CodingKeys: String, CodingKey {
        case user, app, kind, message, appVersion = "app_version", system, language
    }

    /// The server's limits. It counts characters as Unicode scalars, so an emoji may count as several.
    static let maxLength = 5000
    static let maxVersionLength = 40
    static let maxSystemLength = 80

    enum Invalid: Error, Equatable { case empty, tooLong, noAccount }

    /// The message as it is sent: without blank lines and spaces around it.
    static func trimmed(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// How long the message is for the server's limit.
    static func length(_ text: String) -> Int { trimmed(text).unicodeScalars.count }

    /// Whether a text can be sent as it is: something written, and not over the limit.
    static func isSendable(_ text: String) -> Bool { (1...maxLength).contains(length(text)) }

    /// - Parameters:
    ///   - token: the Empire login; the message names its account (`EmpireToken.accountID`), as the server requires.
    init(kind: SupportKind, text: String, token: String, app: EmpireAppIdentity, device: SupportDevice,
         language: AppLanguage = .current) throws(Invalid) {
        let message = Self.trimmed(text)
        guard !message.isEmpty else { throw .empty }
        guard message.unicodeScalars.count <= Self.maxLength else { throw .tooLong }
        guard let account = EmpireToken.accountID(token) else { throw .noAccount }
        user = account
        self.app = app.service
        self.kind = kind.rawValue
        self.message = message
        appVersion = String(device.appVersion.prefix(Self.maxVersionLength))
        system = String(device.system.prefix(Self.maxSystemLength))
        self.language = language.code
    }
}

/// What a support message says about the app and the phone, so a problem can be traced: nothing that identifies the
/// device ("iPhone", not the model).
struct SupportDevice: Equatable, Sendable {
    let appVersion: String
    let system: String

    static var current: SupportDevice {
        SupportDevice(appVersion: appVersion(Bundle.main.infoDictionary),
                      system: system(name: UIDevice.current.systemName,
                                     version: ProcessInfo.processInfo.operatingSystemVersion,
                                     model: UIDevice.current.model))
    }

    /// "1.0 (12)": the marketing version and the build number.
    static func appVersion(_ info: [String: Any]?) -> String {
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        guard let build = info?["CFBundleVersion"] as? String, !build.isEmpty else { return version }
        return "\(version) (\(build))"
    }

    /// "iOS 27.0 · iPhone", or "iOS 27.0.1 · iPhone" with a bug-fix version.
    static func system(name: String, version: OperatingSystemVersion, model: String) -> String {
        var number = "\(version.majorVersion).\(version.minorVersion)"
        if version.patchVersion > 0 { number += ".\(version.patchVersion)" }
        return "\(name) \(number) · \(model)"
    }
}
