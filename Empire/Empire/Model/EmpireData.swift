import Foundation

/// `GET /api/empire` version 2, per account (ares-empire/docs/API-EMPIRE.md). The server decides what this account
/// sees; the app only displays it. Field names are the contract's.
struct EmpireData: Codable, Equatable, Sendable {
    let version: Int
    let me: Me
    let projects: [Province]       // the ring: every app this account has (admin: every province)
    let addable: [Province]        // the "+" sheet: the other apps open to users, each with its `access` (admin: [])
    let chronicle: [ChronicleEntry]
    let ideas: [Idea]              // admin only
    let pending: Int?              // admin: accounts waiting for approval; nil when the hub could not count them

    struct Me: Codable, Equatable, Sendable {
        let id: String
        let name: String
        let admin: Bool
    }
}

extension EmpireData {
    private enum CodingKeys: String, CodingKey { case version, me, projects, addable, chronicle, ideas, pending }

    /// A province's `access` the hub did not send (a hub before 2026-10-25), or sent with a value this app does not
    /// know, follows the list it came in: `projects` are the apps the account has (granted), `addable` the ones it can
    /// ask for (not asked yet). `Province`'s own decoding gives granted; the "+" list is decided here.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        me = try container.decode(Me.self, forKey: .me)
        projects = try container.decode([Province].self, forKey: .projects)
        let sent = try container.decode([SentAccess].self, forKey: .addable)
        addable = zip(try container.decode([Province].self, forKey: .addable), sent).map { province, sent in
            province.with(access: sent.access ?? .notRequested)
        }
        chronicle = try container.decode([ChronicleEntry].self, forKey: .chronicle)
        ideas = try container.decode([Idea].self, forKey: .ideas)
        pending = try container.decodeIfPresent(Int.self, forKey: .pending)
    }

    /// Only a province's `access`, as the hub sent it: nil when missing or unknown.
    private struct SentAccess: Decodable {
        let access: Province.Access?
        private enum CodingKeys: String, CodingKey { case access }
        init(from decoder: Decoder) throws {
            access = Province.Access.lenient(try decoder.container(keyedBy: CodingKeys.self), key: .access)
        }
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
    /// What this account has of the app (contract addition 2026-10-25). In `projects` always granted; in `addable`
    /// requested (asked, waiting for Patrik) or not requested.
    var access: Access = .granted
    /// Where to install the app's iPhone app (a TestFlight public link while testing, the App Store later); only for
    /// apps the account has, nil when the hub sends none.
    var install: String? = nil
    var id: String { slug }
    var isComingSoon: Bool { state == "coming-soon" }

    enum Access: String, Codable, Sendable {
        case granted, requested
        case notRequested = "none"

        /// The value at `key`, nil when it is missing, not text, or a value this build does not know (a newer hub).
        static func lenient<Key: CodingKey>(_ container: KeyedDecodingContainer<Key>, key: Key) -> Access? {
            (try? container.decodeIfPresent(String.self, forKey: key)).flatMap { $0 }.flatMap(Access.init(rawValue:))
        }
    }

    struct Detail: Codable, Equatable, Sendable {
        let about: String
        let features: [String]
        let setup: String
        let wip: [String]
        let ideas: [String]
        // `changelog` exists in the contract but is unused: a province's news are its chronicle entries.
    }
}

extension Province {
    private enum CodingKeys: String, CodingKey {
        case slug, name, url, logo, status, domain, blurb, detail, state, live, app, access, install
    }

    /// The version-1 and version-2 fields as before; `access` and `install` are newer, so a hub without them (or with
    /// an unknown `access`) still decodes: access granted (`EmpireData` decides the "+" list's), no install link.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        slug = try container.decode(String.self, forKey: .slug)
        name = try container.decode(String.self, forKey: .name)
        url = try container.decode(String.self, forKey: .url)
        logo = try container.decode(String.self, forKey: .logo)
        status = try container.decode(String.self, forKey: .status)
        domain = try container.decode(String.self, forKey: .domain)
        blurb = try container.decode(String.self, forKey: .blurb)
        detail = try container.decode(Detail.self, forKey: .detail)
        state = try container.decode(String.self, forKey: .state)
        live = try container.decodeIfPresent(String.self, forKey: .live)
        app = try container.decodeIfPresent(String.self, forKey: .app)
        access = Access.lenient(container, key: .access) ?? .granted
        install = (try? container.decodeIfPresent(String.self, forKey: .install)).flatMap { $0 }
    }

    /// The install link as a URL to open: https with a host only (TestFlight and the App Store), else nil.
    var installURL: URL? {
        guard let install, let url = URL(string: install), url.scheme?.lowercased() == "https", url.host != nil else {
            return nil
        }
        return url
    }

    /// In the "+" sheet: open to users and not asked for yet.
    var canRequest: Bool { !isComingSoon && access == .notRequested }

    /// A copy with these fields changed (sample mode; the "+" list's access in `EmpireData`).
    func with(access: Access? = nil, install: String?? = nil, state: String? = nil) -> Province {
        Province(slug: slug, name: name, url: url, logo: logo, status: status, domain: domain, blurb: blurb,
                 detail: detail, state: state ?? self.state, live: live, app: app, access: access ?? self.access,
                 install: install ?? self.install)
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
