import Foundation
import Testing
@testable import Aresium

/// Sending an unknown bank's format (brief 23): offered only for a confirmed unknown layout that `shareableLayout`
/// accepts, the request's body, the outbox (offline, retries, a final 400, a 429 that waits for the next start; shared
/// with the bank requests since brief 25, `BankRequestTests`), "not now" never asking again, a name that looks like
/// personal data kept on the phone, and "What is sent?". A fake transport answers; nothing reaches the real account
/// server.
@MainActor
struct BankFormatTests {
    private let none = BackendAuth(token: nil)
    static let route = "POST /api/collections/bank_formats/records"

    /// A layout as the engine shares it (made up).
    static let layout = CsvLayout(separator: ";", header: ["Buchungsdatum", "Gegenseite", "Text", "Betrag", "Saldo"],
                                  dateFormat: "DD.MM.YYYY", numberFormat: "de",
                                  columns: .init(date: 0, amount: 3, counterparty: [1], text: [2], balance: 4))
    static let format = BankFormat(layout: layout, key: BankFormat.key(of: layout))

    /// An outbox on a file of its own, a fake transport, and a clock the test moves.
    private final class Clock { var now = Date(timeIntervalSince1970: 1_800_000_000) }
    private func outbox(file: URL? = nil, transport: RoutedTransport, clock: Clock = Clock()) -> BankOutbox {
        BankOutbox(file: file ?? PhoneTest.storage().bankOutboxURL,
                   api: BankOutboxAPI(transport: transport), appVersion: "1.0 (7)", now: { clock.now })
    }

    private func card(_ outbox: BankOutbox, bank: String = "Fiktivbank eG") throws -> BankFormatCard {
        let card = try #require(outbox.card(for: [Self.format]))
        card.bank = bank
        return card
    }

    // MARK: when the card is offered

    @Test func onlyAConfirmedUnknownLayoutThatMayBeSharedIsOffered() async throws {
        let phone = try await PhoneTest.backend(chosen: ["groceries"])
        // A known bank: nothing to learn.
        let known = PhoneTest.phoneResults(try await phone.importFiles([PhoneTest.vrBank([
            ("01.10.2026", "REWE Markt GmbH", "REWE SAGT DANKE", -2345)])], auth: none))
        #expect(known.first?.format == nil)
        // An unknown bank before its layout is confirmed: the question first, nothing to send.
        let file = try PhoneTest.fixture("unknown-fiktivbank.csv")
        let first = PhoneTest.phoneResults(try await phone.importFiles([file], auth: none))
        #expect(first.first?.format == nil && first.first?.readings.count == 2)

        // Confirmed (the engine's first reading): the file reads, and its format may go out.
        let reading = try #require(first.first?.readings.first)
        try await phone.saveLayout(reading.layout)
        let second = PhoneTest.phoneResults(try await phone.importFiles([file], auth: none))
        let format = try #require(second.first?.format)
        #expect(format.key == BankFormat.key(of: reading.layout) && format.suggestion == nil)
        #expect(format.layout.name == nil && format.layout.profile == nil)
        #expect(format.layout.header == reading.layout.header && format.layout.columns == reading.layout.columns)
    }

    @Test func aLayoutThatLooksPersonalIsNeverOffered() async throws {
        let phone = try await PhoneTest.backend(chosen: ["groceries"])
        // A header cell with an account number: `shareableLayout` says no ("digits"), so the result offers nothing.
        let file = ImportFile(name: "Fiktiv.csv", data: Data("""
            Datum;Empfänger;Verwendungszweck;Betrag;Konto 12345678
            02.02.2026;Fiktiv Markt;Einkauf;-12,00;x
            03.02.2026;Fiktiv Werke GmbH;Gehalt;1.200,00;x

            """.utf8))
        let first = PhoneTest.phoneResults(try await phone.importFiles([file], auth: none))
        try await phone.saveLayout(try #require(first.first?.readings.first?.layout))
        let second = PhoneTest.phoneResults(try await phone.importFiles([file], auth: none))
        #expect(second.first?.added == 2 && second.first?.format == nil)
    }

    @Test func theResultShowsTheCardAfterAConfirmedFileOnly() async throws {
        let transport = RoutedTransport()
        let session = await PhoneTest.session(nil, transport: transport)
        let phone = try await PhoneTest.backend(chosen: ["groceries"])
        let formats = outbox(transport: transport)
        let imports = ImportStore(dashboard: DashboardStore(session: session, backend: phone), background: PhoneActivity(),
                                  outbox: formats, bannerScheduler: ImportTestTimer().schedule)
        imports.debugImport([PhoneTest.vrBank([("01.10.2026", "REWE Markt GmbH", "REWE SAGT DANKE", -2345)])])
        await imports.importAndWait()
        #expect(imports.banner?.share == nil)

        imports.debugImport([try PhoneTest.fixture("unknown-fiktivbank.csv")])
        await imports.importAndWait()
        let check = FileCheckModel(request: try #require(imports.layoutRequest), phone: phone, imports: imports)
        #expect(await check.yes())
        await imports.importAndWait()
        let card = try #require(imports.banner?.share)
        #expect(card.shown == .asking && !card.canSend)              // nothing typed yet
        #expect(transport.requests.isEmpty)                           // nothing goes out without Send

        // Closing the result is "not now": the next file of that bank is not asked about again.
        imports.close()
        #expect(imports.banner == nil && formats.hasAsked(card.format.key))
        imports.debugImport([ImportFile(name: "again.csv", data: try PhoneTest.fixture("unknown-fiktivbank.csv").data)])
        await imports.importAndWait()
        #expect(imports.banner != nil && imports.banner?.share == nil)
        #expect(transport.requests.isEmpty)
    }

    @Test func notNowNeverAsksAgainForThatLayout() throws {
        let transport = RoutedTransport()
        let file = PhoneTest.storage().bankOutboxURL
        let first = outbox(file: file, transport: transport)
        try card(first).notNow()
        #expect(first.card(for: [Self.format]) == nil)
        // Not after the next start either; another bank's layout is still asked about.
        let next = outbox(file: file, transport: transport)
        #expect(next.card(for: [Self.format]) == nil)
        var other = Self.layout
        other.header = ["Datum", "Name", "Zweck", "Betrag", "Stand"]
        #expect(next.card(for: [Self.format, BankFormat(layout: other, key: BankFormat.key(of: other))])?.format.layout == other)
        // The file keeps only a hash of which layout was asked, never its column names.
        let saved = try String(contentsOf: file, encoding: .utf8)
        #expect(!saved.contains("Buchungsdatum") && saved.contains(Self.format.key))
        #expect(transport.requests.isEmpty)
    }

    // MARK: the request

    @Test func theRequestCarriesOnlyTheFormatTheNameTheVersionAndTheLanguage() throws {
        let submission = try BankFormatSubmission(format: Self.format, bank: "  Fiktiv\nBank   eG ",
                                                  appVersion: "1.0 (7)\u{0}<x@y>", language: .german)
        #expect(submission.bank == "Fiktiv Bank eG" && submission.appVersion == "1.0 (7)xy" && submission.language == "de")
        let request = try BankOutboxAPI().request(.format(submission))
        #expect(request.url?.absoluteString == "https://auth.ares-empire.de/api/collections/bank_formats/records")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.value(forHTTPHeaderField: "Accept-Language") == "de")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)

        let data = try #require(request.httpBody)
        let body = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(body.keys) == ["bank", "layout", "app_version", "language"])
        #expect(body["bank"] as? String == "Fiktiv Bank eG" && body["app_version"] as? String == "1.0 (7)xy")
        let layout = try #require(body["layout"] as? [String: Any])
        #expect(Set(layout.keys) == ["version", "separator", "header", "dateFormat", "numberFormat", "columns"])
        #expect(layout["header"] as? [String] == Self.layout.header)
        let columns = try #require(layout["columns"] as? [String: Any])
        #expect(Set(columns.keys) == ["date", "amount", "counterparty", "text", "balance"])
    }

    @Test func theBanksNameIsOneLineOfAtMost100Characters() throws {
        #expect(throws: BankSubmission.Invalid.noBank) {
            _ = try BankFormatSubmission(format: Self.format, bank: " \n ", appVersion: "1", language: .english)
        }
        let long = try BankFormatSubmission(format: Self.format, bank: String(repeating: "Bank ", count: 40),
                                            appVersion: String(repeating: "9", count: 60), language: .english)
        #expect(long.bank.count <= 100 && !long.bank.hasSuffix(" ") && long.appVersion.count == 40)
    }

    // MARK: sending and the outbox

    @Test func sentAtOnceSaysThankYou() async throws {
        let transport = RoutedTransport()
        transport.answer(Self.route, 200, ["id": "fictional1"])
        let formats = outbox(transport: transport)
        let card = try card(formats)
        var answered = false
        card.onAnswered = { answered = true }
        await card.send()
        #expect(card.shown == .sent && answered && formats.waiting.isEmpty)
        #expect(transport.requests(to: Self.route).count == 1)
        #expect(formats.hasAsked(Self.format.key))
    }

    @Test func offlineItIsKeptAndSentByItselfLater() async throws {
        let transport = RoutedTransport()
        transport.offline = true
        let clock = Clock()
        let file = PhoneTest.storage().bankOutboxURL
        let formats = outbox(file: file, transport: transport, clock: clock)
        let card = try card(formats)
        await card.send()
        #expect(card.shown == .kept)
        // Kept on the phone: only the request's body (the format, the name, the version, the language) and the tries.
        let waiting = try #require(formats.waiting.first)
        #expect(formats.waiting.count == 1 && waiting.tries == 0)
        #expect(waiting.submission == .format(try BankFormatSubmission(format: Self.format, bank: "Fiktivbank eG",
                                                                       appVersion: "1.0 (7)", language: .english)))

        // Still offline at the next foreground: nothing lost, no try counted.
        clock.now += 120
        await formats.sendWaiting()
        #expect(formats.waiting.first?.tries == 0)

        // Online at the next start: sent; the card, still on screen, says thank you.
        transport.offline = false
        transport.answer(Self.route, 200, ["id": "fictional2"])
        clock.now += 120
        await formats.sendWaiting()
        #expect(formats.waiting.isEmpty && card.shown == .sent)
        // The file keeps only which layout was asked.
        let saved = try String(contentsOf: file, encoding: .utf8)
        #expect(saved.contains("\"waiting\":[]") && !saved.contains("Fiktivbank"))
    }

    @Test func aServerErrorIsTriedAtMostThreeTimes() async throws {
        let transport = RoutedTransport()
        transport.answer(Self.route, 500, ["message": "Something went wrong."])
        let clock = Clock()
        let formats = outbox(transport: transport, clock: clock)
        try await card(formats).send()
        #expect(formats.waiting.first?.tries == 1)
        // The start and the first foreground come together: one round covers both.
        await formats.sendWaiting()
        await formats.sendWaiting()
        #expect(formats.waiting.first?.tries == 2)
        clock.now += 120
        await formats.sendWaiting()
        #expect(formats.waiting.isEmpty)                               // the third try failed too: dropped
        clock.now += 120
        await formats.sendWaiting()
        #expect(transport.requests(to: Self.route).count == 3)
    }

    @Test func a400IsFinalAndShowsTheServersSentence() async throws {
        let transport = RoutedTransport()
        let sentence = "Das Format enthält etwas, das wie persönliche Daten aussieht."
        transport.answer(Self.route, 400, ["status": 400, "message": sentence,
                                           "data": ["layout": ["code": "personal_data", "message": "looks personal"]]])
        let formats = outbox(transport: transport)
        let card = try card(formats)
        var answered = false
        card.onAnswered = { answered = true }
        await card.send()
        #expect(card.shown == .refused(sentence) && formats.waiting.isEmpty)
        #expect(!answered)                                             // the sentence stays until the person closes it
        await formats.sendWaiting()
        #expect(transport.requests(to: Self.route).count == 1)
    }

    @Test func aRefusedNameCanBeTypedAgain() async throws {
        let transport = RoutedTransport()
        let sentence = "The bank's name looks like personal data (an IBAN, an email address, a date, an amount or a long number). Type only the bank's name."
        transport.answer(Self.route, 400, ["status": 400, "message": sentence,
                                           "data": ["bank": ["code": "personal_data", "message": "looks personal"]]])
        transport.answer(Self.route, 200, ["id": "fictional4"])
        let formats = outbox(transport: transport)
        let card = try card(formats, bank: "Fiktivbank Nord")
        await card.send()
        // Nothing kept, nothing sent again by itself; the card asks for the name again with the server's sentence.
        #expect(card.shown == .asking && card.problem == sentence && formats.waiting.isEmpty)
        card.bank = "Fiktivbank"
        #expect(card.problem == nil && card.canSend)
        await card.send()
        #expect(card.shown == .sent && transport.requests(to: Self.route).count == 2)
    }

    /// The app's own check comes first (the engine's rule): a name with an account number never leaves the phone.
    @Test func aNameThatLooksPersonalIsNotSent() async throws {
        let transport = RoutedTransport()
        transport.answer(Self.route, 200, ["id": "fictional5"])
        let formats = outbox(transport: transport)
        let card = try card(formats, bank: "Fiktivbank 1234567")
        await card.send()
        #expect(card.shown == .asking && card.problem == BankSubmission.personalLine())
        #expect(transport.requests.isEmpty && formats.waiting.isEmpty && !formats.hasAsked(Self.format.key))
        card.bank = "Fiktivbank"
        await card.send()
        #expect(card.shown == .sent && transport.requests(to: Self.route).count == 1)
    }

    @Test func a400OnALaterTryDropsItAndAStillShownCardSaysWhy() async throws {
        let transport = RoutedTransport()
        transport.answer(Self.route, 503, Data())
        transport.answer(Self.route, 400, ["status": 400, "message": "The format is too big to send."])
        let clock = Clock()
        let formats = outbox(transport: transport, clock: clock)
        let card = try card(formats)
        await card.send()
        #expect(card.shown == .kept && formats.waiting.count == 1)
        clock.now += 120
        await formats.sendWaiting()
        #expect(formats.waiting.isEmpty && card.shown == .refused("The format is too big to send."))
    }

    @Test func a429WaitsForTheNextStart() async throws {
        let transport = RoutedTransport()
        transport.answer(Self.route, 429, ["message": "Too Many Requests."])
        transport.answer(Self.route, 200, ["id": "fictional3"])
        let clock = Clock()
        let file = PhoneTest.storage().bankOutboxURL
        let formats = outbox(file: file, transport: transport, clock: clock)
        let card = try card(formats)
        await card.send()
        #expect(card.shown == .kept && formats.waitsForNextStart && formats.waiting.first?.tries == 0)
        // Coming back to the foreground sends nothing.
        clock.now += 3600
        await formats.sendWaiting()
        #expect(transport.requests(to: Self.route).count == 1 && formats.waiting.count == 1)
        // The next start does.
        let next = outbox(file: file, transport: transport, clock: clock)
        await next.sendWaiting()
        #expect(next.waiting.isEmpty && transport.requests(to: Self.route).count == 2)
    }

    @Test func theSampleOnlyPretends() async throws {
        let transport = RoutedTransport()
        let formats = BankOutbox.sample(sampleDelay: .milliseconds(1))
        let card = try #require(formats.card(for: [Self.format]))
        card.bank = "Fiktivbank"
        await card.send()
        #expect(card.shown == .sent && formats.waiting.isEmpty && formats.hasAsked(Self.format.key))
        await formats.sendWaiting()
        #expect(transport.requests.isEmpty)
    }

    @Test func deletingAresiumsDataDeletesWaitingFormats() async throws {
        let transport = RoutedTransport()
        transport.offline = true
        let storage = PhoneStorage.init(root: PhoneTest.storage().root)
        let formats = outbox(file: storage.bankOutboxURL, transport: transport)
        try await card(formats).send()
        #expect(FileManager.default.fileExists(atPath: storage.bankOutboxURL.path))
        try storage.delete()
        #expect(!FileManager.default.fileExists(atPath: storage.bankOutboxURL.path))
        #expect(formats.waiting.isEmpty && !formats.hasAsked(Self.format.key))
    }

    // MARK: what is sent

    @Test func whatIsSentNamesEveryColumnAndSetting() {
        var layout = Self.layout
        layout.header.append("Notiz")
        layout.invertSign = true
        layout.skipStatus = ["vorgemerkt"]
        let shared = SharedFormat(layout: layout, bank: "Fiktivbank", appVersion: "1.0 (7)", language: .german,
                                  wording: .english)
        #expect(shared.bank == "Fiktivbank" && shared.appVersion == "1.0 (7)" && shared.language == "Deutsch")
        #expect(shared.columns == [
            .init(name: "Buchungsdatum", meaning: "Booking date"), .init(name: "Gegenseite", meaning: "Name"),
            .init(name: "Text", meaning: "Payment text"), .init(name: "Betrag", meaning: "Amount"),
            .init(name: "Saldo", meaning: "Balance"), .init(name: "Notiz", meaning: nil),
        ])
        #expect(shared.lines == [
            .init(title: "Dates", value: "31.12.2026"), .init(title: "Amounts", value: "1.234,56"),
            .init(title: "Separator", value: "Semicolon"),
            .init(title: "Money in and out", value: "the other way round"),
            .init(title: "Rows left out", value: "vorgemerkt"),
        ])
        // A file without a header row: its columns by place.
        var bare = Self.layout
        bare.header = []
        bare.columnCount = 6
        let german = SharedFormat(layout: bare, bank: "", appVersion: "1", language: .english, wording: .german)
        #expect(german.columns.map(\.name) == ["Spalte 1", "Spalte 2", "Spalte 3", "Spalte 4", "Spalte 5", "Spalte 6"])
        #expect(german.columns.last?.meaning == nil && german.lines[2].value == "Semikolon")
    }

    @Test func theCardShowsExactlyWhatItSends() throws {
        let formats = BankOutbox.sample()
        let card = try #require(formats.card(for: [Self.format]))
        card.bank = "  Fiktiv   Bank "
        #expect(card.shared.bank == "Fiktiv Bank" && card.shared.columns.count == Self.layout.header.count)
    }
}

/// A confirmed VR Bank layout keeps the engine's id formula when the app saves and reads it back (aresium brief 85),
/// so a VR file re-saved by a spreadsheet gives its payments the same ids and nothing shows twice.
struct LayoutIdStyleTests {
    @Test func savedLayoutKeepsTheEnginesIdStyle() throws {
        var layout = BankFormatTests.layout
        layout.idStyle = "vrbank"
        let saved = try JSONEncoder().encode(layout)
        #expect(try JSONDecoder().decode(CsvLayout.self, from: saved).idStyle == "vrbank")
        let plain = try JSONEncoder().encode(BankFormatTests.layout)
        #expect(try JSONDecoder().decode(CsvLayout.self, from: plain).idStyle == nil)
        #expect(String(decoding: plain, as: UTF8.self).contains("idStyle") == false)
    }
}
