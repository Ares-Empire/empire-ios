import Foundation
import Testing
@testable import Aresium

/// Which mode (`GET /api/mode`, remembered per account) and the data's lifecycle: logout keeps the phone's store,
/// another account gets its own, the central logout never deletes; only Leave Aresium, Delete Ares account (after the
/// server said yes) and Settings → "Delete Aresium data on this iPhone" do.
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

    /// A logged-in session (account `fictionalA`), its dashboard and mode store; nothing asked yet.
    private func setup(account: String = "fictionalA", mode: AresiumMode? = .phone,
                       defaults: UserDefaults = PhoneTest.defaults()) async -> Setup {
        let transport = RoutedTransport()
        let tokens = PhoneTokens()
        let marker = PhoneTest.defaults()
        let session = await PhoneTest.session(account, transport: transport, tokens: tokens, markerDefaults: marker)
        if let mode { transport.answer("GET /api/mode", 200, ["mode": mode.rawValue]) }
        let dashboard = DashboardStore(session: session, backend: nil)
        let storage = PhoneTest.storage()
        let modes = ModeStore(session: session, dashboard: dashboard, client: APIClient(transport: transport),
                              defaults: defaults, markerDefaults: marker, storage: storage,
                              makeEngine: { try PhoneTest.engine() })
        return Setup(transport: transport, session: session, tokens: tokens, dashboard: dashboard, modes: modes,
                     defaults: defaults, storage: storage, marker: marker)
    }

    /// Phone mode with a few payments imported.
    private func phoneWithData(_ s: Setup) async throws -> PhoneBackend {
        await s.modes.update()
        let phone = try #require(s.modes.phone)
        try await phone.choose("groceries")
        _ = try await phone.importFiles([PhoneTest.vrBank([("01.10.2026", "REWE Markt GmbH", "REWE", -2000),
                                                            ("02.10.2026", "Fiktiv Laden", "Einkauf", -500)])],
                                        auth: BackendAuth(token: nil))
        await s.dashboard.reload()
        return phone
    }

    // MARK: the mode

    @Test func phoneModeOpensTheAccountsOwnStoreAndAsksNothingElse() async throws {
        let s = await setup()
        await s.modes.update()
        #expect(s.modes.state == .phone("fictionalA"))
        #expect(s.dashboard.backend is PhoneBackend && s.modes.phone?.account == "fictionalA")
        #expect(s.modes.remembered(for: "fictionalA") == .phone)
        let asked = s.transport.requests(to: "GET /api/mode")
        #expect(asked.count == 1)
        #expect(asked.first?.url?.absoluteString == "https://aresium.de/api/mode")
        #expect(asked.first?.value(forHTTPHeaderField: "Authorization") == "Bearer \(PhoneTest.token("fictionalA"))")
        #expect(s.transport.requests.filter { $0.url?.host == "aresium.de" }.count == 1)   // only the mode
        #expect(s.storage.hasStore(for: "fictionalA"))
        // Asked once per session: following the session again asks nothing.
        await s.modes.update()
        #expect(s.transport.requests(to: "GET /api/mode").count == 1)
    }

    @Test func serverModeIsTodaysServer() async throws {
        let s = await setup(mode: .server)
        s.transport.answer("GET /api/data", 200, try JSONEncoder().encode(Dashboard.sample()))
        await s.modes.update()
        #expect(s.modes.state == .server && s.dashboard.backend is ServerBackend && s.modes.phone == nil)
        #expect(s.dashboard.dashboard?.transactions.count == 25)
        #expect(!s.storage.hasStore(for: "fictionalA"))
        #expect(s.transport.requests(to: "GET /api/data").first?.value(forHTTPHeaderField: "Authorization")
                == "Bearer \(PhoneTest.token("fictionalA"))")
    }

    @Test func unknownAndOfflineNeedsAConnectionThenTryAgain() async throws {
        let s = await setup(mode: nil)
        s.transport.offline = true
        await s.modes.update()
        #expect(s.modes.state == .needsConnection && s.session.isSignedIn && s.modes.phone == nil)
        s.transport.offline = false
        s.transport.answer("GET /api/mode", 200, ["mode": "phone"])
        await s.modes.retry()
        #expect(s.modes.state == .phone("fictionalA"))
    }

    @Test func knownAndOfflineUsesTheRememberedMode() async throws {
        let defaults = PhoneTest.defaults()
        defaults.set("phone", forKey: ModeStore.key(for: "fictionalA"))
        let s = await setup(mode: nil, defaults: defaults)
        s.transport.offline = true
        await s.modes.update()
        #expect(s.modes.state == .phone("fictionalA") && s.modes.phone != nil)
        #expect(s.session.isSignedIn)
    }

    @Test func aChangedAnswerSwitchesTheMode() async throws {
        let defaults = PhoneTest.defaults()
        defaults.set("phone", forKey: ModeStore.key(for: "fictionalA"))
        let s = await setup(mode: .server, defaults: defaults)
        s.transport.answer("GET /api/data", 200, try JSONEncoder().encode(Dashboard.sample()))
        await s.modes.update()
        #expect(s.modes.state == .server && s.modes.remembered(for: "fictionalA") == .server)
        #expect(s.storage.hasStore(for: "fictionalA"))           // opened first, never deleted
    }

    @Test func aRefusedLoginLogsOutAndNoAccessClosesTheApp() async throws {
        let refused = await setup(mode: nil)
        refused.transport.answer("GET /api/mode", 401, ["error": "No.", "code": "unauthorized"])
        await refused.modes.update()
        #expect(refused.session.token == nil && refused.tokens.token == nil && refused.modes.state == .signedOut)

        let denied = await setup(mode: nil)
        denied.transport.answer("GET /api/mode", 403, ["error": "No access to Aresium.", "code": "no_access"])
        await denied.modes.update()
        #expect(denied.session.isDenied && denied.modes.state == .signedOut && denied.tokens.token != nil)
    }

    @Test func offlineAtLaunchOpensThePhoneStoreOfTheSavedLogin() async throws {
        let defaults = PhoneTest.defaults()
        defaults.set("phone", forKey: ModeStore.key(for: "fictionalA"))
        let s = await setup(mode: nil, defaults: defaults)
        _ = try await phoneWithData(s)
        // A new launch without a connection: the saved login cannot be renewed.
        let session = EmpireSession(app: .aresium, storage: s.tokens, client: EmpireAuthClient(transport: s.transport),
                                    restoreOnLaunch: true, sharedDefaults: s.marker)
        s.transport.offline = true
        await session.restore()
        #expect(session.needsRestoreRetry && session.token == nil)
        let dashboard = DashboardStore(session: session, backend: nil)
        let modes = ModeStore(session: session, dashboard: dashboard, client: APIClient(transport: s.transport),
                              defaults: defaults, markerDefaults: s.marker, storage: s.storage,
                              makeEngine: { try PhoneTest.engine() })
        await modes.update()
        #expect(modes.state == .phone("fictionalA") && modes.isOffline)
        #expect(dashboard.dashboard?.transactions.count == 2)
        #expect(dashboard.widgetPublisher.store.load()?.account == "fictionalA")
        // Another app logged out meanwhile: on coming back the store closes (its data stays).
        LoginMarker.clear(in: s.marker)
        modes.followMarker()
        #expect(modes.state == .signedOut && modes.phone == nil && s.storage.hasStore(for: "fictionalA"))
    }

    @Test func filesWaitForTheModeAndNeverReachTheServerInPhoneMode() async throws {
        let s = await setup()
        let imports = ImportStore(dashboard: s.dashboard, background: PhoneActivity())
        imports.debugImport([PhoneTest.vrBank([("01.10.2026", "REWE Markt GmbH", "REWE", -2000)])])
        await imports.importPendingFiles()
        #expect(imports.waitingCount == 1 && s.transport.requests(to: "POST /api/import").isEmpty)
        await s.modes.update()
        await imports.sessionChanged()
        #expect(imports.waitingCount == 0 && s.modes.phone?.summary.payments == 1)
        #expect(s.transport.requests(to: "POST /api/import").isEmpty)
    }

    // MARK: the data's lifecycle

    @Test func logoutKeepsTheDataAndTheSameAccountFindsItAgain() async throws {
        let s = await setup()
        let phone = try await phoneWithData(s)
        let payments = phone.summary.payments
        s.session.logOut()
        #expect(s.modes.state == .signedOut && s.modes.phone == nil && s.dashboard.dashboard == nil)
        #expect(s.storage.hasStore(for: "fictionalA"))
        #expect(s.dashboard.widgetPublisher.store.load() == nil)          // nothing shown

        await PhoneTest.login(s.session, as: "fictionalA", transport: s.transport)
        await s.modes.update()
        #expect(s.modes.state == .phone("fictionalA") && s.modes.phone?.summary.payments == payments)
        #expect(s.dashboard.dashboard?.transactions.count == payments)
    }

    @Test func anotherAccountGetsItsOwnStore() async throws {
        let s = await setup()
        _ = try await phoneWithData(s)
        s.session.logOut()
        await PhoneTest.login(s.session, as: "fictionalB", transport: s.transport)
        await s.modes.update()
        #expect(s.modes.state == .phone("fictionalB") && s.modes.phone?.summary.payments == 0)
        #expect(s.storage.hasStore(for: "fictionalA") && s.storage.hasStore(for: "fictionalB"))
    }

    @Test func theCentralLogoutClosesButNeverDeletes() async throws {
        let s = await setup()
        _ = try await phoneWithData(s)
        LoginMarker.save("someoneElse", in: s.marker)          // another app: another account logged in
        s.session.followMarker()
        #expect(!s.session.isSignedIn && s.modes.state == .signedOut && s.modes.phone == nil)
        #expect(s.storage.hasStore(for: "fictionalA"))
        let reopened = try await PhoneTest.backend(account: "fictionalA", storage: s.storage)
        #expect(reopened.summary.payments == 2)
    }

    @Test func leavingAresiumDeletesThePhonesDataAfterTheServerSaidYes() async throws {
        let s = await setup()
        _ = try await phoneWithData(s)
        #expect(s.dashboard.widgetPublisher.store.load() != nil)
        s.transport.answer("POST /api/empire/leave", 200, ["services": ["empire"], "requested": [String]()])
        let flow = LeaveAppFlow(session: s.session, serverData: nil,
                                localData: { [modes = s.modes] in try await modes.deleteLocalData(reopen: false) })
        await flow.leave()
        #expect(flow.phase == .left && !flow.localDataFailed)
        #expect(!s.storage.hasStore(for: "fictionalA") && !FileManager.default.fileExists(atPath: s.storage.directory(for: "fictionalA").path))
        #expect(s.dashboard.widgetPublisher.store.load() == nil)
        #expect(s.session.isDenied && s.modes.state == .signedOut && s.tokens.token != nil)
    }

    @Test func aLeaveTheServerRefusesKeepsTheData() async throws {
        let s = await setup()
        _ = try await phoneWithData(s)
        s.transport.answer("POST /api/empire/leave", 503, Data())
        var ran = false
        let flow = LeaveAppFlow(session: s.session, serverData: nil, localData: { ran = true })
        await flow.leave()
        #expect(flow.phase == .failed(.unavailable) && !ran && s.storage.hasStore(for: "fictionalA"))
        #expect(s.modes.state == .phone("fictionalA"))
    }

    @Test func deletingTheAresAccountDeletesThePhonesData() async throws {
        let s = await setup()
        _ = try await phoneWithData(s)
        s.transport.answer("POST " + PhoneTest.login, 200, PhoneTest.loginAnswer("fictionalA"))
        s.transport.answer("DELETE /api/collections/users/records/fictionalA", 204, Data())
        let flow = DeleteAccountFlow(session: s.session,
                                     localData: { [modes = s.modes] in try await modes.deleteLocalData(reopen: false) })
        flow.password = "fictional-password"
        await flow.check()
        #expect(flow.phase == .confirming && s.storage.hasStore(for: "fictionalA"))   // nothing goes before the server
        await flow.delete()
        #expect(flow.phase == .deleted && !s.storage.hasStore(for: "fictionalA"))
        #expect(s.session.token == nil && s.modes.state == .signedOut)
    }

    @Test func aRefusedDeletionKeepsTheData() async throws {
        let s = await setup()
        _ = try await phoneWithData(s)
        s.transport.answer("POST " + PhoneTest.login, 200, PhoneTest.loginAnswer("fictionalA"))
        s.transport.answer("DELETE /api/collections/users/records/fictionalA", 500, Data())
        let flow = DeleteAccountFlow(session: s.session,
                                     localData: { [modes = s.modes] in try await modes.deleteLocalData(reopen: false) })
        flow.password = "fictional-password"
        await flow.check()
        await flow.delete()
        #expect(flow.phase == .failed(.other) && s.storage.hasStore(for: "fictionalA") && s.session.isSignedIn)
    }

    @Test func theSettingsRowDeletesAndStartsEmpty() async throws {
        let s = await setup()
        _ = try await phoneWithData(s)
        let data = PhoneDataModel(modes: s.modes)
        #expect(!data.canRestore)
        await data.deleteAll()
        #expect(data.problem == nil && s.modes.state == .phone("fictionalA"))
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
