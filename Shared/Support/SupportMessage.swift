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
        case .problem: String(localized: LocalizedStringResource("Problem", table: "Shared", locale: .appLanguage,
                                                                 comment: "Contact form: the kind of message"))
        case .idea: String(localized: LocalizedStringResource("Idea or wish", table: "Shared", locale: .appLanguage,
                                                              comment: "Contact form: the kind of message"))
        case .question: String(localized: LocalizedStringResource("Question", table: "Shared", locale: .appLanguage,
                                                                  comment: "Contact form: the kind of message"))
        case .other: String(localized: LocalizedStringResource("Something else", table: "Shared", locale: .appLanguage,
                                                               comment: "Contact form: the kind of message"))
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
        case .problem: String(localized: LocalizedStringResource("What happened, and what did you expect?",
                                                                 table: "Shared",
                                                                 locale: .appLanguage))
        case .idea: String(localized: LocalizedStringResource("What would make the app better for you?",
                                                              table: "Shared",
                                                              locale: .appLanguage))
        case .question: String(localized: LocalizedStringResource("What would you like to know?", table: "Shared",
                                                                  locale: .appLanguage))
        case .other: String(localized: LocalizedStringResource("What is it about?", table: "Shared",
                                                               locale: .appLanguage))
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

/// One message for "Contact & support" without a login: the second path, only for an app that works without an account
/// (Aresium; every other app always has a login and sends a `SupportMessage`). As the account server's open `contact`
/// collection takes it (`POST /api/collections/contact/records`, which the website's contact form uses too;
/// ares-empire accounts/pb_migrations/1793200000_contact.js, mailed to Patrik by pb_hooks/contact.pb.js): an email to
/// answer to, an optional name, the message with a short footer naming the app, the phone and the topic (the collection
/// has no fields for them), the language, and the honeypot `website`, always empty (any text in it is refused).
struct ContactMessage: Encodable, Equatable, Sendable {
    let name: String
    let email: String
    let message: String
    let language: String
    let website: String

    /// The server's limits: the whole message (with the footer) at most 5,000 characters, the name at most 100.
    static let maxLength = SupportMessage.maxLength
    static let maxNameLength = 100

    enum Invalid: Error, Equatable { case empty, tooLong, email }

    /// - Parameters:
    ///   - text: what the person wrote; the footer is added below it.
    ///   - email: where Patrik answers; it must look like an email address.
    ///   - name: optional; cut to the server's limit.
    init(kind: SupportKind, text: String, email: String, name: String, app: EmpireAppIdentity, device: SupportDevice,
         language: AppLanguage = .current) throws(Invalid) {
        let written = SupportMessage.trimmed(text)
        guard !written.isEmpty else { throw .empty }
        let footer = Self.footer(kind: kind, app: app, device: device)
        guard written.unicodeScalars.count <= Self.maxTextLength(footer: footer) else { throw .tooLong }
        let email = AccountInput.trimmedEmail(email)
        guard AccountInput.looksLikeEmail(email) else { throw .email }
        self.name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.maxNameLength))
        self.email = email
        message = written + "\n\n" + footer
        self.language = language.code
        website = ""
    }

    /// "— Aresium 1.0 (12) · iOS 27.0 · iPhone · Problem": the app, its version, the phone and the topic, in English (for
    /// Patrik, like the `feedback` emails' words).
    static func footer(kind: SupportKind, app: EmpireAppIdentity, device: SupportDevice) -> String {
        "— \(app.name) \(device.appVersion) · \(device.system) · \(kind.englishName)"
    }

    /// How long the written text may be, so that it and the footer stay within the server's limit.
    static func maxTextLength(footer: String) -> Int { maxLength - 2 - footer.unicodeScalars.count }
}

extension SupportKind {
    /// The topic as the `feedback` emails name it (accounts/pb_hooks/feedback.pb.js), for the contact message's footer.
    var englishName: String {
        switch self {
        case .problem: "Problem"
        case .idea: "Idea"
        case .question: "Question"
        case .other: "Other"
        }
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
