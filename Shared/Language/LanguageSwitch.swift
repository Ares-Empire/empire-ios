import Foundation

/// Switching the app to another language from Settings → Language: what to save, the language it brings, and the
/// confirmation's words.
///
/// The confirmation asks in the language it switches to ("Switch to English?", "Aresus restarts in English.",
/// "Restart"): whoever picks a language can read that one, also when they cannot read the one shown now. Its Cancel
/// stays in the current language, so a tap by mistake is undone in words the person has been reading (iOS's own
/// language change asks the same way).
nonisolated struct LanguageSwitch: Equatable, Sendable {
    /// What is saved: a language, or nil for "like the iPhone".
    let choice: AppLanguage?
    /// The language the app shows afterwards.
    let language: AppLanguage

    var title: String {
        switch language {
        case .english: language.string(LocalizedStringResource("Switch to English?", table: "Shared"))
        case .german: language.string(LocalizedStringResource("Switch to German?", table: "Shared"))
        }
    }

    func message(app: String) -> String {
        switch language {
        case .english: language.string(LocalizedStringResource("\(app) restarts in English.", table: "Shared"))
        case .german: language.string(LocalizedStringResource("\(app) restarts in German.", table: "Shared"))
        }
    }

    var confirm: String { language.string(LocalizedStringResource("Restart", table: "Shared")) }
}

/// What a tap on a row of Settings → Language does.
nonisolated enum LanguageTap: Equatable, Sendable {
    /// The row that is chosen already.
    case keep
    /// Another choice that shows the same language (e.g. "Deutsch" while following a German iPhone): saved, nothing
    /// to restart.
    case save(LanguageSwitch)
    /// Another language: asked first, then saved and the app restarts in it.
    case confirm(LanguageSwitch)

    /// - Parameters:
    ///   - option: the row tapped: a language, or nil for "like the iPhone".
    ///   - choice: the saved choice.
    ///   - shown: the language the app shows now.
    ///   - iPhone: the language "like the iPhone" means (read only when that row is tapped).
    static func tap(_ option: AppLanguage?, choice: AppLanguage?, shown: AppLanguage,
                    iPhone: () -> AppLanguage) -> LanguageTap {
        guard option != choice else { return .keep }
        let change = LanguageSwitch(choice: option, language: option ?? iPhone())
        return change.language == shown ? .save(change) : .confirm(change)
    }
}
