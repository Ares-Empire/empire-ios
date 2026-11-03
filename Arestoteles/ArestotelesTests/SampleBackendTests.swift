import Foundation
import Testing
@testable import Arestoteles

/// `-sampleData`: the samples behave like a server in memory, so every screen and action can be tried without one.
@MainActor
struct SampleBackendTests {
    private func store(_ options: SampleBackend.Options = .init(), saved: CachedVault? = nil) throws
        -> (VaultStore, MemoryPersistence) {
        let session = EmpireSession(app: .arestoteles, storage: MemoryTokens(), restoreOnLaunch: false)
        let persistence = MemoryPersistence(vault: saved)
        let store = VaultStore(session: session, backend: try SampleBackend(options: options), persistence: persistence,
                               spotlight: NoSpotlight(), savedAccount: { nil }, sample: true)
        return (store, persistence)
    }

    @Test func theSampleLoadsAndIsThenCurrent() async throws {
        let (store, _) = try store()
        await store.update()
        #expect(store.vault?.commit == "a1b2c3d" && store.lastRefresh != nil)
        await store.update()                                      // 304 now
        #expect(store.vault?.commit == "a1b2c3d" && !store.isOffline)
    }

    @Test func editsAnswerWithTheSampleResult() async throws {
        let (store, _) = try store()
        await store.update()
        #expect(await store.confirmPosition("Printing press#2", version: sampleVersion("Printing press#2")) == .applied)
        #expect(store.vault?.commit == "b2c3d4e" && store.notice == nil)
        await store.update()
        #expect(store.vault?.commit == "b2c3d4e")                 // the sample server kept the edit
    }

    @Test func conflictInvalidAndPushLater() async throws {
        let (conflict, _) = try store(.init(conflict: true))
        await conflict.update()
        #expect(await conflict.confirmPosition("Printing press#2", version: sampleVersion("Printing press#2")) == .conflict)
        let (invalid, _) = try store(.init(invalid: true))
        await invalid.update()
        #expect(await invalid.rewordPosition("Positions#1", text: "x", version: sampleVersion("Positions#1")) == .invalid("A position must be one sentence."))
        let (later, _) = try store(.init(pushLater: true))
        await later.update()
        #expect(later.queueQuickNote("a thought") == .queued)
        await later.quickNotesSettled()
        #expect(later.notice?.tone == .info)
    }

    @Test func offlineShowsTheSavedSample() async throws {
        let (store, _) = try store(.init(offline: true), saved: try SampleBackend.savedVault())
        await store.loadingSettled()
        #expect(store.vault?.commit == "a1b2c3d")
        await store.update()
        #expect(store.isOffline && store.vault != nil)
        #expect(store.queueQuickNote("on the train") == .queued)
        await store.quickNotesSettled()
    }

    @Test func discussedSampleDisappearsAndUndoBringsItBack() async throws {
        let (store, _) = try store()
        await store.update()
        let note = try #require(store.index.openDiscussions.first?.id)
        let offer = try #require(await store.markDiscussed(of: note, version: sampleVersion(note)))
        #expect(!store.index.openDiscussions.contains { $0.id == note })
        let undo = try #require(offer.undo)
        await undo()
        #expect(store.index.openDiscussions.contains { $0.id == note })
    }

    @Test func sourcesForEveryNote() async throws {
        let backend = try SampleBackend()
        #expect(try await backend.source(note: "Spread of print").markdown.hasPrefix("# Spread of print"))
        let made = try await backend.source(note: "Printing press")
        #expect(made.version == "3f2a9c1e4b7d8a0f6e5c2b1a9d8e7f6c5b4a3921" && made.markdown.contains("[!summary]"))
        await #expect(throws: HTTPError.self) { try await backend.source(note: "Nope") }
    }
}
