import Foundation
import Testing
import UIKit
import UniformTypeIdentifiers
@testable import Aresus

/// Brief 100: the words and rules behind the share sheet's screen, the picked row's remove badges and Add, and the
/// Aresync tab's drop hover.
@MainActor
struct ShareScreensTests {
    private func picked(_ name: String, source: DropSource) -> PickedFile {
        PickedFile(file: DropFile(content: .data(Data(name.utf8)), suggestedName: name, source: source,
                                  date: at("2026-11-01T18:03:04Z")), displayName: name)
    }

    private func draft() -> SendDraft {
        SendDraft(temporary: SendTemporaryFiles(base: FileManager.default.temporaryDirectory
            .appending(path: "ShareScreensTests-\(UUID().uuidString)")))
    }

    // MARK: the folder row

    @Test func theFolderRowSaysSortLaterAloneBeforeTheMacsListIsThere() {
        let english = DropPathText.place(nil, fallback: nil, language: .english)
        #expect(english.text == "Sort later" && english.quiet == nil)
        let german = DropPathText.place(nil, fallback: nil, language: .german)
        #expect(german.text == "Später sortieren" && german.quiet == nil)
        // Once the list is there, the Mac's fallback folder follows in quiet words.
        let listed = DropPathText.place(nil, fallback: "Zu sortieren", language: .german)
        #expect(listed.text == "Später sortieren" && listed.quiet == "Zu sortieren")
    }

    @Test func aFallbackFolderNamedLikeTheWordsIsNotSaidTwice() {
        #expect(DropPathText.place(nil, fallback: "Sort later", language: .english).quiet == nil)
        #expect(DropPathText.place(nil, fallback: " sort LATER ", language: .english).quiet == nil)
        #expect(DropPathText.place(nil, fallback: "Später sortieren", language: .german).quiet == nil)
        #expect(DropPathText.place(nil, fallback: "Spater sortieren", language: .german).quiet == nil)
        #expect(DropPathText.place(nil, fallback: "Sort later", language: .german).quiet == "Sort later")
        #expect(DropPathText.place(nil, fallback: "  ", language: .english).quiet == nil)
    }

    // MARK: removing and adding

    @Test func theAppRemovesEveryItemAndTheLastGoesBackToTheThreeChoices() {
        let draft = draft()
        #expect(!draft.canRemove(sharing: false), "nothing picked, nothing to remove")
        draft.use([picked("IMG_0412.HEIC", source: .photo), picked("IMG_0413.HEIC", source: .photo)],
                  source: .photo, last: nil)
        #expect(draft.canRemove(sharing: false) && draft.height == .large)
        draft.remove(draft.picked[0].id)
        #expect(draft.picked.map(\.displayName) == ["IMG_0413.HEIC"] && draft.canRemove(sharing: false))
        draft.show("A photo could not be loaded.")
        draft.remove(draft.picked[0].id)
        #expect(!draft.hasPicked && draft.height == .medium, "back to the three choices, at their height")
        #expect(draft.failure == nil, "no line left from the earlier pick under the three choices")
        #expect(!draft.canRemove(sharing: false))
    }

    @Test func theShareSheetKeepsItsLastItem() {
        let draft = SendDraft(files: [DropFile(content: .data(Data("a".utf8)), suggestedName: "Plan.pdf"),
                                      DropFile(content: .data(Data("b".utf8)), suggestedName: "Notes.txt")])
        #expect(draft.canRemove(sharing: true))
        draft.remove(draft.picked[0].id)
        #expect(draft.picked.count == 1 && !draft.canRemove(sharing: true), "its close button cancels instead")
        #expect(draft.canRemove(sharing: false))
    }

    @Test func aSecondPickAddsAndTheHeadingFollowsWhatIsPicked() {
        let draft = draft()
        draft.use([picked("IMG_0412.HEIC", source: .photo)], source: .photo, last: nil)
        #expect(SendPickText.heading(draft.picked.map(\.file.source), language: .english) == "Photo")
        draft.use([picked("IMG_0413.HEIC", source: .camera)], source: .camera, last: nil)
        #expect(SendPickText.heading(draft.picked.map(\.file.source), language: .english) == "Photos")
        draft.use([picked("Plan.pdf", source: .file)], source: .file, last: nil)
        #expect(draft.picked.count == 3)
        #expect(SendPickText.heading(draft.picked.map(\.file.source), language: .english) == "Files", "a photo is a file too")
        #expect(SendPickText.heading(draft.picked.map(\.file.source), language: .german) == "Dateien")
    }

    @Test func pickHeadingsInBothLanguages() {
        #expect(SendPickText.heading([.photo], language: .german) == "Foto")
        #expect(SendPickText.heading([.photo, .photo], language: .german) == "Fotos")
        #expect(SendPickText.heading([.file], language: .english) == "File")
        #expect(SendPickText.heading([.file], language: .german) == "Datei")
        #expect(SendPickText.heading([], language: .english) == "Files")
    }

    // MARK: the share sheet

    @Test func unreadableItemsAreOneQuietLineInBothLanguages() {
        #expect(SendPickText.unreadable(1, language: .english) == "1 item could not be read.")
        #expect(SendPickText.unreadable(2, language: .english) == "2 items could not be read.")
        #expect(SendPickText.unreadable(1, language: .german) == "1 Objekt konnte nicht gelesen werden.")
        #expect(SendPickText.unreadable(2, language: .german) == "2 Objekte konnten nicht gelesen werden.")
        #expect(SendPickText.preparing(language: .english) == "Preparing …")
        #expect(SendPickText.preparing(language: .german) == "Wird vorbereitet …")
    }

    @Test func theLoadingTilesFollowTheSharedTypes() {
        #expect(DropFileKind(types: [UTType.heic.identifier]) == .photo)
        #expect(DropFileKind(types: ["public.jpeg", "public.image"]) == .photo)
        #expect(DropFileKind(types: [UTType.quickTimeMovie.identifier]) == .video)
        #expect(DropFileKind(types: [UTType.pdf.identifier]) == .pdf)
        #expect(DropFileKind(types: [UTType.plainText.identifier]) == .other)
        #expect(DropFileKind(types: ["dyn.fictional-type"]) == .other)
        #expect(DropFileKind(types: []) == .other)
        #expect([DropFileKind.photo, .video].map(\.source) == [.photo, .photo])
        #expect([DropFileKind.pdf, .other].map(\.source) == [.file, .file])
    }

    // MARK: the drop hover

    @Test func theHoverSaysWhatLettingGoDoesAndWhatIsHeld() {
        #expect(DropHoverWords.title(language: .english) == "Let go to send to the MacBook")
        #expect(DropHoverWords.title(language: .german) == "Zum Senden ans MacBook loslassen")
        let one = ProviderFiles.Hover(count: 1, name: "Exercise sheet 3.pdf")
        #expect(DropHoverWords.line(one, language: .english) == "Exercise sheet 3.pdf")
        #expect(DropHoverWords.line(ProviderFiles.Hover(count: 3, name: nil), language: .english) == "3 files")
        #expect(DropHoverWords.line(ProviderFiles.Hover(count: 3, name: nil), language: .german) == "3 Dateien")
        #expect(DropHoverWords.line(ProviderFiles.Hover(count: 1, name: nil), language: .english) == "1 file")
        #expect(DropHoverWords.line(ProviderFiles.Hover(count: 1, name: nil), language: .german) == "1 Datei")
    }

    // MARK: the extension's look

    @Test func theExtensionReadsTheAppsAppearanceFromTheGroup() throws {
        let suite = "ShareScreensTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let look = ExtensionAppearance(defaults: defaults, app: "de.ares-empire.aresus")
        #expect(look.choice == .iPhone, "nothing published: like the iPhone")
        look.publish(.dark)
        #expect(look.choice == .dark && look.choice.interfaceStyle == .dark)
        let other = ExtensionAppearance(defaults: defaults, app: "de.ares-empire.arestemis")
        #expect(other.choice == .iPhone, "apps sharing a group keep their choices apart")
        look.publish(.light)
        #expect(look.choice.interfaceStyle == .light)
        look.publish(.iPhone)
        #expect(look.choice == .iPhone && look.choice.interfaceStyle == .unspecified)
        #expect(defaults.string(forKey: "appearance.de.ares-empire.aresus") == nil, "like the iPhone removes it")
        #expect(ExtensionAppearance(defaults: nil, app: "de.ares-empire.aresus").choice == .iPhone)
    }

    @Test func sharedPicturesKeepAPersonsNameButNotACamerasName() {
        for camera in ["IMG_1234.HEIC", "IMG_E1234.JPG", "img_1234", "PXL_20261102_123456789.jpg", "DSC01234.JPG",
                       "DSCN0042.jpg", "VID_20261102_101010.mp4", "FullSizeRender.jpg", "image.png", "Image 2.png",
                       "Foto (3).jpg", "4F2A9C1E-1B2C-4D5E-8F90-ABCDEF123456.jpeg", ".jpg", ""] {
            #expect(DropNames.isCameraName(camera), "\(camera) is a camera's or the system's name")
        }
        for chosen in ["Lake.jpg", "Receipt Bauhaus.png", "IMG of the flat.jpg", "Image of receipt.png", "Blatt 3.pdf",
                       "2026-11-02 Rechnung.jpg", "Photoshop export.png", "Imagine.png"] {
            #expect(!DropNames.isCameraName(chosen), "\(chosen) is a name a person chose")
        }
    }
}
