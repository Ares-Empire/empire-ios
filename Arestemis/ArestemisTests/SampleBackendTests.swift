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
        #expect(store.card(1)?.hunt.active == true && store.latest.map(\.id) == [41, 40, 38])
        // Every site an active hunt reads answered; mydealz and MTB-News Bikemarkt, which none reads, are idle.
        #expect(store.overview?.sources.filter { $0.state != .ok }.map(\.source.rawValue) == ["mydealz", "bikemarkt"])
        #expect(store.overview?.sources.filter { $0.state == .idle }.count == 2)
    }

    @Test func pausedAndNoHunt() async throws {
        let paused = try await store(.init(paused: true))
        #expect(paused.hunts.allSatisfy { !$0.hunt.active } && paused.overview?.sources.allSatisfy { $0.state == .idle } == true)
        let none = try await store(.init(noHunt: true))
        #expect(none.hunts.isEmpty && none.latest.isEmpty && none.overview?.counts == .init(new: 0, today: 0, saved: 0, applied: 0))
    }

    @Test func actionsWorkInMemory() async throws {
        let store = try await store()
        await store.setState(.saved, for: 41)
        #expect(store.match(41)?.state == .saved && store.overview?.counts.new == 7 && store.overview?.counts.saved == 2)
        await store.setActive(id: 1, active: false)
        #expect(store.card(1)?.hunt.active == false && store.overview?.sources.first?.state == .idle)
        await store.loadMatches(.saved)
        #expect(store.matches(.saved).map(\.id) == [41, 40])
        await store.loadRejected()
        #expect(store.rejected.count == 2)
    }

    @Test func searchesAreCreatedPausedAndDeleted() async throws {
        let store = try await store(.init(noHunt: true))
        let search = try #require(try sample(Overview.self, "overview").hunt?.search.flat)
        let created = try #require(await store.saveHunt(id: nil, kind: .flat, name: nil, search: .flat(search)))
        #expect(store.card(created.id)?.hunt.active == false && store.card(created.id)?.hunt.search.flat == search)
        #expect(await store.deleteHunt(id: created.id))
        #expect(store.hunts.isEmpty)
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
        guard case .flat(let parsed)? = await store.parse(text: "2-room flat in Schwabing", kind: .flat) else {
            Issue.record("Expected a flat search"); return
        }
        #expect(parsed.search.kinds == [.flat, .wg] && parsed.search.people == 2 && !parsed.unclear.isEmpty)
        guard case .item(let thing)? = await store.parse(text: "An Aeron near Garching", kind: .item) else {
            Issue.record("Expected a thing search"); return
        }
        #expect(thing.search.query == "Herman Miller Aeron" && thing.search.priceMax == 450)
    }
}
