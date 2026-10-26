import Foundation
import Testing
@testable import Empire

/// The Empire app's notification (ares-empire docs/EMPIRE-APP.md → Notifications): a member is told "<App> is ready"
/// when Patrik approved a request (`url` `empire://ring`, thread `access`). Tapping it shows the ring, asked for again.
/// Patrik's sign-ups and requests come by email, not as a push (Patrik, 2026-10-26).
@MainActor
struct NotificationTests {
    @Test func theRingLinkIsFollowed() {
        #expect(EmpireLink(url: URL(string: "empire://ring")!) == .ring)
        #expect(EmpireLink(url: URL(string: "EMPIRE://ring")!) == .ring)
        #expect(EmpireLink(url: URL(string: "empire://ring/")!) == .ring)
    }

    @Test func otherLinksAreNotFollowed() {
        for text in ["empire://ring/extra", "empire://approvals/fictional00001?apps=arestemis", "empire://sample",
                     "empire://", "aresium://ring", "https://www.ares-empire.de/ring"] {
            #expect(EmpireLink(url: URL(string: text)!) == nil, "\(text)")
        }
    }

    /// The payload for `simctl push` (Empire/PushSamples) carries the link the app follows.
    @Test func theSamplePayloadMatchesTheApp() throws {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "PushSamples/app-ready.apns")
        let payload = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [AnyHashable: Any])
        #expect(PushCenter.url(from: payload).flatMap(EmpireLink.init(url:)) == .ring)
        #expect((payload["aps"] as? [String: Any])?["thread-id"] as? String == "access")
    }

    @Test func navigationShowsTheRing() {
        let navigation = EmpireNavigation()
        navigation.sheet = .moreApps
        navigation.expanded = true
        navigation.follow(.ring)
        #expect(navigation.sheet == nil && !navigation.expanded)
        navigation.sheet = .moreApps
        navigation.expanded = true
        navigation.reset()
        #expect(navigation.sheet == nil && !navigation.expanded)
    }

    /// The tap: the sheet closes and the hub is asked again, which brings the new app into the ring.
    @Test func aTapShowsTheRingWithTheNewApp() async throws {
        let session = await empireSession()
        let transport = EmpireFakeTransport(data: Data(EmpireFixtures.catalog().utf8))
        let store = EmpireStore(session: session, client: EmpireAPI(transport: transport))
        await store.reload()
        let navigation = EmpireNavigation()
        navigation.sheet = .moreApps
        let approved = EmpireFixtures.catalogApproved
        transport.data = Data(approved.utf8)
        #expect(await navigation.open(URL(string: "empire://ring")!, store: store))
        #expect(navigation.sheet == nil)
        #expect(transport.requests.count == 2 && transport.requests.last?.url?.path == "/api/empire")
        #expect(store.data == (try JSONDecoder().decode(EmpireData.self, from: Data(approved.utf8))))
        #expect(store.data?.projects.map(\.slug) == ["aresolus", "arestemis"])
    }

    /// Any other link (an older or a future push) opens the app and nothing more.
    @Test func anUnknownLinkDoesNothing() async throws {
        let session = await empireSession()
        let transport = EmpireFakeTransport(data: Data(EmpireFixtures.catalog().utf8))
        let store = EmpireStore(session: session, client: EmpireAPI(transport: transport))
        await store.reload()
        let navigation = EmpireNavigation()
        navigation.sheet = .moreApps
        #expect(await navigation.open(URL(string: "empire://approvals/fictional00001?apps=aresus")!, store: store) == false)
        #expect(await navigation.open(URL(string: "empire://sample")!, store: store) == false)
        #expect(navigation.sheet?.id == "more-apps" && transport.requests.count == 1)
    }
}
