import Foundation
import Testing
import UIKit
@testable import Empire

@MainActor
struct ProvinceServicesTests {
    private func imageData() throws -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2), format: format).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }
        return try #require(image.pngData())
    }

    @Test func marksUseBearerDecodeAndCache() async throws {
        let session = await empireSession()
        let transport = EmpireFakeTransport(data: try imageData())
        let marks = ProvinceMarks(session: session, transport: transport)
        let first = try #require(await marks.image(for: "brand/fictional.png"))
        let cached = await marks.image(for: "/brand/fictional.png")
        #expect(cached === first && first.size.width == 2)
        let request = try #require(transport.requests.only)
        #expect(request.url?.absoluteString == "https://www.ares-empire.de/brand/fictional.png")
        #expect(request.httpMethod == "GET" && request.httpBody == nil)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer fictional-empire-token")
        #expect(request.timeoutInterval == 30)
    }

    @Test(arguments: ["https://other.example/brand/icon.png", "//other.example/brand/icon.png", "api/empire",
                      "/brand/../api/empire", "/brand/%2e%2e/api/empire", "/brand/%252e%252e/api/empire",
                      "/brand/icon.png?target=other", "/brand/icon.png#fragment", "", "/brandish/icon.png"])
    func marksRejectPathsOutsideBrand(logo: String) async {
        let session = await empireSession()
        let transport = EmpireFakeTransport()
        #expect(await ProvinceMarks(session: session, transport: transport).image(for: logo) == nil)
        #expect(transport.requests.isEmpty)
    }

    @Test(arguments: [200, 401, 403, 503])
    func markFailuresReturnNilWithoutCaching(status: Int) async throws {
        let session = await empireSession()
        let transport = EmpireFakeTransport(data: status == 200 ? Data("not an image".utf8) : try imageData())
        transport.status = status
        let marks = ProvinceMarks(session: session, transport: transport)
        #expect(await marks.image(for: "brand/fictional.png") == nil)
        transport.status = 200
        transport.data = try imageData()
        #expect(await marks.image(for: "brand/fictional.png") != nil)
        #expect(transport.requests.count == 2)
    }

    @Test func markTransportFailureReturnsNil() async {
        let session = await empireSession()
        let transport = EmpireFakeTransport()
        transport.failure = URLError(.notConnectedToInternet)
        #expect(await ProvinceMarks(session: session, transport: transport).image(for: "brand/fictional.png") == nil)
    }

    @Test func sampleAndSignedOutMarksNeverSendRequests() async {
        let session = await empireSession()
        let transport = EmpireFakeTransport()
        let sample = ProvinceMarks(session: session, transport: transport, sample: true)
        #expect(await sample.image(for: "brand/fictional.png") == nil)
        session.logOut()
        let live = ProvinceMarks(session: session, transport: transport)
        #expect(await live.image(for: "brand/fictional.png") == nil)
        #expect(transport.requests.isEmpty)
    }

    @Test(arguments: [false, true])
    func appDataResetClearsMarkCache(denied: Bool) async throws {
        let session = await empireSession()
        let transport = EmpireFakeTransport(data: try imageData())
        let marks = ProvinceMarks(session: session, transport: transport)
        #expect(await marks.image(for: "brand/fictional.png") != nil)
        if denied { session.handleAuthFailure(HTTPError.server(403, "Denied"), generation: session.generation) }
        else { session.logOut() }
        #expect(await marks.image(for: "brand/fictional.png") == nil)
        await session.login(email: "member@example.invalid", password: "fictional")
        #expect(await marks.image(for: "brand/fictional.png") != nil)
        #expect(transport.requests.count == 2)
    }

    @Test func lateMarkResponseCannotRepopulateCacheAfterReset() async throws {
        let session = await empireSession()
        let transport = EmpireFakeTransport(data: try imageData())
        let marks = ProvinceMarks(session: session, transport: transport)
        let gate = EmpireRequestGate()
        transport.nextGate = gate
        let loading = Task { await marks.image(for: "brand/fictional.png") }
        await gate.waitUntilPaused()
        session.logOut()
        await session.login(email: "member@example.invalid", password: "fictional")
        gate.resume()
        #expect(await loading.value == nil)
        #expect(await marks.image(for: "brand/fictional.png") != nil)
        #expect(transport.requests.count == 2)
    }

    private func province(app: String? = "aresium://", url: String = "https://aresium.de", state: String = "open") throws -> Province {
        let original = try #require(EmpireSamples.load(user: false).projects.first)
        return Province(slug: original.slug, name: original.name, url: url, logo: original.logo,
                        status: original.status, domain: original.domain, blurb: original.blurb,
                        detail: original.detail, state: state, live: original.live, app: app)
    }

    @Test(arguments: [true, false])
    func openerChoosesInstalledAppOtherwiseWebsite(installed: Bool) async throws {
        let application = FakeProvinceApplication()
        application.installed = installed
        #expect(await ProvinceOpener(application: application).open(try province()))
        #expect(application.queried.map(\.absoluteString) == ["aresium://"])
        #expect(application.opened.map(\.absoluteString) == [installed ? "aresium://" : "https://aresium.de"])
    }

    @Test func openerUsesWebsiteWhenNoAppIsSpecified() async throws {
        let application = FakeProvinceApplication()
        application.installed = true
        #expect(await ProvinceOpener(application: application).open(try province(app: nil)))
        #expect(application.queried.isEmpty)
        #expect(application.opened.map(\.absoluteString) == ["https://aresium.de"])
    }

    @Test func comingSoonProvinceDoesNotOpen() async throws {
        let application = FakeProvinceApplication()
        application.installed = true
        #expect(await ProvinceOpener(application: application).open(try province(state: "coming-soon")) == false)
        #expect(application.queried.isEmpty && application.opened.isEmpty)
    }

    @Test(arguments: ["", "relative/path", "javascript:alert(1)"])
    func missingOrInvalidWebsiteDoesNotOpen(url: String) async throws {
        let application = FakeProvinceApplication()
        #expect(await ProvinceOpener(application: application).open(try province(app: nil, url: url)) == false)
        #expect(application.opened.isEmpty)
    }

    @Test func openerReturnsSystemOpenResult() async throws {
        let application = FakeProvinceApplication()
        application.openResult = false
        #expect(await ProvinceOpener(application: application).open(try province()) == false)
    }

    @Test func appAllowsQueryingAresiumScheme() {
        #expect((Bundle.main.object(forInfoDictionaryKey: "LSApplicationQueriesSchemes") as? [String])?.contains("aresium") == true)
    }
}

@MainActor
private final class FakeProvinceApplication: ProvinceURLOpening {
    var installed = false
    var openResult = true
    var queried: [URL] = []
    var opened: [URL] = []
    func canOpenURL(_ url: URL) -> Bool { queried.append(url); return installed }
    func open(_ url: URL) async -> Bool { opened.append(url); return openResult }
}
