import Foundation
import os
import Testing
@testable import Arestia

private let away = "listener.home.example.net"
private let awayURL = "https://listener.home.example.net:8443"
private let awayPin = String(repeating: "cd", count: 32)
nonisolated private let moved = URL(string: "https://192.0.2.77:8788")!
private let unlockError = FlatdError.awayNeedsUnlock(needsPasscode: false)

private struct RouteFixture {
    let connection = Flat.connection(linked: false)
    let transport = FakeTransport()
    let marker = OSAllocatedUnfairLock(initialState: true)
    let pairing: FlatdPairing

    init() throws {
        var pairing = Flat.pairing()
        pairing.remote = try #require(RemoteListener.parse(url: awayURL, pin: awayPin, homePin: pairing.pin))
        self.pairing = pairing
        try connection.save(pairing)
    }

    var reach: FlatdReach {
        FlatdReach(connection: connection, transport: transport, rediscover: { [] },
                   path: { .localPossible }, allowsRemote: { marker.withLock { $0 } }, needsPasscode: { false })
    }

    func health(_ host: String, delay: Duration? = nil, after: (@Sendable () async -> Void)? = nil) {
        transport.answer("GET \(host)/api/health", body: ["ok": true, "version": "1.7.0-test"], delay: delay,
                         beforeReply: after)
    }

    func lockOnRemoteHealth() {
        health(Flat.base.host()!, delay: .milliseconds(1500))
        health(away) { marker.withLock { $0 = false } }
    }

    func fans() {
        transport.answer("GET /api/devices", body: ["devices": [Flat.fan(1), Flat.fan(2)]])
        for fan in 1...2 {
            transport.answer("POST /api/devices/fan:fan_\(fan)", body: Flat.fan(fan, on: true))
        }
    }

    func cooking() {
        transport.answer("GET /api/modes", body: ["modes": [Flat.cooking]])
        var active = Flat.cooking
        active["active"] = true
        transport.answer("POST /api/modes/cooking", body: active)
    }

    var writes: [URLRequest] { transport.sent.filter { $0.httpMethod == "POST" } }
    var authenticated: [URLRequest] { transport.sent.filter { $0.value(forHTTPHeaderField: "Authorization") != nil } }
}

struct RemoteRouteTests {
    @Test func homeWins() async throws {
        let flat = try RouteFixture()
        #expect(try await flat.reach.run { $0.route } == .home)
        #expect(flat.transport.requests(to: away).isEmpty)
    }

    @Test func remoteWinsWhenHomeTimesOut() async throws {
        let flat = try RouteFixture()
        flat.health(Flat.base.host()!, delay: .seconds(60))
        // Home's 2.5 s cap expires before this remote answer.
        flat.health(away, delay: .milliseconds(2200))
        #expect(try await flat.reach.run { $0.route } == .remote)
        #expect(flat.authenticated.isEmpty)
    }

    @Test func noWiFiSkipsHomeAndUnknownPathProbesHome() async throws {
        let flat = try RouteFixture()
        var reach = flat.reach
        reach.path = { .remoteOnly }
        #expect(try await reach.run { $0.route } == .remote)
        #expect(flat.transport.requests(to: Flat.base.host()!).isEmpty)
        reach.path = { .unknown }
        #expect(try await reach.run { $0.route } == .home)
        #expect(flat.transport.requests(to: Flat.base.host()!).count == 1)
    }

    @Test(arguments: [true, false]) func bonjourWinsBesideDeadSavedAddress(unlocked: Bool) async throws {
        let flat = try RouteFixture()
        flat.marker.withLock { $0 = unlocked }
        flat.health(Flat.base.host()!, delay: .seconds(60))
        flat.health(moved.host()!, delay: .seconds(1))
        flat.health(away, delay: .seconds(60))
        var reach = flat.reach
        reach.rediscover = { [moved] }
        let start = ContinuousClock().now
        let selected = try await reach.run { $0 }
        #expect(start.duration(to: ContinuousClock().now) < .seconds(2))
        #expect(selected.route == .home && selected.baseURL == moved)
        #expect(flat.connection.pairing?.baseURL == moved)
    }

    @Test func hangingProbeIsCancelledAtCapAndChoiceRespectsDeadline() async throws {
        let flat = try RouteFixture()
        flat.health(Flat.base.host()!, delay: .seconds(60))
        flat.health(away, delay: .seconds(60))
        var reach = flat.reach
        reach.path = { .remoteOnly }
        var start = ContinuousClock().now
        await #expect(throws: FlatdError.unreachable) { try await reach.run { $0.route } }
        let elapsed = start.duration(to: ContinuousClock().now)
        #expect(elapsed >= .seconds(4) && elapsed < .seconds(5))
        start = ContinuousClock().now
        await #expect(throws: FlatdError.unreachable) {
            try await reach.run(deadline: Deadline(after: .milliseconds(150))) { $0.route }
        }
        #expect(start.duration(to: ContinuousClock().now) < .milliseconds(600))
    }

    @Test func markerDeniesRemoteAtChoiceAndDispatchButAllowsHome() async throws {
        let flat = try RouteFixture()
        flat.fans()
        flat.marker.withLock { $0 = false }
        var reach = flat.reach
        reach.path = { .remoteOnly }
        await #expect(throws: unlockError) { try await reach.run { try await $0.devices() } }
        #expect(flat.transport.sent.isEmpty)

        let lockedRemote = try #require(FlatdClient(remoteOf: flat.pairing, transport: flat.transport))
            .gated(by: flat.connection, allowsRemote: { false }, needsPasscode: { false })
        await #expect(throws: unlockError) { try await lockedRemote.devices() }
        #expect(flat.transport.sent.isEmpty)

        _ = try await FlatdClient(flat.pairing, transport: flat.transport)
            .gated(by: flat.connection, allowsRemote: { false }).devices()
        #expect(flat.authenticated.count == 1)
    }

    @Test func sharedDefaultAllowsRemoteAndChoiceHonorsPolicy() async throws {
        let selected = try await HomeRoute.select(deadline: Deadline(after: .seconds(1)), path: { .remoteOnly },
                                                 home: { _ in nil }, discover: { _ in nil },
                                                 remote: { _ in "remote" })
        guard case .reached("remote") = selected else { Issue.record("The default policy withheld remote"); return }
    }

    @Test(arguments: [true, false]) func lockAfterRemoteWinsRetriesHomeOnlyOnce(homeAnswers: Bool) async throws {
        let flat = try RouteFixture()
        flat.lockOnRemoteHealth()
        flat.cooking()
        if !homeAnswers { flat.transport.answer("GET 192.0.2.10/api/health", fails: true) }
        let actions = FlatActions(reach: flat.reach)
        if homeAnswers {
            #expect(try await actions.setCooking(true).isActive)
        } else {
            await #expect(throws: unlockError) { try await actions.setCooking(true) }
        }
        #expect(flat.transport.requests(to: away).count == 1)
        #expect(flat.transport.requests(to: Flat.base.host()!).filter { $0.url?.path() == "/api/health" }.count == 2)
        #expect(flat.writes.count == (homeAnswers ? 1 : 0))
        #expect(flat.writes.allSatisfy { $0.url?.host() == Flat.base.host() })
    }

    @Test(arguments: [true, false]) func refusedFirstReadRestartsFansOrCookingAtHome(fans: Bool) async throws {
        let flat = try RouteFixture()
        flat.lockOnRemoteHealth()
        flat.fans()
        flat.cooking()
        let actions = FlatActions(reach: flat.reach)
        if fans { #expect(try await actions.setFans(on: true).count == 2) }
        else { #expect(try await actions.toggleCooking().isActive) }
        #expect(flat.authenticated.allSatisfy { $0.url?.host() == Flat.base.host() })
        #expect(flat.authenticated.filter { $0.httpMethod == "GET" }.count == 1)
        #expect(Set(flat.writes.compactMap { $0.url?.path() }).count == (fans ? 2 : 1))
        #expect(flat.writes.count == (fans ? 2 : 1))
    }

    @Test func remoteFansReadAndWriteUnderTheirOwnPin() async throws {
        let flat = try RouteFixture()
        flat.fans()
        var reach = flat.reach
        reach.path = { .remoteOnly }
        let actions = FlatActions(reach: reach)
        #expect(try await actions.fans().count == 2)
        #expect(try await actions.setFans(on: true).count == 2)
        #expect(flat.writes.count == 2)
        #expect(flat.authenticated.allSatisfy { $0.url?.host() == away })
        #expect(flat.connection.pairing?.baseURL == Flat.base)
    }

    @Test func refusalAfterOneFanWriteNeverReplays() async throws {
        let flat = try RouteFixture()
        flat.fans()
        let reads = OSAllocatedUnfairLock(initialState: 0)
        var reach = flat.reach
        reach.path = { .remoteOnly }
        reach.allowsRemote = {
            // Choice, devices read, first write, second write.
            reads.withLock { $0 += 1; return $0 <= 3 }
        }
        await #expect(throws: unlockError) { try await FlatActions(reach: reach).setFans(on: true) }
        #expect(flat.writes.count == 1)
        #expect(flat.writes.first?.url?.host() == away)
        #expect(flat.transport.requests(to: Flat.base.host()!).isEmpty)
    }
}

struct ActionDeadlineTests {
    // Advance the same clock between requests and let its timer cancel sleeping work.
    private nonisolated struct TestClock: Sendable {
        let offset = OSAllocatedUnfairLock(initialState: Duration.zero)
        var clock: Deadline.Clock {
            let now: @Sendable () -> ContinuousClock.Instant = {
                ContinuousClock().now + offset.withLock { $0 }
            }
            return .init(now: now, sleepUntil: { instant in
                while now() < instant {
                    try await Task.sleep(for: min(now().duration(to: instant), .milliseconds(10)))
                }
            })
        }

        func advance(_ duration: Duration) { offset.withLock { $0 += duration } }
    }

    @Test func lessThanThreeSecondsRefusesAWrite() async throws {
        let flat = try RouteFixture()
        flat.cooking()
        await #expect(throws: FlatdError.unreachable) {
            try await flat.reach.run(deadline: Deadline(after: .seconds(2))) {
                try await $0.setMode(FlatMode.cookingID, active: true)
            }
        }
        #expect(flat.writes.isEmpty)
    }

    @Test func cookingReadAndWriteShareDeadlineAndTimedOutWriteIsNotRetried() async throws {
        let flat = try RouteFixture()
        let clock = TestClock()
        flat.health(away) { clock.advance(.milliseconds(3500)) }
        flat.transport.answer("GET /api/modes", body: ["modes": [Flat.cooking]]) {
            clock.advance(.milliseconds(5500))
        }
        var reach = flat.reach
        reach.path = { .remoteOnly }
        let actions = FlatActions(reach: reach)
        flat.transport.answer("POST /api/modes/cooking") {
            clock.advance(.seconds(7))
            try? await Task.sleep(for: .seconds(60))
        }
        let deadline = Deadline(after: .seconds(15), clock: clock.clock)
        await #expect(throws: FlatdError.noAnswer) {
            try await FlatdReach.$intentBudget.withValue(deadline) {
                try await actions.toggleCooking()
            }
        }
        #expect(flat.writes.count == 1)
        #expect((5.5...6).contains(try #require(flat.writes.first?.timeoutInterval)))
        #expect(flat.authenticated.map { $0.url?.path() } == ["/api/modes", "/api/modes/cooking"])
    }

    @Test func ordinaryCapsApplyBeforeDeadlineAndRequestTimeoutIsNotRetried() async throws {
        let flat = try RouteFixture()
        flat.fans()
        flat.transport.answer("POST /api/modes/cooking", fails: true, failure: .timedOut)
        await #expect(throws: FlatdError.noAnswer) {
            try await flat.reach.run(deadline: Deadline(after: .seconds(60))) { client in
                _ = try await client.devices()
                return try await client.setMode(FlatMode.cookingID, active: true)
            }
        }
        #expect(flat.authenticated.map(\.timeoutInterval) == [6, 12])
        #expect(flat.writes.count == 1)
    }

    @Test func ordinaryAbsoluteCapCancelsAWriteBeforeDeadline() async throws {
        let flat = try RouteFixture()
        let clock = TestClock()
        flat.transport.answer("POST /api/modes/cooking") {
            clock.advance(.seconds(13))
            try? await Task.sleep(for: .seconds(60))
        }
        let deadline = Deadline(after: .seconds(60), clock: clock.clock)
        await #expect(throws: FlatdError.noAnswer) {
            try await flat.reach.run(deadline: deadline) { try await $0.setMode(FlatMode.cookingID, active: true) }
        }
        #expect(flat.writes.count == 1 && deadline.remaining > .seconds(30))
    }

    @Test func cancellingCallerKeepsCancellationAfterWrite() async throws {
        let flat = try RouteFixture()
        let (started, signal) = AsyncStream<Void>.makeStream()
        flat.transport.answer("POST /api/modes/cooking") {
            signal.yield(())
            try? await Task.sleep(for: .seconds(60))
        }
        let task = Task {
            defer { signal.finish() }
            return try await FlatActions(reach: flat.reach).setCooking(true)
        }
        for await _ in started { break }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(flat.writes.count == 1)
    }
}

struct RemoteEnrollmentTests {
    @MainActor @Test func aLiveHomeSnapshotEnrollsAndRemoteClientNeverAsks() async throws {
        let (store, transport, events, _) = Flat.store()
        defer { store.stop() }
        transport.answer("GET /api/scenes", body: ["scenes": []])
        transport.answer("GET /api/remote", body: ["url": awayURL, "spki_sha256": awayPin])
        let connection = store.connection
        store.start()
        try #require(await eventually { events.isOpen })
        events.send(try Flat.snapshot())
        try #require(await eventually { connection.pairing?.remote != nil })
        let saved = try connection.current()
        #expect(saved.remote?.url.absoluteString == awayURL)
        #expect(saved.baseURL == Flat.base)

        let remote = try #require(FlatdClient(remoteOf: saved, transport: transport))
            .gated(by: connection, allowsRemote: { true })
        await FlatStore.enrollRemote(from: remote, read: saved, connection: connection)
        _ = try await remote.remoteEnrollment()
        connection.move(saved, to: remote)
        #expect(transport.sent.filter { $0.url?.path() == "/api/remote" }.count == 1)
        #expect(connection.pairing?.baseURL == Flat.base)
    }

    @Test func rejectsInvalidRemotePartFromWireAndStorage() throws {
        let old = Flat.pairing()
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(old)
        #expect(try decoder.decode(FlatdPairing.self, from: data) == old)
        let invalid = [
            "http://listener.home.example.net:8443", "https://127.0.0.1:8443", "https://[::1]:8443",
            awayURL + "/", awayURL + "?test", awayURL + "#test", "https://user@listener.home.example.net:8443",
            "https://listener.home.example.net", "https://listener:8443", "https://listener.home.example.net.:8443",
            "https://-listener.home.example.net:8443", "https://listener.home.example.net:0",
            "https://listener.home.example.net:65536", "HTTPS://listener.home.example.net:8443",
        ].map { ($0, awayPin) } + [(awayURL, old.pin.hex), (awayURL, "bad-pin"), (awayURL, awayPin.uppercased())]
        for (url, pin) in invalid {
            #expect(RemoteListener.parse(url: url, pin: pin, homePin: old.pin) == nil)
            var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            object["remote"] = ["url": url, "pin": pin]
            let decoded = try Flat.decode(FlatdPairing.self, object)
            #expect(decoded == old)
        }
    }

    @Test func equalHomePinAnd404LeaveEnrollmentWhileNullsClearIt() async throws {
        let flat = try RouteFixture()
        let client = FlatdClient(flat.pairing, transport: flat.transport).gated(by: flat.connection)
        flat.transport.answer("GET /api/remote", body: ["url": awayURL, "spki_sha256": flat.pairing.pin.hex])
        await FlatStore.enrollRemote(from: client, read: flat.pairing, connection: flat.connection)
        #expect(flat.connection.pairing == flat.pairing)
        flat.transport.answer("GET /api/remote", status: 404)
        await FlatStore.enrollRemote(from: client, read: flat.pairing, connection: flat.connection)
        #expect(flat.connection.pairing == flat.pairing)
        flat.transport.answer("GET /api/remote", body: ["url": NSNull(), "spki_sha256": NSNull()])
        await FlatStore.enrollRemote(from: client, read: flat.pairing, connection: flat.connection)
        #expect(flat.connection.pairing?.remote == nil)
    }

    @Test(arguments: ["pin", "url", "nulls", "token"]) func staleRemoteClientSendsNothing(change: String) async throws {
        let flat = try RouteFixture()
        let old = flat.pairing
        let client = try #require(FlatdClient(remoteOf: old, transport: flat.transport))
            .gated(by: flat.connection, allowsRemote: { true })
        if change == "token" {
            var renewal = Flat.pairing(token: Flat.renewedKey)
            renewal.remote = old.remote
            #expect(flat.connection.renew(old, with: renewal))
            #expect(flat.connection.pairing?.remote == nil)
        } else {
            let url = change == "url" ? "https://another.home.example.net:8443" : awayURL
            let pin = change == "pin" ? String(repeating: "12", count: 32) : awayPin
            let answer: [String: Any] = change == "nulls" ? ["url": NSNull(), "spki_sha256": NSNull()]
                : ["url": url, "spki_sha256": pin]
            flat.transport.answer("GET /api/remote", body: answer)
            let home = FlatdClient(old, transport: flat.transport).gated(by: flat.connection)
            await FlatStore.enrollRemote(from: home, read: old, connection: flat.connection)
            #expect(flat.connection.pairing?.remote != old.remote)
        }
        await #expect(throws: FlatdError.unreachable) { try await client.devices() }
        #expect(flat.transport.requests(to: away).isEmpty)
    }

    @Test func forgottenHomeClientSendsNothing() async throws {
        let flat = try RouteFixture()
        let home = FlatdClient(flat.pairing, transport: flat.transport).gated(by: flat.connection)
        try flat.connection.forget()
        await #expect(throws: FlatdError.notPaired) { try await home.devices() }
        #expect(flat.transport.sent.isEmpty)
    }

    @Test(arguments: ["move", "renew", "forget"]) func lateEnrollmentCannotOverwritePairingChange(change: String) async throws {
        let flat = try RouteFixture()
        let old = flat.pairing
        let home = FlatdClient(old, transport: flat.transport).gated(by: flat.connection)
        let changed = Flat.pairing(token: Flat.renewedKey)
        flat.transport.answer("GET /api/remote", body: ["url": NSNull(), "spki_sha256": NSNull()]) {
            switch change {
            case "move": flat.connection.move(old, to: FlatdClient(old, at: moved))
            case "renew": _ = flat.connection.renew(old, with: changed)
            default: try? flat.connection.forget()
            }
        }
        await FlatStore.enrollRemote(from: home, read: old, connection: flat.connection)
        switch change {
        case "move":
            #expect(flat.connection.pairing?.baseURL == moved)
            #expect(flat.connection.pairing?.remote == old.remote)
        case "renew": #expect(flat.connection.pairing == changed)
        default: #expect(flat.connection.pairing == nil)
        }
    }
}
