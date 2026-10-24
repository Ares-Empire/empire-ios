import Foundation
import Testing
@testable import Empire

/// `EmpireSession.followSharedLogin()`: the saved login is shared by every Empire app, so an app coming back to the
/// foreground follows what the others did meanwhile.
@MainActor
struct SharedLoginTests {
    /// A fictional, unsigned PocketBase-style token for `account` (only its payload is read on the device).
    static func token(account: String, renewal: Int = 0) -> String {
        let payload = Data(#"{"id":"\#(account)","type":"auth","n":\#(renewal)}"#.utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "eyJhbGciOiJIUzI1NiJ9.\(payload).fictional-signature"
    }

    static func response(_ token: String, account: String = "account-a") -> Data {
        Data(#"{"token":"\#(token)","record":{"id":"\#(account)","approved":true,"services":["empire"]}}"#.utf8)
    }

    private func signedIn(as token: String, storage: EmpireMemoryTokens, auth: EmpireFakeTransport) async -> EmpireSession {
        auth.data = Self.response(token)
        let session = EmpireSession(app: .empire, storage: storage, client: EmpireAuthClient(transport: auth),
                                    restoreOnLaunch: false)
        await session.login(email: "member@example.invalid", password: "fictional-password")
        return session
    }

    @Test func readsTheAccountFromAToken() {
        #expect(EmpireToken.accountID(Self.token(account: "abc123")) == "abc123")
        #expect(EmpireToken.accountID("not-a-token") == nil)
        #expect(EmpireToken.accountID("a.%%%.c") == nil)
    }

    @Test func picksUpALoginMadeInAnotherApp() async {
        let storage = EmpireMemoryTokens()
        let auth = EmpireFakeTransport(data: Self.response(Self.token(account: "account-a")))
        let session = EmpireSession(app: .empire, storage: storage, client: EmpireAuthClient(transport: auth),
                                    restoreOnLaunch: false)
        await session.followSharedLogin()
        #expect(!session.isSignedIn && auth.requests.isEmpty)       // nothing saved: nothing to do

        storage.token = Self.token(account: "account-a")            // the other app logged in
        await session.followSharedLogin()
        #expect(session.isSignedIn && auth.requests.count == 1)
        #expect(auth.requests.first?.url?.lastPathComponent == "auth-refresh")
    }

    @Test func followsALogoutMadeInAnotherAppAndForgetsThisAppsData() async {
        let storage = EmpireMemoryTokens()
        let session = await signedIn(as: Self.token(account: "account-a"), storage: storage, auth: EmpireFakeTransport())
        var resets = 0
        session.onAppDataReset { resets += 1 }
        let generation = session.generation

        storage.token = nil                                         // the other app logged out
        await session.followSharedLogin()
        #expect(!session.isSignedIn && resets == 1 && session.generation == generation + 1)
    }

    @Test func takesOverARenewedTokenOfTheSameAccountWithoutTheServer() async {
        let storage = EmpireMemoryTokens()
        let auth = EmpireFakeTransport()
        let session = await signedIn(as: Self.token(account: "account-a"), storage: storage, auth: auth)
        var resets = 0
        session.onAppDataReset { resets += 1 }
        let generation = session.generation

        let renewed = Self.token(account: "account-a", renewal: 1)
        storage.token = renewed                                     // the other app renewed the login
        await session.followSharedLogin()
        #expect(session.token == renewed && session.isSignedIn)
        #expect(auth.requests.count == 1)                           // only the login itself
        #expect(resets == 0 && session.generation == generation)
    }

    @Test func switchesWhenAnotherAccountLoggedIn() async {
        let storage = EmpireMemoryTokens()
        let auth = EmpireFakeTransport()
        let session = await signedIn(as: Self.token(account: "account-a"), storage: storage, auth: auth)
        var resets = 0
        session.onAppDataReset { resets += 1 }
        let generation = session.generation

        let other = Self.token(account: "account-b")
        storage.token = other                                       // someone else logged in in the other app
        auth.data = Self.response(other, account: "account-b")
        await session.followSharedLogin()
        #expect(resets == 1)                                        // account A's data is gone
        #expect(session.isSignedIn && session.token == other && session.generation > generation)
        #expect(auth.requests.count == 2)                           // checked with the server
    }

    @Test func sameTokenChangesNothing() async {
        let storage = EmpireMemoryTokens()
        let auth = EmpireFakeTransport()
        let session = await signedIn(as: Self.token(account: "account-a"), storage: storage, auth: auth)
        let generation = session.generation
        await session.followSharedLogin()
        #expect(session.isSignedIn && session.generation == generation && auth.requests.count == 1)
    }
}
