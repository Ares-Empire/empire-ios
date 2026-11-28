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
        reach.allowsRemote = {
            entered.withLock { $0 = true }
            _ = release.wait(timeout: .now() + 2)
            finish.yield(())
            finish.finish()
            return true
        }
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
            (try? connection.lock.withLock(until: Deadline(after: .milliseconds(250))) { true }) ?? false
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
            .gated(by: flat.connection, allowsRemote: { false })
        await #expect(throws: FlatdGate.RemoteDenied.self) { try await lockedRemote.devices() }
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

    @Test func stalledMarkerAfterLockReturnsByDeadlineAndNeverDispatches() async throws {
        let flat = try RouteFixture()
        let clock = TestClock()
        var reach = flat.reach
        reach.path = { .remoteOnly }
        let reads = OSAllocatedUnfairLock(initialState: 0)
        let stall = BlockingStep()
        defer { stall.release.signal() }
        reach.allowsRemote = {
            let count = reads.withLock { $0 += 1; return $0 }
            if count == 2 { stall.wait() }
            return true
        }
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
        try await Deadline(after: .seconds(1)).work { work in
            try flat.connection.lock.withLock(work: work) {}
        }
        #expect(flat.transport.sent.count == 1)
    }

    @Test(arguments: [1, 3]) func stalledPairingReadReturnsByDeadline(readToStall: Int) async throws {
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
        try connection.note(trouble)
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
        try await Deadline(after: .seconds(1)).work { work in try held.lock.withLock(work: work) {} }
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
        let (sleeping, signal) = AsyncStream<Void>.makeStream()
        let boundary = Deadline.Clock(now: clock.clock.now, sleepUntil: { _ in
            defer { clock.advance(.seconds(2)) }
            signal.yield(())
            signal.finish()
            try await Task.sleep(for: .seconds(60))
        })
        let cap = Deadline(after: .seconds(1), clock: boundary)
        await #expect(throws: Deadline.Expired.self) {
            try await cap.run {
                for await _ in sleeping { break }
                return true
            }
        }
    }

    @Test(arguments: [true, false]) func unansweredFanWriteTakesPrecedence(timeoutFirst: Bool) async throws {
        let flat = try RouteFixture()
        flat.fans()
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
        #expect(flat.writes.count == 2)
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
        try connection.save(Flat.pairing())
        let (store, transport, events, _) = Flat.store(connection: connection)
        defer { store.stop() }
        transport.answer("GET /api/scenes", body: ["scenes": []])
        transport.answer("GET /api/remote", body: ["url": awayURL, "spki_sha256": awayPin]) {
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
        #expect(connection.pairing?.remote == nil)
        #expect(connection.knownDevices.first?.label == "Fan 1")
        if holdBeyondCap {
            try await Task.sleep(for: .milliseconds(6300))
            #expect(!held.stall.exited)
        }
        held.stall.release.signal()
        try #require(await eventually { connection.knownDevices.first?.label == "Desk fan" })
        if holdBeyondCap {
            #expect(connection.pairing?.remote == nil)
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
                let current = try connection.current()
                try connection.move(current, to: FlatdClient(current, at: moved))
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
            .gated(by: flat.connection, allowsRemote: { true })
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
            .gated(by: flat.connection, allowsRemote: { true })
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
            .gated(by: connection, allowsRemote: { true })
        await FlatStore.enrollRemote(from: remote, read: saved, connection: connection)
        _ = try await remote.remoteEnrollment()
        try? connection.move(saved, to: remote)
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
            .gated(by: flat.connection, allowsRemote: { true })
        if change == "token" {
            var renewal = Flat.pairing(token: Flat.renewedKey)
            renewal.remote = old.remote
            #expect(try flat.connection.renew(old, with: renewal))
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

    @Test func oldTokensCannotDispatchAfterRenewalAndReenrollment() async throws {
        let flat = try RouteFixture()
        flat.fans()
        let oldHome = FlatdClient(flat.pairing, transport: flat.transport).gated(by: flat.connection)
        let oldRemote = try #require(FlatdClient(remoteOf: flat.pairing, transport: flat.transport))
            .gated(by: flat.connection, allowsRemote: { true })
        let renewed = Flat.pairing(token: Flat.renewedKey)
        try #require(try flat.connection.renew(flat.pairing, with: renewed))
        flat.transport.answer("GET /api/remote", body: ["url": awayURL, "spki_sha256": awayPin])
        let home = FlatdClient(renewed, transport: flat.transport).gated(by: flat.connection)
        await FlatStore.enrollRemote(from: home, read: renewed, connection: flat.connection)
        try #require(flat.connection.pairing?.remote?.url == flat.pairing.remote?.url)
        for client in [oldHome, oldRemote] {
            await #expect(throws: FlatdError.unreachable) { try await client.devices() }
        }
        #expect(flat.authenticated.map { $0.url?.path() } == ["/api/remote"])
    }

    private struct UngatedTransport: HTTPTransport {
        let inner: FakeTransport
        func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) { try await inner.send(request) }
    }

    @Test func pairedRoutesRefuseAnUngatedTransportEvenWithAGate() async throws {
        let flat = try RouteFixture()
        let transport = UngatedTransport(inner: flat.transport)
        let home = FlatdClient(flat.pairing, transport: transport).gated(by: flat.connection)
        let remote = try #require(FlatdClient(remoteOf: flat.pairing, transport: transport))
            .gated(by: flat.connection, allowsRemote: { true })
        for client in [home, remote] {
            await #expect(throws: FlatdError.unreachable) { try await client.devices() }
        }
        #expect(flat.transport.sent.isEmpty)
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
            case "move": try? flat.connection.move(old, to: FlatdClient(old, at: moved))
            case "renew": _ = try? flat.connection.renew(old, with: changed)
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

private nonisolated final class BlockingStep: Sendable {
    let release = DispatchSemaphore(value: 0)
    private let status = OSAllocatedUnfairLock(initialState: 0)
    var entered: Bool { status.withLock { $0 > 0 } }
    var exited: Bool { status.withLock { $0 == 2 } }

    func wait() {
        status.withLock { $0 = 1 }
        _ = release.wait(timeout: .now() + 9)
        status.withLock { $0 = 2 }
    }
}

private nonisolated struct HeldDispatchLock: Sendable {
    let stall = BlockingStep()
    let waiting: OSAllocatedUnfairLock<Bool>
    let lock: FlatdDispatchLock

    init() {
        let waiting = OSAllocatedUnfairLock(initialState: false)
        self.waiting = waiting
        lock = .processOnly(onContention: { waiting.withLock { $0 = true } })
    }

    func take() async {
        DispatchQueue.global().async { try? lock.withLock { stall.wait() } }
        while !stall.entered && !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(10))
        }
    }
}
