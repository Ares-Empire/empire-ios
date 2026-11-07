import Foundation
import Testing
import UniformTypeIdentifiers
@testable import Aresium

/// Brief 204: files dropped on the main screen. Which items a drop takes (the import's types by their own extensions,
/// so a Markdown file, a property list or a piece of text from a page is not taken), when the target is on, what the
/// copies are called, and that the copies are read the way a shared file is and removed (also those a launch left).
/// Made-up files only.
@MainActor
struct FileDropTests {
    private static func item(_ types: [String], _ name: String? = nil) -> FileDrop.Item { FileDrop.Item(types: types, name: name) }

    private static func folder() throws -> URL {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appending(path: "build/204-test-drops/\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: which items

    @Test func takesTheImportsFiles() {
        // As Files hands them over: the file's own type first.
        #expect(FileDrop.importType(of: Self.item(["public.comma-separated-values-text"], "Umsaetze")) == "public.comma-separated-values-text")
        #expect(FileDrop.importType(of: Self.item(["public.xml"], "camt053")) == "public.xml")
        #expect(FileDrop.importType(of: Self.item([UTType.mt940.identifier], "Kontoauszug")) == UTType.mt940.identifier)
        #expect(FileDrop.importType(of: Self.item(["public.plain-text"], "MT940 Auszug")) == "public.plain-text")
        #expect(FileDrop.importType(of: Self.item(["public.zip-archive"], "camt-Dateien")) == "public.zip-archive")
        // A `.sta` file where iOS made up a type from the extension (Aresium's declared type is not known there).
        let dynamic = UTType(tag: "mt940", tagClass: .filenameExtension, conformingTo: .data)!.identifier
        #expect(FileDrop.importType(of: Self.item([dynamic], "Auszug")) == dynamic)
        // The first type the import reads, after others the source lists first.
        #expect(FileDrop.importType(of: Self.item(["com.example.fictional", "public.comma-separated-values-text"])) ==
                "public.comma-separated-values-text")
        // Named as a bank file though its type says nothing: read as its own type.
        #expect(FileDrop.importType(of: Self.item(["public.data"], "Umsaetze.CSV")) == "public.data")
    }

    @Test func leavesOtherFilesOut() {
        for types in [["public.json"], ["com.adobe.pdf"], ["public.png"], ["net.daringfireball.markdown"],
                      ["com.apple.xml-property-list"], ["public.svg-image"], ["public.html"], ["public.url"],
                      ["public.utf8-plain-text"], ["public.data"], []] {
            #expect(FileDrop.importType(of: Self.item(types, "Fiktiv")) == nil, "\(types)")
        }
        // A piece of text dragged from a page or a note: plain text in memory, without a name.
        #expect(FileDrop.importType(of: Self.item(["public.utf8-plain-text", "public.text"])) == nil)
        #expect(FileDrop.importType(of: Self.item(["public.utf8-plain-text", "public.plain-text"])) == nil)
        #expect(FileDrop.importType(of: Self.item(["public.plain-text"], " ")) == nil)
        // An export of Aresium's: restoring stays in Settings.
        #expect(FileDrop.importType(of: Self.item(["public.json"], "Aresium-2026-11-02.json")) == nil)
        #expect(!FileDrop.accepts([Self.item(["public.json"], "Aresium-2026-11-02.json"), Self.item(["com.adobe.pdf"])]))
        #expect(!FileDrop.accepts([]))
    }

    @Test func aMixedDropTakesOnlyTheBankFiles() {
        let items = [Self.item(["public.comma-separated-values-text"], "Umsaetze"), Self.item(["com.adobe.pdf"], "Brief"),
                     Self.item(["public.xml"], "camt053")]
        #expect(FileDrop.accepts(items))
        #expect(FileDrop.taken(items).map(\.name) == ["Umsaetze", "camt053"])
    }

    @Test func whatHoveringSays() {
        let csv = "public.comma-separated-values-text"
        #expect(FileDrop.hover([Self.item(["public.json"], "Aresium-2026-11-02.json")]) == nil, "not allowed")
        #expect(FileDrop.hover([Self.item([csv], "Umsaetze_Girokonto")]) == FileDrop.Hover(count: 1, name: "Umsaetze_Girokonto"))
        #expect(FileDrop.hover([Self.item([csv])]) == FileDrop.Hover(count: 1, name: nil))
        #expect(FileDrop.hover([Self.item([csv], "Umsaetze"), Self.item(["com.adobe.pdf"], "Brief")]) ==
                FileDrop.Hover(count: 1, name: "Umsaetze"), "only what is taken")
        #expect(FileDrop.hover([Self.item([csv], "Umsaetze"), Self.item(["public.xml"], "camt053")]) ==
                FileDrop.Hover(count: 2, name: nil))
    }

    // MARK: when

    @Test func theTargetIsOnOnlyOnPhoneModesMainScreen() {
        #expect(FileDrop.targetOn(screen: .firstScreen, phoneMode: true, locked: false))
        #expect(FileDrop.targetOn(screen: .dashboard, phoneMode: true, locked: false))
        for screen: MainScreen in [.tour, .opening, .waitingForLogin] {
            #expect(!FileDrop.targetOn(screen: screen, phoneMode: true, locked: false), "\(screen)")
        }
        #expect(!FileDrop.targetOn(screen: .dashboard, phoneMode: false, locked: false), "server mode")
        #expect(!FileDrop.targetOn(screen: .dashboard, phoneMode: true, locked: true), "behind the lock")
    }

    // MARK: the copies

    @Test func theCopyKeepsTheFilesName() {
        // A source that suggests the name without its extension; the handed-over file has it.
        #expect(FileDrop.copyName(loaded: "Umsaetze_Girokonto.csv", suggested: "Umsaetze_Girokonto",
                                  type: "public.comma-separated-values-text") == "Umsaetze_Girokonto.csv")
        #expect(FileDrop.copyName(loaded: "x.xml", suggested: "camt053 Oktober.xml", type: "public.xml") == "camt053 Oktober.xml")
        // A name with dots but no extension the import reads gets the type's.
        #expect(FileDrop.copyName(loaded: "file", suggested: "Auszug 01.11.2026", type: UTType.mt940.identifier) ==
                "Auszug 01.11.2026.sta")
        #expect(FileDrop.copyName(loaded: nil, suggested: nil, type: "public.comma-separated-values-text") == "Dropped file.csv")
        #expect(FileDrop.copyName(loaded: "a.txt", suggested: "  ", type: "public.plain-text") == "a.txt")
        // Never a folder in the name.
        #expect(FileDrop.copyName(loaded: nil, suggested: "Konto/Oktober", type: "public.xml") == "Konto-Oktober.xml")
    }

    @Test func copiesAreReadAsSharedFilesAndRemoved() throws {
        let root = try Self.folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let container = root.appending(path: "app", directoryHint: .isDirectory)
        let original = root.appending(path: "Umsaetze.csv")
        try Data("fictional".utf8).write(to: original)
        let dropped = FileDrop.folder(container: container)
        // Two files of the same name never meet: each copy has a folder of its own.
        let first = try FileDrop.copy(original, name: "Umsaetze.csv", into: dropped)
        let second = try FileDrop.copy(original, name: "Umsaetze.csv", into: dropped)
        #expect(first != second && first.lastPathComponent == "Umsaetze.csv")
        let files = try ImportFileReader.read([first, second], source: .shared, extensions: ImportFileReader.phoneExtensions,
                                              container: container)
        #expect(files.map(\.name) == ["Umsaetze.csv", "Umsaetze.csv"] && files[0].data == Data("fictional".utf8))
        #expect((try? FileManager.default.contentsOfDirectory(atPath: dropped.path)) == [], "the copies and their folders")
        #expect(FileManager.default.fileExists(atPath: original.path), "the dropped original stays")
    }

    @Test func copiesALaunchLeftGoAtTheNext() throws {
        let root = try Self.folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let container = root.appending(path: "app", directoryHint: .isDirectory)
        let outside = root.appending(path: "outside.csv")
        try Data("fictional".utf8).write(to: outside)
        let dropped = FileDrop.folder(container: container)
        _ = try FileDrop.copy(outside, name: "held.csv", into: dropped)       // held behind the lock when the app ended
        // A link in the drops' folder pointing out of the app: the link goes, never what it points to.
        let linkFolder = dropped.appending(path: "link", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: linkFolder, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: linkFolder.appending(path: "link.csv"), withDestinationURL: outside)
        ImportFileReader.removeSharedCopy(dropped.appending(path: "../../../outside.csv"), container: container)
        #expect(FileManager.default.fileExists(atPath: outside.path), "outside the drops' folder: untouched")
        ImportFileReader.clearInbox(container: container)
        #expect((try? FileManager.default.contentsOfDirectory(atPath: dropped.path)) == [])
        #expect(FileManager.default.fileExists(atPath: outside.path))
    }

    @Test func providersAreCopiedOutAndOthersLeftAlone() async throws {
        let root = try Self.folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appending(path: "source", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let csv = source.appending(path: "Umsaetze_Fiktiv.csv")
        let json = source.appending(path: "Aresium-2026-11-02.json")
        try Data("IBAN Auftragskonto;Buchungstag\n".utf8).write(to: csv)
        try Data("{}".utf8).write(to: json)
        // As Files hands a file over: its name suggested; and one that suggests none.
        let named = try #require(NSItemProvider(contentsOf: csv))
        named.suggestedName = "Umsaetze_Fiktiv.csv"
        let unnamed = try #require(NSItemProvider(contentsOf: csv))
        let providers = [named, try #require(NSItemProvider(contentsOf: json)), unnamed,
                         NSItemProvider(object: "a piece of text" as NSString)]
        let into = root.appending(path: "Dropped", directoryHint: .isDirectory)
        let (copies, failed) = await withCheckedContinuation { continuation in
            FileDrop.copyTaken(providers, into: into) { copies, failed in continuation.resume(returning: (copies, failed)) }
        }
        #expect(failed == 0)
        #expect(copies.count == 2, "the export and the piece of text are left alone")
        #expect(copies.first?.lastPathComponent == "Umsaetze_Fiktiv.csv")
        // Without a name: the name the system gave its copy (a CSV's is "comma-separated values.csv"), still a .csv.
        #expect(copies.last?.pathExtension == "csv")
        #expect(try Data(contentsOf: copies[0]) == Data("IBAN Auftragskonto;Buchungstag\n".utf8))
        #expect(copies[0].path.hasPrefix(into.path + "/"))
    }

    /// End to end below the gesture: the copies of a drop go through the import as a shared file (the payments in, the
    /// category picker after it, the copies gone).
    @Test func aDropImportsLikeASharedFile() async throws {
        let session = await PhoneTest.session(nil, transport: RoutedTransport())
        let phone = try await PhoneTest.backend()
        let dashboard = DashboardStore(session: session, backend: phone)
        let imports = ImportStore(dashboard: dashboard, background: PhoneActivity(), bannerScheduler: ImportTestTimer().schedule)
        let root = try Self.folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = ImportThenCategoriesTests.bankFile
        let original = root.appending(path: "Umsaetze.csv")
        try file.data.write(to: original)
        // Into the app's own drops' folder (the test runs inside the app), as a drop copies it.
        let copy = try FileDrop.copy(original, name: "Umsaetze.csv")
        await imports.receive([copy], source: .shared)
        #expect(!FileManager.default.fileExists(atPath: copy.deletingLastPathComponent().path), "the copy went once read")
        await imports.importAndWait()
        #expect(phone.summary.payments == 4 && imports.asksForCategories)
        #expect(imports.banner?.message == "4 new · 0 already there · 0 sorted · 4 not sorted")
        #expect(FileManager.default.fileExists(atPath: original.path))
    }
}
