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

    // MARK: a refused login (EmpireSession.handleAuthFailure)

    /// The password was changed in another app; this app took over the new token. A request made with the old one
    /// comes back 401 late: it must neither log out nor delete the new token every app now uses.
    @Test func aLate401ForAnOlderTokenChangesNothing() async {
        let storage = EmpireMemoryTokens()
        let old = Self.token(account: "account-a")
        let session = await signedIn(as: old, storage: storage, auth: EmpireFakeTransport())
        let renewed = Self.token(account: "account-a", renewal: 1)
        storage.token = renewed                                     // the other app's login after its password change
        await session.followSharedLogin()
        #expect(session.token == renewed)

        session.handleAuthFailure(HTTPError.unauthorized, generation: session.generation, token: old)
        session.handleAuthFailure(HTTPError.server(403, "No access."), generation: session.generation, token: old)
        #expect(session.isSignedIn && session.token == renewed && storage.token == renewed)
    }

    /// The token was refused before this app followed the newer login another app saved: it takes that one over.
    @Test func a401ForThisAppsTokenTakesOverANewerSavedLoginOfTheSameAccount() async {
        let storage = EmpireMemoryTokens()
        let old = Self.token(account: "account-a")
        let session = await signedIn(as: old, storage: storage, auth: EmpireFakeTransport())
        let generation = session.generation
        let renewed = Self.token(account: "account-a", renewal: 1)
        storage.token = renewed
        session.handleAuthFailure(HTTPError.unauthorized, generation: generation, token: old)
        #expect(session.isSignedIn && session.token == renewed && storage.token == renewed)
        #expect(session.generation == generation)                   // the same session: the app keeps its data
    }

    /// Another account's login saved meanwhile is not this app's to delete: this app ends its own, the saved one stays
    /// (picked up at the next foreground).
    @Test func a401NeverDeletesAnotherAccountsSavedLogin() async {
        let storage = EmpireMemoryTokens()
        let old = Self.token(account: "account-a")
        let session = await signedIn(as: old, storage: storage, auth: EmpireFakeTransport())
        let other = Self.token(account: "account-b")
        storage.token = other
        session.handleAuthFailure(HTTPError.unauthorized, generation: session.generation, token: old)
        #expect(!session.isSignedIn && storage.token == other)
    }

    @Test func a401ForTheSavedLoginEndsItEverywhere() async {
        let storage = EmpireMemoryTokens()
        let current = Self.token(account: "account-a")
        let session = await signedIn(as: current, storage: storage, auth: EmpireFakeTransport())
        session.handleAuthFailure(HTTPError.unauthorized, generation: session.generation, token: nil)   // never sent
        #expect(session.isSignedIn)
        session.handleAuthFailure(HTTPError.unauthorized, generation: session.generation, token: current)
        #expect(!session.isSignedIn && storage.token == nil)
    }

    /// A refused renewal of the saved login deletes it only while it is still that one.
    @Test func aRefusedRenewalKeepsALoginSavedMeanwhile() async {
        let storage = EmpireMemoryTokens()
        let auth = EmpireFakeTransport()
        let session = await signedIn(as: Self.token(account: "account-a"), storage: storage, auth: auth)
        let other = Self.token(account: "account-b")
        let gate = EmpireRequestGate()
        auth.nextGate = gate
        auth.status = 401
        let renewal = Task { await session.restore() }
        await gate.waitUntilPaused()
        storage.token = other                                       // another app logged in meanwhile
        gate.resume()
        await renewal.value
        #expect(!session.isSignedIn && storage.token == other)
    }

    // MARK: no access, asked for (EmpireSession.followSharedLogin)

    private func denied(storage: EmpireMemoryTokens, auth: EmpireFakeTransport) async -> EmpireSession {
        auth.data = Data(#"{"token":"\#(Self.token(account: "account-a"))","record":{"id":"account-a","approved":true,"services":["aresium"],"requested":["empire"]}}"#.utf8)
        let session = EmpireSession(app: .empire, storage: storage, client: EmpireAuthClient(transport: auth),
                                    restoreOnLaunch: false)
        await session.login(email: "member@example.invalid", password: "fictional-password")
        return session
    }

    /// After "Ask for access" the app asks the account server again when it comes to the foreground, at most once a
    /// minute, and opens once access is granted, without a loading screen in between.
    @Test func noAccessIsCheckedAgainAndOpensOnceApproved() async {
        let storage = EmpireMemoryTokens()
        let auth = EmpireFakeTransport()
        let session = await denied(storage: storage, auth: auth)
        var signIns = 0
        session.onSignIn { signIns += 1 }
        #expect(session.canAskForAccess && session.hasAskedForAccess && auth.requests.count == 1)
        let generation = session.generation

        await session.followSharedLogin(now: .now.addingTimeInterval(30))
        #expect(auth.requests.count == 1)                           // checked at the login, under a minute ago

        let gate = EmpireRequestGate()
        auth.nextGate = gate
        let later = Date.now.addingTimeInterval(61)
        let check = Task { await session.followSharedLogin(now: later) }
        await gate.waitUntilPaused()
        #expect(!session.isRestoring && session.isDenied)           // quietly: the no-access screen stays meanwhile
        gate.resume()
        await check.value
        #expect(auth.requests.count == 2 && auth.requests.last?.url?.lastPathComponent == "auth-refresh")
        #expect(session.isDenied)                                   // not approved yet

        await session.followSharedLogin(now: later.addingTimeInterval(59))
        #expect(auth.requests.count == 2)

        auth.data = Self.response(Self.token(account: "account-a"))  // approved: services now include "empire"
        await session.followSharedLogin(now: later.addingTimeInterval(61))
        #expect(auth.requests.count == 3 && session.isSignedIn && session.error == nil)
        #expect(signIns == 1 && session.generation == generation + 1)   // this app's session starts (push, data)

        await session.followSharedLogin(now: later.addingTimeInterval(200))
        #expect(auth.requests.count == 3)                           // signed in: nothing to check
    }

    @Test func aFailedCheckLeavesTheNoAccessScreenAsItWas() async {
        let storage = EmpireMemoryTokens()
        let auth = EmpireFakeTransport()
        let session = await denied(storage: storage, auth: auth)
        let error = session.error
        auth.failure = URLError(.notConnectedToInternet)
        await session.followSharedLogin(now: .now.addingTimeInterval(61))
        #expect(auth.requests.count == 2 && session.isDenied && session.error == error && !session.needsRestoreRetry)

        auth.failure = nil
        auth.status = 401                                           // the login itself was refused meanwhile
        await session.followSharedLogin(now: .now.addingTimeInterval(200))
        #expect(!session.isSignedIn && session.token == nil && storage.token == nil)
    }

    /// A 403 from the app's own server (the account has the service): the account server cannot tell more.
    @Test func aDenialByTheAppsServerIsNotCheckedAgain() async {
        let storage = EmpireMemoryTokens()
        let auth = EmpireFakeTransport()
        let session = await signedIn(as: Self.token(account: "account-a"), storage: storage, auth: auth)
        session.handleAuthFailure(HTTPError.server(403, "No access."), generation: session.generation, token: session.token)
        #expect(session.isDenied && !session.canAskForAccess)
        await session.followSharedLogin(now: .now.addingTimeInterval(3600))
        #expect(auth.requests.count == 1)
    }
}
