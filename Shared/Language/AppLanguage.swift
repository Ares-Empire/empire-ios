import Foundation
import Synchronization

/// The language an Empire app shows: English or German (ares-empire/docs/LANGUAGES.md). iOS picks it from the phone's
/// languages, or from the app's own setting (Settings → Apps → the app → Language); English for every other language.
/// The app's servers learn it from `Accept-Language` on every request, the push service from the device registration.
///
/// Settings → Language can switch it while the app runs (`LanguageRoot`). iOS keeps the language it started the app
/// in for its own lookups (`Bundle.main`, `Locale.current`), so every text of the apps asks this type instead:
/// - SwiftUI texts (`Text("…")`, `Button("…")`, `Text("…", tableName: "Shared")`, plurals) take the root's
///   `.environment(\.locale, language.locale)`;
/// - `String(localized: "…")` is this module's own (below);
/// - `String(localized: "…", table: …)` and calls with a comment pass `bundle: .appLanguage, locale: .appLanguage`
///   (`scripts/strings.py check` finds any that do not);
/// - formatting uses `AppLanguage.current.locale`, model code `language.string("…")`.
nonisolated enum AppLanguage: String, Sendable {
    case english = "en", german = "de"

    /// The language the app shows now: the one iOS started it in, until Settings → Language switches it (`show(_:)`).
    static var current: AppLanguage { scoped ?? shown.withLock { $0 } }

    /// The language iOS started this process in: the bundle's best match for the user's languages.
    static let launched = from(Bundle.main.preferredLocalizations)

    /// From now on the app's texts, formats and requests use this language. Called by `LanguageRoot`, which then
    /// builds every view again so nothing keeps a text of the old language, and by a widget following its app.
    static func show(_ language: AppLanguage) { shown.withLock { $0 = language } }

    /// Tests: the language `current` gives inside `AppLanguage.$scoped.withValue(.german) { … }`, for that code only
    /// (tests run side by side; `show` would change it for all of them). The apps never set it.
    @TaskLocal static var scoped: AppLanguage?

    private static let shown = Mutex(launched)

    static func from(_ localizations: [String]) -> AppLanguage {
        localizations.first.map { $0.hasPrefix("de") ? .german : .english } ?? .english
    }

    /// The locale numbers, money and dates are formatted in: "€1,400 · Sat 24 Oct" or "1.400 € · Sa. 24. Okt."
    /// Fixed per language (not the phone's region), so a text reads the same everywhere in the app.
    var locale: Locale { Locale(identifier: self == .german ? "de_DE" : "en_GB") }

    /// The request header's value: exactly "en" or "de".
    var code: String { rawValue }

    /// The running target's strings in this language: its `de.lproj` or `en.lproj` folder (the English one holds only
    /// the plural rules; a key missing there is its own English text). The main bundle if the folder is missing.
    var bundle: Bundle { Self.bundles[self] ?? .main }

    private static let bundles: [AppLanguage: Bundle] = {
        var bundles: [AppLanguage: Bundle] = [:]
        for language in [english, german] {
            if let path = Bundle.main.path(forResource: language.code, ofType: "lproj") {
                bundles[language] = Bundle(path: path)
            }
        }
        return bundles
    }()
}

extension String {
    /// `String(localized: "…")` in the language the app shows now (`AppLanguage.current`), numbers in its locale.
    /// Declared in the apps' own module with only the key, so every plain `String(localized: "…")` calls this one
    /// instead of Foundation's, which keeps the language iOS started the app in. Xcode still finds the key (it reads
    /// the `String.LocalizationValue`), but not a table or comment: those calls use Foundation's with
    /// `bundle: .appLanguage, locale: .appLanguage`.
    nonisolated init(localized key: String.LocalizationValue) {
        let language = AppLanguage.current
        self.init(localized: key, table: nil, bundle: language.bundle, locale: language.locale)
    }
}

extension Bundle {
    /// The strings of the language the app shows now: `String(localized: "…", table: "Shared", bundle: .appLanguage,
    /// locale: .appLanguage)`.
    nonisolated static var appLanguage: Bundle { AppLanguage.current.bundle }
}

extension Locale {
    /// The locale of the language the app shows now (`AppLanguage.current.locale`).
    nonisolated static var appLanguage: Locale { AppLanguage.current.locale }
}

extension URLRequest {
    /// The request with the app's language, unless the caller already chose one.
    nonisolated func withLanguage(_ language: AppLanguage = .current) -> URLRequest {
        guard value(forHTTPHeaderField: "Accept-Language") == nil else { return self }
        var request = self
        request.setValue(language.code, forHTTPHeaderField: "Accept-Language")
        return request
    }
}

extension AppLanguage {
    /// A string from the app's String Catalog in this language. Code that builds text outside SwiftUI takes the language
    /// as a parameter (default `.current`) and looks its words up here, so tests can ask for either language. A table:
    /// `language.string(LocalizedStringResource("…", table: "Shared"))`.
    nonisolated func string(_ key: LocalizedStringResource) -> String {
        var key = key
        key.locale = locale
        return String(localized: key)
    }
}
