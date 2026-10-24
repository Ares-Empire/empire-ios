import Foundation
import Testing
@testable import Empire

struct AppLanguageTests {
    @Test func picksGermanOnlyWhenTheBundleMatchesGerman() {
        #expect(AppLanguage.from(["de"]) == .german)
        #expect(AppLanguage.from(["de-DE", "en"]) == .german)
        #expect(AppLanguage.from(["en"]) == .english)
        #expect(AppLanguage.from(["en", "de"]) == .english)
        #expect(AppLanguage.from([]) == .english)
    }

    @Test func formatsInAFixedLocalePerLanguage() {
        #expect(AppLanguage.german.locale.identifier == "de_DE")
        #expect(AppLanguage.english.locale.identifier == "en_GB")
        #expect(1400.formatted(.currency(code: "EUR").precision(.fractionLength(0)).locale(AppLanguage.german.locale))
                == "1.400\u{a0}€")
    }

    @Test func everyRequestCarriesTheLanguageUnlessOneIsSet() {
        var request = URLRequest(url: URL(string: "https://www.ares-empire.de/api/empire")!)
        #expect(request.withLanguage(.german).value(forHTTPHeaderField: "Accept-Language") == "de")
        #expect(request.withLanguage(.english).value(forHTTPHeaderField: "Accept-Language") == "en")
        request.setValue("en", forHTTPHeaderField: "Accept-Language")
        #expect(request.withLanguage(.german).value(forHTTPHeaderField: "Accept-Language") == "en")
    }
}
