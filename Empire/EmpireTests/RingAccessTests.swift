import Foundation
import Testing
@testable import Empire

/// The ring shows every app the account has, "+" the others with their access state, and an app the account has may
/// carry its install link (Patrik, 2026-10-25; ares-empire docs/EMPIRE-APP.md → Whose ring shows what).
@MainActor
struct RingAccessTests {
    private func decode(_ json: String) throws -> EmpireData {
        try JSONDecoder().decode(EmpireData.self, from: Data(json.utf8))
    }

    private func hub(projects: [String] = [], addable: [String] = []) -> String {
        EmpireFixtures.member(projects: projects, addable: addable)
    }

    @Test func theNewHubsFieldsDecode() throws {
        let data = try decode(EmpireFixtures.catalog())
        let ring = try #require(data.projects.only)
        #expect(ring.access == .granted && ring.install == "https://testflight.apple.com/join/FICTION1")
        #expect(ring.installURL == URL(string: "https://testflight.apple.com/join/FICTION1"))
        #expect(data.addable.map(\.slug) == ["arestemis", "aresium"])
        #expect(data.addable.map(\.access) == [.notRequested, .notRequested])
        #expect(data.addable.map(\.canRequest) == [true, false])           // Aresium is coming soon
        #expect(data.addable.allSatisfy { $0.install == nil })

        let asked = try decode(EmpireFixtures.catalog(arestemis: "requested"))
        #expect(asked.addable.first?.access == .requested && asked.addable.first?.canRequest == false)
    }

    /// An older hub sends neither field: the ring's apps count as granted, the "+" list's as not asked for, no link.
    @Test func anOlderHubWithoutTheFieldsStillDecodes() throws {
        let old = try decode(hub(projects: [EmpireFixtures.province("aresolus", state: "open", access: nil, install: nil)],
                                 addable: [EmpireFixtures.province("arestemis", state: "open", access: nil, install: nil),
                                           EmpireFixtures.province("aresium", state: "coming-soon", access: nil,
                                                                   install: nil)]))
        #expect(old.projects.map(\.access) == [.granted] && old.projects.first?.install == nil)
        #expect(old.addable.map(\.access) == [.notRequested, .notRequested])
        #expect(old.addable.map(\.canRequest) == [true, false])

        // The fixtures written before the change, and the hub's own samples of today.
        let emptyRing = try decode(EmpireFixtures.emptyRing)
        #expect(emptyRing.addable.only?.access == .notRequested && emptyRing.addable.only?.canRequest == false)
        for user in [false, true] {
            let sample = try EmpireSamples.load(user: user)
            #expect(sample.projects.allSatisfy { $0.access == .granted })
            #expect(sample.addable.allSatisfy { $0.access != .granted })
        }
    }

    /// A value this build does not know (a newer hub) or of the wrong type follows the list it is in.
    @Test func unknownOrWrongValuesFallBackSafely() throws {
        let data = try decode(hub(
            projects: [EmpireFixtures.province("aresolus", state: "open", access: "suspended", install: "42"),
                       EmpireFixtures.province("aresus", state: "open", access: nil, rawAccess: "7", install: "true")],
            addable: [EmpireFixtures.province("arestemis", state: "open", access: "declined"),
                      EmpireFixtures.province("aresync", state: "open", access: nil, rawAccess: "[]")]))
        #expect(data.projects.map(\.access) == [.granted, .granted])
        #expect(data.projects.allSatisfy { $0.install == nil })
        #expect(data.addable.map(\.access) == [.notRequested, .notRequested])
    }

    @Test func onlyAnHTTPSInstallLinkOpens() {
        let base = Province(slug: "aresolus", name: "Aresolus", url: "", logo: "", status: "CONQUERED", domain: "",
                            blurb: "", detail: .init(about: "", features: [], setup: "", wip: [], ideas: []),
                            state: "open", live: nil, app: "aresolus://")
        #expect(base.installURL == nil)
        #expect(base.with(install: "https://apps.apple.com/app/id000000").installURL != nil)
        #expect(base.with(install: "HTTPS://testflight.apple.com/join/FICTION1").installURL != nil)
        for link in ["http://testflight.apple.com/join/x", "javascript:alert(1)", "itms-services://x", "https://", "",
                     "not a link"] {
            #expect(base.with(install: link).installURL == nil, "\(link)")
        }
    }

    /// What the app holds goes back out and in unchanged (the store keeps what it decoded).
    @Test func theNewFieldsSurviveARoundTrip() throws {
        let data = try decode(EmpireFixtures.catalog(arestemis: "requested"))
        #expect(try JSONDecoder().decode(EmpireData.self, from: JSONEncoder().encode(data)) == data)
    }

    // MARK: The "+" sheet's states in sample mode

    @Test func theCatalogSampleShowsEveryState() throws {
        let sample = try EmpireSamples.catalog()
        #expect(!sample.me.admin && sample.ideas.isEmpty && sample.pending == 0)
        let ring = try #require(sample.projects.only)
        #expect(ring.slug == "arestemis" && ring.installURL != nil && ring.access == .granted)
        #expect(sample.addable.map(\.slug) == ["aresolus", "aresync", "aresium"])
        #expect(sample.addable.map(\.access) == [.notRequested, .requested, .notRequested])
        #expect(sample.addable.map(\.canRequest) == [true, false, false])
        #expect(sample.addable.last?.isComingSoon == true)
        #expect(sample.chronicle.allSatisfy { $0.project == "arestemis" })
    }

    /// Sample mode asks in memory: the app becomes "asked", a coming-soon one stays as it is, nothing is sent.
    @Test func sampleModeAsksInMemory() async throws {
        let session = EmpireSession(app: .empire, storage: EmpireMemoryTokens(), restoreOnLaunch: false)
        let transport = EmpireFakeTransport()
        let store = EmpireStore(session: session, client: EmpireAPI(transport: transport), sample: true,
                                sampleUser: false, sampleCatalog: true)
        await store.reload()
        #expect(store.data == (try EmpireSamples.catalog()))
        #expect(await store.request("aresolus"))
        #expect(store.data?.addable.first { $0.slug == "aresolus" }?.access == .requested)
        #expect(await store.request("aresium"))
        #expect(store.data?.addable.first { $0.slug == "aresium" }?.access == .notRequested)
        await store.reload()
        #expect(store.data?.addable.first { $0.slug == "aresolus" }?.access == .requested)
        await store.loadApprovals()
        #expect(store.approvals.isEmpty)                                // a member: no approvals
        #expect(transport.requests.isEmpty)
    }

    @Test func theCatalogSampleNeedsSampleData() {
        #expect(!EmpireSamples.enabled(arguments: ["Empire", "-sampleCatalog"]))
        #expect(EmpireSamples.enabled(arguments: ["Empire", "-sampleData", "-sampleCatalog"]))
    }
}
