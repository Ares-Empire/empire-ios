import Foundation
import Testing
@testable import Aresium

/// Brief 27 (Patrik, 2026-10-27: the file first): Import data opens the file picker at once; the category picker opens
/// when an import in phone mode ended and added payments while no category is chosen, whatever brought the files in
/// (the file picker, the share sheet, the file check window), once per import. Not after a cancelled picker, a failed
/// file, a file whose payments were all there already, a restore, the tour, or with categories chosen. Ticking sorts the
/// waiting payments at once, and the result line is counted again when the picker closes. Made-up files only.
@MainActor
struct ImportThenCategoriesTests {
    /// 2 groceries (REWE), 1 rent (the landlord), 1 that fits no category.
    static let bankFile = PhoneTest.vrBank([
        ("01.10.2026", "REWE Markt GmbH", "REWE SAGT DANKE", -2345),
        ("02.10.2026", "Fiktiv Hausverwaltung", "Miete Oktober", -78000),
        ("03.10.2026", "Fiktiv Laden", "Einkauf", -500),
        ("08.10.2026", "REWE Markt GmbH", "REWE SAGT DANKE", -1210),
    ])

    private struct Setup {
        let phone: PhoneBackend
        let dashboard: DashboardStore
        let imports: ImportStore
        let timer: ImportTestTimer
    }

    /// The person's phone store (these categories chosen), its dashboard and imports, nobody logged in.
    private func setup(chosen: [String] = []) async throws -> Setup {
        let session = await PhoneTest.session(nil, transport: RoutedTransport())
        let phone = try await PhoneTest.backend(chosen: chosen)
        let dashboard = DashboardStore(session: session, backend: phone)
        let timer = ImportTestTimer()
        return Setup(phone: phone, dashboard: dashboard,
                     imports: ImportStore(dashboard: dashboard, background: PhoneActivity(), bannerScheduler: timer.schedule),
                     timer: timer)
    }

    /// Files written to a folder of the worktree's build folder, as the file picker hands them over.
    private func urls(_ files: [ImportFile]) throws -> [URL] {
        let directory = PhoneTest.storage().root
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return try files.map { file in
            let url = directory.appending(path: file.name)
            try file.data.write(to: url)
            return url
        }
    }

    /// The files as the file picker gives them, imported to the end.
    private func pick(_ files: [ImportFile], into s: Setup, source: ImportFileSource = .picker) async throws {
        await s.imports.receive(try urls(files), source: source)
        await s.imports.importAndWait()
    }

    private func sortedInStore(_ phone: PhoneBackend) async throws -> Int {
        try await phone.ledger.payments().filter { $0.category != nil }.count
    }

    // MARK: Import data: the file first

    @Test func importDataOpensTheFilePickerFirst() async throws {
        // Nothing stands between Import data and the file picker: no category is chosen and nothing asks for one before
        // a file is in. A cancelled file picker hands over no file, so nothing asks either.
        let s = try await setup()
        #expect(!s.phone.hasChosenCategories && !s.imports.asksForCategories)
        await s.imports.receive([])
        await s.imports.importAndWait()
        #expect(!s.imports.asksForCategories && s.phone.summary.payments == 0)
        // The server sorts by itself: its imports never ask.
        #expect(!ServerBackend().waitsForCategories)
    }

    // MARK: when the picker opens

    @Test func thePickerOpensAfterAnImportThatAddedPayments() async throws {
        let s = try await setup()
        try await pick([Self.bankFile], into: s)
        #expect(s.phone.summary.payments == 4 && s.phone.summary.unsorted == 4)
        #expect(s.imports.asksForCategories)
        #expect(s.dashboard.dashboard?.transactions.count == 4, "the payments are in before the picker shows")
        #expect(s.imports.banner?.message == "4 new · 0 already there · 0 sorted · 4 not sorted")
        s.timer.advance(by: .seconds(100))
        #expect(s.imports.banner != nil, "the category picker cancelled dismissal")
    }

    @Test func aFileSharedIntoAresiumOpensItToo() async throws {
        let s = try await setup()
        try await pick([Self.bankFile], into: s, source: .shared)
        #expect(s.phone.summary.payments == 4 && s.imports.asksForCategories)
    }

    @Test func aFileConfirmedInTheFileCheckOpensIt() async throws {
        let s = try await setup()
        try await pick([PhoneTest.fixture("unknown-fiktivbank.csv")], into: s)
        let request = try #require(s.imports.layoutRequest)
        #expect(!s.imports.asksForCategories, "nothing is in while the file check asks")
        #expect(await FileCheckModel(request: request, phone: s.phone, imports: s.imports).yes())
        await s.imports.importAndWait()
        #expect(s.phone.summary.payments == 4 && s.imports.asksForCategories)
    }

    @Test func onceForSeveralFilesAfterTheLast() async throws {
        let s = try await setup()
        // Two files picked together: the bank's, and an unknown bank's the file check asks about.
        try await pick([Self.bankFile, PhoneTest.fixture("unknown-fiktivbank.csv")], into: s)
        #expect(s.phone.summary.payments == 4 && s.imports.layoutRequest != nil)
        #expect(!s.imports.asksForCategories, "the import is not over while a file waits for the file check")

        let request = try #require(s.imports.layoutRequest)
        #expect(await FileCheckModel(request: request, phone: s.phone, imports: s.imports).yes())
        await s.imports.importAndWait()
        #expect(s.phone.summary.payments == 8 && s.imports.asksForCategories)

        s.imports.categoriesClosed()
        await s.imports.importAndWait()                    // nothing left: it does not ask a second time
        #expect(!s.imports.asksForCategories)
    }

    @Test func aSkippedFileCheckEndsTheImport() async throws {
        let s = try await setup()
        try await pick([Self.bankFile, PhoneTest.fixture("unknown-fiktivbank.csv")], into: s)
        let request = try #require(s.imports.layoutRequest)
        FileCheckModel(request: request, phone: s.phone, imports: s.imports).cancel()
        #expect(s.phone.summary.payments == 4 && s.imports.asksForCategories)
    }

    // MARK: when it does not open

    @Test func notWithCategoriesChosen() async throws {
        let s = try await setup(chosen: ["groceries"])
        try await pick([Self.bankFile], into: s)
        #expect(s.phone.summary.payments == 4 && !s.imports.asksForCategories)
    }

    @Test func notAfterAFailedFile() async throws {
        let s = try await setup()
        let zip = ImportFile(name: "Sparkasse.zip", data: Data([0x50, 0x4B, 0x03, 0x04, 1, 2, 3]))
        try await pick([zip], into: s)
        #expect(s.imports.banner?.success == false && s.phone.summary.payments == 0)
        #expect(!s.imports.asksForCategories)
    }

    @Test func notWhenAllPaymentsWereThereAlready() async throws {
        let s = try await setup()
        try await pick([Self.bankFile], into: s)
        s.imports.categoriesClosed()                            // closed with nothing ticked
        try await pick([Self.bankFile], into: s)
        #expect(s.imports.banner?.message.hasPrefix("0 new · 4 already there") == true)
        #expect(!s.imports.asksForCategories)
    }

    @Test func closedWithNothingTickedTheNextImportAsksAgain() async throws {
        let s = try await setup()
        try await pick([Self.bankFile], into: s)
        await s.imports.categoriesClosed()?.value
        #expect(!s.imports.asksForCategories && s.phone.summary.unsorted == 4, "the payments stay Not sorted")
        try await pick([PhoneTest.vrBank([("09.10.2026", "Fiktiv Kiosk", "Zeitung", -250)], name: "more.csv")], into: s)
        #expect(s.imports.asksForCategories)
    }

    @Test func notAfterARestore() async throws {
        // An export with payments and no category chosen, restored into the empty store: no import, no picker.
        let source = try await PhoneTest.backend()
        _ = try await source.importFiles([Self.bankFile], auth: BackendAuth(token: nil))
        let export = try await urls([ImportFile(name: "Aresium-2026-10-27.json", data: try await source.export().encoded())])[0]

        let session = await PhoneTest.session(nil, transport: RoutedTransport())
        let dashboard = DashboardStore(session: session, backend: nil)
        let modes = ModeStore(session: session, dashboard: dashboard, client: APIClient(transport: RoutedTransport()),
                              defaults: PhoneTest.defaults(), markerDefaults: PhoneTest.defaults(),
                              storage: PhoneTest.storage(), makeEngine: { try PhoneTest.engine() })
        await modes.start()
        let imports = ImportStore(dashboard: dashboard, background: PhoneActivity(), bannerScheduler: ImportTestTimer().schedule)
        await PhoneDataModel(modes: modes).restore(from: export)
        let phone = try #require(modes.phone)
        #expect(phone.summary.payments == 4 && !phone.hasChosenCategories)
        #expect(!imports.asksForCategories)
    }

    @Test func notInTheTour() async throws {
        let parent = PhoneTest.storage().root
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let now = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 27, hour: 12))!
        let world = try await TourWorld.make(in: parent, now: now, makeEngine: { try PhoneTest.engine() })
        defer { world.delete() }
        #expect(world.phone.summary.payments > 100 && !world.imports.asksForCategories)
    }

    // MARK: ticking, and the result line after the picker

    @Test func tickingAfterTheImportSortsTheWaitingPayments() async throws {
        let s = try await setup()
        try await pick([Self.bankFile], into: s)
        #expect(s.imports.asksForCategories)
        let picker = CategoryPickerModel(phone: s.phone) { await s.dashboard.reloadAfterTransactionChange() }
        await picker.load()

        await picker.toggle("groceries")
        #expect(await picker.flush())
        #expect(s.phone.summary.unsorted == 2, "both REWE payments went to Groceries at once")
        #expect(s.dashboard.dashboard?.transactions.filter { $0.categoryName == "Groceries" }.count == 2)
        await picker.toggle("rent")
        #expect(await picker.flush())
        #expect(s.phone.summary.unsorted == 1)
        #expect(try await s.phone.ledger.payments().map(\.category) == ["groceries", "rent", nil, "groceries"])
    }

    @Test func theResultLineIsCountedAgainWhenThePickerCloses() async throws {
        let s = try await setup()
        try await pick([Self.bankFile], into: s)
        let shown = try #require(s.imports.banner)
        #expect(shown.message == "4 new · 0 already there · 0 sorted · 4 not sorted")
        #expect(shown.files == ["vr.csv: 4 new · 0 already there"])

        let picker = CategoryPickerModel(phone: s.phone) { await s.dashboard.reloadAfterTransactionChange() }
        await picker.load()
        await picker.toggle("groceries")
        #expect(await picker.flush())
        await s.imports.categoriesClosed()?.value

        // The same result, its numbers as the store holds them now.
        let line = try #require(s.imports.banner)
        #expect(line.id == shown.id && !s.imports.asksForCategories)
        #expect(line.message == "4 new · 0 already there · 2 sorted · 2 not sorted")
        #expect(try await sortedInStore(s.phone) == 2)
        #expect(line.files == ["vr.csv: 4 new · 0 already there"], "the files' lines claim no sorting")
    }

    @Test func theLineOfTheLastFileIsCountedAgain() async throws {
        // Two files, one confirmed in the file check: the line showing is the confirmed file's import, and that is what
        // is counted again (its own payments, not the other file's).
        let s = try await setup()
        try await pick([Self.bankFile, PhoneTest.fixture("unknown-fiktivbank.csv")], into: s)
        let request = try #require(s.imports.layoutRequest)
        #expect(await FileCheckModel(request: request, phone: s.phone, imports: s.imports).yes())
        await s.imports.importAndWait()
        let before = try #require(s.imports.banner?.message)
        #expect(before.hasPrefix("4 new · 0 already there · "))

        let picker = CategoryPickerModel(phone: s.phone) {}
        await picker.load()
        await picker.toggle("groceries")
        #expect(await picker.flush())
        await s.imports.categoriesClosed()?.value
        let results = try #require(s.imports.banner?.results)
        let files = PhoneTest.phoneResults(results)
        #expect(files.map(\.name) == ["unknown-fiktivbank.csv"])
        let sorted = Set(try await s.phone.ledger.payments().filter { $0.category != nil }.map(\.id))
        let file = try #require(files.first)
        #expect(file.sorted == file.newIDs.filter(sorted.contains).count && file.sorted + file.waiting == 4)
        #expect(s.imports.banner?.message == "4 new · 0 already there · \(file.sorted) sorted · \(file.waiting) not sorted")
    }
}
