import Foundation
import Testing
@testable import Arestemis

/// `-sampleData`: the samples behave like a server in memory, so every screen's actions can be tried without one.
@MainActor
struct SampleBackendTests {
    private func store(_ options: SampleBackend.Options = .init()) async throws -> ArestemisStore {
        let session = EmpireSession(app: .arestemis, storage: MemoryTokens(), restoreOnLaunch: false)
        let store = ArestemisStore(session: session, backend: try SampleBackend(options: options), sample: true,
                                   placeDelay: .zero)
        await store.reloadOverview()
        return store
    }

    @Test func theSampleIsFresh() async throws {
        let store = try await store()
        let lastScan = try #require(store.overview?.lastScan.flatMap(Timestamp.parse))
        #expect(abs(Date.now.timeIntervalSince(lastScan) - 40) < 5)
        #expect(store.hunt?.active == true && store.latest.map(\.id) == [41, 40, 38])
        #expect(store.overview?.sources.allSatisfy { $0.state == .ok } == true)
    }

    @Test func pausedAndNoHunt() async throws {
        let paused = try await store(.init(paused: true))
        #expect(paused.hunt?.active == false && paused.overview?.sources.allSatisfy { $0.state == .idle } == true)
        let none = try await store(.init(noHunt: true))
        #expect(none.hunt == nil && none.latest.isEmpty && none.overview?.counts == .init(new: 0, today: 0, saved: 0, applied: 0))
    }

    @Test func actionsWorkInMemory() async throws {
        let store = try await store()
        await store.setState(.saved, for: 41)
        #expect(store.match(41)?.state == .saved && store.overview?.counts.new == 4 && store.overview?.counts.saved == 2)
        await store.setHuntActive(false)
        #expect(store.hunt?.active == false && store.overview?.sources.first?.state == .idle)
        await store.loadMatches(.saved)
        #expect(store.matches(.saved).map(\.id) == [41, 40])
        await store.loadRejected()
        #expect(store.rejected.count == 2)
    }

    @Test func searchesAreCreatedPausedAndDeleted() async throws {
        let store = try await store(.init(noHunt: true))
        let search = try #require(try sample(Overview.self, "overview").hunt?.search.flat)
        #expect(await store.saveSearch(search))
        #expect(store.hunt?.active == false && store.hunt?.search.flat == search)
        #expect(await store.deleteSearch())
        #expect(store.hunt == nil)
    }

    @Test func applicationsFollowTheMode() async throws {
        let store = try await store()
        await store.loadSettings()
        await store.loadApplication(for: 41)
        let written = try #require(store.application(41).application)
        #expect(written.mode == .ai && written.text.contains("Helle 2-Zimmer-Wohnung mit Balkon in Schwabing"))
        #expect(written.text.contains(try #require(store.settings?.applicationNotes)))     // the notes are in it
        var settings = try #require(store.settings)
        settings.applicationMode = .own
        await store.saveSettings(settings)
        await store.loadApplication(for: 41)
        #expect(store.application(41).application?.mode == .own)
        #expect(store.application(41).application?.text == settings.ownText)
    }

    /// Settings → Application's screenshots: the switch off, and nothing written yet.
    @Test func applicationSettingsForScreenshots() async throws {
        let own = try await store(.init(ownMode: true))
        await own.loadSettings()
        #expect(own.settings?.applicationMode == .own && own.settings?.ownText.isEmpty == false)
        let empty = try await store(.init(noTexts: true))
        await empty.loadSettings()
        let settings = try #require(empty.settings)
        #expect(settings.ownText.isEmpty && settings.applicationNotes.isEmpty && settings.aboutMe.isEmpty)
    }

    @Test func placesAndDescribeIt() async throws {
        let store = try await store()
        store.places.update("garch")
        await store.places.settle()
        #expect(store.places.results.map(\.id) == ["wg:400", "wg:401"])
        store.places.update("munch")                                // without the umlaut
        await store.places.settle()
        #expect(store.places.results.map(\.name) == ["München", "Garching bei München"])
        let parsed = await store.parse("2-room flat in Schwabing")
        #expect(parsed?.search.kinds == [.flat, .wg] && parsed?.search.people == 2 && parsed?.unclear.isEmpty == false)
    }
}
