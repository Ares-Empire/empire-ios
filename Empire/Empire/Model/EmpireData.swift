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
    let pending: Int               // admin: accounts waiting for approval

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

/// One pending sign-up (`GET /api/empire/approvals`, admin only).
struct PendingAccount: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let email: String
    let name: String
    let created: String
}
