import Foundation
@testable import Empire

@MainActor
final class EmpireFakeTransport: HTTPTransport {
    var requests: [URLRequest] = []
    var status = 200
    var data = Data()
    var responses: [(Int, Data)] = []
    var failure: Error?
    var nextGate: EmpireRequestGate?

    init(data: Data = Data()) { self.data = data }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let response = responses.isEmpty ? (status, data) : responses.removeFirst()
        let failure = failure
        if let gate = nextGate {
            nextGate = nil
            await gate.pause()
        }
        if let failure { throw failure }
        return (response.1, HTTPURLResponse(url: request.url!, statusCode: response.0,
                                          httpVersion: nil, headerFields: nil)!)
    }
}

@MainActor
final class EmpireRequestGate {
    private var pending: CheckedContinuation<Void, Never>?
    private var waiter: CheckedContinuation<Void, Never>?

    func pause() async {
        await withCheckedContinuation {
            pending = $0
            waiter?.resume()
            waiter = nil
        }
    }

    func waitUntilPaused() async {
        if pending != nil { return }
        await withCheckedContinuation { waiter = $0 }
    }

    func resume() {
        pending?.resume()
        pending = nil
    }
}

@MainActor
final class EmpireMemoryTokens: TokenStorage {
    var token: String?
    func read() throws -> String? { token }
    func save(_ token: String) throws { self.token = token }
    func delete() throws { token = nil }
}

@MainActor
func empireAuthResponse(token: String = "fictional-empire-token") -> Data {
    Data("""
    {"token":"\(token)","record":{"id":"fictional-account","approved":true,"services":["empire","aresium"]}}
    """.utf8)
}

@MainActor
func empireSession(storage: EmpireMemoryTokens = EmpireMemoryTokens(),
                   auth: EmpireFakeTransport? = nil) async -> EmpireSession {
    let session = EmpireSession(app: .empire, storage: storage,
                                client: EmpireAuthClient(transport: auth ?? EmpireFakeTransport(data: empireAuthResponse())),
                                restoreOnLaunch: false)
    await session.login(email: "member@example.invalid", password: "fictional-password")
    return session
}

@MainActor
func empireJSON(user: Bool = false) throws -> Data {
    try JSONEncoder().encode(EmpireSamples.load(user: user))
}

@MainActor
func empireWithPending(_ count: Int) throws -> EmpireData {
    let original = try EmpireSamples.load(user: false)
    return EmpireData(version: original.version, me: original.me, projects: original.projects,
                      addable: original.addable, chronicle: original.chronicle, ideas: original.ideas, pending: count)
}

/// Small hub answers written out here, shaped as `GET /api/empire` sends them (ares-empire webauth/server.py
/// `empire_data`). The larger samples in Preview Content come from the server itself.
enum EmpireFixtures {
    /// A member approved a moment ago: an empty ring, Aresium to add (coming soon), no chronicle entries yet.
    static let emptyRing = #"""
    {"version": 2, "me": {"id": "fictional00003", "name": "", "admin": false},
     "projects": [],
     "addable": [{"slug": "aresium", "name": "Aresium", "url": "https://aresium.de", "logo": "brand/hermes.webp",
                  "status": "CONQUERED", "domain": "aresium.de", "blurb": "Fictional blurb.",
                  "detail": {"about": "", "features": [], "setup": "", "wip": [], "ideas": [], "changelog": []},
                  "state": "coming-soon", "live": null, "app": "aresium://"}],
     "chronicle": [], "ideas": [], "pending": 0}
    """#

    /// The hub since 2026-10-25 for a member (`access`, `install`): Aresolus in the ring with an install link, and in
    /// "+" Arestemis (open; `arestemis` is its `access`) and Aresium (coming soon). Fictional texts.
    static func catalog(arestemis: String = "none") -> String {
        member(projects: [province("aresolus", state: "open", access: "granted",
                                   install: #""https://testflight.apple.com/join/FICTION1""#)],
               addable: [province("arestemis", state: "open", access: arestemis),
                         province("aresium", state: "coming-soon", access: "none")])
    }

    /// `catalog()` once Patrik approved Arestemis: it moved into the ring.
    static let catalogApproved = member(
        projects: [province("aresolus", state: "open", access: "granted",
                            install: #""https://testflight.apple.com/join/FICTION1""#),
                   province("arestemis", state: "open", access: "granted")],
        addable: [province("aresium", state: "coming-soon", access: "none")])

    /// A member's `GET /api/empire` with these provinces (JSON from `province`).
    static func member(projects: [String], addable: [String]) -> String {
        #"""
        {"version": 2, "me": {"id": "fictional00004", "name": "Robin Vale", "admin": false},
         "projects": [\#(projects.joined(separator: ", "))], "addable": [\#(addable.joined(separator: ", "))],
         "chronicle": [{"at": "2026-10-25", "project": "aresolus", "text": "Fictional news."}],
         "ideas": [], "pending": 0}
        """#
    }

    /// One province as the hub writes it. `access`: its text; `rawAccess`: raw JSON instead (a number, a wrong type);
    /// both nil leave the key out, as an older hub does. `install`: raw JSON; nil leaves it out.
    static func province(_ slug: String, state: String, access: String?, rawAccess: String? = nil,
                         install: String? = "null") -> String {
        var fields = [#""slug": "\#(slug)", "name": "\#(slug.capitalized)", "url": "", "logo": "brand/\#(slug).webp""#,
                      #""status": "CONQUERED", "domain": "", "blurb": "Fictional blurb.""#,
                      #""detail": {"about": "", "features": [], "setup": "", "wip": [], "ideas": [], "changelog": []}"#,
                      #""state": "\#(state)", "live": null, "app": "\#(slug)://""#]
        if let value = rawAccess ?? access.map({ #""\#($0)""# }) { fields.append(#""access": \#(value)"#) }
        if let install { fields.append(#""install": \#(install)"#) }
        return "{" + fields.joined(separator: ", ") + "}"
    }
}
