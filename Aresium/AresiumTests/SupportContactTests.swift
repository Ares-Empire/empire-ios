import Foundation
import Testing
@testable import Aresium

/// Contact & support without a login (brief 22, Aresium only): the message goes to the account server's open `contact`
/// collection with an email to answer to, a short footer naming the app and the phone, the language and the empty
/// honeypot; no token is sent. Always, also while an Ares login exists (brief 25, Patrik 2026-10-27); the other apps
/// keep the account-linked `feedback` record.
@MainActor
struct SupportContactTests {
    static let device = SupportDevice(appVersion: "1.0 (12)", system: "iOS 27.0 · iPhone")

    /// A form in Aresium (signed out, or logged in as account A); the account server answers through `server`.
    private func form(server: RoutedTransport, signedIn: Bool = false) async -> (SupportForm, EmpireSession) {
        let login = RoutedTransport()
        let session = await PhoneTest.session(signedIn ? "fictionalA" : nil, transport: login)
        let form = SupportForm(session: session, api: SupportAPI(transport: server), device: { Self.device },
                               language: .german, sampleDelay: .zero)
        return (form, session)
    }

    private static func body(_ request: URLRequest?) -> [String: String]? {
        request?.httpBody.flatMap { try? JSONDecoder().decode([String: String].self, from: $0) }
    }

    @Test func withoutALoginItBuildsAContactRecord() async {
        let server = RoutedTransport()
        server.answer("POST /api/collections/contact/records", 200, ["id": "fictional"])
        let (form, _) = await form(server: server)
        #expect(form.sendsWithoutLogin && !form.canSend)
        form.kind = .question
        form.text = "  Can I import two banks?  "
        #expect(!form.canSend)                                          // an email to answer to is needed
        form.email = " friend@example.invalid "
        form.name = "Fictional Friend"
        #expect(form.canSend)
        await form.send()
        #expect(form.phase == .sent && server.requests.count == 1)
        let request = server.requests.first
        #expect(request?.url == URL(string: "https://auth.ares-empire.de/api/collections/contact/records"))
        #expect(request?.httpMethod == "POST" && request?.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(Self.body(request) == [
            "name": "Fictional Friend", "email": "friend@example.invalid",
            "message": "Can I import two banks?\n\n— Aresium 1.0 (12) · iOS 27.0 · iPhone · Question",
            "language": "de", "website": "",
        ])
    }

    @Test func theMessageAndItsFooterStayWithinTheServersLimit() throws {
        let footer = ContactMessage.footer(kind: .problem, app: .aresium, device: Self.device)
        let room = ContactMessage.maxTextLength(footer: footer)
        let fits = try ContactMessage(kind: .problem, text: String(repeating: "a", count: room), email: "a@b.de", name: "",
                                      app: .aresium, device: Self.device)
        #expect(fits.message.unicodeScalars.count == ContactMessage.maxLength)
        #expect(throws: ContactMessage.Invalid.tooLong) {
            try ContactMessage(kind: .problem, text: String(repeating: "a", count: room + 1), email: "a@b.de", name: "",
                               app: .aresium, device: Self.device)
        }
        #expect(throws: ContactMessage.Invalid.email) {
            try ContactMessage(kind: .problem, text: "Fictional", email: "not an address", name: "", app: .aresium,
                               device: Self.device)
        }
        #expect(throws: ContactMessage.Invalid.empty) {
            try ContactMessage(kind: .problem, text: "   ", email: "a@b.de", name: "", app: .aresium, device: Self.device)
        }
        let long = try ContactMessage(kind: .idea, text: "Fictional", email: "a@b.de",
                                      name: String(repeating: "n", count: 140), app: .aresium, device: Self.device)
        #expect(long.name.count == ContactMessage.maxNameLength)
    }

    @Test func aRefusedAddressOrTooManyKeepTheText() async {
        let server = RoutedTransport()
        let (form, _) = await form(server: server)
        form.text = "Fictional problem"
        form.email = "friend@nowhere"
        await form.send()
        #expect(form.phase == .failed(.invalidEmail) && server.requests.isEmpty)   // checked before sending
        form.email = "friend@example.invalid"
        server.answer("POST /api/collections/contact/records", 400,
                      ["status": 400, "message": "Failed to create record.",
                       "data": ["email": ["code": "validation_is_email", "message": "Must be a valid email address."]]])
        await form.send()
        #expect(form.phase == .failed(.invalidEmail) && form.text == "Fictional problem")
        server.routes["POST /api/collections/contact/records"] = [(429, Data(#"{"message":"Too Many Requests."}"#.utf8))]
        await form.send()
        #expect(form.phase == .failed(.tooMany) && form.canSend)
    }

    @Test func signedInAresiumStillBuildsAContactRecord() async {
        let server = RoutedTransport()
        server.answer("POST /api/collections/contact/records", 200, ["id": "fictional"])
        let (form, session) = await form(server: server, signedIn: true)
        #expect(session.token != nil)
        #expect(form.sendsWithoutLogin && form.maxLength < SupportMessage.maxLength)
        // The account's address is there to answer to, and can be changed.
        #expect(form.email == "fictionalA@example.invalid")
        form.kind = .idea
        form.text = "Fictional wish"
        await form.send()
        #expect(form.phase == .sent && server.requests.count == 1)
        #expect(server.requests(to: "POST /api/collections/feedback/records").isEmpty)
        let request = server.requests.first
        #expect(request?.url == URL(string: "https://auth.ares-empire.de/api/collections/contact/records"))
        #expect(request?.value(forHTTPHeaderField: "Authorization") == nil)          // the login never goes with it
        #expect(Self.body(request) == [
            "name": "", "email": "fictionalA@example.invalid",
            "message": "Fictional wish\n\n— Aresium 1.0 (12) · iOS 27.0 · iPhone · Idea",
            "language": "de", "website": "",
        ])
    }

    /// Only Aresium's identity sends without a login; every other app keeps its account-linked `feedback`.
    @Test func onlyAresiumSendsWithoutALogin() {
        #expect(EmpireAppIdentity.aresium.supportWithoutLogin)
        let others = EmpireAppIdentity.all.filter { $0 != .aresium }
        #expect(others.count == 4 && others.allSatisfy { !$0.supportWithoutLogin })
    }
}
