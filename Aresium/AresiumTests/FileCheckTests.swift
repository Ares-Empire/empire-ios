import Foundation
import Testing
@testable import Aresium

/// An unknown bank's file (brief 23): the engine's readings one after the other ("Does this look right?"), Yes saves the
/// shown reading and imports, No shows the next with what changed, after the last one the column check; Cancel leaves
/// the file out. Made-up files only.
@MainActor
struct FileCheckTests {
    /// A card statement in a made-up bank's style: dates that read either way, purchases as positive amounts, the shop in
    /// "Beschreibung". The engine offers four readings: its guess, day and month swapped, the amounts the other way
    /// round, name and text swapped.
    static let cardFile = ImportFile(name: "Fiktivkarte.csv", data: Data("""
        Datum;Beschreibung;Details;Betrag
        03/04/2026;FIKTIV MARKT BERLIN;Kartenzahlung girocard;12,00
        05/04/2026;FIKTIV CAFE;Kartenzahlung girocard;3,50
        07/04/2026;FIKTIV KINO;Kartenzahlung girocard;9,00

        """.utf8))

    /// A phone backend, an import store on it, and the window's model for `file` after its first import.
    private func check(_ file: ImportFile) async throws -> (PhoneBackend, ImportStore, FileCheckModel) {
        let transport = RoutedTransport()
        let session = await PhoneTest.session(nil, transport: transport)
        let phone = try await PhoneTest.backend(chosen: ["groceries", "eating-out"])
        let imports = ImportStore(dashboard: DashboardStore(session: session, backend: phone), background: PhoneActivity())
        imports.debugImport([file])
        await imports.importAndWait()
        let request = try #require(imports.layoutRequest)
        return (phone, imports, FileCheckModel(request: request, phone: phone, imports: imports))
    }

    // MARK: the readings

    @Test func theEnginesReadingsComeWithTheRequest() async throws {
        let (phone, _, model) = try await check(Self.cardFile)
        #expect(model.readings.map(\.reason) == [nil, .dateFormat, .invertSign, .counterpartyText])
        #expect(model.step == .reading(0) && model.number == 1 && model.change == nil)
        #expect(model.payments.count == FileCheckModel.shownPayments)
        #expect(model.payments.map(\.day) == ["2026-04-03", "2026-04-05", "2026-04-07"])
        #expect(phone.summary.payments == 0 && phone.summary.layouts == 0)      // nothing saved before an answer
    }

    @Test func yesOnTheFirstReadingSavesItAndImports() async throws {
        let (phone, imports, model) = try await check(Self.cardFile)
        #expect(await model.yes())
        #expect(imports.layoutRequest == nil)
        #expect(try await phone.ledger.layouts() == [model.readings[0].layout])
        await imports.importAndWait()
        let payments = try await phone.ledger.payments()
        #expect(payments.count == 3 && Set(payments.map(\.bookingDate)).contains("2026-04-03"))
    }

    @Test func noShowsTheNextReadingAndSaysWhatChanged() async throws {
        let (phone, imports, model) = try await check(Self.cardFile)
        model.no()
        #expect(model.step == .reading(1) && model.number == 2)
        #expect(model.change == "Day and month swapped")
        #expect(model.payments.map(\.day) == ["2026-03-04", "2026-05-04", "2026-07-04"])
        model.no()
        #expect(model.change == "Money in and out swapped")
        #expect(model.payments.map(\.amount) == ["-12.00", "-3.50", "-9.00"])

        // Yes on the third: that reading is the one saved, and the file reads with it.
        #expect(await model.yes())
        #expect(try await phone.ledger.layouts() == [model.readings[2].layout])
        await imports.importAndWait()
        #expect(Set(try await phone.ledger.payments().map(\.amount)) == ["-12.00", "-3.50", "-9.00"])
    }

    @Test func noAfterTheLastReadingOpensTheColumnCheck() async throws {
        let (phone, imports, model) = try await check(Self.cardFile)
        for _ in model.readings { model.no() }
        #expect(model.step == .columns && model.reading == nil && model.change == nil)
        let columns = try #require(model.columns)
        // The column check starts from the engine's guess and can import it.
        #expect(columns.canConfirm)
        #expect(columns.chosen(.date)?.name == "Datum" && columns.chosen(.amount)?.name == "Betrag")
        model.no()                                                       // nothing further
        #expect(model.step == .columns)

        // Cancel leaves the file out.
        model.cancel()
        #expect(imports.layoutRequest == nil && imports.waitingCount == 0)
        #expect(phone.summary.payments == 0 && phone.summary.layouts == 0)
    }

    @Test func withoutReadingsTheColumnCheckComesAtOnce() async throws {
        let (phone, imports, model) = try await check(Self.cardFile)
        let bare = LayoutRequest(file: model.request.file, guess: model.request.guess, readings: [])
        let direct = FileCheckModel(request: bare, phone: phone, imports: imports)
        #expect(direct.step == .columns && direct.columns != nil && direct.number == nil)
    }

    @Test func theColumnCheckAsksPlainQuestions() async throws {
        let (_, _, model) = try await check(try PhoneTest.fixture("unknown-fiktivbank.csv"))
        for _ in model.readings { model.no() }
        let columns = try #require(model.columns)
        // The guess reads money out and money in from two columns.
        #expect(columns.draft.amountInTwoColumns)
        #expect(columns.chosen(.debit)?.name == "Lastschrift" && columns.chosen(.credit)?.name == "Gutschrift")
        #expect(columns.choices.first?.label == "Buchungsdatum · 07.02.2026")

        // One amount column instead, then two again: the amount column becomes money out.
        columns.choose(.amount, column: 4)
        #expect(!columns.draft.amountInTwoColumns && columns.draft.missing.isEmpty)
        columns.useTwoAmountColumns()
        #expect(columns.draft.amountInTwoColumns && columns.chosen(.debit)?.index == 4)
        #expect(columns.draft.missing == [.amount])                    // money in still to answer
        columns.choose(.credit, column: 5)
        #expect(columns.canConfirm)

        // Name and text: one column each, or none.
        columns.choose(.counterparty, column: nil)
        #expect(columns.chosen(.counterparty) == nil && columns.canConfirm)
        columns.choose(.text, column: 2)
        #expect(columns.draft.columns(of: .text) == [2])
        // The date is required: without it nothing can be imported.
        columns.choose(.date, column: nil)
        #expect(!columns.canConfirm && columns.draft.missing == [.date])
    }

    // MARK: words

    @Test func theSentencesPerReason() {
        let english: [ReadingReason: String] = [
            .dateFormat: "Day and month swapped", .debitCredit: "Money in and out swapped",
            .invertSign: "Money in and out swapped", .counterpartyText: "Name and payment text swapped",
            .sign: "Money in and out read another way", .amount: "Other amounts", .counterparty: "Other names",
            .valueDate: "The file's other date",
        ]
        let german: [ReadingReason: String] = [
            .dateFormat: "Tag und Monat getauscht", .debitCredit: "Einnahmen und Ausgaben getauscht",
            .invertSign: "Einnahmen und Ausgaben getauscht", .counterpartyText: "Name und Verwendungszweck getauscht",
            .sign: "Einnahmen und Ausgaben anders gelesen", .amount: "Andere Beträge", .counterparty: "Andere Namen",
            .valueDate: "Das andere Datum der Datei",
        ]
        for reason in ReadingReason.allCases where reason != .other {
            #expect(FileCheckWording.change(reason, language: .english) == english[reason], "\(reason)")
            #expect(FileCheckWording.change(reason, language: .german) == german[reason], "\(reason)")
        }
        #expect(FileCheckWording.change(.other, language: .german) == nil)
        #expect(FileCheckWording.change(nil, language: .english) == nil)
    }

    @Test func aReasonFromANewerEngineDoesNotBreakTheAnswer() throws {
        let json = #"[{"reason":"somethingNew","layout":{"version":1,"separator":";","header":["Datum","Betrag"],"dateFormat":"DD.MM.YYYY","numberFormat":"de","columns":{"date":0,"amount":1}},"preview":[]},{"reason":null,"layout":{"version":1,"separator":";","header":["Datum","Betrag"],"dateFormat":"DD.MM.YYYY","numberFormat":"de","columns":{"date":0,"amount":1}},"preview":[]}]"#
        let readings = try JSONDecoder().decode([FileReading].self, from: Data(json.utf8))
        #expect(readings.map(\.reason) == [.other, nil])
    }
}
