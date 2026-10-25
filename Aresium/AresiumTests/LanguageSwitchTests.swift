import Foundation
import Testing
@testable import Aresium

/// The app's texts follow Settings → Language while it runs (Shared/Language): asked in both languages.
struct LanguageSwitchTests {
    @Test(arguments: [AppLanguage.english, .german]) func modelTextsFollowTheLanguageShown(language: AppLanguage) {
        AppLanguage.$scoped.withValue(language) {
            let german = language == .german
            #expect(DashboardSide.expenses.title == (german ? "Ausgaben" : "Expenses"))
            #expect(Money.total(1400) == (german ? "1.400\u{a0}€" : "€1,400"))
        }
    }
}
