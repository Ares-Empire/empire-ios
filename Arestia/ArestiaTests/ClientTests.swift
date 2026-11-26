import Foundation
import Testing
@testable import Arestia

/// How the app asks flatd, and how it reads a refusal.
struct ClientTests {
    let transport = FakeTransport()
    var client: FlatdClient { FlatdClient(Flat.pairing(), transport: transport) }

    @Test func everyRequestButHealthCarriesTheKey() async throws {
        transport.answer("GET /api/health", body: ["ok": true, "version": "1.1.0"])
        transport.answer("GET /api/devices", body: ["devices": [Flat.fan(1)]])
        #expect(try await client.health())
        #expect(try await client.devices().map(\.id) == ["fan:fan_1"])
        let sent = transport.sent
        #expect(sent[0].value(forHTTPHeaderField: "Authorization") == nil)
        #expect(sent[1].value(forHTTPHeaderField: "Authorization") == "Bearer \(Flat.key)")
        #expect(sent[1].url?.absoluteString == "https://192.0.2.10:8788/api/devices")
    }

    @Test func aCommandGoesToTheDeviceWithFlatdsBody() async throws {
        transport.answer("POST /api/devices/fan:fan_1", body: Flat.fan(1, on: true, offAt: "2026-11-19T18:30:00Z"))
        let device = try await client.send(.power(on: true, seconds: 1800), to: "fan:fan_1")
        #expect(device.state.on == true)
        let body = try #require(transport.bodies(for: "POST /api/devices/fan:fan_1").first)
        #expect(body["on"] as? Bool == true)
        #expect(body["for_s"] as? Double == 1800)
        #expect(transport.sent.first?.value(forHTTPHeaderField: "Content-Type") == "application/json")
    }

    @Test func idsAreKeptReadableInThePath() {
        #expect(FlatdClient.pathID("fan:fan_1") == "fan:fan_1")
        #expect(FlatdClient.pathID("rollo:w 1/2") == "rollo:w%201%2F2")
    }

    @Test func refusalsInTheAppsTerms() async {
        let cases: [(Int, FlatdError)] = [(401, .refused), (404, .unknown), (409, .notPossible),
                                          (504, .deviceDidNotAnswer), (500, .failed(status: 500, message: nil))]
        for (status, expected) in cases {
            transport.answer("POST /api/devices/rollo:blind_2", status: status, body: ["detail": "x"])
            await #expect(throws: expected) { try await client.send(.rollo(.favourite), to: "rollo:blind_2") }
        }
        transport.answer("POST /api/devices/fan:fan_1", status: 400, body: ["error": "body must be {\"on\": …}"])
        await #expect(throws: FlatdError.failed(status: 400, message: "body must be {\"on\": …}")) {
            try await client.send(.power(on: true), to: "fan:fan_1")
        }
    }

    @Test func noAnswerMeansOutOfReach() async {
        transport.answer("GET /api/modes", fails: true)
        await #expect(throws: FlatdError.unreachable) { try await client.modes() }
    }

    @Test func anAnswerThatDoesNotFit() async {
        transport.answer("GET /api/scenes", body: ["scenes": "none"])
        await #expect(throws: FlatdError.invalidAnswer) { try await client.scenes() }
    }

    @Test func modesAndScenesSayWhichDevicesDidNotFollow() async throws {
        var mode = Flat.cooking
        mode["active"] = true
        mode["failed"] = ["fan:fan_2": "did not answer"]
        transport.answer("POST /api/modes/cooking", body: mode)
        let (answered, failed) = try await client.setMode("cooking", active: true)
        #expect(answered.active)
        #expect(failed == ["fan:fan_2"])
        #expect(transport.bodies(for: "POST /api/modes/cooking").first?["active"] as? Bool == true)

        transport.answer("POST /api/scenes/all_down", body: ["id": "all_down", "failed": [:]])
        #expect(try await client.runScene("all_down").isEmpty)
    }

    @Test func theStream() {
        let events = client.eventsRequest
        #expect(events.url?.absoluteString == "wss://192.0.2.10:8788/api/events")
        #expect(events.value(forHTTPHeaderField: "Authorization") == "Bearer \(Flat.key)")
        #expect(events.url?.query == nil)
    }

    @Test func thePageIsFetchedByTheClientWithTheKeyInTheHeader() async throws {
        transport.answer("GET /viewer", body: ["page": true])
        _ = try await client.viewerPage()
        let page = try #require(transport.sent.last)
        #expect(page.url?.absoluteString == "https://192.0.2.10:8788/viewer")
        #expect(page.value(forHTTPHeaderField: "Authorization") == "Bearer \(Flat.key)")
        #expect(page.value(forHTTPHeaderField: "If-None-Match") == nil)
        transport.answer("GET /viewer", status: 404, body: ["error": "not configured"])
        await #expect(throws: FlatdError.unknown) { _ = try await client.viewerPage() }
    }

    @Test func theViewerETagIsKeptAndSentBackExactly() async throws {
        let etag = #""abc-123""#
        let pinnedClient = FlatdClient(Flat.pairing(), transport: ViewerTransport(base: transport, etag: etag))
        transport.answer("GET /viewer", body: ["page": true])
        let answer = try await pinnedClient.viewerPage(ifNoneMatch: nil)
        #expect(answer == .page(Data(#"{"page":true}"#.utf8), etag: etag))

        transport.answer("GET /viewer", status: 304)
        #expect(try await pinnedClient.viewerPage(ifNoneMatch: etag) == .unchanged)
        let request = try #require(transport.sent.last)
        #expect(request.value(forHTTPHeaderField: "If-None-Match") == etag)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer \(Flat.key)")
        #expect(request.timeoutInterval == 30)
    }

    private struct ViewerTransport: HTTPTransport, Sendable {
        let base: FakeTransport
        let etag: String

        func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
            let (data, response) = try await base.send(request)
            let tagged = HTTPURLResponse(url: request.url!, statusCode: response.statusCode,
                                         httpVersion: nil, headerFields: ["ETag": etag])!
            return (response.statusCode == 304 ? Data() : data, tagged)
        }
    }

    @Test func messagesInBothLanguages() {
        #expect(FlatdError.unreachable.message(language: .english).contains("flat service isn't answering"))
        #expect(FlatdError.unreachable.message(language: .german).contains("Wohnungsdienst antwortet nicht"))
        #expect(FlatdError.failed(status: 400, message: "flatd's own words").message() == "flatd's own words")
    }
}

/// What Shortcuts and the controls do (`FlatActions`), through the same client.
struct ActionsTests {
    let transport = FakeTransport()

    func actions(_ connection: FlatdConnection = Flat.connection()) -> FlatActions {
        FlatActions(reach: FlatdReach(connection: connection, transport: transport, rediscover: { [] }))
    }

    @Test func fansOnSwitchesEveryFanForAWhile() async throws {
        transport.answer("GET /api/devices", body: ["devices": [Flat.fan(1), Flat.fan(2), Flat.rollo(1)]])
        transport.answer("POST /api/devices/fan:fan_1", body: Flat.fan(1, on: true))
        transport.answer("POST /api/devices/fan:fan_2", body: Flat.fan(2, on: true))
        let fans = try await actions().setFans(on: true, minutes: 30)
        #expect(Set(fans.map(\.id)) == ["fan:fan_1", "fan:fan_2"])
        for fan in ["fan:fan_1", "fan:fan_2"] {
            #expect(transport.bodies(for: "POST /api/devices/\(fan)").first?["for_s"] as? Double == 1800)
        }
        #expect(transport.bodies(for: "POST /api/devices/rollo:blind_1").isEmpty)
    }

    @Test func oneFanOnly() async throws {
        transport.answer("GET /api/devices", body: ["devices": [Flat.fan(1), Flat.fan(2)]])
        transport.answer("POST /api/devices/fan:fan_2", body: Flat.fan(2))
        try await actions().setFans(on: false, only: [SavedDevice.id(for: "fan:fan_2", of: Flat.id)])
        #expect(transport.bodies(for: "POST /api/devices/fan:fan_1").isEmpty)
        #expect(transport.bodies(for: "POST /api/devices/fan:fan_2").first?["on"] as? Bool == false)
    }

    @Test func aChoiceMadeForAnotherFlatdIsNeverUsedOnThisOne() async throws {
        // flatd's ids are names inside one flatd: after pairing with another, "blind_1" may be another blind.
        let other = UUID()                                          // another pairing's identity
        transport.answer("GET /api/devices", body: ["devices": [Flat.fan(1), Flat.rollo(1)]])
        transport.answer("POST /api/devices/rollo:blind_1", body: Flat.rollo(1))
        transport.answer("POST /api/devices/fan:fan_1", body: Flat.fan(1))
        let foreignBlind = SavedDevice.id(for: "rollo:blind_1", of: other)
        await #expect(throws: ChosenDeviceGone.blind) { try await actions().move(rollo: foreignBlind, .up) }
        await #expect(throws: ChosenDeviceGone.fan) {
            try await actions().setFans(on: true, only: [SavedDevice.id(for: "fan:fan_1", of: other)])
        }
        await #expect(throws: ChosenDeviceGone.blind) { try await actions().move(rollo: "rollo:blind_1", .up) }   // no flatd named
        #expect(try await actions().rollo(foreignBlind) == nil)
        #expect(transport.sent.allSatisfy { $0.httpMethod != "POST" })
        // The same choice for the paired flatd works, whatever its address is now.
        let mine = SavedDevice.id(for: "rollo:blind_1", of: Flat.id)
        try await actions().move(rollo: mine, .up)
        #expect(try await actions().rollo(mine)?.id == "rollo:blind_1")
        #expect(transport.bodies(for: "POST /api/devices/rollo:blind_1").count == 1)
    }

    @Test func shortcutsChoicesCarryThePairedFlatd() async throws {
        let connection = Flat.connection()
        transport.answer("GET /api/devices", body: ["devices": [Flat.fan(1), Flat.rollo(1)]])
        let reach = FlatdReach(connection: connection, transport: transport, rediscover: { [] })
        let blinds = await DeviceChoices.load(kind: .rollo, connection: connection, reach: reach)
        #expect(blinds == [.init(id: SavedDevice.id(for: "rollo:blind_1", of: Flat.id), label: "Blind 1")])
        #expect(try SavedDevice.device(blinds[0].id, of: Flat.id) == "rollo:blind_1")
        // Paired with another flatd: the old choices are no longer offered.
        try connection.save(FlatdPairing(baseURL: Flat.base, token: Flat.key, pin: MadeUpCertificates.pinB))
        transport.answer("GET /api/devices", fails: true)
        #expect(await DeviceChoices.load(kind: .rollo, connection: connection, reach: reach).isEmpty)
    }

    @Test func aFanThatDoesNotAnswerIsReportedAfterTheOthers() async throws {
        transport.answer("GET /api/devices", body: ["devices": [Flat.fan(1), Flat.fan(2)]])
        transport.answer("POST /api/devices/fan:fan_1", body: Flat.fan(1, on: true))
        transport.answer("POST /api/devices/fan:fan_2", status: 504, body: ["error": "timeout"])
        await #expect(throws: FlatdError.deviceDidNotAnswer) { try await actions().setFans(on: true) }
        #expect(transport.bodies(for: "POST /api/devices/fan:fan_1").count == 1)
    }

    @Test func cookingAndItsState() async throws {
        var active = Flat.cooking
        active["active"] = true
        transport.answer("POST /api/modes/cooking", body: active.merging(["failed": [:]]) { $1 })
        transport.answer("GET /api/modes", body: ["modes": [Flat.cooking]])
        #expect(try await actions().setCooking(true) == CookingChange(isActive: true, failed: []))
        transport.answer("GET /api/modes", body: ["modes": [active]])
        #expect(try await actions().cookingState() == CookingState(active: true, notFollowed: []))
    }

    @Test func withoutAKeyNothingIsSent() async {
        await #expect(throws: FlatdError.notPaired) { try await actions(Flat.connection(linked: false)).fansRunning() }
        #expect(transport.sent.isEmpty)
    }

    @Test func theDevicesAreRememberedForShortcutsPickers() async throws {
        let connection = Flat.connection()
        transport.answer("GET /api/devices", body: ["devices": [Flat.fan(1), Flat.rollo(1)]])
        _ = try await actions(connection).rollos()
        #expect(connection.knownDevices.map(\.label) == ["Fan 1", "Blind 1"])
        #expect(connection.knownDevices.map(\.kind) == ["fan", "rollo"])
    }
}
