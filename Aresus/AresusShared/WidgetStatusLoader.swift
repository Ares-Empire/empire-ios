import Foundation
import SwiftUI
import WidgetKit

/// What the widget shows.
nonisolated enum WidgetContent: Equatable, Sendable {
    case status(WidgetStatus)
    /// No Empire login on this phone, or the server refused it (401/403): "Open Aresus to log in".
    case loggedOut
    /// Logged in, but nothing saved yet and the server out of reach.
    case notLoaded
}

/// How the widget gets its status (its timeline provider calls `load`). The widget never logs in or renews the login;
/// it only reads the token the Empire apps share.
/// 1. No login → logged out (and the saved status of the last login is deleted).
/// 2. A status the app saved a moment ago → shown as it is (the app reloads the widget after each overview).
/// 3. Otherwise `GET /overview` → shown and saved. A 401/403 → logged out.
/// 4. Offline, server down, the Keychain locked → the saved status with its `checked` time, whose age tells it is old.
struct WidgetStatusLoader {
    /// A saved status this young is used without asking the server: the server checks once a minute, so a fetch would
    /// bring nothing newer.
    static let freshFor: TimeInterval = 120

    var readToken: () throws -> String?
    var fetch: (String) async throws -> Overview
    var store: WidgetStatusStore

    /// The real one: the shared Keychain, the Aresus API and the App Group file.
    static func live() -> WidgetStatusLoader {
        let keychain = TokenKeychain()
        let api = AresusAPI()
        return WidgetStatusLoader(readToken: { try keychain.read() }, fetch: { try await api.overview(token: $0) },
                                  store: .appGroup)
    }

    /// `fetching: false` answers from what is saved (the widget gallery's quick snapshot).
    func load(now: Date = .now, fetching: Bool = true) async -> WidgetContent {
        let token: String?
        do {
            token = try readToken()
        } catch {
            // The token is readable only while the phone is unlocked: show what was saved.
            return saved()
        }
        guard let token else {
            try? store.delete()
            return .loggedOut
        }
        let saved = store.read().status
        if let saved, !fetching || (0..<Self.freshFor).contains(now.timeIntervalSince(saved.checked)) {
            return .status(saved)
        }
        guard fetching else { return .notLoaded }
        do {
            let status = WidgetStatus(overview: try await fetch(token))
            try? store.save(status)
            return .status(status)
        } catch HTTPError.unauthorized {
            try? store.delete()
            return .loggedOut
        } catch HTTPError.server(403, _) {
            try? store.delete()
            return .loggedOut
        } catch {
            return saved.map(WidgetContent.status) ?? .notLoaded
        }
    }

    private func saved() -> WidgetContent {
        store.read().status.map(WidgetContent.status) ?? .notLoaded
    }
}

/// One moment of the widget.
nonisolated struct StatusEntry: TimelineEntry, Sendable {
    let date: Date
    let content: WidgetContent
}

/// The widget's timeline: the entry now, and for a status still fresh a second one at the moment it turns stale (in
/// case no refresh comes before). A new timeline is asked for after 15 minutes; iOS decides when it really comes.
nonisolated enum StatusTimeline {
    static let refresh: TimeInterval = 15 * 60

    static func entries(_ content: WidgetContent, now: Date) -> [StatusEntry] {
        var entries = [StatusEntry(date: now, content: content)]
        if case .status(let status) = content, !status.isStale(at: now) {
            entries.append(StatusEntry(date: status.staleAt, content: content))
        }
        return entries
    }

    static func timeline(_ content: WidgetContent, now: Date) -> Timeline<StatusEntry> {
        Timeline(entries: entries(content, now: now), policy: .after(now.addingTimeInterval(refresh)))
    }
}

/// "checked 4 minutes ago": the system's live relative time, so the widget's age keeps counting between refreshes
/// (a widget cannot run its own clock). One unit, from minutes up; under half a minute it reads "now".
nonisolated enum WidgetAge {
    static var locale: Locale { AppLanguage.current.locale }

    static func style(since checked: Date) -> SystemFormatStyle.DateReference {
        SystemFormatStyle.DateReference(to: checked, allowedFields: [.minute, .hour, .day], maxFieldCount: 1)
            .locale(locale)
    }

    /// The text the live view shows at `now`.
    static func text(since checked: Date, now: Date) -> String {
        String(localized: "checked \(String(style(since: checked).format(now).characters))", table: "AresusShared",
               bundle: .appLanguage, locale: .appLanguage)
    }
}
