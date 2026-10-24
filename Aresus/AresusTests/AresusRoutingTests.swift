import Foundation
import Testing
@testable import Aresus

/// Links into the app: from iOS, from the Empire app (`aresus://`) and from notifications (aresus/docs/API.md → Pushes).
@MainActor
struct AresusRoutingTests {
    @Test(arguments: [
        ("aresus://", AresusLink.home),
        ("aresus:", .home),
        ("aresus://server", .server),
        ("ARESUS://Server", .server),
        ("aresus://sync", .sync),
        ("aresus://province/aresium", .province("aresium")),
        ("aresus://province/aresium/", .province("aresium")),
        ("aresus://province/ares-empire_2", .province("ares-empire_2")),
        ("aresus://sync/run/612", .run(612)),
        ("aresus://sync/run/612?from=push", .run(612))
    ])
    func linksParse(url: String, expected: AresusLink) throws {
        #expect(AresusLink(url: try #require(URL(string: url))) == expected)
    }

    @Test(arguments: [
        "https://www.ares-empire.de/province/aresium",
        "aresium://province/aresium",
        "aresus://province",
        "aresus://province/Aresium",
        "aresus://province/-aresium",
        "aresus://province/a%2Fb",
        "aresus://province/aresium/checks",
        "aresus://sync/run",
        "aresus://sync/run/0",
        "aresus://sync/run/-3",
        "aresus://sync/run/12x",
        "aresus://sync/run/0612",
        "aresus://sync/runs/612",
        "aresus://server/disk",
        "aresus://overview"
    ])
    func otherLinksAreIgnored(url: String) throws {
        let link = try #require(URL(string: url))
        #expect(AresusLink(url: link) == nil)
        let navigation = AresusNavigation(tab: .aresync, provincePath: ["aresis"], openRun: RunRef(id: 1))
        #expect(!navigation.open(link))
        #expect(navigation.tab == .aresync && navigation.provincePath == ["aresis"] && navigation.openRun == RunRef(id: 1))
    }

    /// The notification links of the contract's push table land on the right screen.
    @Test func notificationLinksOpenTheirScreens() throws {
        let navigation = AresusNavigation(tab: .aresync, openRun: RunRef(id: 1))
        #expect(navigation.open(try #require(URL(string: "aresus://province/aresium"))))
        #expect(navigation.tab == .aresus && navigation.provincePath == ["aresium"] && navigation.openRun == nil)
        #expect(navigation.visibleParts == [.province("aresium")])

        #expect(navigation.open(try #require(URL(string: "aresus://sync/run/612"))))
        #expect(navigation.tab == .aresync && navigation.openRun == RunRef(id: 612))
        #expect(navigation.provincePath == ["aresium"])              // the other tab keeps its page
        #expect(navigation.visibleParts == [.sync])

        let before = navigation.serverRequest
        #expect(navigation.open(try #require(URL(string: "aresus://server"))))
        #expect(navigation.tab == .aresus && navigation.provincePath.isEmpty && navigation.openRun == nil)
        #expect(navigation.serverRequest == before + 1)
        #expect(navigation.visibleParts == [.overview])
    }

    @Test func openingTheAppKeepsItsPlace() throws {
        let navigation = AresusNavigation(tab: .aresus, provincePath: ["aresync"])
        #expect(navigation.open(try #require(URL(string: "aresus://"))))
        #expect(navigation.tab == .aresus && navigation.provincePath == ["aresync"])
        navigation.open(.sync)
        #expect(navigation.tab == .aresync && navigation.provincePath == ["aresync"])
    }

    @Test func aNewProvinceReplacesThePushedOne() {
        let navigation = AresusNavigation(provincePath: ["aresium", "empire"])
        navigation.open(.province("arestemis"))
        #expect(navigation.provincePath == ["arestemis"])
    }

    @Test func logoutResetsTheNavigation() {
        let navigation = AresusNavigation(tab: .aresync, provincePath: ["aresium"], openRun: RunRef(id: 7))
        navigation.reset()
        #expect(navigation.tab == .aresus && navigation.provincePath.isEmpty && navigation.openRun == nil)
    }

    @Test func launchArgumentsForScreenshots() {
        let plain = AresusNavigation.launched(arguments: ["Aresus", "-sampleData"])
        #expect(plain.tab == .aresus && plain.provincePath.isEmpty && plain.openRun == nil)
        let sync = AresusNavigation.launched(arguments: ["Aresus", "-tab", "aresync"])
        #expect(sync.tab == .aresync)
        let province = AresusNavigation.launched(arguments: ["Aresus", "-openProvince", "aresium"])
        #expect(province.tab == .aresus && province.provincePath == ["aresium"])
        let run = AresusNavigation.launched(arguments: ["Aresus", "-openRun", "612"])
        #expect(run.tab == .aresync && run.openRun == RunRef(id: 612))
        let invalid = AresusNavigation.launched(arguments: ["Aresus", "-tab", "other", "-openProvince", "../x", "-openRun", "x"])
        #expect(invalid.tab == .aresus && invalid.provincePath.isEmpty && invalid.openRun == nil)
    }
}
