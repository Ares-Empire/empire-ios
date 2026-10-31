import Foundation
import Testing
@testable import Arestemis

/// Settings → Application (brief 61): the row under the switch follows it, each page edits its own text, and the rows
/// show the start of what is written, or that nothing is, in both languages.
@MainActor
struct ApplicationTextsTests {
    @Test func theRowFollowsTheSwitch() {
        #expect(ApplicationPage.written(for: .ai) == .notes)
        #expect(ApplicationPage.written(for: .own) == .ownText)
    }

    @Test func eachPageEditsItsOwnText() throws {
        var settings = try sample(Settings.self, "settings")
        settings[keyPath: ApplicationPage.ownText.field] = "Own"
        settings[keyPath: ApplicationPage.notes.field] = "Notes"
        settings[keyPath: ApplicationPage.aboutMe.field] = "About"
        #expect(settings.ownText == "Own" && settings.applicationNotes == "Notes" && settings.aboutMe == "About")
        #expect(settings.applicationMode == .ai)                          // the switch is not a page's
    }

    @Test func previewsAreOneLine() {
        #expect(ApplicationPage.preview("Hallo,\n\nmein Name ist Leon.\n") == "Hallo, mein Name ist Leon.")
        #expect(ApplicationPage.preview("  Abends   frei\t") == "Abends frei")
        #expect(ApplicationPage.preview("") == nil && ApplicationPage.preview(" \n\n ") == nil)
    }

    @Test func rowsSayWhatIsWritten() throws {
        var settings = try sample(Settings.self, "settings")
        #expect(ApplicationPage.ownText.summary(of: settings).hasPrefix("Hallo, mein Name ist Leon"))
        #expect(ApplicationPage.notes.summary(of: settings) == settings.applicationNotes)
        settings.ownText = ""
        settings.applicationNotes = "\n"
        settings.aboutMe = ""
        #expect(ApplicationPage.ownText.summary(of: settings) == "Not written yet")
        #expect(ApplicationPage.notes.summary(of: settings) == "None")
        #expect(ApplicationPage.aboutMe.summary(of: settings) == "Not written yet")
        #expect(ApplicationPage.ownText.summary(of: settings, language: .german) == "Noch nicht geschrieben")
        #expect(ApplicationPage.notes.summary(of: settings, language: .german) == "Keine")
    }

    @Test func germanWords() {
        #expect(ApplicationPage.allCases.map { $0.title(in: .german) } == ["Dein Text", "Hinweise", "Über dich"])
        #expect(ApplicationPage.allCases.map { $0.title(in: .english) } == ["Your text", "Notes", "About you"])
        for page in ApplicationPage.allCases {
            #expect(page.caption(in: .german) != page.caption(in: .english))
            #expect(!page.caption(in: .german).contains("KI"))
        }
        #expect(ApplicationPage.notes.placeholder(in: .german).hasPrefix("z. B."))
    }

    @Test func launchArgumentValues() {
        #expect(["ownText", "notes", "aboutMe"].compactMap(ApplicationPage.init(rawValue:)) == ApplicationPage.allCases)
    }
}
