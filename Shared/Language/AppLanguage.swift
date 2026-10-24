import Foundation

/// The language an Empire app shows: English or German (ares-empire/docs/LANGUAGES.md). iOS picks it from the phone's
/// languages, or from the app's own setting (Settings → Apps → the app → Language); English for every other language.
/// The app's servers learn it from `Accept-Language` on every request, the push service from the device registration.
nonisolated enum AppLanguage: String, Sendable {
    case english = "en", german = "de"

    /// The language of the app's strings right now (the bundle's best match for the user's languages).
    static var current: AppLanguage { from(Bundle.main.preferredLocalizations) }

    static func from(_ localizations: [String]) -> AppLanguage {
        localizations.first.map { $0.hasPrefix("de") ? .german : .english } ?? .english
    }

    /// The locale numbers, money and dates are formatted in: "€1,400 · Sat 24 Oct" or "1.400 € · Sa. 24. Okt."
    /// Fixed per language (not the phone's region), so a text reads the same everywhere in the app.
    var locale: Locale { Locale(identifier: self == .german ? "de_DE" : "en_GB") }

    /// The request header's value: exactly "en" or "de".
    var code: String { rawValue }
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
    /// as a parameter (default `.current`) and looks its words up here, so tests can ask for either language.
    nonisolated func string(_ key: LocalizedStringResource) -> String {
        var key = key
        key.locale = locale
        return String(localized: key)
    }
}
