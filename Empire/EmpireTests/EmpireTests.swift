import Testing
@testable import Empire

struct EmpireTests {
    @Test func usesTheEmpireService() {
        #expect(EmpireAppIdentity.empire.service == "empire")
        #expect(EmpireShared.appGroup == "group.de.ares-empire.shared")
    }
}

import Foundation

/// Half of the one-login check across apps (scripts/check-shared-login.sh): only runs when the script asks.
struct SharedLoginProbe {
    nonisolated static let env = ProcessInfo.processInfo.environment

    @Test(.enabled(if: env["SHARED_LOGIN_PROBE"] == "write"))
    func writesTheSharedLogin() throws {
        try TokenKeychain().save(try #require(Self.env["SHARED_LOGIN_PROBE_TOKEN"]))
    }
}
