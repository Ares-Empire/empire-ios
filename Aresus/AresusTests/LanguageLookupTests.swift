import Foundation
import SwiftUI
import Testing
@testable import Aresus

/// Every way the app looks up a text follows the language it shows while it runs (Shared/Language/AppLanguage.swift),
/// not only the one iOS started it in. Each test asks in both languages through `AppLanguage.$scoped`; the suite runs
/// in English (the scheme), and again in German to switch the other way:
/// `xcodebuild test … -only-testing:AresusTests/LanguageLookupTests -testLanguage de -testRegion DE`.
@MainActor
struct LanguageLookupTests {
    /// What each path gives in English and German.
    struct Expected {
        let english: String
        let german: String
        func callAsFunction(_ language: AppLanguage) -> String { language == .german ? german : english }
    }

    /// The language this test process was started in, and the other one (the switch a test proves).
    static let other: AppLanguage = AppLanguage.launched == .german ? .english : .german

    @Test(arguments: [AppLanguage.english, .german]) func theAppsOwnStringLocalized(language: AppLanguage) {
        AppLanguage.$scoped.withValue(language) {
            #expect(AppLanguage.current == language)
            #expect(String(localized: "Machines") == Expected(english: "Machines", german: "Geräte")(language))
            #expect(String(localized: "\(1) quiet runs")
                    == Expected(english: "1 quiet run", german: "1 ruhiger Lauf")(language))
            #expect(String(localized: "\(3) quiet runs")
                    == Expected(english: "3 quiet runs", german: "3 ruhige Läufe")(language))
            // Numbers in the text take the language's locale, not the one the app started with.
            #expect(String(localized: "\(1400) quiet runs")
                    == Expected(english: "1,400 quiet runs", german: "1.400 ruhige Läufe")(language))
        }
    }

    @Test(arguments: [AppLanguage.english, .german])
    func tablesThroughAResourceInTheAppLanguage(language: AppLanguage) {
        AppLanguage.$scoped.withValue(language) {
            let allRunning = LocalizedStringResource("All running", table: "AresusShared", locale: .appLanguage)
            #expect(String(localized: allRunning) == Expected(english: "All running", german: "Alles läuft")(language))
            let general = LocalizedStringResource("General", table: "Shared", locale: .appLanguage)
            #expect(String(localized: general) == Expected(english: "General", german: "Allgemein")(language))
            let more = LocalizedStringResource("and \(1400) more", table: "AresusShared", locale: .appLanguage)
            #expect(String(localized: more)
                    == Expected(english: "and 1,400 more", german: "und 1.400 weitere")(language))
        }
    }

    @Test(arguments: [AppLanguage.english, .german]) func modelCodeOnTheseLookups(language: AppLanguage) {
        AppLanguage.$scoped.withValue(language) {
            // A plural from a table, in code the widget shares.
            #expect(WidgetStatus.summary(issues: 1) == Expected(english: "1 issue", german: "1 Problem")(language))
            #expect(WidgetStatus.summary(issues: 3) == Expected(english: "3 issues", german: "3 Probleme")(language))
            #expect(WidgetStatus.summary(issues: 0)
                    == Expected(english: "All running", german: "Alles läuft")(language))
            // A date formatted in `AppLanguage.current.locale` (the default argument).
            #expect(AresusFormat.day(at("2026-10-24T12:00:00Z"), calendar: berlin)
                    == Expected(english: "Sat 24 Oct", german: "Sa. 24. Okt.")(language))
            #expect(language.string("Machines") == Expected(english: "Machines", german: "Geräte")(language))
            // Requests carry it to the servers.
            let request = URLRequest(url: URL(string: "https://www.ares-empire.de/api/aresus/overview")!).withLanguage()
            #expect(request.value(forHTTPHeaderField: "Accept-Language") == language.code)
        }
    }

    /// Why a table or comment lookup names a `LocalizedStringResource` in the app's language (`strings.py check` looks
    /// for it): Foundation's own call keeps the language the process was started in.
    @Test func foundationsTableLookupKeepsTheStartLanguage() {
        AppLanguage.$scoped.withValue(Self.other) {
            #expect(String(localized: "All running", table: "AresusShared")
                    == Expected(english: "All running", german: "Alles läuft")(AppLanguage.launched))
        }
    }

    @Test(arguments: [AppLanguage.english, .german]) func swiftUITextsTakeTheRootsLocale(language: AppLanguage) {
        func rendered(_ text: Text) -> Data? {
            let renderer = ImageRenderer(content: text.font(.system(size: 14)).foregroundStyle(.black)
                .environment(\.locale, language.locale)                   // what LanguageRoot sets
                .frame(width: 320, height: 24, alignment: .leading).background(Color.white))
            renderer.scale = 1
            return renderer.uiImage?.pngData()
        }
        #expect(rendered(Text("Machines"))
                == rendered(Text(verbatim: Expected(english: "Machines", german: "Geräte")(language))))
        #expect(rendered(Text("All running", tableName: "AresusShared"))
                == rendered(Text(verbatim: Expected(english: "All running", german: "Alles läuft")(language))))
        #expect(rendered(Text("\(3) quiet runs"))
                == rendered(Text(verbatim: Expected(english: "3 quiet runs", german: "3 ruhige Läufe")(language))))
        #expect(rendered(Text("\(1) quiet runs"))
                == rendered(Text(verbatim: Expected(english: "1 quiet run", german: "1 ruhiger Lauf")(language))))
        // The comparison tells the languages apart.
        #expect(rendered(Text(verbatim: "Machines")) != rendered(Text(verbatim: "Geräte")))
    }
}
