import Foundation
import Testing
@testable import Aresus

@MainActor
struct ProvinceOpeningTests {
    @Test func appOpensFirst() async {
        let application = FakeProvinceApplication(installed: true)
        #expect(await ProvinceLinkOpener(application: application)
            .open(app: "fictional://", website: "https://province.example/") == .app)
        #expect(application.opened == ["fictional://"])
    }

    @Test func websiteFollowsAnUninstalledApp() async {
        let application = FakeProvinceApplication()
        #expect(await ProvinceLinkOpener(application: application)
            .open(app: "fictional://", website: "https://province.example/") == .website)
        #expect(application.opened == ["fictional://", "https://province.example/"])
    }

    @Test func websiteWithoutApp() async {
        let application = FakeProvinceApplication()
        #expect(await ProvinceLinkOpener(application: application)
            .open(app: nil, website: "https://province.example/") == .website)
        #expect(application.opened == ["https://province.example/"])
    }

    @Test func uninstalledAppWithoutWebsite() async {
        let application = FakeProvinceApplication()
        #expect(await ProvinceLinkOpener(application: application)
            .open(app: "fictional://", website: nil) == .notOpened)
        #expect(application.opened == ["fictional://"])
    }

    @Test func noLinks() async {
        let application = FakeProvinceApplication()
        #expect(await ProvinceLinkOpener(application: application).open(app: nil, website: nil) == .notOpened)
        #expect(application.opened.isEmpty)
    }

    @Test(arguments: ["", "relative/path", "javascript:alert(1)"])
    func invalidWebsite(website: String) async {
        let application = FakeProvinceApplication()
        #expect(await ProvinceLinkOpener(application: application).open(app: nil, website: website) == .notOpened)
        #expect(application.opened.isEmpty)
    }

    @Test func rejectedWebsiteOpensNothing() async {
        let application = FakeProvinceApplication(websitesOpen: false)
        #expect(await ProvinceLinkOpener(application: application)
            .open(app: "fictional://", website: "https://province.example/") == .notOpened)
        #expect(application.opened == ["fictional://", "https://province.example/"])
    }
}

@MainActor
private final class FakeProvinceApplication: ProvinceURLOpening {
    let installed: Bool
    let websitesOpen: Bool
    var opened: [String] = []

    init(installed: Bool = false, websitesOpen: Bool = true) {
        self.installed = installed
        self.websitesOpen = websitesOpen
    }

    func open(_ url: URL) async -> Bool {
        opened.append(url.absoluteString)
        return url.scheme == "https" ? websitesOpen : installed
    }
}
