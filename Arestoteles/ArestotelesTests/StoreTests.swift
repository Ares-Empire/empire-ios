import Foundation
import Testing
@testable import Arestoteles

/// The store's vault: from the disk first, then the server (304 when current), offline, and the login rules (401 logs
/// out everywhere, 403 closes this app, answers after a logout are dropped; both forget the vault on disk and in
/// Spotlight).
@MainActor
struct StoreTests {
    private func saved(account: String? = "account-a", etag: String? = "\"a1b2c3d\"") throws -> MemoryPersistence {
        MemoryPersistence(vault: CachedVault(vault: try sampleVault(), etag: etag, account: account))
    }

    @Test func theSavedVaultShowsBeforeAnyRequest() async throws {
        let persistence = try saved()
        let h = try await makeStore(persistence: persistence)
        #expect(h.store.vault?.commit == "a1b2c3d" && h.transport.requests.isEmpty)
        #expect(h.store.index.note("Printing press")?.title == "Printing press")
        #expect(!h.store.search.results("Druckort").isEmpty)
        await h.store.spotlightSettled()
        #expect(h.spotlight.calls.isEmpty)                         // indexed when it was first loaded
    }

    @Test func aCurrentVaultIsNotDownloadedAgain() async throws {
        let h = try await makeStore(persistence: try saved())
        h.transport.answer("GET /vault", 304, json: Data())
        await h.store.refresh()
        #expect(h.transport.requests.only?.value(forHTTPHeaderField: "If-None-Match") == "\"a1b2c3d\"")
        #expect(h.store.vault?.commit == "a1b2c3d" && h.store.lastRefresh != nil && !h.store.isOffline)
        await h.store.spotlightSettled()
        #expect(h.spotlight.calls.isEmpty)
    }

    @Test func aNewVaultReplacesTheSavedOne() async throws {
        let h = try await makeStore(persistence: try saved(etag: "\"0000000\""))
        let newer = try sample(EditResult.self, "edit-result").vault
        try h.transport.answer("GET /vault", encoding: newer)
        h.transport.routes["GET /vault"]?.headers = ["ETag": "\"b2c3d4e\""]
        await h.store.refresh()
        #expect(h.store.vault?.commit == "b2c3d4e")
        #expect(h.store.index.position("Printing press#2")?.draft == false)
        #expect(h.persistence.vault == CachedVault(vault: newer, etag: "\"b2c3d4e\"", account: "account-a"))
        await h.store.spotlightSettled()
        #expect(h.spotlight.calls == [.replace(newer.notes.map(\.id))])

        h.transport.answer("GET /vault", 304, json: Data())
        await h.store.refresh()
        #expect(h.transport.requests.last?.value(forHTTPHeaderField: "If-None-Match") == "\"b2c3d4e\"")
    }

    @Test func theFirstLoadWithoutASavedVault() async throws {
        let h = try await makeStore()
        #expect(h.store.vault == nil)
        await h.store.refresh()
        #expect(h.store.vault?.notes.count == 12 && h.store.loadError == nil)
        #expect(h.transport.requests.only?.value(forHTTPHeaderField: "If-None-Match") == nil)
        #expect(h.persistence.vault?.etag == "\"a1b2c3d\"" && h.persistence.vault?.account == "account-a")
    }

    @Test func anotherAccountsVaultIsDeletedNotShown() async throws {
        let persistence = try saved(account: "account-b")
        persistence.quickNotes = [PendingQuickNote(text: "someone else's")]
        let h = try await makeStore(persistence: persistence)
        #expect(h.store.vault == nil && h.store.pendingQuickNotes.isEmpty)
        #expect(persistence.vault == nil && persistence.quickNotes.isEmpty)
    }

    @Test func aVaultLeftAfterALogoutElsewhereIsDeleted() async throws {
        let persistence = try saved()
        let h = try await makeStore(persistence: persistence, savedAccount: nil)
        #expect(h.store.vault == nil && persistence.vault == nil)
    }

    @Test func offlineKeepsTheSavedVault() async throws {
        let h = try await makeStore(persistence: try saved())
        h.transport.failure = URLError(.notConnectedToInternet)
        await h.store.refresh()
        #expect(h.store.isOffline && h.store.loadError == nil && h.store.vault?.commit == "a1b2c3d")
        h.transport.failure = nil
        h.transport.answer("GET /vault", 304, json: Data())
        await h.store.refresh()
        #expect(!h.store.isOffline)
    }

    @Test func aServerErrorIsShownNotTakenForOffline() async throws {
        let h = try await makeStore()
        h.transport.answer("GET /vault", 500, json: Data(#"{"error":"Made-up failure"}"#.utf8))
        await h.store.refresh()
        #expect(h.store.vault == nil && h.store.loadError == "Made-up failure" && !h.store.isOffline)
    }

    /// The account server cannot be reached at launch: the login waits, the saved vault stays on screen, and the app
    /// catches up once the account server answers again.
    @Test func anOfflineLaunchShowsTheSavedVaultUntilTheLoginIsBack() async throws {
        let auth = authServer()
        auth.failure = URLError(.notConnectedToInternet)
        let storage = MemoryTokens(token: fakeToken(account: "account-a"))
        let session = EmpireSession(app: .arestoteles, storage: storage, client: EmpireAuthClient(transport: auth))
        let h = try await makeStore(session: session, persistence: try saved())
        await session.restore()
        #expect(session.needsRestoreRetry && !session.isSignedIn)
        #expect(h.store.vault?.commit == "a1b2c3d")

        await h.store.update()
        #expect(h.store.isOffline && h.transport.requests.isEmpty)
        #expect(await h.store.confirmPosition("Printing press#2") == .failed(VaultStore.offlineMessage))

        auth.failure = nil
        h.transport.answer("GET /vault", 304, json: Data())
        await h.store.update()
        #expect(session.isSignedIn && !h.store.isOffline && h.transport.requests("GET /vault").count == 1)
    }

    @Test func theForegroundRefreshesOnlyAnOldVault() async throws {
        let h = try await makeStore()
        await h.store.update()
        #expect(h.transport.requests.count == 1)
        await h.store.update(now: .now.addingTimeInterval(10), minimumAge: 30)
        #expect(h.transport.requests.count == 1)
        h.transport.answer("GET /vault", 304, json: Data())
        await h.store.update(now: .now.addingTimeInterval(40), minimumAge: 30)
        #expect(h.transport.requests.count == 2)
    }

    @Test func anOldLoginIsRenewedFirst() async throws {
        let auth = authServer()
        let session = await signedInSession(auth: auth)
        let h = try await makeStore(session: session)
        let renewals = auth.requests.count
        await h.store.update(now: .now.addingTimeInterval(13 * 3600))
        #expect(auth.requests.count == renewals + 1 && h.store.vault != nil)
    }

    // MARK: login rules

    @Test func unauthorizedLogsOutAndForgetsEverything() async throws {
        let storage = MemoryTokens()
        let persistence = try saved()
        persistence.quickNotes = [PendingQuickNote(text: "waiting")]
        let h = try await makeStore(session: await signedInSession(storage: storage), persistence: persistence)
        #expect(h.store.pendingQuickNotes.count == 1)
        h.transport.answer("GET /vault", 401, json: Data())
        await h.store.refresh()
        #expect(!h.session.isSignedIn && storage.token == nil)
        #expect(h.store.vault == nil && h.store.pendingQuickNotes.isEmpty && h.store.loadError == nil)
        #expect(persistence.vault == nil && persistence.quickNotes.isEmpty)
        await h.store.spotlightSettled()
        #expect(h.spotlight.calls == [.removeAll])
    }

    @Test func forbiddenClosesOnlyThisApp() async throws {
        let storage = MemoryTokens()
        let h = try await makeStore(session: await signedInSession(storage: storage), persistence: try saved())
        h.transport.answer("GET /vault", 403, json: Data(#"{"error":"No arestoteles service."}"#.utf8))
        await h.store.refresh()
        #expect(h.session.isDenied && h.session.access == .denied("No arestoteles service."))
        #expect(storage.token != nil)                              // the other apps keep the login
        #expect(h.store.vault == nil && h.persistence.vault == nil)
    }

    @Test func answersAfterALogoutAreDropped() async throws {
        let h = try await makeStore()
        let gate = RequestGate()
        h.transport.gates["GET /vault"] = gate
        let load = Task { await h.store.refresh() }
        await gate.waitUntilPaused()
        h.session.logOut()
        gate.resume()
        await load.value
        #expect(h.store.vault == nil && h.persistence.vault == nil && !h.store.isRefreshing)
    }

    @Test func refreshingDeduplicates() async throws {
        let h = try await makeStore()
        let gate = RequestGate()
        h.transport.gates["GET /vault"] = gate
        let load = Task { await h.store.refresh() }
        await gate.waitUntilPaused()
        await h.store.refresh()
        #expect(h.store.isRefreshing && h.transport.requests.count == 1)
        gate.resume()
        await load.value
        #expect(h.store.vault != nil && !h.store.isRefreshing)
    }

    @Test func filesSurviveARestartAndLogoutDeletesThem() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "arestoteles-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let files = FilePersistence(directory: directory)
        #expect(files.loadVault() == nil && files.loadQuickNotes().isEmpty)
        let cached = CachedVault(vault: try sampleVault(), etag: "\"a1b2c3d\"", account: "account-a")
        let note = PendingQuickNote(text: "paper first?", created: Date(timeIntervalSince1970: 1_790_000_000))
        try files.saveVault(cached)
        try files.saveQuickNotes([note])
        let reopened = FilePersistence(directory: directory)
        #expect(reopened.loadVault() == cached && reopened.loadQuickNotes() == [note])
        try reopened.saveQuickNotes([])
        #expect(reopened.loadQuickNotes().isEmpty)
        try reopened.deleteAll()
        try reopened.deleteAll()                                   // nothing left: still fine
        #expect(reopened.loadVault() == nil)
    }
}
