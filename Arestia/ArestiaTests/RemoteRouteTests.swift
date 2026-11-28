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
        let remote = try #require(RemoteListener.parse(url: awayURL, pin: awayPin, homePin: pairing.pin))
        pairing.remote = remote
        self.pairing = pairing
        try connection.save(pairing)
    }

    var reach: FlatdReach {
        FlatdReach(connection: connection, transport: transport, rediscover: { [] },
                   path: { .localPossible }, marker: RemoteMarker(read: { marker.withLock { $0 } }), needsPasscode: { false })
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

    @Test(arguments: [true, false]) func bonjourProbesBeforeSlowResolutionFinishes(unlocked: Bool) async throws {
        let flat = try RouteFixture()
        flat.marker.withLock { $0 = unlocked }
        flat.health(Flat.base.host()!, delay: .seconds(60))
        flat.health(away, delay: .seconds(60))
        let slowCancelled = OSAllocatedUnfairLock(initialState: false)
        var reach = flat.reach
        reach.rediscover = nil
        reach.bonjour = FlatdBonjour(browse: { ["fast", "slow"] }, resolve: { name in
            if name == "fast" { return moved }
            do {
                try await Task.sleep(for: .seconds(4))
            } catch {
                slowCancelled.withLock { $0 = true }
            }
            return nil
        })
        let start = ContinuousClock().now
        let selected = try await reach.run { $0 }
        #expect(start.duration(to: ContinuousClock().now) < .seconds(2))
        #expect(selected.route == .home && selected.baseURL == moved)
        #expect(slowCancelled.withLock { $0 })
    }

    @Test(arguments: [true, false]) func abandonedPolicyLookupCannotDispatch(homeWins: Bool) async throws {
        let flat = try RouteFixture()
        flat.fans()
        if homeWins {
            flat.health(Flat.base.host()!, delay: .milliseconds(750))
        } else {
            flat.transport.answer("GET 192.0.2.10/api/health", fails: true)
        }
        let release = DispatchSemaphore(value: 0)
        let (finished, finish) = AsyncStream<Void>.makeStream()
        let entered = OSAllocatedUnfairLock(initialState: false)
        var reach = flat.reach
        reach.path = { .localPossible }
        reach.marker = RemoteMarker(read: {
            entered.withLock { $0 = true }
            _ = release.wait(timeout: .now() + 2)
            finish.yield(())
            finish.finish()
            return true
        })
        let start = ContinuousClock().now
        let deadline = Deadline(after: homeWins ? .seconds(4) : .milliseconds(350))
        if homeWins {
            let route = try await reach.run(deadline: deadline) {
                _ = try await $0.devices()
                return $0.route
            }
            #expect(route == .home)
        } else {
            await #expect(throws: unlockError) {
                try await reach.run(deadline: deadline) { try await $0.devices() }
            }
        }
        #expect(entered.withLock { $0 })
        #expect(start.duration(to: ContinuousClock().now) < .milliseconds(1500))
        release.signal()
        for await _ in finished { break }
        try await Task.sleep(for: .milliseconds(100))
        #expect(flat.transport.requests(to: away).isEmpty)
    }

    @Test func passcodeLookupRunsAfterDispatchLockIsReleased() async throws {
        let flat = try RouteFixture()
        let connection = flat.connection
        var reach = flat.reach
        reach.path = { .remoteOnly }
        flat.transport.answer("GET 192.0.2.10/api/health", fails: true)
        flat.health(away) { flat.marker.withLock { $0 = false } }
        reach.needsPasscode = {
            let cap = Deadline(after: .milliseconds(250))
            return (try? connection.lock.withLock(until: cap, hold: Attempt<Void>(until: cap)) { true }) ?? false
        }
        await #expect(throws: FlatdError.awayNeedsUnlock(needsPasscode: true)) {
            try await reach.run { try await $0.devices() }
        }
        #expect(flat.authenticated.isEmpty)
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
            .gated(by: flat.connection, marker: RemoteMarker(read: { false }))
        await #expect(throws: FlatdGate.RemoteDenied.self) { try await lockedRemote.devices() }
        #expect(flat.transport.sent.isEmpty)

        _ = try await FlatdClient(flat.pairing, transport: flat.transport)
            .gated(by: flat.connection, marker: RemoteMarker(read: { false })).devices()
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
        let pins = OSAllocatedUnfairLock(initialState: [FlatdPin]())
        reach.transport = nil
        let actions = FlatActions(reach: reach)
        try await FlatdTransport.$fixtureTransport.withValue({ pin in
            pins.withLock { $0.append(pin) }
            return flat.transport
        }) { () async throws in
            #expect(try await actions.fans().count == 2)
            #expect(try await actions.setFans(on: true).count == 2)
        }
        let expectedPin = try #require(flat.pairing.remote?.pin)
        #expect(pins.withLock { $0 } == Array(repeating: expectedPin, count: flat.transport.sent.count))
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
        reach.marker = RemoteMarker(read: {
            // Choice, devices read, first write, second write.
            reads.withLock { $0 += 1; return $0 <= 3 }
        })
        await #expect(throws: FlatdError.partialFans(needsUnlock: true)) {
            try await FlatActions(reach: reach).setFans(on: true)
        }
        #expect(flat.writes.count == 1)
        #expect(flat.writes.first?.url?.host() == away)
        #expect(flat.transport.requests(to: Flat.base.host()!).isEmpty)
    }
}

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

struct ActionDeadlineTests {
    @Test func stalledRemoteMarkerLeavesTimeForOneHomeAction() async throws {
        let flat = try RouteFixture()
        flat.cooking()
        let clock = TestClock()
        let stall = BlockingStep()
        defer { stall.release.signal() }
        var reach = flat.reach
        reach.path = { .remoteOnly }
        let reads = OSAllocatedUnfairLock(initialState: 0)
        reach.marker = RemoteMarker(read: {
            if reads.withLock({ $0 += 1; return $0 }) == 2 { stall.wait() }
            return true
        })
        let deadline = Deadline(after: .seconds(15), clock: clock.clock)
        let actions = FlatActions(reach: reach)
        let action = Task {
            try await FlatdReach.$intentBudget.withValue(deadline) { try await actions.toggleCooking() }
        }
        try #require(await eventually { stall.entered })
        clock.advance(.milliseconds(1100))
        try #require(await eventually {
            flat.transport.requests(to: Flat.base.host()!).contains { $0.url?.path() == "/api/health" }
        })
        #expect(!stall.exited)
        #expect(flat.authenticated.isEmpty)
        stall.release.signal()
        #expect(try await action.value.isActive)
        #expect(flat.authenticated.map { $0.url?.host() } == [Flat.base.host(), Flat.base.host()])
        #expect(flat.writes.count == 1)
    }

    @Test func stalledMarkerAfterLockReturnsByDeadlineAndNeverDispatches() async throws {
        let flat = try RouteFixture()
        let clock = TestClock()
        var reach = flat.reach
        reach.path = { .remoteOnly }
        let reads = OSAllocatedUnfairLock(initialState: 0)
        let stall = BlockingStep()
        defer { stall.release.signal() }
        reach.marker = RemoteMarker(read: {
            let count = reads.withLock { $0 += 1; return $0 }
            if count == 2 { stall.wait() }
            return true
        })
        let deadline = Deadline(after: .seconds(4), clock: clock.clock)
        let task = Task {
            try await reach.run(deadline: deadline) { try await $0.setMode(FlatMode.cookingID, active: true) }
        }
        try #require(await eventually { stall.entered })
        clock.advance(.seconds(5))
        await #expect(throws: FlatdError.unreachable) { try await task.value }
        #expect(!stall.exited)
        #expect(flat.transport.sent.count == 1)   // only the remote health probe
        stall.release.signal()
        try #require(await eventually { stall.exited })
        // Wait for the worker to leave the dispatch lock before counting arrivals.
        try await Deadline(after: .seconds(1)).blocking { hold in
            try flat.connection.lock.withLock(until: hold.deadline, hold: hold) {}
        }
        #expect(flat.transport.sent.count == 1)
    }

    @Test(arguments: [1, 2]) func stalledPairingReadReturnsByDeadline(readToStall: Int) async throws {
        let keys = MemoryKeys()
        let connection = FlatdConnection(defaults: nil, names: nil, keychain: keys, lock: .processOnly)
        try connection.save(Flat.pairing())
        let clock = TestClock()
        let stall = BlockingStep()
        defer { stall.release.signal() }
        let reads = OSAllocatedUnfairLock(initialState: 0)
        keys.afterRead = {
            if reads.withLock({ $0 += 1; return $0 }) == readToStall { stall.wait() }
        }
        let transport = FakeTransport()
        let reach = FlatdReach(connection: connection, transport: transport, rediscover: { [] }, path: { .localPossible })
        let deadline = Deadline(after: .seconds(4), clock: clock.clock)
        let task = Task { try await reach.run(deadline: deadline) { $0.route } }
        try #require(await eventually { stall.entered })
        clock.advance(.seconds(5))
        await #expect(throws: FlatdError.unreachable) { try await task.value }
        #expect(!stall.exited)
        stall.release.signal()
        try #require(await eventually { stall.exited })
        #expect(transport.sent.count == (readToStall == 1 ? 0 : 1))
    }

    @Test func remoteRefusalLeavesHomeWriteBudget() async throws {
        let flat = try RouteFixture()
        let clock = TestClock()
        var reach = flat.reach
        reach.path = { .remoteOnly }
        reach.needsPasscode = {
            Issue.record("Home can answer, so no unlock sentence is needed")
            clock.advance(.seconds(12))
            return false
        }
        flat.health(away) { flat.marker.withLock { $0 = false } }
        flat.cooking()
        let remaining = OSAllocatedUnfairLock(initialState: Duration.zero)
        let deadline = Deadline(after: .seconds(15), clock: clock.clock)
        var active = Flat.cooking
        active["active"] = true
        flat.transport.answer("POST /api/modes/cooking", body: active) {
            remaining.withLock { $0 = deadline.remaining }
        }
        let change = try await FlatdReach.$intentBudget.withValue(deadline) {
            try await FlatActions(reach: reach).setCooking(true)
        }
        #expect(change.isActive)
        #expect(remaining.withLock { $0 } >= .seconds(3))
        #expect(flat.writes.map { $0.url?.host() } == [Flat.base.host()])
    }

    @Test(arguments: ["move", "note", "clearTrouble"])
    func cancellationWhileWaitingForBookkeeping(operation: String) async throws {
        let held = HeldDispatchLock()
        defer { held.stall.release.signal() }
        let connection = FlatdConnection(defaults: UserDefaults(suiteName: "arestia-tests-" + UUID().uuidString),
                                        names: nil, keychain: MemoryKeys(), lock: held.lock)
        let pairing = Flat.pairing()
        try connection.save(pairing)
        let trouble = ModeTrouble(pairing: pairing.id, mode: "cooking", active: true, names: ["Earlier fan"], at: .now)
        try await connection.note(trouble)
        let transport = FakeTransport()
        if operation == "move" {
            transport.answer("GET 192.0.2.10/api/health", fails: true)
        }
        var active = Flat.cooking
        active["active"] = true
        if operation == "note" { active["failed"] = ["fan:fan_1": "timeout"] }
        transport.answer("POST /api/modes/cooking", body: active) { await held.take() }
        let reach = FlatdReach(connection: connection, transport: transport, rediscover: { [moved] }, path: { .localPossible })
        let task = Task { try await FlatActions(reach: reach).setCooking(true) }
        try #require(await eventually { held.waiting.withLock { $0 } })
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(!held.stall.exited)
        held.stall.release.signal()
        try #require(await eventually { held.stall.exited })
        try await Deadline(after: .seconds(1)).blocking { hold in try held.lock.withLock(until: hold.deadline, hold: hold) {} }
        #expect(connection.pairing == pairing)
        #expect(connection.trouble(mode: "cooking", active: true, pairing: pairing.id) == trouble)
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

    @Test func completionRacingTheCapStillExpires() async {
        let clock = TestClock()
        let cap = Deadline(after: .seconds(1), clock: clock.clock)
        await #expect(throws: Deadline.Expired.self) {
            try await cap.run {
                clock.advance(.seconds(2))
                return true
            }
        }
    }

    @Test(arguments: [true, false]) func unansweredFanWriteTakesPrecedence(timeoutFirst: Bool) async throws {
        let flat = try RouteFixture()
        flat.fans()
        flat.transport.answer("GET /api/devices", body: ["devices": [Flat.fan(1), Flat.fan(2), Flat.fan(3)]])
        flat.transport.answer("POST /api/devices/fan:fan_3", body: Flat.fan(3, on: true))
        let clock = TestClock()
        let deadline = Deadline(after: .seconds(15), clock: clock.clock)
        flat.transport.answer("POST /api/devices/fan:fan_1", status: 500,
                              delay: timeoutFirst ? .milliseconds(250) : nil)
        if timeoutFirst {
            flat.transport.answer("POST /api/devices/fan:fan_2", fails: true, failure: .timedOut)
        } else {
            flat.transport.answer("POST /api/devices/fan:fan_2", delay: .milliseconds(250)) {
                clock.advance(.seconds(16))
                try? await Task.sleep(for: .seconds(60))
            }
        }
        await #expect(throws: FlatdError.noAnswer) {
            try await FlatdReach.$intentBudget.withValue(deadline) {
                try await FlatActions(reach: flat.reach).setFans(on: true)
            }
        }
        #expect(flat.writes.count == 3)
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
    @MainActor @Test func supersededEnrollmentCannotCommitEvenIfItReturnsSuccessfully() async throws {
        let connection = Flat.connection()
        let pairing = try connection.current()
        let transport = FakeTransport()
        transport.answer("GET /api/remote", body: ["url": awayURL, "spki_sha256": awayPin])
        let home = FlatdClient(pairing, transport: transport).gated(by: connection)
        await FlatStore.enrollRemote(from: home, read: pairing, connection: connection, isLatest: { false })
        #expect(transport.sent.map { $0.url?.path() } == ["/api/remote"])
        #expect(connection.pairing == pairing)
    }

    @MainActor @Test func newerSnapshotSupersedesDelayedEnrollmentAcrossReconnect() async throws {
        let connection = Flat.connection(linked: false)
        var initial = Flat.pairing()
        let initialRemote: RemoteListener = try #require(RemoteListener.parse(url: "https://old.home.example.net:8443",
                                                                              pin: awayPin, homePin: initial.pin))
        initial.remote = initialRemote
        try connection.save(initial)
        let (store, transport, events, _) = Flat.store(connection: connection)
        let oldReply = OSAllocatedUnfairLock<CheckedContinuation<Void, Never>?>(initialState: nil)
        func releaseOldReply() { oldReply.withLock { $0?.resume(); $0 = nil } }
        defer {
            releaseOldReply()
            store.stop()
        }
        let replies = OSAllocatedUnfairLock(initialState: [Int]())
        transport.answer("GET /api/scenes", body: ["scenes": []])
        transport.answer("GET /api/remote", body: ["url": awayURL, "spki_sha256": awayPin]) {
            await withCheckedContinuation { ready in oldReply.withLock { $0 = ready } }
            replies.withLock { $0.append(1) }
        }
        store.start()
        try #require(await eventually { events.isOpen })
        events.send(try Flat.snapshot())
        try #require(await eventually { oldReply.withLock { $0 != nil } })
        transport.answer("GET /api/remote", body: ["url": NSNull(), "spki_sha256": NSNull()]) {
            replies.withLock { $0.append(2) }
        }
        events.end(FlatdError.unreachable)
        try #require(await eventually({ events.isOpen }, timeout: .seconds(4)))
        events.send(try Flat.snapshot())
        try #require(await eventually { replies.withLock { $0 } == [2] && connection.pairing?.remote == nil })
        // The newer reply has committed before the server completes the old request.
        releaseOldReply()
        try #require(await eventually { replies.withLock { $0 } == [2, 1] })
        try await Task.sleep(for: .milliseconds(100))
        #expect(store.connection.pairing?.remote == nil)
    }

    @MainActor @Test(arguments: [false, true])
    func streamEventAppliesWhileEnrollmentCommitWaitsForLock(holdBeyondCap: Bool) async throws {
        let held = HeldDispatchLock()
        defer { held.stall.release.signal() }
        let connection = FlatdConnection(defaults: nil, names: Flat.nameFile(), keychain: MemoryKeys(), lock: held.lock)
        var initial = Flat.pairing()
        if holdBeyondCap {
            let remote: RemoteListener = try #require(RemoteListener.parse(url: awayURL, pin: awayPin, homePin: initial.pin))
            initial.remote = remote
        }
        try connection.save(initial)
        let (store, transport, events, _) = Flat.store(connection: connection)
        defer { store.stop() }
        transport.answer("GET /api/scenes", body: ["scenes": []])
        let enrollment: [String: Any] = holdBeyondCap
            ? ["url": NSNull(), "spki_sha256": NSNull()] : ["url": awayURL, "spki_sha256": awayPin]
        transport.answer("GET /api/remote", body: enrollment) {
            let savedNames = await eventually { connection.devicesVersion != nil }
            #expect(savedNames)
            await held.take()
        }
        store.start()
        try #require(await eventually { events.isOpen })
        events.send(try Flat.snapshot())
        try #require(await eventually { held.waiting.withLock { $0 } })
        var renamed = Flat.fan(1, on: true)
        renamed["label"] = "Desk fan"
        let fan = try Flat.decode(Device.self, renamed)
        events.send(.device(fan, source: nil))
        events.send(.state(id: fan.id, state: fan.state, source: nil))
        try #require(await eventually { store.device(fan.id)?.label == "Desk fan" && store.device(fan.id)?.state.on == true })
        #expect(!held.stall.exited)
        #expect(connection.pairing?.remote == initial.remote)
        #expect(connection.knownDevices.first?.label == "Fan 1")
        if holdBeyondCap {
            try await Task.sleep(for: .milliseconds(6300))
            #expect(!held.stall.exited)
        }
        held.stall.release.signal()
        try #require(await eventually { connection.knownDevices.first?.label == "Desk fan" })
        if holdBeyondCap {
            try #require(await eventually { connection.pairing?.remote == nil })
            #expect(transport.sent.filter { $0.url?.path() == "/api/remote" }.count == 1)
            let reach = FlatdReach(connection: connection, transport: transport, rediscover: { [] },
                                   path: { .remoteOnly }, marker: RemoteMarker(read: { true }))
            await #expect(throws: FlatdError.unreachable) {
                try await FlatActions(reach: reach).setCooking(true)
            }
            #expect(transport.requests(to: away).isEmpty)
        } else {
            try #require(await eventually { connection.pairing?.remote?.url.absoluteString == awayURL })
        }
    }

    @MainActor @Test func enrollmentCannotMoveOverANewerHomeAddress() async throws {
        let (store, transport, events, _) = Flat.store()
        let connection = store.connection
        defer { store.stop() }
        transport.answer("GET /api/scenes", body: ["scenes": []])
        transport.answer("GET /api/remote", body: ["url": awayURL, "spki_sha256": awayPin])
        _ = store.listen { event in
            guard case .snapshot = event else { return }
            // A control saved the new address after this snapshot read the old one.
            do {
                var current = try connection.current()
                current.baseURL = moved
                current.revision = UUID()
                try connection.save(current)
            } catch {
                Issue.record(error)
            }
        }
        store.start()
        try #require(await eventually { events.isOpen })
        events.send(try Flat.snapshot())
        try #require(await eventually { connection.pairing?.remote?.url.absoluteString == awayURL })
        #expect(connection.pairing?.baseURL == moved)
    }

    @Test func clearingAndReenrollingIdenticalRemoteRetiresOldClient() async throws {
        let flat = try RouteFixture()
        let home = FlatdClient(flat.pairing, transport: flat.transport).gated(by: flat.connection)
        let old = try #require(FlatdClient(remoteOf: flat.pairing, transport: flat.transport))
            .gated(by: flat.connection, marker: RemoteMarker(read: { true }))
        flat.transport.answer("GET /api/remote", body: ["url": NSNull(), "spki_sha256": NSNull()])
        await FlatStore.enrollRemote(from: home, read: flat.pairing, connection: flat.connection)
        let cleared = try flat.connection.current()
        try #require(cleared.remote == nil)
        flat.transport.answer("GET /api/remote", body: ["url": awayURL, "spki_sha256": awayPin])
        await FlatStore.enrollRemote(from: home, read: cleared, connection: flat.connection)
        let reenrolled = try flat.connection.current()
        #expect(reenrolled.token == flat.pairing.token)
        #expect(reenrolled.remote?.url == flat.pairing.remote?.url)
        #expect(reenrolled.remote?.pin == flat.pairing.remote?.pin)
        #expect(reenrolled.remote?.generation != flat.pairing.remote?.generation)
        await #expect(throws: FlatdError.unreachable) { try await old.devices() }
        #expect(flat.transport.requests(to: away).isEmpty)
        flat.fans()
        let current = try #require(FlatdClient(remoteOf: reenrolled, transport: flat.transport))
            .gated(by: flat.connection, marker: RemoteMarker(read: { true }))
        #expect(try await current.devices().count == 2)
    }

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
            .gated(by: connection, marker: RemoteMarker(read: { true }))
        await FlatStore.enrollRemote(from: remote, read: saved, connection: connection)
        _ = try await remote.remoteEnrollment()
        try? await connection.move(saved, to: remote)
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

    @Test func aSavedRemoteWithoutGenerationMigratesOnTheNextWrite() throws {
        let original = Flat.pairing()
        let data = try JSONEncoder().encode(original)
        var oldRecord = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        oldRecord["remote"] = ["url": awayURL, "pin": awayPin]
        let saved = try Flat.decode(FlatdPairing.self, oldRecord)
        #expect(saved.remote?.generation == original.revision)
        var movedPairing = saved
        movedPairing.baseURL = moved
        movedPairing.revision = UUID()
        let reread = try JSONDecoder().decode(FlatdPairing.self, from: JSONEncoder().encode(movedPairing))
        #expect(reread.remote?.generation == saved.remote?.generation)
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
            .gated(by: flat.connection, marker: RemoteMarker(read: { true }))
        if change == "token" {
            var renewal = Flat.pairing(token: Flat.renewedKey)
            renewal.remote = old.remote
            #expect(try await flat.connection.renew(old, with: renewal))
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
        try await flat.connection.forgetSavedPairing()
        await #expect(throws: FlatdError.notPaired) { try await home.devices() }
        #expect(flat.transport.sent.isEmpty)
    }

    @Test func oldTokensCannotDispatchAfterRenewalAndReenrollment() async throws {
        let flat = try RouteFixture()
        flat.fans()
        let oldHome = FlatdClient(flat.pairing, transport: flat.transport).gated(by: flat.connection)
        let oldRemote = try #require(FlatdClient(remoteOf: flat.pairing, transport: flat.transport))
            .gated(by: flat.connection, marker: RemoteMarker(read: { true }))
        let renewed = Flat.pairing(token: Flat.renewedKey)
        try #require(try await flat.connection.renew(flat.pairing, with: renewed))
        flat.transport.answer("GET /api/remote", body: ["url": awayURL, "spki_sha256": awayPin])
        let home = FlatdClient(renewed, transport: flat.transport).gated(by: flat.connection)
        await FlatStore.enrollRemote(from: home, read: renewed, connection: flat.connection)
        try #require(flat.connection.pairing?.remote?.url == flat.pairing.remote?.url)
        for client in [oldHome, oldRemote] {
            await #expect(throws: FlatdError.unreachable) { try await client.devices() }
        }
        #expect(flat.authenticated.map { $0.url?.path() } == ["/api/remote"])
    }

    @Test func neitherPairedRouteSendsAuthenticatedRequestsWithoutGate() async throws {
        let flat = try RouteFixture()
        flat.fans()
        let home = FlatdClient(flat.pairing, transport: flat.transport)
        let remote = try #require(FlatdClient(remoteOf: flat.pairing, transport: flat.transport))
        for client in [home, remote] {
            #expect(try await client.health())
            await #expect(throws: FlatdError.unreachable) { try await client.devices() }
        }
        #expect(flat.authenticated.isEmpty)
    }

    @Test(arguments: ["move", "renew", "forget"]) func lateEnrollmentCannotOverwritePairingChange(change: String) async throws {
        let flat = try RouteFixture()
        let old = flat.pairing
        let home = FlatdClient(old, transport: flat.transport).gated(by: flat.connection)
        let changed = Flat.pairing(token: Flat.renewedKey)
        flat.transport.answer("GET /api/remote", body: ["url": NSNull(), "spki_sha256": NSNull()]) {
            switch change {
            case "move": try? await flat.connection.move(old, to: FlatdClient(old, at: moved))
            case "renew": _ = try? await flat.connection.renew(old, with: changed)
            default: try? await flat.connection.forgetSavedPairing()
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

private nonisolated final class BlockingStep: Sendable {
    let release = DispatchSemaphore(value: 0)
    private let timeout: TimeInterval

    init(timeout: TimeInterval = 9) { self.timeout = timeout }

    private let status = OSAllocatedUnfairLock(initialState: 0)
    var entered: Bool { status.withLock { $0 > 0 } }
    var exited: Bool { status.withLock { $0 == 2 } }

    func wait() {
        status.withLock { $0 = 1 }
        _ = release.wait(timeout: .now() + timeout)
        status.withLock { $0 = 2 }
    }
}

private nonisolated struct HeldDispatchLock: Sendable {
    let stall: BlockingStep
    let waiting: OSAllocatedUnfairLock<Bool>
    let lock: FlatdDispatchLock

    init(timeout: TimeInterval = 9) {
        stall = BlockingStep(timeout: timeout)
        let waiting = OSAllocatedUnfairLock(initialState: false)
        self.waiting = waiting
        lock = .processOnly(onContention: { waiting.withLock { $0 = true } })
    }

    func take() async {
        Task {
            _ = try? await Deadline(after: .seconds(30)).blocking { hold in
                try lock.withLock(until: hold.deadline, hold: hold) { stall.wait() }
            }
        }
        while !stall.entered && !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}

struct RouteIsolationTests {
    @Test func stalledHomeProbeDoesNotHoldRemoteWinner() async throws {
        let stall = BlockingStep()
        defer { stall.release.signal() }
        let homeEntered = AsyncStream<Void>.makeStream()
        let choice = Task {
            try await HomeRoute.select(deadline: Deadline(after: .seconds(5)), path: { .localPossible },
                                       home: { cap in
                try? await cap.blocking { _ in
                    homeEntered.continuation.yield(())
                    stall.wait()
                    return "home"
                }
            }, discover: { _ in nil }, remote: { _ in "remote" })
        }
        for await _ in homeEntered.stream { break }
        let answer = try await choice.value
        guard case .reached("remote") = answer else {
            Issue.record("The remote probe did not win")
            return
        }
        #expect(!stall.exited)
    }

    @Test func stalledSessionCreationDoesNotHoldAnotherPin() async throws {
        let stall = BlockingStep()
        defer { stall.release.signal() }
        let other = try #require(FlatdPin(awayPin))
        let homePin = Flat.pin
        let pool = PinnedSession(makeSession: { config, pin in
            if pin == homePin { stall.wait() }
            return URLSession(configuration: config)
        })
        let first = Task { try await Deadline(after: .seconds(2)).blocking { _ in pool.shared(pin: homePin) } }
        defer { first.cancel() }
        try #require(await eventually { stall.entered })
        let second = try await Deadline(after: .milliseconds(300)).blocking { _ in pool.shared(pin: other) }
        #expect(!stall.exited)
        second.invalidateAndCancel()
        stall.release.signal()
        try await first.value.invalidateAndCancel()
    }
}

struct LaunchTests {
    @Test func pairedStreamRefusesAnUngatedRemoteClient() async throws {
        let flat = try RouteFixture()
        let client = try #require(FlatdClient(remoteOf: flat.pairing, transport: flat.transport))
        let events = FakeEvents()
        await #expect(throws: FlatdError.notPaired) { try await client.openEvents(using: events) }
        #expect(events.requests.isEmpty)
    }

    @Test(arguments: [false, true]) func markerIsReadAfterHTTPSAndWebSocketPreparation(socket: Bool) async throws {
        let flat = try RouteFixture()
        let client = try #require(FlatdClient(remoteOf: flat.pairing, transport: flat.transport))
            .gated(by: flat.connection, marker: flat.reach.marker)
        let marker = flat.marker
        let lockPhone: @Sendable () -> Void = { marker.withLock { $0 = false } }
        if socket {
            let events = FakeEvents()
            events.onPrepare = lockPhone
            await #expect(throws: FlatdGate.RemoteDenied.self) {
                try await client.openEvents(using: events)
            }
            #expect(events.requests.isEmpty)
            marker.withLock { $0 = true }
            events.onPrepare = nil
            _ = try await client.openEvents(using: events)
            #expect(events.requests.map { $0.url?.host() } == [away])
            #expect(events.pins == [client.pin])
        } else {
            flat.transport.onPrepare = { _ in lockPhone() }
            await #expect(throws: FlatdGate.RemoteDenied.self) {
                try await client.setMode("cooking", active: true)
            }
            #expect(flat.writes.isEmpty)
        }
    }

    @Test func aMarkerReadOlderThanOneSecondRefusesAdmission() async throws {
        let flat = try RouteFixture()
        let clock = TestClock()
        var client = try #require(FlatdClient(remoteOf: flat.pairing, transport: flat.transport))
            .gated(by: flat.connection, marker: RemoteMarker(read: {
                clock.advance(.seconds(2))
                return true
            }))
        client.deadline = Deadline(after: .seconds(6), clock: clock.clock)
        client.action = FlatdActionDispatch()
        await #expect(throws: FlatdGate.RemoteDenied.self) { try await client.setMode("cooking", active: true) }
        #expect(client.action?.writeStarted == false)
        #expect(flat.writes.isEmpty)
    }

    @Test func aStalledPairingReadDuringAdmissionCannotResumeLater() async throws {
        let keys = MemoryKeys()
        let connection = FlatdConnection(defaults: nil, names: nil, keychain: keys, lock: .processOnly)
        let saved = Flat.pairing()
        try connection.save(saved)
        let clock = TestClock()
        let stall = BlockingStep()
        defer { stall.release.signal() }
        keys.afterRead = { stall.wait() }
        let transport = FakeTransport()
        var client = FlatdClient(saved, transport: transport).gated(by: connection)
        client.deadline = Deadline(after: .seconds(4), clock: clock.clock)
        let request = Task { try await client.setMode("cooking", active: true) }
        try #require(await eventually { stall.entered })
        clock.advance(.seconds(5))
        await #expect(throws: FlatdError.unreachable) { try await request.value }
        #expect(!stall.exited)
        stall.release.signal()
        let cap = Deadline(after: .seconds(1))
        try await cap.blocking { hold in
            try connection.lock.withLock(until: cap, hold: hold) {}
        }
        #expect(transport.sent.isEmpty)
    }

    @Test(arguments: [false, true]) func stalledAfterResumeDoesNotDelayReplyOrTimeout(answers: Bool) async throws {
        let flat = try RouteFixture()
        let clock = TestClock()
        let stall = BlockingStep(timeout: 5)
        defer { stall.release.signal() }
        let cancelled = OSAllocatedUnfairLock(initialState: false)
        flat.transport.afterResume = { _ in stall.wait() }
        flat.transport.cancelled = { _ in cancelled.withLock { $0 = true } }
        flat.transport.answer("POST /api/modes/cooking", body: Flat.cooking) {
            if !answers { try? await Task.sleep(for: .seconds(60)) }
        }
        var client = FlatdClient(flat.pairing, transport: flat.transport).gated(by: flat.connection)
        client.deadline = Deadline(after: .seconds(4), clock: clock.clock)
        client.action = FlatdActionDispatch()
        let task = Task { try await client.setMode("cooking", active: true) }
        try #require(await eventually { stall.entered })
        if answers {
            #expect(try await task.value.mode.id == "cooking")
            #expect(!cancelled.withLock { $0 })
        } else {
            clock.advance(.seconds(5))
            await #expect(throws: FlatdError.noAnswer) { try await task.value }
            #expect(await eventually { cancelled.withLock { $0 } })
        }
        #expect(!stall.exited)
    }

    @Test func outerCancellationCancelsTheResumedRequest() async throws {
        let flat = try RouteFixture()
        let cancelled = OSAllocatedUnfairLock(initialState: false)
        flat.transport.cancelled = { _ in cancelled.withLock { $0 = true } }
        flat.transport.answer("POST /api/modes/cooking") { try? await Task.sleep(for: .seconds(60)) }
        let client = FlatdClient(flat.pairing, transport: flat.transport).gated(by: flat.connection)
        let task = Task {
            try await Deadline(after: .seconds(15)).run { try await client.setMode("cooking", active: true) }
        }
        try #require(await eventually { flat.writes.count == 1 })
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        #expect(await eventually { cancelled.withLock { $0 } })
    }

    @Test func productionTimeoutStopsLoadingAResumedRequest() async throws {
        let flat = try RouteFixture()
        let clock = TestClock()
        let pool = PinnedSession(makeSession: { config, _ in
            config.protocolClasses = [StalledHTTP.self]
            return URLSession(configuration: config)
        })
        var transport = FlatdTransport(pin: flat.pairing.pin)
        transport.testSessions = pool
        var client = FlatdClient(flat.pairing, transport: transport).gated(by: flat.connection)
        client.deadline = Deadline(after: .seconds(4), clock: clock.clock)
        client.action = FlatdActionDispatch()
        let task = Task { try await client.setMode("cooking", active: true) }
        try #require(await eventually { StalledHTTP.state.withLock { $0 == 1 } })
        clock.advance(.seconds(5))
        await #expect(throws: FlatdError.noAnswer) { try await task.value }
        #expect(await eventually { StalledHTTP.state.withLock { $0 == 2 } })
    }

    @Test func replyAndCapRaceHasOneOutcomeAcrossTwoHundredRuns() async throws {
        let url = URL(string: "https://fixture.example.net")!
        let reply = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        for _ in 0..<200 {
            let instant = ContinuousClock().now
            let boundary = OSAllocatedUnfairLock(initialState: false)
            let tick = AsyncStream<Void>.makeStream()
            let late = AsyncStream<Bool>.makeStream()
            let clock = Deadline.Clock(now: { boundary.withLock { $0 ? instant + .seconds(1) : instant } },
                                       sleepUntil: { _ in for await _ in tick.stream { break } })
            let cancelled = OSAllocatedUnfairLock(initialState: 0)
            let outcome: Attempt<HTTPReply>.Outcome = await FlatdLaunch.run(
                admission: .open, rule: WriteRule(cap: Deadline(after: .seconds(1), clock: clock), isWrite: true),
                prepare: { attempt in
                    .init(request: FakeRequest(onResume: {}, onCancel: { cancelled.withLock { $0 += 1 } }), afterStart: {
                        boundary.withLock { $0 = true }
                        tick.continuation.yield(())
                        $0.end(.success((Data(), reply)))
                        late.continuation.yield($0.end(.success((Data(), reply))))
                        late.continuation.finish()
                        tick.continuation.finish()
                    })
                })
            #expect(outcome.committed)
            #expect(throws: FlatdError.noAnswer) {
                try FlatdClient.classify(outcome, isWrite: true, inAction: true)
            }
            #expect(await eventually { cancelled.withLock { $0 } == 1 })
            var laterReply = late.stream.makeAsyncIterator()
            #expect(await laterReply.next() == false)
        }
    }

    @Test func droppedActionWriteProducesNoAnswer() async throws {
        let flat = try RouteFixture()
        flat.transport.answer("POST /api/modes/cooking", fails: true, failure: .networkConnectionLost)
        await #expect(throws: FlatdError.noAnswer) {
            try await flat.reach.run { try await $0.setMode("cooking", active: true) }
        }
        #expect(flat.writes.count == 1)
    }

    @Test func stalledProbePreparationDoesNotHoldTheRemoteWinner() async throws {
        let flat = try RouteFixture()
        let clock = TestClock()
        let stall = BlockingStep()
        defer { stall.release.signal() }
        let homeHost = Flat.base.host()
        flat.transport.onPrepare = { request in
            if request.url?.host() == homeHost { stall.wait() }
        }
        let choice = Task {
            try await flat.reach.run(deadline: Deadline(after: .seconds(5), clock: clock.clock)) { $0.route }
        }
        try #require(await eventually { stall.entered })
        let start = ContinuousClock.now
        clock.advance(.milliseconds(500))
        #expect(try await choice.value == .remote)
        #expect(start.duration(to: .now) < .milliseconds(100))
        #expect(!stall.exited)
        #expect(flat.transport.requests(to: try #require(homeHost)).isEmpty)
    }
}

private nonisolated final class StalledHTTP: URLProtocol, @unchecked Sendable {
    static let state = OSAllocatedUnfairLock(initialState: 0)

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { Self.state.withLock { $0 = 1 } }
    override func stopLoading() { Self.state.withLock { $0 = 2 } }
}

struct OutcomeTests {
    @Test func requestClassificationMatchesEveryRow() throws {
        let response = try #require(HTTPURLResponse(url: Flat.base, statusCode: 409, httpVersion: nil, headerFields: nil))
        let bytes = Data("fixture".utf8)
        let received = try FlatdClient.classify(.init(result: .success((bytes, response)), committed: true),
                                                isWrite: true, inAction: true)
        #expect(received.0 == bytes && received.1.statusCode == 409)

        func classify(_ error: any Error, committed: Bool, write: Bool = true, action: Bool = true) throws {
            _ = try FlatdClient.classify(.init(result: .failure(error), committed: committed),
                                         isWrite: write, inAction: action)
        }
        for committed in [false, true] {
            #expect(throws: CancellationError.self) { try classify(CancellationError(), committed: committed) }
        }
        for refusal in [FlatdError.notPaired, .pairingUnreadable, .unreachable] {
            #expect(throws: refusal) { try classify(refusal, committed: false) }
        }
        #expect(throws: FlatdGate.RemoteDenied.self) { try classify(FlatdGate.RemoteDenied(), committed: false) }
        #expect(throws: FlatdError.unreachable) { try classify(Deadline.Expired(), committed: false) }
        #expect(throws: FlatdError.noAnswer) { try classify(Deadline.Expired(), committed: true) }
        #expect(throws: FlatdError.noAnswer) {
            try classify(URLError(.timedOut), committed: true, write: false, action: false)
        }
        #expect(throws: FlatdError.noAnswer) { try classify(URLError(.networkConnectionLost), committed: true) }
        #expect(throws: FlatdError.unreachable) {
            try classify(URLError(.networkConnectionLost), committed: true, action: false)
        }
        #expect(throws: FlatdError.unreachable) {
            try classify(URLError(.networkConnectionLost), committed: true, write: false)
        }
    }

    @Test func actionResolutionMatchesEveryRowInOrder() throws {
        typealias Outcome = FlatdOutcome<Int>
        let value = Result<Int, Error>.success(7)
        let denied = Result<Int, Error>.failure(FlatdGate.RemoteDenied())
        let unanswered = Result<Int, Error>.failure(FlatdError.noAnswer)

        func result(_ outcome: Outcome) throws -> Int {
            guard case let .finish(result) = outcome else {
                Issue.record("Expected a final outcome")
                throw FlatdError.invalidAnswer
            }
            return try result.get()
        }

        #expect(throws: CancellationError.self) {
            try result(Outcome.resolve(denied, writeStarted: true, pairing: .gone, cancelled: true))
        }
        #expect(throws: FlatdError.notPaired) {
            try result(Outcome.resolve(unanswered, writeStarted: true, pairing: .gone, cancelled: false))
        }
        if case .retryHome = Outcome.resolve(denied, writeStarted: false, pairing: .same, cancelled: false) {}
        else { Issue.record("A refusal before the first write must allow one home retry") }
        if case .needsUnlock = Outcome.resolve(denied, writeStarted: true, pairing: .same, cancelled: false) {}
        else { Issue.record("A refusal after a write must retain the unlock outcome") }
        #expect(try result(Outcome.resolve(value, writeStarted: true, pairing: .unknown, cancelled: false)) == 7)
        #expect(throws: FlatdError.noAnswer) {
            try result(Outcome.resolve(unanswered, writeStarted: true, pairing: .unknown, cancelled: false))
        }
        #expect(throws: FlatdError.refused) {
            try result(Outcome.resolve(.failure(FlatdError.refused), writeStarted: false, pairing: .unknown, cancelled: false))
        }
        #expect(try result(Outcome.resolve(value, writeStarted: false, pairing: .same, cancelled: false)) == 7)
        #expect(throws: FlatdError.unreachable) {
            try result(Outcome.resolve(value, writeStarted: false, pairing: .unknown, cancelled: false))
        }
    }

    @Test func postflightTimeoutPreservesUnansweredWrite() async throws {
        let keys = MemoryKeys()
        let connection = FlatdConnection(defaults: nil, names: nil, keychain: keys, lock: .processOnly)
        try connection.save(Flat.pairing())
        let reads = OSAllocatedUnfairLock(initialState: 0)
        let stall = BlockingStep()
        defer { stall.release.signal() }
        keys.afterRead = {
            if reads.withLock({ $0 += 1; return $0 }) == 3 { stall.wait() }
        }
        let clock = TestClock()
        let transport = FakeTransport()
        transport.answer("POST /api/modes/cooking") {
            clock.advance(.seconds(13))
            try? await Task.sleep(for: .seconds(60))
        }
        let deadline = Deadline(after: .seconds(15), clock: clock.clock)
        let reach = FlatdReach(connection: connection, transport: transport, path: { .localPossible })
        let action = Task { try await reach.run(deadline: deadline) { try await $0.setMode("cooking", active: true) } }
        try #require(await eventually { stall.entered })
        #expect(deadline.remaining > .zero)
        clock.advance(.seconds(3))
        await #expect(throws: FlatdError.noAnswer) { try await action.value }
        #expect(!stall.exited)
        #expect(transport.sent.filter { $0.httpMethod == "POST" }.count == 1)
    }

    @Test(arguments: [false, true]) func confirmedCookingSurvivesTroubleCacheContention(failedFans: Bool) async throws {
        let held = HeldDispatchLock()
        defer { held.stall.release.signal() }
        let connection = FlatdConnection(defaults: nil, names: nil, keychain: MemoryKeys(), lock: held.lock)
        try connection.save(Flat.pairing())
        let transport = FakeTransport()
        var active = Flat.cooking
        active["active"] = true
        if failedFans { active["failed"] = ["fan:fan_1": "timeout"] }
        transport.answer("POST /api/modes/cooking", body: active) { await held.take() }
        let reach = FlatdReach(connection: connection, transport: transport, path: { .localPossible })
        let action = Task { try await FlatActions(reach: reach).setCooking(true) }
        try #require(await eventually { held.waiting.withLock { $0 } })
        let start = ContinuousClock.now
        let change = try await action.value
        #expect(change == CookingChange(isActive: true, failed: failedFans ? ["fan:fan_1"] : []))
        #expect(start.duration(to: .now) < .seconds(2))
        #expect(!held.stall.exited)
    }

    @Test func confirmedSceneFallsBackToIdsWhenNamesStall() async throws {
        let keys = MemoryKeys()
        let connection = FlatdConnection(defaults: nil, names: nil, keychain: keys, lock: .processOnly)
        try connection.save(Flat.pairing())
        let reads = OSAllocatedUnfairLock(initialState: 0)
        let stall = BlockingStep()
        defer { stall.release.signal() }
        keys.afterRead = {
            if reads.withLock({ $0 += 1; return $0 }) == 3 { stall.wait() }
        }
        let transport = FakeTransport()
        transport.answer("POST /api/scenes/test-scene", body: ["failed": ["fan:fan_1": "timeout"]])
        let reach = FlatdReach(connection: connection, transport: transport, path: { .localPossible })
        let action = Task { try await FlatActions(reach: reach).runScene("test-scene") }
        try #require(await eventually { stall.entered })
        #expect(try await action.value == ["fan:fan_1"])
        #expect(!stall.exited)
    }

    @Test func completedPostflightForgetOverridesConfirmedWrite() async throws {
        let flat = try RouteFixture()
        flat.transport.answer("POST /api/modes/cooking", body: Flat.cooking) { try? await flat.connection.forgetSavedPairing() }
        await #expect(throws: FlatdError.notPaired) {
            try await flat.reach.run { try await $0.setMode("cooking", active: true) }
        }
        #expect(flat.writes.count == 1)
    }
}

struct IntentBoundaryTests {
    @Test func coldIntentSetupReturnsByDeadlineWhileWorkerStalls() async throws {
        let flat = try RouteFixture()
        let actions = FlatActions(reach: flat.reach)
        let stall = BlockingStep()
        defer { stall.release.signal() }
        let clock = TestClock()
        let errors = OSAllocatedUnfairLock<FlatIntentError?>(initialState: nil)
        let deadline = Deadline(after: .seconds(15), clock: clock.clock)
        let intent = Task {
            do {
                try await FlatActions.$liveFactory.withValue({
                    stall.wait()
                    return actions
                }) {
                    try await performFlatIntent(deadline: deadline, reloadControls: {}) {
                        try await FlatActions.live.setCooking(true)
                    }
                }
            } catch let error as FlatIntentError {
                errors.withLock { $0 = error }
            }
        }
        try #require(await eventually { stall.entered })
        clock.advance(.seconds(16))
        try #require(await eventually { errors.withLock { $0?.underlying is Deadline.Expired } })
        #expect(!stall.exited)
        #expect(flat.transport.sent.isEmpty)
        stall.release.signal()
        try await intent.value
    }

    @Test func intentReturnsWhileControlReloadStalls() async throws {
        let reload = BlockingStep()
        defer { reload.release.signal() }
        let returned = OSAllocatedUnfairLock<Int?>(initialState: nil)
        let intent = Task {
            let answer = try await performFlatIntent(deadline: Deadline(after: .seconds(15)),
                                                     reloadControls: { reload.wait() }) { 1 }
            returned.withLock { $0 = answer }
        }
        try #require(await eventually { reload.entered && returned.withLock { $0 == 1 } })
        #expect(!reload.exited)
        try await intent.value
    }

    @Test func intentChecksCancellationAfterWorkReturnsAValue() async {
        await #expect(throws: CancellationError.self) {
            try await Task {
                try await performFlatIntent(deadline: Deadline(after: .seconds(15)), reloadControls: {}) {
                    withUnsafeCurrentTask { $0?.cancel() }
                    return 1
                }
            }.value
        }
    }
}

struct ForgetDispatchTests {
    @MainActor @Test(arguments: [false, true])
    func admittedForgetFinishesAfterCancellationOrDeadline(cancel: Bool) async throws {
        let keys = MemoryKeys()
        let stall = BlockingStep()
        defer { stall.release.signal() }
        keys.beforeDelete = { stall.wait() }
        let connection = FlatdConnection(defaults: nil, names: Flat.nameFile(), keychain: keys, lock: .processOnly)
        try connection.save(Flat.pairing())
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let cache = ViewerPageCache(folder: folder)
        try #require(await cache.save(Data("<p>test</p>".utf8), etag: nil, pairing: Flat.id, pin: Flat.pin) != nil)
        let reloads = Counter()
        let session = FlatSession(connection: connection, viewerCache: cache, reloadControls: { reloads.count += 1 })
        let oldStore = try #require(session.store)
        let clock = TestClock()
        let deadline = Deadline(after: .seconds(3600), clock: clock.clock)
        let returned = Counter()
        let forget = Task {
            let result = await session.forget(deadline: deadline)
            returned.count += 1
            return result
        }
        try #require(await eventually { stall.entered })
        if cancel { forget.cancel() } else { clock.advance(.seconds(3601)) }
        try await Task.sleep(for: .milliseconds(100))
        #expect(returned.count == 0)
        #expect(session.isForgetting)
        #expect(connection.pairing != nil)
        stall.release.signal()
        #expect(await forget.value)
        #expect(connection.pairing == nil)
        #expect(oldStore.isRetired)
        #expect(session.store?.pairingID == nil)
        #expect(await cache.page(pairing: Flat.id, pin: Flat.pin) == nil)
        #expect(reloads.count == 1)
    }

    @MainActor @Test func forgetTimesOutWithoutDeletingAndCanRetryAfterLockRelease() async throws {
        let held = HeldDispatchLock(timeout: 20)
        defer { held.stall.release.signal() }
        let connection = FlatdConnection(defaults: nil, names: Flat.nameFile(), keychain: MemoryKeys(), lock: held.lock)
        try connection.save(Flat.pairing())
        await connection.remember(try Flat.devices([Flat.fan(1)]), for: Flat.id)
        let (session, _, _, reloads) = Flat.session(connection: connection)
        await held.take()
        let counter = Counter()
        let ticker = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(25))
                counter.count += 1
            }
        }
        defer { ticker.cancel() }
        let start = ContinuousClock.now
        #expect(await !session.forget())
        #expect(start.duration(to: .now) >= .seconds(10))
        #expect(counter.count > 10)
        #expect(!held.stall.exited)
        #expect(connection.pairing?.id == Flat.id)
        #expect(connection.knownDevices.count == 1)
        #expect(reloads.count == 0)

        held.stall.release.signal()
        #expect(await session.forget())
        #expect(connection.pairing == nil && connection.knownDevices.isEmpty)
        #expect(reloads.count == 1)
    }
}
