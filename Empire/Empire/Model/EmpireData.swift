import Foundation

/// `GET /api/empire` version 2, per account (ares-empire/docs/API-EMPIRE.md). The server decides what this account
/// sees; the app only displays it. Field names are the contract's.
struct EmpireData: Codable, Equatable, Sendable {
    let version: Int
    let me: Me
    let projects: [Province]       // the ring as this account sees it
    let addable: [Province]        // the "+" list (non-admins)
    let chronicle: [ChronicleEntry]
    let ideas: [Idea]              // admin only
    let pending: Int?              // admin: accounts waiting for approval; nil when the hub could not count them

    struct Me: Codable, Equatable, Sendable {
        let id: String
        let name: String
        let admin: Bool
    }
}

struct Province: Codable, Equatable, Identifiable, Sendable {
    let slug: String
    let name: String
    let url: String
    let logo: String               // path on the hub, e.g. "brand/hermes.webp"
    let status: String             // CONQUERED, BESIEGING, … (admin view)
    let domain: String
    let blurb: String
    let detail: Detail
    let state: String              // "open" | "coming-soon"
    let live: String?              // one live line from the province, e.g. "€1,339 spent in October"
    let app: String?               // iPhone app URL scheme, e.g. "aresium://"
    var id: String { slug }
    var isComingSoon: Bool { state == "coming-soon" }

    struct Detail: Codable, Equatable, Sendable {
        let about: String
        let features: [String]
        let setup: String
        let wip: [String]
        let ideas: [String]
        // `changelog` exists in the contract but is unused: a province's news are its chronicle entries.
    }
}

struct ChronicleEntry: Codable, Equatable, Hashable, Sendable {
    let at: String                 // "2026-10-23"
    let project: String?           // province slug, nil/"empire" for the empire itself
    let text: String
}

struct Idea: Codable, Equatable, Hashable, Sendable {
    let title: String
    let note: String
}

/// One account waiting for Patrik (`GET /api/empire/approvals`, admin only): a new sign-up (`approved == false`), or an
/// approved account asking for more apps. `requested` names the apps it asked for (service ids); approving grants them,
/// declining deletes a new sign-up or only clears an approved account's request (ares-empire docs/ACCOUNTS.md).
struct PendingAccount: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let email: String
    let name: String
    let created: String
    var requested: [String] = []
    var approved = false
    /// Whether the account confirmed its email (it can log in only once it has); nil from a hub that does not say.
    var verified: Bool? = nil

    init(id: String, email: String, name: String, created: String, requested: [String] = [], approved: Bool = false,
         verified: Bool? = nil) {
        self.id = id
        self.email = email
        self.name = name
        self.created = created
        self.requested = requested
        self.approved = approved
        self.verified = verified
    }

    private enum CodingKeys: String, CodingKey { case id, email, name, created, requested, approved, verified }

    /// The newer fields are optional, so the list still loads from a hub that does not send them yet.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        email = try container.decode(String.self, forKey: .email)
        name = try container.decode(String.self, forKey: .name)
        created = try container.decode(String.self, forKey: .created)
        requested = (try? container.decodeIfPresent([String].self, forKey: .requested)) ?? []
        approved = try container.decodeIfPresent(Bool.self, forKey: .approved) ?? false
        verified = try container.decodeIfPresent(Bool.self, forKey: .verified)
    }

    /// The account has not confirmed its email yet (a hub that does not say counts as confirmed).
    var awaitsEmailConfirmation: Bool { verified == false }

    /// The apps it asked for, by name: "Arestemis, Aresus".
    var requestedApps: String { requested.map(EmpireAppIdentity.name(of:)).joined(separator: ", ") }
}

/// What `POST /api/empire/approvals/<id>` answers: `{"ok": true, "approvals": [...], "pending": n|null}`, the list and
/// the count after the decision. Without a list (`"approvals": null`, or an older hub's `{"ok": true}`) `EmpireAPI`
/// gives nil, and the app asks for the list and the count again.
struct DecisionAnswer: Decodable, Equatable {
    let approvals: [PendingAccount]
    let pending: Int?
}
