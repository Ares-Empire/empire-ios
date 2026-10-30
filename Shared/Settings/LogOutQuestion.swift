import Foundation
import Observation

/// Settings → Account → Log out (brief 41): the row only asks; the login ends with the question's Log out. One login
/// serves every Ares app on this iPhone, so the question says it ends in all of them; an app that works without an
/// account (Aresium, `EmpireAppIdentity.accountOptional`) keeps its data on this iPhone and says that too, as Leave
/// does. Shown as Apple's confirmation dialog, like the app's other questions before an account action (Leave, Delete
/// Ares account): Log out (destructive) and Cancel.
@MainActor @Observable
final class LogOutQuestion {
    /// The question is on screen.
    var isAsking = false

    /// The row: asks first.
    func ask() { isAsking = true }

    /// Cancel, or the question closed without an answer: nothing happens.
    func cancel() { isAsking = false }

    /// The question's Log out: only now does the app log out (`logOut`: the app's own log-out, which in sample mode
    /// leaves the sample as before).
    func confirm(_ logOut: () -> Void) {
        isAsking = false
        logOut()
    }

    nonisolated static func title(_ language: AppLanguage = .current) -> String {
        language.string(LocalizedStringResource("Log out?", table: "Shared"))
    }

    /// - Parameters:
    ///   - app: the app's name.
    ///   - keepsData: the app works without an account and keeps its data on this iPhone (Aresium).
    nonisolated static func message(app: String, keepsData: Bool, language: AppLanguage = .current) -> String {
        keepsData
            ? language.string(LocalizedStringResource("You'll be logged out of all Ares apps on this iPhone. Your data in \(app) stays.",
                                                      table: "Shared"))
            : language.string(LocalizedStringResource("You'll be logged out of all Ares apps on this iPhone.", table: "Shared"))
    }
}
