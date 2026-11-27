#if DEBUG && ARESTIA_GATE
import Foundation
import XCTest
@testable import Arestia

nonisolated final class GateTests: XCTestCase {
    func testWrongWebSocketPin() async throws {
        let client = try GateInput.load().client
        let events = await WebSocketEvents().events(from: client.eventsRequest, pin: client.pin)
        do {
            for try await _ in events {
                XCTFail("The wrong identity sent an event.")
                return
            }
            XCTFail("The event stream ended without .unreachable.")
        } catch let error as FlatdError {
            XCTAssertEqual(error, .unreachable)
        } catch {
            XCTFail("The event stream didn't report a FlatdError.")
        }
    }

    func testWrongPOSTPin() async throws {
        let client = try GateInput.load().client
        do {
            _ = try await post(client)
            XCTFail("The wrong identity answered a pinned POST.")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .serverCertificateUntrusted)
        } catch {
            XCTFail("The POST didn't report a TLS error.")
        }
    }

    func testRightPin() async throws {
        let client = try GateInput.load().client
        let events = await WebSocketEvents().events(from: client.eventsRequest, pin: client.pin)
        do {
            var first: FlatEvent?
            for try await event in events {
                first = event
                break
            }
            guard case .snapshot = first else {
                XCTFail("The pinned socket didn't receive a snapshot.")
                return
            }
            let status = try await post(client)
            XCTAssertEqual(status, 200)
        } catch {
            XCTFail("The pinned socket or authenticated POST failed.")
        }
    }

    func testEchoRoundTrip() async throws {
        let input = try GateInput.load()
        let client = input.client
        var components = URLComponents(url: client.baseURL.appending(path: "test/echo"),
                                       resolvingAgainstBaseURL: false)
        components?.scheme = "wss"
        var request = client.eventsRequest
        request.url = try XCTUnwrap(components?.url)
        let session = FlatdSession.events(pin: client.pin)
        let socket = session.webSocketTask(with: request)
        socket.resume()
        defer {
            socket.cancel(with: .normalClosure, reason: nil)
            session.invalidateAndCancel()
        }

        do {
            // Complete the upgrade and warm up the socket before starting the clock.
            try await socket.send(.data(payload(-1)))
            try await receive(-1, on: socket)
            let slots = input.echoSeconds * 50
            let samples = try await measureEcho(socket, slots: slots)
            let spacing = zip(samples, samples.dropFirst()).map { previous, next in
                milliseconds(next.sent - previous.sent)
            }
            let missed = slots - samples.count
            print(String(format: "Gate echo cadence: %d/%d slots sent, %d missed (%.1f%%)",
                         samples.count, slots, missed, 100 * Double(missed) / Double(slots)))
            if let p50 = percentile(spacing, 0.50), let p95 = percentile(spacing, 0.95) {
                let hz = 1_000 * Double(spacing.count) / spacing.reduce(0, +)
                print(String(format: "Gate echo spacing: %.2f Hz, p50 %.2f ms, p95 %.2f ms", hz, p50, p95))
            }
            guard echoCadenceIsConclusive(missed: missed, slots: slots, spacing: spacing) else {
                XCTFail("Gate echo inconclusive. More than 5% of send slots were missed or spacing p95 exceeded 40 ms.")
                return
            }
            let times = samples.map(\.roundTrip)
            let p50 = try XCTUnwrap(percentile(times, 0.50))
            let p95 = try XCTUnwrap(percentile(times, 0.95))
            print(String(format: "Gate echo: %d round trips, p50 %.2f ms, p95 %.2f ms",
                         times.count, p50, p95))
        } catch let error as URLError {
            XCTFail("The echo run failed with URL error code \(error.code.rawValue).")
        } catch {
            XCTFail("The echo run timed out or returned an unexpected message.")
        }
    }

    func testEchoPacingAfterStall() {
        let start = ContinuousClock().now
        var pacing = EchoPacing(start: start, slots: 50)
        XCTAssertTrue(pacing.sent(at: start))
        let late = start + .milliseconds(500)
        XCTAssertTrue(pacing.sent(at: late))
        XCTAssertEqual(pacing.next, late + .milliseconds(20))
        XCTAssertFalse(pacing.sent(at: late))
        XCTAssertFalse(pacing.sent(at: start + .seconds(1)))

        var nearBoundary = EchoPacing(start: start, slots: 50)
        XCTAssertTrue(nearBoundary.sent(at: start + .milliseconds(519)))
        XCTAssertEqual(nearBoundary.next, start + .milliseconds(520))
        XCTAssertFalse(nearBoundary.sent(at: start + .milliseconds(522)))
        XCTAssertEqual(nearBoundary.next, start + .milliseconds(540))
        XCTAssertTrue(nearBoundary.sent(at: start + .milliseconds(542)))

        XCTAssertTrue(echoCadenceIsConclusive(missed: 5, slots: 100, spacing: [20, 40]))
        XCTAssertFalse(echoCadenceIsConclusive(missed: 6, slots: 100, spacing: [20, 40]))
        XCTAssertFalse(echoCadenceIsConclusive(missed: 0, slots: 100, spacing: [20, 41]))
    }

    /// Run with the loopback fake flatd seeded with one reachable and one offline fan.
    @MainActor func testFanBatchTrace() async throws {
        let client = try GateInput.load().client
        let fans = try await client.devices().filter { $0.kind == .fan }
        guard fans.count == 2, fans.filter({ $0.state.online }).count == 1 else {
            throw XCTSkip("Fan trace needs two fake fans, one offline.")
        }
        let online = try XCTUnwrap(fans.first { $0.state.online })
        let connection = FlatdConnection(defaults: nil, names: nil, keychain: MemoryKeys(), lock: .live)
        try connection.save(FlatdPairing(baseURL: client.baseURL, token: client.token, pin: client.pin))
        let actions = FlatActions(reach: FlatdReach(connection: connection))
        let trace = GateAction("FanBatchTest", isFanBatch: true)
        do {
            _ = try await performFlatIntent(timing: trace, { try await actions.setFans(on: true) }) { $0.count }
            XCTFail("The offline fan's failure should be reported after both fan commands.")
        } catch is FlatIntentError {}
        let rows = try GateTimingLog.newestFirst().reversed().map { $0.split(separator: "\t") }
            .filter { $0.count >= 4 && $0[1] == trace.id.uuidString }
        XCTAssertEqual(rows.map { $0.dropFirst(3).joined(separator: "\t") }, [
            "intent entry", "dispatch", "completion\tdeviceDidNotAnswer", "result returned\tdeviceDidNotAnswer"
        ])
        let updated = try await client.device(online.id)
        XCTAssertEqual(updated.state.on, true)
    }

    private func post(_ client: FlatdClient) async throws -> Int {
        let body = try JSONEncoder().encode(["active": true])
        let request = client.request("api/modes/cooking", method: "POST", body: body, timeout: client.commandTimeout)
        let (_, response) = try await FlatdTransport(pin: client.pin).send(request)
        return response.statusCode
    }
}

private nonisolated struct GateInput {
    let client: FlatdClient
    let echoSeconds: Int

    static func load() throws -> Self {
        struct File: Decodable {
            let url: String
            let token: String
            let pin_a: String
            let pin_b: String
            let echo_seconds: Int?
        }
        enum InvalidInput: Error {
            case unreadableGateFile, invalidGateFile
        }

        let file = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask,
                                               appropriateFor: nil, create: false)
            .appending(path: "arestia-gate.local.json")
        let data: Data
        do {
            data = try Data(contentsOf: file)
        } catch CocoaError.fileReadNoSuchFile {
            throw XCTSkip("Missing arestia-gate.local.json in the app's Library/Caches. See docs/apps/Arestia.md.")
        } catch {
            throw InvalidInput.unreadableGateFile
        }
        guard let input = try? JSONDecoder().decode(File.self, from: data),
              let base = PairingCode.serviceURL(input.url), let token = PairingCode.cleanToken(input.token),
              let pin = FlatdPin(input.pin_a), let other = FlatdPin(input.pin_b), pin != other else {
            throw InvalidInput.invalidGateFile
        }
        let seconds = input.echo_seconds ?? 120
        guard seconds > 0, seconds <= Int.max / 50 else { throw InvalidInput.invalidGateFile }
        return Self(client: FlatdClient(baseURL: base, token: token, pin: pin), echoSeconds: seconds)
    }
}

private nonisolated enum EchoFailure: Error {
    case unexpectedMessage, timedOut
}

private nonisolated struct EchoPacing {
    private static let interval = Duration.milliseconds(20)
    private static let minimumSpacing = Duration.milliseconds(15)
    let end: ContinuousClock.Instant
    private(set) var next: ContinuousClock.Instant
    private var previous: ContinuousClock.Instant?

    init(start: ContinuousClock.Instant, slots: Int) {
        next = start
        end = start + Self.interval * slots
    }

    /// Use the latest slot after a stall. Skip another slot if sending there would put two sends too close together.
    mutating func sent(at now: ContinuousClock.Instant) -> Bool {
        guard next <= now, now < end else { return false }
        let expired = Int((now - next) / Self.interval)
        next += Self.interval * (expired + 1)
        if let previous, now - previous < Self.minimumSpacing { return false }
        previous = now
        return true
    }
}

private nonisolated struct EchoSample: Sendable {
    let sent: ContinuousClock.Instant
    let roundTrip: Double
}

private nonisolated func milliseconds(_ duration: Duration) -> Double {
    let parts = duration.components
    return Double(parts.seconds) * 1_000 + Double(parts.attoseconds) / 1e15
}

private nonisolated func percentile(_ values: [Double], _ fraction: Double) -> Double? {
    guard !values.isEmpty else { return nil }
    return values.sorted()[Int(ceil(Double(values.count) * fraction)) - 1]
}

private nonisolated func echoCadenceIsConclusive(missed: Int, slots: Int, spacing: [Double]) -> Bool {
    guard let p95 = percentile(spacing, 0.95) else { return false }
    return missed <= slots / 20 && p95 <= 40
}

private nonisolated func payload(_ index: Int) -> Data {
    var sequence = Int64(index).bigEndian
    var data = Data(count: 100)
    withUnsafeBytes(of: &sequence) { data.replaceSubrange(0..<$0.count, with: $0) }
    return data
}

private nonisolated func receive(_ index: Int, on socket: URLSessionWebSocketTask) async throws {
    guard case let .data(data) = try await socket.receive(), data == payload(index) else {
        throw EchoFailure.unexpectedMessage
    }
}

private nonisolated func measureEcho(_ socket: URLSessionWebSocketTask, slots: Int) async throws -> [EchoSample] {
    let clock = ContinuousClock()
    let schedule = EchoPacing(start: clock.now, slots: slots)
    let (sends, sent) = AsyncStream<ContinuousClock.Instant>.makeStream()
    return try await withThrowingTaskGroup(of: [EchoSample]?.self) { group in
        group.addTask {
            defer { sent.finish() }
            var pacing = schedule
            var index = 0
            while pacing.next < pacing.end {
                try await clock.sleep(until: pacing.next, tolerance: .zero)
                let message = URLSessionWebSocketTask.Message.data(payload(index))
                let now = clock.now
                if now >= pacing.end { break }
                guard pacing.sent(at: now) else { continue }
                sent.yield(now)
                try await socket.send(message)
                index += 1
            }
            return nil
        }
        group.addTask {
            var samples: [EchoSample] = []
            for await sentAt in sends {
                try await receive(samples.count, on: socket)
                samples.append(EchoSample(sent: sentAt, roundTrip: milliseconds(clock.now - sentAt)))
            }
            return samples
        }
        group.addTask {
            try await clock.sleep(until: schedule.end + .seconds(120))
            throw EchoFailure.timedOut
        }
        do {
            while let result = try await group.next() {
                if let result {
                    group.cancelAll()
                    return result
                }
            }
            throw EchoFailure.unexpectedMessage
        } catch {
            socket.cancel(with: .goingAway, reason: nil)
            throw error
        }
    }
}
#endif
