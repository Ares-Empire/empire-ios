import Foundation
import Testing
@testable import Empire

@MainActor
struct LoginMarkerTests {
    /// Every test owns its defaults, so no test reads or writes the device's real shared login marker.
    static func withDefaults(_ action: (UserDefaults) async throws -> Void) async throws {
        let suite = "empire.tests.marker." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: FirstLaunchTokenReset.key)
        try await action(defaults)
    }

    private func session(_ defaults: UserDefaults?, storage: any TokenStorage = EmpireMemoryTokens(),
                         auth: EmpireFakeTransport? = nil) -> EmpireSession {
        EmpireSession(app: .empire, storage: storage,
                      client: EmpireAuthClient(transport: auth ?? EmpireFakeTransport(data:
                        SharedLoginTests.response(SharedLoginTests.token(account: "account-a")))),
                      restoreOnLaunch: false, sharedDefaults: defaults)
    }

    @Test func loginAndRestoreSaveOnlyTheAccountMarker() async throws {
        try await Self.withDefaults { defaults in
            let storage = EmpireMemoryTokens()
            let session = session(defaults, storage: storage)
            await session.login(email: "member@example.invalid", password: "fictional-password")
            #expect(LoginMarker.account(in: defaults) == "account-a")
            #expect(defaults.string(forKey: LoginMarker.key) != session.token)
            LoginMarker.clear(in: defaults)
            let restored = self.session(defaults, storage: storage)
            await restored.restore()
            #expect(restored.isSignedIn && LoginMarker.account(in: defaults) == "account-a")
            restored.logOut()
            #expect(LoginMarker.account(in: defaults) == nil && storage.token == nil)
        }
    }

    @Test func refusedSavedLoginClearsTheMarker() async throws {
        try await Self.withDefaults { defaults in
            let auth = EmpireFakeTransport(data: SharedLoginTests.response(SharedLoginTests.token(account: "account-a")))
            let session = session(defaults, auth: auth)
            await session.login(email: "member@example.invalid", password: "fictional-password")
            auth.status = 401
            await session.restore()
            #expect(session.token == nil && LoginMarker.account(in: defaults) == nil)
        }
    }

    @Test func refusingAnOlderSavedTokenLeavesTheNewMarker() async throws {
        try await Self.withDefaults { defaults in
            let storage = EmpireMemoryTokens()
            let session = session(defaults, storage: storage)
            await session.login(email: "member@example.invalid", password: "fictional-password")
            let ended = session.token
            storage.token = SharedLoginTests.token(account: "account-b")
            LoginMarker.save("account-b", in: defaults)
            session.logOut(refusedToken: ended)
            #expect(session.token == nil && storage.token != nil)
            #expect(LoginMarker.account(in: defaults) == "account-b")
        }
    }

    @Test func followingAKeychainLogoutLeavesTheMarkerAlone() async throws {
        try await Self.withDefaults { defaults in
            let storage = EmpireMemoryTokens()
            let session = session(defaults, storage: storage)
            await session.login(email: "member@example.invalid", password: "fictional-password")
            storage.token = nil
            await session.followSharedLogin()
            #expect(session.token == nil && LoginMarker.account(in: defaults) == "account-a")
        }
    }

    @Test func firstLaunchClearsTheMarkerOnlyAfterDeletingTheToken() async throws {
        try await Self.withDefaults { defaults in
            defaults.removeObject(forKey: FirstLaunchTokenReset.key)
            LoginMarker.save("previous-install", in: defaults)
            let storage = EmpireMemoryTokens()
            storage.token = "fictional-old-token"
            try FirstLaunchTokenReset.run(storage: storage, defaults: defaults)
            #expect(storage.token == nil && LoginMarker.account(in: defaults) == nil)
            LoginMarker.save("current-install", in: defaults)
            try FirstLaunchTokenReset.run(storage: storage, defaults: defaults)
            #expect(LoginMarker.account(in: defaults) == "current-install")
        }
    }

    @Test func nilDefaultsStayIsolated() async {
        let session = session(nil)
        await session.login(email: "member@example.invalid", password: "fictional-password")
        session.followMarker()
        #expect(session.isSignedIn && LoginMarker.account(in: nil) == nil)
        session.logOut()
        #expect(LoginMarker.account(in: nil) == nil)
    }

    @Test(arguments: [nil, "account-b"] as [String?])
    func foregroundEndsSynchronouslyWithoutReadingTheLockedKeychain(account: String?) async throws {
        try await Self.withDefaults { defaults in
            let storage = LockableTokens()
            let session = session(defaults, storage: storage)
            await session.login(email: "member@example.invalid", password: "fictional-password")
            var resets = 0
            var ended: EmpireSession.EndedLogin?
            session.onAppDataReset { resets += 1 }
            session.onLogout { ended = $0 }
            let token = session.token
            let generation = session.generation
            if let account { LoginMarker.save(account, in: defaults) }
            else { LoginMarker.clear(in: defaults) }
            storage.locked = true
            session.followMarker()
            #expect(session.token == nil && session.accountID == nil && resets == 1)
            #expect(session.generation == generation + 1)
            #expect(ended?.token == token && ended?.deletedSavedLogin == false && ended?.wasRefused == false)
            #expect(LoginMarker.account(in: defaults) == account)
            session.followMarker()
            #expect(resets == 1)
        }
    }

    @Test func matchingMarkerKeepsTheSessionAndAChangedOneRestoresTheNewAccount() async throws {
        try await Self.withDefaults { defaults in
            let storage = EmpireMemoryTokens()
            let auth = EmpireFakeTransport(data: SharedLoginTests.response(SharedLoginTests.token(account: "account-a")))
            let session = session(defaults, storage: storage, auth: auth)
            await session.login(email: "member@example.invalid", password: "fictional-password")
            session.followMarker()
            #expect(session.isSignedIn)
            storage.token = SharedLoginTests.token(account: "account-b")
            auth.data = SharedLoginTests.response(storage.token!, account: "account-b")
            LoginMarker.save("account-b", in: defaults)
            session.followMarker()
            #expect(session.token == nil)
            await session.followSharedLogin()
            #expect(session.isSignedIn && session.accountID == "account-b")
        }
    }
}

@MainActor
private final class LockableTokens: TokenStorage {
    var token: String?
    var locked = false
    func read() throws -> String? {
        if locked { throw URLError(.noPermissionsToReadFile) }
        return token
    }
    func save(_ token: String) throws { self.token = token }
    func delete() throws { token = nil }
}
