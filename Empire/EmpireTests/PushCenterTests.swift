import Foundation
import Testing
import UserNotifications
@testable import Empire

/// Shared/Push: PushCenter against a fake push service, a fake permission dialog and a counted "ask iOS for the token".
@MainActor
struct PushCenterTests {
    static let app = "de.ares-empire.empire"
    static let device = Data([0x00, 0xab, 0x10, 0xff] + Array(repeating: 0x42, count: 28))
    static let deviceHex = "00ab10ff" + String(repeating: "42", count: 28)

    @MainActor
    final class FakePermissions: PushPermissions {
        var status: UNAuthorizationStatus = .notDetermined
        var answer: UNAuthorizationStatus = .authorized
        var requests: [UNAuthorizationOptions] = []
        var categories: Set<UNNotificationCategory> = []

        func authorizationStatus() async -> UNAuthorizationStatus { status }
        func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
            requests.append(options)
            status = answer
            return answer == .authorized
        }
        func setCategories(_ categories: Set<UNNotificationCategory>) { self.categories = categories }
    }

    struct Setup {
        let push: PushCenter
        let server: EmpireFakeTransport
        let permissions: FakePermissions
        let session: EmpireSession
        let storage: EmpireMemoryTokens
        let auth: EmpireFakeTransport
        let asks: Counter
    }

    @MainActor final class Counter { var count = 0 }

    static func token(_ account: String) -> String { SharedLoginTests.token(account: account) }

    /// A push center started on a session; `signedIn` logs in as account A first.
    func setup(signedIn: Bool = true, permission: UNAuthorizationStatus = .notDetermined,
               categories: [UNNotificationCategory] = [],
               actionURL: @escaping (String, URL?) -> URL? = { _, url in url }) async -> Setup {
        let storage = EmpireMemoryTokens()
        let auth = EmpireFakeTransport(data: SharedLoginTests.response(Self.token("account-a")))
        let session = EmpireSession(app: .empire, storage: storage, client: EmpireAuthClient(transport: auth),
                                    restoreOnLaunch: false)
        if signedIn { await session.login(email: "member@example.invalid", password: "fictional-password") }
        let server = EmpireFakeTransport()
        server.status = 204
        let permissions = FakePermissions()
        permissions.status = permission
        let push = PushCenter(api: PushAPI(transport: server), permissions: permissions, environment: .sandbox)
        let asks = Counter()
        push.registerForRemote = { asks.count += 1 }
        push.start(app: Self.app, session: session, categories: categories, actionURL: actionURL)
        await push.idle()
        return Setup(push: push, server: server, permissions: permissions, session: session, storage: storage,
                     auth: auth, asks: asks)
    }

    /// iOS answers the token request.
    func deliverToken(_ setup: Setup) async {
        setup.push.didRegister(deviceToken: Self.device)
        await setup.push.idle()
    }

    static func body(_ request: URLRequest) -> [String: String]? {
        request.httpBody.flatMap { try? JSONDecoder().decode([String: String].self, from: $0) }
    }

    // MARK: Registering

    @Test func signedInAsksPermissionOnceThenRegistersTheDevice() async {
        let setup = await setup()
        #expect(setup.permissions.requests == [PushCenter.permissionOptions])
        #expect(PushCenter.permissionOptions == [.alert, .sound, .badge])
        #expect(setup.asks.count == 1)

        await deliverToken(setup)
        let request = try! #require(setup.server.requests.first)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://www.ares-empire.de/api/push/devices")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer \(Self.token("account-a"))")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(Self.body(request) == ["app": Self.app, "token": Self.deviceHex, "environment": "sandbox",
                                       "language": AppLanguage.current.code])
        #expect(setup.push.deviceToken == Self.deviceHex)

        setup.push.refresh()                                         // the next foreground
        await setup.push.idle()
        #expect(setup.permissions.requests.count == 1 && setup.asks.count == 2)
        await deliverToken(setup)
        #expect(setup.server.requests.count == 2)                    // re-registered: the device is alive
    }

    @Test func signedOutDoesNothingUntilALoginStarts() async {
        let setup = await setup(signedIn: false)
        setup.push.refresh()
        await deliverToken(setup)
        #expect(setup.permissions.requests.isEmpty && setup.asks.count == 0 && setup.server.requests.isEmpty)

        await setup.session.login(email: "member@example.invalid", password: "fictional-password")
        await setup.push.idle()
        #expect(setup.asks.count == 1)
        await deliverToken(setup)
        #expect(setup.server.requests.count == 1)
    }

    @Test func aRestoredLoginAtLaunchRegistersToo() async {
        let setup = await setup(signedIn: false, permission: .authorized)
        setup.storage.token = Self.token("account-a")
        await setup.session.restore()
        await setup.push.idle()
        #expect(setup.permissions.requests.isEmpty)                  // already decided: not asked again
        #expect(setup.asks.count == 1)
    }

    @Test func deniedPermissionNeverAsksIOSForAToken() async {
        let setup = await setup(permission: .denied)
        setup.push.refresh()
        await setup.push.idle()
        #expect(setup.permissions.requests.isEmpty && setup.asks.count == 0)
    }

    @Test func userSaysNoToTheDialog() async {
        let storage = EmpireMemoryTokens()
        let session = await empireSession(storage: storage)
        let permissions = FakePermissions()
        permissions.answer = .denied
        let server = EmpireFakeTransport()
        let push = PushCenter(api: PushAPI(transport: server), permissions: permissions, environment: .sandbox)
        var asks = 0
        push.registerForRemote = { asks += 1 }
        push.start(app: Self.app, session: session)
        await push.idle()
        push.refresh()
        await push.idle()
        #expect(permissions.requests.count == 1 && asks == 0 && server.requests.isEmpty)
    }

    @Test func setsTheAppsCategories() async {
        let category = UNNotificationCategory(identifier: "ARESTEMIS_MATCH",
                                              actions: [UNNotificationAction(identifier: "OPEN_LISTING",
                                                                             title: "Open listing")],
                                              intentIdentifiers: [])
        let setup = await setup(categories: [category])
        #expect(setup.permissions.categories.map(\.identifier) == ["ARESTEMIS_MATCH"])
    }

    @Test func startingTwiceKeepsTheFirstApp() async {
        let setup = await setup()
        setup.push.start(app: "de.ares-empire.aresium", session: setup.session)
        await deliverToken(setup)
        #expect(Self.body(setup.server.requests[0])?["app"] == Self.app)
    }

    // MARK: Restarting in another language

    /// Settings → Language rebuilds the app with a new session (Shared/Language/AppRoot.swift): the push center
    /// takes it, sets the categories again (their titles in the new language) and registers the device with the new
    /// language once the new session has restored the login. The replaced session no longer reaches it.
    @Test func aRestartRegistersAgainInTheNewLanguage() async {
        let setup = await setup()
        await deliverToken(setup)
        #expect(Self.body(setup.server.requests[0])?["language"] == AppLanguage.current.code)

        let other: AppLanguage = AppLanguage.launched == .german ? .english : .german
        let restarted = EmpireSession(app: .empire, storage: setup.storage,
                                      client: EmpireAuthClient(transport: setup.auth))
        let category = UNNotificationCategory(identifier: "ARESUS_ISSUE", actions: [], intentIdentifiers: [])
        await AppLanguage.$scoped.withValue(other) {
            setup.push.start(app: Self.app, session: restarted, categories: [category])
            await setup.push.idle()
            #expect(setup.asks.count == 1)                          // still restoring: nothing yet
            await restarted.restore()
            await setup.push.idle()
            #expect(setup.asks.count == 2)
            await deliverToken(setup)
        }
        #expect(setup.permissions.categories.map(\.identifier) == ["ARESUS_ISSUE"])
        #expect(setup.permissions.requests.count == 1)              // permission is not asked again
        #expect(setup.server.requests.count == 2)
        #expect(Self.body(setup.server.requests[1])?["language"] == other.code)

        // The same session again (SwiftUI may build the root again): nothing happens.
        setup.push.start(app: Self.app, session: restarted)
        await setup.push.idle()
        #expect(setup.asks.count == 2 && setup.server.requests.count == 2)

        // The replaced session ending (a late answer of the old app) does not remove the device.
        setup.session.logOut()
        await setup.push.idle()
        #expect(setup.server.requests.count == 2)
    }

    // MARK: Account switch, logout, denied

    @Test func anAccountSwitchRemovesTheOldRegistrationAndRegistersTheNewAccount() async {
        let setup = await setup()
        await deliverToken(setup)

        let other = Self.token("account-b")
        setup.storage.token = other                                  // another app logged in as B
        setup.auth.data = SharedLoginTests.response(other, account: "account-b")
        await setup.session.followSharedLogin()
        await setup.push.idle()
        #expect(setup.asks.count == 2)
        await deliverToken(setup)

        let calls = setup.server.requests.map { ($0.httpMethod ?? "", $0.value(forHTTPHeaderField: "Authorization") ?? "") }
        #expect(calls.map(\.0) == ["POST", "DELETE", "POST"])
        #expect(calls.map(\.1) == ["Bearer \(Self.token("account-a"))", "Bearer \(Self.token("account-a"))",
                                   "Bearer \(other)"])
    }

    @Test func logoutRemovesTheDeviceWithTheTokenItWasRegisteredWith() async {
        let setup = await setup()
        await deliverToken(setup)
        setup.server.status = 500                                    // errors are ignored
        setup.session.logOut()
        await setup.push.idle()
        let delete = try! #require(setup.server.requests.last)
        #expect(delete.httpMethod == "DELETE")
        #expect(delete.url?.absoluteString == "https://www.ares-empire.de/api/push/devices")
        #expect(delete.value(forHTTPHeaderField: "Authorization") == "Bearer \(Self.token("account-a"))")
        #expect(Self.body(delete) == ["app": Self.app, "token": Self.deviceHex])
        #expect(setup.session.token == nil)

        setup.session.logOut()                                       // nothing registered any more
        await setup.push.idle()
        #expect(setup.server.requests.count == 2)
    }

    @Test func logoutBeforeAnyRegistrationSendsNothing() async {
        let setup = await setup()
        setup.session.logOut()
        await setup.push.idle()
        #expect(setup.server.requests.isEmpty)
    }

    @Test func deniedAccessRemovesTheDevice() async {
        let setup = await setup()
        await deliverToken(setup)
        setup.session.handleAuthFailure(HTTPError.server(403, "No access."), generation: setup.session.generation,
                                        token: setup.session.token)
        await setup.push.idle()
        #expect(setup.session.isDenied)
        #expect(setup.server.requests.map(\.httpMethod) == ["POST", "DELETE"])
        #expect(setup.server.requests[1].value(forHTTPHeaderField: "Authorization") == "Bearer \(Self.token("account-a"))")

        setup.push.refresh()                                         // denied: no new registration
        await deliverToken(setup)
        #expect(setup.server.requests.count == 2)
    }

    // MARK: Answers of the push service

    @Test func a401IsARejectedLogin() async {
        let setup = await setup()
        setup.server.status = 401
        await deliverToken(setup)
        await setup.push.idle()
        #expect(setup.session.token == nil && setup.storage.token == nil)   // logged out everywhere
        #expect(setup.server.requests.map(\.httpMethod) == ["POST"])       // no DELETE with a rejected token
    }

    @Test func a403StopsTryingForThisSession() async {
        let setup = await setup()
        setup.server.status = 403
        await deliverToken(setup)
        #expect(setup.session.isSignedIn)                            // the app itself stays open
        setup.push.refresh()
        await deliverToken(setup)
        #expect(setup.server.requests.count == 1 && setup.asks.count == 1)

        setup.session.logOut()                                       // the next session tries again
        setup.server.status = 204
        await setup.session.login(email: "member@example.invalid", password: "fictional-password")
        await setup.push.idle()
        await deliverToken(setup)
        #expect(setup.server.requests.filter { $0.httpMethod == "POST" }.count == 2)
    }

    @Test func offlineTriesAgainAtTheNextForeground() async {
        let setup = await setup()
        setup.server.failure = URLError(.notConnectedToInternet)
        await deliverToken(setup)
        setup.server.failure = nil
        setup.push.refresh()
        await deliverToken(setup)
        #expect(setup.server.requests.count == 2 && setup.session.isSignedIn)
    }

    // MARK: Opening notifications

    @Test func extractsTheURLFromAPayload() {
        #expect(PushCenter.url(from: ["aps": ["alert": "x"], "url": "arestemis://match/123"])
                == URL(string: "arestemis://match/123"))
        #expect(PushCenter.url(from: ["url": "https://www.ares-empire.de/x"]) == URL(string: "https://www.ares-empire.de/x"))
        #expect(PushCenter.url(from: ["aps": ["alert": "x"]]) == nil)
        #expect(PushCenter.url(from: ["url": 42]) == nil)
        #expect(PushCenter.url(from: ["url": "no scheme"]) == nil)
        #expect(PushCenter.url(from: ["url": ""]) == nil)
    }

    @Test func theSamplePayloadCarriesAURL() throws {
        // Read from the source tree (the simulator shares the Mac's files), so it does not matter which bundles ship it.
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appending(path: "Shared/Push/sample-push.apns")
        let payload = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [AnyHashable: Any])
        #expect(PushCenter.url(from: payload) == URL(string: "empire://sample"))
        #expect((payload["aps"] as? [String: Any])?["alert"] != nil)
    }

    @Test func aTapOpensTheURLAndAnActionWhatTheAppMapsItTo() async {
        let setup = await setup(actionURL: { action, url in
            action == "OPEN_LISTING" ? URL(string: "https://example.com/listing") : (action == "MUTE" ? nil : url)
        })
        let push = setup.push
        let url = URL(string: "arestemis://match/123")!

        push.open(action: UNNotificationDefaultActionIdentifier, url: url)
        #expect(push.openedURL == url && push.lastActionIdentifier == UNNotificationDefaultActionIdentifier)
        #expect(push.takeOpenedURL() == url)
        #expect(push.openedURL == nil && push.takeOpenedURL() == nil)

        push.open(action: "OPEN_LISTING", url: url)
        #expect(push.takeOpenedURL() == URL(string: "https://example.com/listing"))
        #expect(push.lastActionIdentifier == "OPEN_LISTING")

        push.open(action: "APPLY", url: url)
        #expect(push.takeOpenedURL() == url && push.lastActionIdentifier == "APPLY")

        push.open(action: "MUTE", url: url)                          // mapped to nothing
        push.open(action: UNNotificationDismissActionIdentifier, url: url)
        push.open(action: UNNotificationDefaultActionIdentifier, url: nil)
        #expect(push.openedURL == nil && push.lastActionIdentifier == "APPLY")
    }

    @Test func deviceTokensAreLowercaseHex() {
        #expect(PushCenter.hex(Data([0x00, 0xAB, 0x0F, 0xFF])) == "00ab0fff")
        #expect(PushCenter.hex(Self.device) == Self.deviceHex)
    }

    // MARK: The session's sign-in hook

    @Test func signInHandlersRunForNewSessionsOnly() async {
        let storage = EmpireMemoryTokens()
        let auth = EmpireFakeTransport(data: SharedLoginTests.response(Self.token("account-a")))
        let session = EmpireSession(app: .empire, storage: storage, client: EmpireAuthClient(transport: auth),
                                    restoreOnLaunch: false)
        var signIns = 0
        session.onSignIn { signIns += 1 }
        await session.login(email: "member@example.invalid", password: "fictional-password")
        #expect(signIns == 1)
        await session.restore()                                      // renewal of the running session
        #expect(signIns == 1)
        storage.token = SharedLoginTests.token(account: "account-a", renewal: 1)
        await session.followSharedLogin()                            // same account renewed elsewhere
        #expect(signIns == 1)
        session.logOut()
        storage.token = Self.token("account-a")
        await session.restore()                                      // the saved login at launch
        #expect(signIns == 2)
        auth.status = 401
        await session.login(email: "member@example.invalid", password: "wrong")
        #expect(signIns == 2)                                        // a failed login starts nothing
    }
}
