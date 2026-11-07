import Foundation
import Testing
@testable import Aresium

/// Aresium without an account (brief 22): phone mode on the phone's one store from the launch, no login needed; server
/// mode only for an owner's login (`GET /api/mode` says `server`); every other answer, refusal or error is phone mode;
/// a login ending anywhere goes back to the phone's store, which no login, logout, leaving or account deletion touches.
/// Only Settings → "Delete Aresium data on this iPhone" deletes it.
@MainActor
struct PhoneModeTests {
    private struct Setup {
        let transport: RoutedTransport
        let session: EmpireSession
        let tokens: PhoneTokens
        let dashboard: DashboardStore
        let modes: ModeStore
        let defaults: UserDefaults
        let storage: PhoneStorage
        let marker: UserDefaults
    }

    /// A session (logged in as `account`, or nobody), its dashboard and mode store; nothing opened or asked yet.
    private func setup(account: String? = nil, services: [String] = ["empire", "aresium"], mode: AresiumMode? = .phone,
                       defaults: UserDefaults = PhoneTest.defaults(), marker: UserDefaults = PhoneTest.defaults(),
                       storage: PhoneStorage = PhoneTest.storage()) async -> Setup {
        let transport = RoutedTransport()
        let tokens = PhoneTokens()
        let session = await PhoneTest.session(account, services: services, transport: transport, tokens: tokens,
                                              markerDefaults: marker)
        if let mode { transport.answer("GET /api/mode", 200, ["mode": mode.rawValue]) }
        let dashboard = DashboardStore(session: session, backend: nil)
        let modes = ModeStore(session: session, dashboard: dashboard, client: APIClient(transport: transport),
                              defaults: defaults, markerDefaults: marker, storage: storage,
                              makeEngine: { try PhoneTest.engine() })
        return Setup(transport: transport, session: session, tokens: tokens, dashboard: dashboard, modes: modes,
                     defaults: defaults, storage: storage, marker: marker)
    }

    /// The launch's two steps: the phone's store opens at once, then the session (restored) is followed.
    private func launch(_ s: Setup) async {
        await s.modes.start()
        await s.modes.update()
    }

    /// Phone mode with two payments imported.
    private func phoneWithData(_ s: Setup) async throws -> PhoneBackend {
        await launch(s)
        let phone = try #require(s.modes.phone)
        try await phone.choose("groceries")
        _ = try await phone.importFiles([PhoneTest.vrBank([("01.10.2026", "REWE Markt GmbH", "REWE", -2000),
                                                            ("02.10.2026", "Fiktiv Laden", "Einkauf", -500)])],
                                        auth: BackendAuth(token: nil))
        await s.dashboard.reload()
        return phone
    }

    private func serverAnswers(_ s: Setup) throws {
        s.transport.answer("GET /api/data", 200, try JSONEncoder().encode(Dashboard.sample()))
    }

    // MARK: no login

    @Test func launchWithoutALoginOpensThePhonesOwnStore() async throws {
        let s = await setup()
        await launch(s)
        #expect(s.modes.state == .phone && s.dashboard.backend is PhoneBackend && s.modes.phone != nil)
        #expect(s.storage.hasStore && s.storage.directory.lastPathComponent == "local")
        #expect(s.session.token == nil && s.transport.requests.isEmpty)          // nothing asked of any server
        #expect(s.dashboard.dashboard != nil)
    }

    // MARK: logins

    @Test func theOwnersLoginOpensServerMode() async throws {
        let s = await setup(account: "fictionalA", mode: .server)
        try serverAnswers(s)
        await launch(s)
        #expect(s.modes.state == .server && s.dashboard.backend is ServerBackend && s.modes.phone == nil)
        #expect(s.dashboard.dashboard?.transactions.count == 25)
        #expect(s.modes.remembered(for: "fictionalA") == .server)
        let asked = s.transport.requests(to: "GET /api/mode")
        #expect(asked.count == 1 && asked.first?.url?.absoluteString == "https://aresium.de/api/mode")
        #expect(asked.first?.value(forHTTPHeaderField: "Authorization") == "Bearer \(PhoneTest.token("fictionalA"))")
        #expect(s.dashboard.widgetPublisher.store.load()?.account == "fictionalA")
        // Asked once per session: following the session again asks nothing.
        await s.modes.update()
        #expect(s.transport.requests(to: "GET /api/mode").count == 1)
    }

    @Test func anotherLoginStaysOnTheSameLocalStore() async throws {
        let s = await setup()
        let phone = try await phoneWithData(s)
        // A friend logs in (in another app, say) with an account that has Aresium: the server says phone.
        await PhoneTest.login(s.session, as: "fictionalB", transport: s.transport)
        await s.modes.update()
        #expect(s.modes.state == .phone && s.modes.phone === phone && phone.summary.payments == 2)
        #expect(s.transport.requests(to: "GET /api/mode").count == 1 && s.modes.remembered(for: "fictionalB") == .phone)
        #expect(s.transport.requests.filter { $0.url?.host == "aresium.de" }.count == 1)    // only the mode
        // An account without Aresium: nothing is asked, Aresium opens all the same.
        s.session.logOut()
        await PhoneTest.login(s.session, as: "fictionalC", services: ["empire", "arestemis"], transport: s.transport)
        await s.modes.update()
        #expect(s.session.isSignedIn && !s.session.isDenied)
        #expect(s.modes.state == .phone && s.modes.phone === phone && s.transport.requests(to: "GET /api/mode").count == 1)
    }

    @Test func aLogoutElsewhereGoesBackToThePhone() async throws {
        let s = await setup(mode: .server)
        _ = try await phoneWithData(s)
        try serverAnswers(s)
        await PhoneTest.login(s.session, as: "fictionalA", transport: s.transport)
        await s.modes.update()
        #expect(s.modes.state == .server && s.dashboard.widgetPublisher.store.load()?.account == "fictionalA")
        // Another Ares app logged out (the central logout's marker), seen on coming back to the foreground.
        LoginMarker.clear(in: s.marker)
        s.session.followMarker()
        await s.modes.update()
        #expect(s.session.token == nil && s.modes.state == .phone && s.dashboard.backend is PhoneBackend)
        #expect(s.modes.phone?.summary.payments == 2 && s.dashboard.dashboard?.transactions.count == 2)
        let widget = try #require(s.dashboard.widgetPublisher.store.load())
        #expect(widget.phone && widget.account == nil)                // the server's numbers went, the phone's came
        // The owner logs in again (the remembered server), then out here.
        await PhoneTest.login(s.session, as: "fictionalA", transport: s.transport)
        await s.modes.update()
        #expect(s.modes.state == .server)
        s.session.logOut()
        await s.modes.update()
        #expect(s.modes.state == .phone && s.modes.phone?.summary.payments == 2)
    }

    @Test func refusalsAndErrorsMeanPhoneMode() async throws {
        // 401: the login is refused (it ends everywhere): phone mode.
        let refused = await setup(account: "fictionalA", mode: nil)
        refused.transport.answer("GET /api/mode", 401, ["error": "No.", "code": "unauthorized"])
        await launch(refused)
        #expect(refused.session.token == nil && refused.tokens.token == nil && refused.modes.state == .phone)

        // 403: this account's data is not on the server: phone mode, remembered; the login stays for the other apps.
        let denied = await setup(account: "fictionalA", mode: nil)
        denied.transport.answer("GET /api/mode", 403, ["error": "No access to Aresium.", "code": "no_access"])
        await launch(denied)
        #expect(denied.modes.state == .phone && denied.modes.remembered(for: "fictionalA") == .phone)
        #expect(denied.tokens.token != nil && denied.session.isSignedIn)

        // Offline without a remembered answer: phone mode; the next foreground asks again.
        let offline = await setup(account: "fictionalA", mode: nil)
        offline.transport.offline = true
        await launch(offline)
        #expect(offline.modes.state == .phone && offline.modes.remembered(for: "fictionalA") == nil)
        offline.transport.offline = false
        offline.transport.answer("GET /api/mode", 200, ["mode": "server"])
        try serverAnswers(offline)
        await offline.modes.update()
        #expect(offline.modes.state == .server)
    }

    @Test func aRememberedServerAnswerWorksOfflineAlsoAtLaunch() async throws {
        let defaults = PhoneTest.defaults()
        defaults.set("server", forKey: ModeStore.key(for: "fictionalA"))
        // Logged in, but Aresium's server cannot be asked: the remembered server mode.
        let online = await setup(account: "fictionalA", mode: nil, defaults: defaults)
        online.transport.answer("GET /api/data", 503, Data())
        online.transport.routes["GET /api/mode"] = nil
        online.transport.offline = true
        await launch(online)
        #expect(online.modes.state == .server)

        // A new launch without any connection: the saved login cannot be renewed yet, its account was in server mode.
        let marker = PhoneTest.defaults()
        marker.set(true, forKey: FirstLaunchTokenReset.key)          // not a fresh install: the saved login stays
        LoginMarker.save("fictionalA", in: marker)
        let s = await setup(mode: nil, defaults: defaults, marker: marker)
        #expect(s.modes.state == .server && s.dashboard.backend is ServerBackend)    // from the first frame
        s.tokens.token = PhoneTest.token("fictionalA")
        s.transport.offline = true
        await s.session.restore()
        #expect(s.session.needsRestoreRetry && s.session.token == nil)
        await launch(s)
        #expect(s.modes.state == .server && s.transport.requests(to: "GET /api/data").isEmpty)   // no login to ask with
        // Another app logged out meanwhile: on coming back, the phone's store.
        LoginMarker.clear(in: marker)
        s.modes.followMarker()
        await s.modes.update()
        #expect(s.modes.state == .phone && s.dashboard.backend is PhoneBackend)
    }

    @Test func filesWaitForThePhonesStoreAndNeverReachTheServer() async throws {
        let s = await setup(account: "fictionalA")
        let imports = ImportStore(dashboard: s.dashboard, background: PhoneActivity())
        imports.debugImport([PhoneTest.vrBank([("01.10.2026", "REWE Markt GmbH", "REWE", -2000)])])
        await imports.importAndWait()
        #expect(imports.waitingCount == 1 && s.transport.requests(to: "POST /api/import").isEmpty)
        await launch(s)
        await imports.sessionChanged()
        #expect(imports.waitingCount == 0 && s.modes.phone?.summary.payments == 1)
        #expect(s.transport.requests(to: "POST /api/import").isEmpty)
    }

    // MARK: the data's lifecycle

    @Test func leavingAresiumKeepsThePhonesData() async throws {
        let s = await setup(account: "fictionalA")
        let phone = try await phoneWithData(s)
        s.transport.answer("POST /api/empire/leave", 200, ["services": ["empire"], "requested": [String]()])
        let flow = LeaveAppFlow(session: s.session, serverData: nil)
        await flow.leave()
        await s.modes.update()
        #expect(flow.phase == .left && !s.session.isDenied && s.tokens.token != nil)
        #expect(s.modes.state == .phone && s.modes.phone === phone && phone.summary.payments == 2 && s.storage.hasStore)
        #expect(s.dashboard.widgetPublisher.store.load()?.phone == true)
    }

    @Test func theOwnerLeavingAresiumGoesBackToThePhone() async throws {
        let s = await setup(account: "fictionalA", mode: .server)
        try serverAnswers(s)
        await launch(s)
        #expect(s.modes.state == .server)
        s.transport.answer("POST /api/empire/leave", 200, ["services": ["empire"], "requested": [String]()])
        await LeaveAppFlow(session: s.session, serverData: nil).leave()
        await s.modes.update()                          // the app follows `session.services`
        #expect(s.modes.state == .phone && s.dashboard.backend is PhoneBackend)
    }

    @Test func deletingTheAresAccountKeepsThePhonesData() async throws {
        let s = await setup(account: "fictionalA")
        let phone = try await phoneWithData(s)
        s.transport.answer("POST " + PhoneTest.login, 200, PhoneTest.loginAnswer("fictionalA"))
        s.transport.answer("DELETE /api/collections/users/records/fictionalA", 204, Data())
        let flow = DeleteAccountFlow(session: s.session)
        flow.password = "fictional-password"
        await flow.check()
        await flow.delete()
        await s.modes.update()
        #expect(flow.phase == .deleted && s.session.token == nil)
        #expect(s.modes.state == .phone && s.modes.phone === phone && phone.summary.payments == 2 && s.storage.hasStore)
    }

    @Test func theSettingsRowDeletesAndStartsEmpty() async throws {
        let s = await setup()
        _ = try await phoneWithData(s)
        let data = PhoneDataModel(modes: s.modes)
        #expect(!data.canRestore)
        await data.deleteAll()
        #expect(data.problem == nil && s.modes.state == .phone)
        #expect(s.modes.phone?.summary.payments == 0 && s.modes.phone?.summary.chosen.isEmpty == true)
        #expect(data.canRestore)
        #expect(s.dashboard.widgetPublisher.store.load() == nil)
        #expect(s.dashboard.dashboard?.transactions.isEmpty == true)
    }

    @Test func exportWritesOneFileForTheShareSheetAndCleansUp() async throws {
        let s = await setup()
        _ = try await phoneWithData(s)
        let directory = PhoneTest.storage().root
        let data = PhoneDataModel(modes: s.modes, directory: directory)
        await data.export()
        let file = try #require(data.exportFile)
        #expect(file.url.lastPathComponent.hasPrefix("Aresium-") && file.url.pathExtension == "json")
        let export = try LedgerExport.decode(Data(contentsOf: file.url))
        #expect(export.payments.count == 2 && export.accounts.count == 1)
        data.exportClosed()
        #expect(data.exportFile == nil && !FileManager.default.fileExists(atPath: file.url.path))
    }
}
