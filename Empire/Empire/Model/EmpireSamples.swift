import Foundation

enum EmpireSamples {
    static var isEnabled: Bool {
        enabled(arguments: LaunchArguments.current)
    }

    /// A member's view: `-sampleUser`, or `-sampleCatalog` (below).
    static var isUser: Bool { isCatalog || LaunchArguments.current.contains("-sampleUser") }
    static var isCatalog: Bool { LaunchArguments.current.contains("-sampleCatalog") }

    static func enabled(arguments: [String]) -> Bool {
        #if DEBUG
        arguments.contains("-sampleData")
        #else
        false
        #endif
    }

    static func load(user: Bool) throws -> EmpireData {
        guard let url = Bundle.main.url(forResource: user ? "empire.user" : "empire.admin", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder().decode(EmpireData.self, from: Data(contentsOf: url))
    }

    /// Screenshots of getting more apps (`-sampleCatalog`, a member): Arestemis in the ring with an install link (its
    /// page after a tap that opened nothing shows Install), and in "+" one app to ask for, one asked for and one coming
    /// soon. Made up from the admin sample's provinces (the hub's own answer in Preview Content), so it keeps working
    /// when the samples are made again; a province missing there is left out.
    static func catalog() throws -> EmpireData {
        let admin = try load(user: false)
        let member = try load(user: true)
        func province(_ slug: String) -> Province? { admin.projects.first { $0.slug == slug } }
        let ring = [province("arestemis")?.with(install: "https://testflight.apple.com/join/SAMPLE00")]
        let addable = [province("aresolus")?.with(access: .notRequested),
                       province("aresync")?.with(access: .requested),
                       province("aresium")?.with(access: .notRequested, state: "coming-soon")]
        let projects = ring.compactMap { $0 }
        let slugs = Set(projects.map(\.slug))
        return EmpireData(version: 2, me: member.me, projects: projects, addable: addable.compactMap { $0 },
                          chronicle: admin.chronicle.filter { slugs.contains($0.project ?? "") }, ideas: [], pending: 0)
    }

    /// Fictional sign-ups and an access request for exercising approvals without contacting an account server.
    static let approvals = [
        PendingAccount(id: "sample-pending-one", email: "alex@example.invalid", name: "Alex Sample", created: "2026-10-24",
                       requested: ["empire"], verified: true),
        PendingAccount(id: "sample-pending-two", email: "sam@example.invalid", name: "Sam Sample", created: "2026-10-24",
                       requested: ["arestemis"], verified: false),
        PendingAccount(id: "sample-member-one", email: "kim@example.invalid", name: "Kim Sample", created: "2026-10-12",
                       requested: ["arestemis", "aresus"], approved: true, verified: true),
    ]
}
