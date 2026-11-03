import Foundation
import Testing
@testable import Empire

/// Shared/Support: the contact form's message, its request to the account server, and how sending ends.
@MainActor
struct SupportTests {
    static let token = SharedLoginTests.token(account: "account-a")
    static let device = SupportDevice(appVersion: "1.0 (12)", system: "iOS 27.0 · iPhone")

    /// A form on a session logged in as account A; the account server answers with `server`.
    func form(server: EmpireFakeTransport = EmpireFakeTransport(), sample: Bool = false,
              signedIn: Bool = true) async -> (SupportForm, EmpireSession, EmpireMemoryTokens) {
        let storage = EmpireMemoryTokens()
        let session = EmpireSession(app: .empire, storage: storage,
                                    client: EmpireAuthClient(transport: EmpireFakeTransport(data: SharedLoginTests.response(Self.token))),
                                    restoreOnLaunch: false)
        if signedIn { await session.login(email: "member@example.invalid", password: "fictional-password") }
        let form = SupportForm(session: session, sample: sample, api: SupportAPI(transport: server),
                               device: { Self.device }, language: .german, sampleDelay: .zero)
        return (form, session, storage)
    }

    static func json(_ data: Data?) -> [String: String]? {
        data.flatMap { try? JSONDecoder().decode([String: String].self, from: $0) }
    }

    // MARK: the message

    @Test func theBodyNamesTheAccountTheAppAndThePhone() throws {
        let message = try SupportMessage(kind: .idea, text: "  \nFictional idea: a darker wall.\n\n", token: Self.token,
                                         app: .arestoteles, device: Self.device, language: .german)
        #expect(Self.json(try JSONEncoder().encode(message)) == [
            "user": "account-a", "app": "arestoteles", "kind": "idea", "message": "Fictional idea: a darker wall.",
            "app_version": "1.0 (12)", "system": "iOS 27.0 · iPhone", "language": "de",
        ])
    }

    @Test func refusesWhatTheServerWouldRefuse() {
        func problem(_ text: String, token: String = Self.token) -> SupportMessage.Invalid? {
            do {
                _ = try SupportMessage(kind: .problem, text: text, token: token, app: .empire, device: Self.device)
                return nil
            } catch { return error }
        }
        #expect(problem("") == .empty)
        #expect(problem(" \n\t ") == .empty)
        #expect(problem(String(repeating: "x", count: 5000)) == nil)
        #expect(problem(String(repeating: "x", count: 5001)) == .tooLong)
        // The server counts Unicode scalars: one family emoji is five of them.
        #expect(problem(String(repeating: "👨‍👩‍👧", count: 1000)) == nil)
        #expect(problem(String(repeating: "👨‍👩‍👧", count: 1001)) == .tooLong)
        #expect(problem("Fictional", token: "not-a-token") == .noAccount)
    }

    @Test func keepsVersionAndSystemWithinTheServersLimits() throws {
        let long = SupportDevice(appVersion: String(repeating: "9", count: 60), system: String(repeating: "s", count: 120))
        let message = try SupportMessage(kind: .other, text: "Fictional", token: Self.token, app: .aresus, device: long)
        #expect(message.appVersion.count == 40 && message.system.count == 80)
    }

    @Test func describesTheAppVersionAndThePhone() {
        #expect(SupportDevice.appVersion(["CFBundleShortVersionString": "1.0", "CFBundleVersion": "12"]) == "1.0 (12)")
        #expect(SupportDevice.appVersion(["CFBundleShortVersionString": "1.0"]) == "1.0")
        #expect(SupportDevice.appVersion(nil) == "?")
        let version = OperatingSystemVersion(majorVersion: 27, minorVersion: 0, patchVersion: 0)
        #expect(SupportDevice.system(name: "iOS", version: version, model: "iPhone") == "iOS 27.0 · iPhone")
        let fix = OperatingSystemVersion(majorVersion: 27, minorVersion: 0, patchVersion: 1)
        #expect(SupportDevice.system(name: "iOS", version: fix, model: "iPhone") == "iOS 27.0.1 · iPhone")
    }

    // MARK: sending

    @Test func sendsOneRequestWithTheLoginAndTheMessage() async {
        let server = EmpireFakeTransport()
        let (form, _, _) = await form(server: server)
        form.kind = .question
        form.text = "Fictional question?"
        await form.send()

        #expect(form.phase == .sent)
        #expect(server.requests.count == 1)
        let request = server.requests.first
        #expect(request?.url == URL(string: "https://auth.ares-empire.de/api/collections/feedback/records"))
        #expect(request?.httpMethod == "POST")
        #expect(request?.value(forHTTPHeaderField: "Authorization") == "Bearer " + Self.token)
        #expect(request?.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(Self.json(request?.httpBody) == [
            "user": "account-a", "app": "empire", "kind": "question", "message": "Fictional question?",
            "app_version": "1.0 (12)", "system": "iOS 27.0 · iPhone", "language": "de",
        ])
    }

    @Test func tooManyMessagesKeepsTheTextAndOffersToSendAgain() async {
        let server = EmpireFakeTransport(data: Data(#"{"message":"Too Many Requests."}"#.utf8))
        server.status = 429
        let (form, session, _) = await form(server: server)
        form.text = "Fictional problem"
        await form.send()
        #expect(form.phase == .failed(.tooMany) && form.failure == .tooMany)
        #expect(form.text == "Fictional problem" && form.canSend && form.hasUnsentText)
        #expect(session.isSignedIn)
    }

    @Test func noConnectionKeepsTheText() async {
        let server = EmpireFakeTransport()
        server.failure = URLError(.notConnectedToInternet)
        let (form, _, _) = await form(server: server)
        form.text = "Fictional problem"
        await form.send()
        #expect(form.phase == .failed(.offline) && form.text == "Fictional problem" && form.canSend)

        server.failure = nil                                         // back online: Send again works
        await form.send()
        #expect(form.phase == .sent && server.requests.count == 2)
    }

    @Test func aRefusalHereNeverClosesTheApp() async {
        for status in [400, 403, 500] {
            let server = EmpireFakeTransport(data: Data(#"{"message":"Failed to create record."}"#.utf8))
            server.status = status
            let (form, session, _) = await form(server: server)
            form.text = "Fictional"
            await form.send()
            #expect(form.phase == .failed(.other))
            #expect(session.isSignedIn && session.access == .granted)     // a 403 here is not "no access to the app"
        }
    }

    @Test func aRejectedLoginLogsOut() async {
        let server = EmpireFakeTransport()
        server.status = 401
        let (form, session, storage) = await form(server: server)
        form.text = "Fictional"
        await form.send()
        #expect(form.phase == .failed(.loggedOut) && form.text == "Fictional")
        #expect(!session.isSignedIn && storage.token == nil)
    }

    @Test func withoutALoginNothingIsSent() async {
        let server = EmpireFakeTransport()
        let (form, _, _) = await form(server: server, signedIn: false)
        form.text = "Fictional"
        await form.send()
        #expect(form.phase == .failed(.loggedOut) && server.requests.isEmpty)
    }

    @Test func sampleModePretendsAndNeverCallsTheServer() async {
        let server = EmpireFakeTransport()
        let (form, _, _) = await form(server: server, sample: true, signedIn: false)
        form.text = "Fictional"
        await form.send()
        #expect(form.phase == .sent && server.requests.isEmpty)
    }

    // MARK: the form's state

    @Test func sendsOnlyWrittenTextAndOnlyOnce() async {
        let server = EmpireFakeTransport()
        let gate = EmpireRequestGate()
        server.nextGate = gate
        let (form, _, _) = await form(server: server)
        #expect(!form.canSend && !form.hasUnsentText)
        form.text = "  \n "
        #expect(!form.canSend && !form.hasUnsentText)
        await form.send()
        #expect(form.phase == .writing && server.requests.isEmpty)
        form.text = String(repeating: "x", count: 5001)
        #expect(!form.canSend && form.isTooLong && form.hasUnsentText)

        form.text = "Fictional"
        let sending = Task { await form.send() }
        await gate.waitUntilPaused()
        #expect(form.phase == .sending && !form.canSend && form.hasUnsentText)
        await form.send()                                            // a second tap while sending does nothing
        gate.resume()
        await sending.value
        #expect(form.phase == .sent && server.requests.count == 1)
        #expect(!form.canSend && !form.hasUnsentText)                // closing no longer asks
    }

    /// Opened for one purpose (Arestemis's "Suggest a shop", brief 157): the kind and the text's start are set, the start
    /// alone is nothing written (closing asks nothing, Send waits), and the message sent is the whole text.
    @Test func opensWithAKindAndAStartedText() async throws {
        let server = EmpireFakeTransport()
        let (plain, session, _) = await form(server: server)
        #expect(plain.kind == .problem && plain.text.isEmpty && !plain.startsWithText)
        let form = SupportForm(session: session, api: SupportAPI(transport: server), device: { Self.device },
                               language: .german, sampleDelay: .zero, kind: .idea, text: "Shop vorschlagen: ")
        #expect(form.kind == .idea && form.text == "Shop vorschlagen: " && form.startsWithText)
        #expect(!form.canSend && !form.hasUnsentText)
        form.text += "  "
        #expect(!form.canSend && !form.hasUnsentText)
        form.text = "Shop vorschlagen: Otto"
        #expect(form.canSend && form.hasUnsentText)
        await form.send()
        #expect(form.phase == .sent && server.requests.count == 1)
        let sent = Self.json(server.requests.first?.httpBody)
        #expect(sent?["kind"] == "idea" && sent?["message"] == "Shop vorschlagen: Otto")
    }

    @Test func failuresReadAsOneOfTheFormsLines() {
        #expect(SupportFailure(HTTPError.server(429, nil)) == .tooMany)
        #expect(SupportFailure(HTTPError.unauthorized) == .loggedOut)
        #expect(SupportFailure(URLError(.timedOut)) == .offline)
        #expect(SupportFailure(URLError(.networkConnectionLost)) == .offline)
        #expect(SupportFailure(URLError(.badServerResponse)) == .other)
        #expect(SupportFailure(HTTPError.server(500, nil)) == .other)
        #expect(SupportFailure.allLines.count == Set(SupportFailure.allLines).count)
    }
}

private extension SupportFailure {
    static var allLines: [String] { [SupportFailure.offline, .tooMany, .loggedOut, .other].map(\.message) }
}
