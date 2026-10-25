import Foundation
import Testing
import UserNotifications
@testable import Arestemis

/// The app's texts follow Settings → Language while it runs (Shared/Language): asked in both languages.
struct LanguageSwitchTests {
    @Test(arguments: [AppLanguage.english, .german]) func modelTextsFollowTheLanguageShown(language: AppLanguage) {
        AppLanguage.$scoped.withValue(language) {
            let german = language == .german
            #expect(MatchFilter.saved.title == (german ? "Gespeichert" : "Saved"))
            // The notification actions' titles, set again when the app restarts in the other language.
            #expect(MatchNotification.categories.first?.actions.first?.title
                    == (german ? "Angebot öffnen" : "Open listing"))
            #expect(Format.money(1400) == (german ? "1.400\u{a0}€" : "€1,400"))
        }
    }
}
