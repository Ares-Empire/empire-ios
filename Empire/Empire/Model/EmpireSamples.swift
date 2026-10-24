import Foundation

enum EmpireSamples {
    static var isEnabled: Bool {
        enabled(arguments: ProcessInfo.processInfo.arguments)
    }

    static var isUser: Bool { ProcessInfo.processInfo.arguments.contains("-sampleUser") }

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

    /// Fictional sign-ups for exercising approvals without contacting an account server.
    static let approvals = [
        PendingAccount(id: "sample-pending-one", email: "alex@example.invalid", name: "Alex Sample", created: "2026-10-24"),
        PendingAccount(id: "sample-pending-two", email: "sam@example.invalid", name: "Sam Sample", created: "2026-10-24")
    ]
}
