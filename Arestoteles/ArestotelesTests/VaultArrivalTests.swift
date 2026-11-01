import Foundation
import Synchronization
import Testing
@testable import Arestoteles

@MainActor
struct VaultArrivalTests {
    @Test func aSlowRefreshAnswerNeverReplacesAnEdit() async throws {
        let h = try await makeStore()
        let gate = RequestGate()
        h.transport.gates["GET /vault"] = gate
        let refresh = Task { await h.store.refresh() }
        await gate.waitUntilPaused()
        try h.transport.answer("POST /edits", sample: "edit-result")
        #expect(await h.store.confirmPosition("Printing press#2") == .applied)
        gate.resume()
        await refresh.value
        #expect(h.store.vault?.commit == "b2c3d4e" && h.persistence.vault?.vault.commit == "b2c3d4e")
        #expect(h.store.index.position("Printing press#2")?.draft == false)
        await h.store.spotlightSettled()
        #expect(h.spotlight.calls.count == 1)
    }

    @Test func anOldRefreshStillHandlesAnAuthenticationFailure() async throws {
        let h = try await makeStore()
        let gate = RequestGate()
        h.transport.gates["GET /vault"] = gate
        h.transport.answer("GET /vault", 401, json: Data())
        let refresh = Task { await h.store.refresh() }
        await gate.waitUntilPaused()
        try h.transport.answer("POST /edits", sample: "edit-result")
        #expect(await h.store.confirmPosition("Printing press#2") == .applied)
        gate.resume()
        await refresh.value
        await h.store.persistenceSettled()
        #expect(!h.session.isSignedIn && h.store.vault == nil && h.persistence.vault == nil)
    }

    @Test func aLatePreparationCannotReplaceANewerVault() async throws {
        let preparation = PausedPreparation(commit: "a1b2c3d")
        let h = try await makeStore(preparation: preparation)
        let refresh = Task { await h.store.refresh() }
        await preparation.gate.waitUntilPaused()
        try h.transport.answer("POST /edits", sample: "edit-result")
        #expect(await h.store.confirmPosition("Printing press#2") == .applied)
        preparation.gate.resume()
        await refresh.value
        #expect(h.store.vault?.commit == "b2c3d4e" && h.persistence.vault?.vault.commit == "b2c3d4e")
        #expect(h.store.index.position("Printing press#2")?.draft == false)
        await h.store.spotlightSettled()
        #expect(h.spotlight.calls.count == 1)
    }

    @Test func anEditStillAppliesWhenARefreshFinishesWhileItIsOnTheWay() async throws {
        let h = try await makeStore()
        let gate = RequestGate()
        h.transport.gates["POST /edits"] = gate
        try h.transport.answer("POST /edits", sample: "edit-result")
        let edit = Task { await h.store.confirmPosition("Printing press#2") }
        await gate.waitUntilPaused()
        await h.store.refresh()
        #expect(h.store.vault?.commit == "a1b2c3d")
        gate.resume()
        #expect(await edit.value == .applied)
        #expect(h.store.vault?.commit == "b2c3d4e" && h.persistence.vault?.vault.commit == "b2c3d4e")
    }

    @Test func aLatePreparationCannotOutliveLogout() async throws {
        let preparation = PausedPreparation(commit: "a1b2c3d")
        let h = try await makeStore(preparation: preparation)
        let refresh = Task { await h.store.refresh() }
        await preparation.gate.waitUntilPaused()
        h.session.logOut()
        preparation.gate.resume()
        await refresh.value
        await h.store.persistenceSettled()
        await h.store.spotlightSettled()
        #expect(h.store.vault == nil && h.persistence.vault == nil)
        #expect(h.store.search.results("print").isEmpty && h.store.tabSearch.positions("print").isEmpty)
        #expect(h.spotlight.calls == [.removeAll])
    }

    @Test func aLateSavedVaultCannotOutliveLogout() async throws {
        let persistence = BlockingVaultFiles(cached: CachedVault(vault: try sampleVault(), etag: nil, account: "account-a"),
                                             blocksLoad: true)
        let session = await signedInSession()
        let store = VaultStore(session: session, backend: ArestotelesAPI(token: { session.token }),
                               persistence: persistence, spotlight: NoSpotlight(), savedAccount: { "account-a" })
        #expect(await eventually { persistence.entered.withLock { $0 } })
        session.logOut()
        persistence.release.signal()
        await store.loadingSettled()
        await store.persistenceSettled()
        #expect(store.vault == nil && persistence.memory.vault == nil)
    }

    @Test func startupLoadsTheCacheBeforeRenewingTheLogin() async throws {
        let persistence = BlockingVaultFiles(cached: CachedVault(vault: try sampleVault(), etag: nil, account: "account-a"),
                                             blocksLoad: true)
        let auth = authServer()
        let session = EmpireSession(app: .arestoteles, storage: MemoryTokens(token: fakeToken(account: "account-a")),
                                    client: EmpireAuthClient(transport: auth), restoreOnLaunch: false)
        auth.failure = URLError(.notConnectedToInternet)
        await session.restore()                              // retrying an offline launch starts the session
        auth.failure = nil
        let renewalsBeforeLoad = auth.requests.count
        let transport = FakeTransport()
        transport.failure = URLError(.notConnectedToInternet)
        let store = VaultStore(session: session, backend: ArestotelesAPI(transport: transport, token: { session.token }),
                               persistence: persistence, spotlight: NoSpotlight(), savedAccount: { "account-a" })
        #expect(await eventually { persistence.entered.withLock { $0 } })
        var started = false
        let update = Task { started = true; await store.update() }
        #expect(await eventually { started })
        #expect(auth.requests.count == renewalsBeforeLoad)
        persistence.release.signal()
        await update.value
        #expect(session.isSignedIn && store.isOffline && store.vault?.commit == "a1b2c3d")
    }

    @Test func aNewNoteQueuedDuringLoadSurvivesAnOldAccountsCache() async throws {
        let persistence = BlockingVaultFiles(cached: CachedVault(vault: try sampleVault(), etag: nil, account: "account-b"),
                                             blocksLoad: true)
        persistence.memory.quickNotes = [PendingQuickNote(text: "old account")]
        let session = await signedInSession()
        let transport = FakeTransport()
        try transport.answer("POST /edits", sample: "edit-result")
        let store = VaultStore(session: session, backend: ArestotelesAPI(transport: transport, token: { session.token }),
                               persistence: persistence, spotlight: NoSpotlight(), savedAccount: { "account-a" })
        #expect(await eventually { persistence.entered.withLock { $0 } })
        #expect(store.queueQuickNote("new account") == .queued)
        persistence.release.signal()
        await store.quickNotesSettled()
        #expect(try transport.edits().map { $0["text"] as? String } == ["new account"])
        #expect(store.pendingQuickNotes.isEmpty && persistence.memory.quickNotes.isEmpty)
    }

    @Test func logoutDeletionFollowsAnAlreadyWritingVault() async throws {
        let persistence = BlockingVaultFiles(blocksLoad: false)
        let session = await signedInSession()
        let transport = FakeTransport()
        try transport.answer("GET /vault", sample: "vault")
        let spotlight = FakeSpotlight()
        let store = VaultStore(session: session, backend: ArestotelesAPI(transport: transport, token: { session.token }),
                               persistence: persistence, spotlight: spotlight, savedAccount: { "account-a" })
        let refresh = Task { await store.refresh() }
        #expect(await eventually { persistence.entered.withLock { $0 } })
        #expect(store.vault != nil)                            // assignment is independent of the ongoing write
        session.logOut()
        persistence.release.signal()
        await refresh.value
        await store.persistenceSettled()
        await store.spotlightSettled()
        #expect(store.vault == nil && persistence.memory.vault == nil)
        #expect(spotlight.calls.last == .removeAll)
    }
}

/// Pauses after an answer arrived, at the preparation suspension, without depending on machine speed.
@MainActor
private final class PausedPreparation: VaultPreparing {
    let gate = RequestGate()
    let commit: String
    let worker = VaultWorker(persistence: MemoryPersistence())
    init(commit: String) { self.commit = commit }
    func prepare(_ vault: Vault, previous: Vault?) async -> VaultWorker.Prepared {
        let result = await worker.prepare(vault, previous: previous)
        if vault.commit == commit { await gate.pause() }
        return result
    }
}

/// Blocks only the worker queue; the main actor remains free to log out. Never used with real files or a real login.
nonisolated private final class BlockingVaultFiles: VaultPersistence {
    let memory: MemoryPersistence
    let blocksLoad: Bool
    let entered = Mutex(false)
    let release = DispatchSemaphore(value: 0)
    init(cached: CachedVault? = nil, blocksLoad: Bool) {
        memory = MemoryPersistence(vault: cached)
        self.blocksLoad = blocksLoad
    }
    func loadVault() -> CachedVault? {
        let cached = memory.loadVault()
        if blocksLoad { block() }
        return cached
    }
    func saveVault(_ cached: CachedVault) throws {
        if !blocksLoad { block() }
        try memory.saveVault(cached)
    }
    private func block() { entered.withLock { $0 = true }; release.wait() }
    func deleteVault() throws { try memory.deleteVault() }
    func loadQuickNotes() -> [PendingQuickNote] { memory.loadQuickNotes() }
    func saveQuickNotes(_ notes: [PendingQuickNote]) throws { try memory.saveQuickNotes(notes) }
    func deleteAll() throws { try memory.deleteAll() }
}
