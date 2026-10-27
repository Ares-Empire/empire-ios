import Foundation
import Testing
@testable import Aresium

/// "My bank is missing" (brief 25): the request's body, the outbox the bank formats use (both kinds in one file, the
/// same tries, 400 and 429), a name that looks like personal data refused in the app, the sample, and deleting Aresium's
/// data. A fake transport answers; nothing reaches the real account server.
@MainActor
struct BankRequestTests {
    static let route = "POST /api/collections/bank_requests/records"
    static let formatRoute = "POST /api/collections/bank_formats/records"

    private final class Clock { var now = Date(timeIntervalSince1970: 1_800_000_000) }

    private func outbox(file: URL? = nil, transport: RoutedTransport, clock: Clock = Clock()) -> BankOutbox {
        BankOutbox(file: file ?? PhoneTest.storage().bankOutboxURL,
                   api: BankOutboxAPI(transport: transport), appVersion: "1.0 (12)", now: { clock.now })
    }

    private func form(_ outbox: BankOutbox, bank: String = "Fiktivbank Süd") -> BankRequestForm {
        BankRequestForm(bank: bank, outbox: outbox, language: { .german })
    }

    // MARK: the request

    @Test func theRequestCarriesOnlyTheNameTheVersionAndTheLanguage() throws {
        let submission = try BankRequestSubmission(bank: "  Fiktiv\nSparkasse   Nord ", appVersion: "1.0 (12)\u{0}<x>",
                                                   language: .german)
        #expect(submission.bank == "Fiktiv Sparkasse Nord" && submission.appVersion == "1.0 (12)x")
        let request = try BankOutboxAPI().request(.request(submission))
        #expect(request.url?.absoluteString == "https://auth.ares-empire.de/api/collections/bank_requests/records")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(request.value(forHTTPHeaderField: "Accept-Language") == "de")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        let data = try #require(request.httpBody)
        let body = try #require(try JSONSerialization.jsonObject(with: data) as? [String: String])
        #expect(body == ["bank": "Fiktiv Sparkasse Nord", "app_version": "1.0 (12)x", "language": "de"])

        #expect(throws: BankSubmission.Invalid.noBank) {
            _ = try BankRequestSubmission(bank: " \n ", appVersion: "1", language: .english)
        }
        let long = try BankRequestSubmission(bank: String(repeating: "Bank ", count: 40), appVersion: "1",
                                             language: .english)
        #expect(long.bank.count <= 100 && !long.bank.hasSuffix(" "))
    }

    @Test func sentAtOnceSaysThankYou() async throws {
        let transport = RoutedTransport()
        transport.answer(Self.route, 200, ["id": "fictional1"])
        let outbox = outbox(transport: transport)
        let form = form(outbox)
        #expect(form.canSend)
        await form.send()
        #expect(form.shown == .sent && outbox.waiting.isEmpty)
        #expect(transport.requests(to: Self.route).count == 1 && transport.requests.count == 1)
        let body = try #require(transport.requests.first?.httpBody)
        #expect(try JSONSerialization.jsonObject(with: body) as? [String: String]
                == ["bank": "Fiktivbank Süd", "app_version": "1.0 (12)", "language": "de"])
    }

    // MARK: a name that looks like personal data

    @Test(arguments: ["DE89 3704 0044 0532 0130 00", "fictional@example.invalid", "Fiktivbank 27.10.2026",
                      "Fiktivbank 12,34 €", "Kunde 1234567", "Konto 0532 0130 00"])
    func aNameThatLooksPersonalIsRefusedInTheApp(name: String) async throws {
        let transport = RoutedTransport()
        transport.answer(Self.route, 200, ["id": "fictional"])
        let outbox = outbox(transport: transport)
        let form = form(outbox, bank: name)
        await form.send()
        #expect(form.shown == .asking)
        #expect(form.problem == BankSubmission.personalLine(language: .german))
        #expect(transport.requests.isEmpty && outbox.waiting.isEmpty)
        // Typing again clears the line; a plain name goes.
        form.bank = "Fiktivbank"
        #expect(form.problem == nil)
        await form.send()
        #expect(form.shown == .sent && transport.requests.count == 1)
    }

    /// Real banks' names are not personal data (numbers in a name are fine while they are short).
    @Test func banksNamesPass() async throws {
        let outbox = outbox(transport: RoutedTransport())
        for name in ["Sparda-Bank Südwest", "1822direkt", "Bank11", "N26", "C24 Bank", "PSD Bank Nürnberg",
                     "Sparkasse Märkisch-Oderland", "VR Bank Main-Kinzig-Büdingen", "ABK Allgemeine Beamten Bank"] {
            #expect(await !outbox.looksPersonal(name), "\(name)")
        }
    }

    // MARK: the outbox both kinds share

    @Test func offlineItIsKeptWithTheFormatsAndSentByItselfLater() async throws {
        let transport = RoutedTransport()
        transport.offline = true
        let clock = Clock()
        let file = PhoneTest.storage().bankOutboxURL
        let outbox = outbox(file: file, transport: transport, clock: clock)
        let form = form(outbox)
        await form.send()
        #expect(form.shown == .kept)
        // A format waits beside it, in the same file.
        let layout = BankFormatTests.layout
        let format = try BankFormatSubmission(format: BankFormat(layout: layout, key: BankFormat.key(of: layout)),
                                              bank: "Fiktivbank Süd", appVersion: "1.0 (12)", language: .german)
        _ = await outbox.submit(.format(format))
        #expect(outbox.waiting.map(\.submission.kind) == [.request, .format])
        #expect(outbox.waiting.allSatisfy { $0.tries == 0 })
        let saved = try String(contentsOf: file, encoding: .utf8)
        #expect(saved.contains(#""kind":"request""#) && saved.contains(#""kind":"format""#))

        // Online at the next round: each goes to its own collection; the form, still on screen, says thank you.
        transport.offline = false
        transport.answer(Self.route, 200, ["id": "fictional2"])
        transport.answer(Self.formatRoute, 200, ["id": "fictional3"])
        clock.now += 120
        await outbox.sendWaiting()
        #expect(outbox.waiting.isEmpty && form.shown == .sent)
        #expect(transport.requests(to: Self.route).count == 2 && transport.requests(to: Self.formatRoute).count == 2)
    }

    @Test func aServerErrorIsTriedAtMostThreeTimes() async throws {
        let transport = RoutedTransport()
        transport.answer(Self.route, 500, ["message": "Something went wrong."])
        let clock = Clock()
        let outbox = outbox(transport: transport, clock: clock)
        await form(outbox).send()
        #expect(outbox.waiting.first?.tries == 1)
        clock.now += 120
        await outbox.sendWaiting()
        #expect(outbox.waiting.first?.tries == 2)
        clock.now += 120
        await outbox.sendWaiting()
        #expect(outbox.waiting.isEmpty)                                 // the third try failed too: dropped
        clock.now += 120
        await outbox.sendWaiting()
        #expect(transport.requests(to: Self.route).count == 3)
    }

    @Test func a400IsFinalAndAboutTheNameLetsItBeTypedAgain() async throws {
        let transport = RoutedTransport()
        let sentence = "Der Name sieht nach persönlichen Daten aus. Gib nur den Namen der Bank ein."
        transport.answer(Self.route, 400, ["status": 400, "message": sentence,
                                           "data": ["bank": ["code": "personal_data", "message": "looks personal"]]])
        transport.answer(Self.route, 400, ["status": 400, "message": "Something is wrong with this request."])
        let outbox = outbox(transport: transport)
        let form = form(outbox)
        await form.send()
        // About the name: nothing kept, the form asks again with the server's sentence.
        #expect(form.shown == .asking && form.problem == sentence && outbox.waiting.isEmpty)
        form.bank = "Fiktivbank Ost"
        await form.send()
        // Any other 400: final, its sentence shown, never sent again.
        #expect(form.shown == .refused("Something is wrong with this request.") && outbox.waiting.isEmpty)
        await outbox.sendWaiting()
        #expect(transport.requests(to: Self.route).count == 2)
    }

    @Test func a429WaitsForTheNextStart() async throws {
        let transport = RoutedTransport()
        transport.answer(Self.route, 429, ["message": "Too Many Requests."])
        transport.answer(Self.route, 200, ["id": "fictional4"])
        let clock = Clock()
        let file = PhoneTest.storage().bankOutboxURL
        let outbox = outbox(file: file, transport: transport, clock: clock)
        let form = form(outbox)
        await form.send()
        #expect(form.shown == .kept && outbox.waitsForNextStart && outbox.waiting.first?.tries == 0)
        clock.now += 3600
        await outbox.sendWaiting()                                     // a return to the foreground sends nothing
        #expect(transport.requests(to: Self.route).count == 1 && outbox.waiting.count == 1)
        let next = self.outbox(file: file, transport: transport, clock: clock)
        await next.sendWaiting()                                       // the next start does
        #expect(next.waiting.isEmpty && transport.requests(to: Self.route).count == 2)
    }

    @Test func theSampleOnlyPretends() async {
        let transport = RoutedTransport()
        let outbox = BankOutbox.sample(sampleDelay: .milliseconds(1))
        let form = form(outbox)
        await form.send()
        #expect(form.shown == .sent && outbox.waiting.isEmpty)
        await outbox.sendWaiting()
        #expect(transport.requests.isEmpty)
    }

    @Test func deletingAresiumsDataDeletesWaitingRequests() async throws {
        let transport = RoutedTransport()
        transport.offline = true
        let storage = PhoneTest.storage()
        let outbox = outbox(file: storage.bankOutboxURL, transport: transport)
        await form(outbox).send()
        #expect(outbox.waiting.count == 1)
        try storage.delete()
        #expect(!FileManager.default.fileExists(atPath: storage.bankOutboxURL.path))
        #expect(outbox.waiting.isEmpty)
        // Nothing comes back later either.
        transport.offline = false
        await outbox.sendWaiting()
        #expect(transport.requests.count == 1)
    }

    /// A file written by brief 23's build (formats only, no `kind`) still reads: its formats wait as before.
    @Test func anOlderOutboxFileStillReads() throws {
        let file = PhoneTest.storage().bankOutboxURL
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let old = #"""
            {"asked":["abc"],"waiting":[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","tries":1,
             "submission":{"bank":"Fiktivbank","layout":{"version":1,"separator":";","header":["Datum","Betrag"],
             "dateFormat":"DD.MM.YYYY","numberFormat":"de","columns":{"date":0,"amount":1}},
             "app_version":"1.0 (7)","language":"en"}}]}
            """#
        try Data(old.utf8).write(to: file)
        let outbox = outbox(file: file, transport: RoutedTransport())
        #expect(outbox.hasAsked("abc"))
        let waiting = try #require(outbox.waiting.first)
        #expect(waiting.tries == 1 && waiting.submission.kind == .format && waiting.submission.bank == "Fiktivbank")
    }
}
