import Foundation
import Testing
@testable import Arestia

@MainActor
struct ToggleCookingTests {
    private let transport = FakeTransport()
    private let command = "POST /api/modes/cooking"

    private var intent: ToggleCookingIntent {
        ToggleCookingIntent(actions: FlatActions(reach: FlatdReach(
            connection: Flat.connection(), transport: transport, rediscover: { [] })))
    }

    @Test(arguments: [true, false])
    func togglesTheServiceState(active: Bool) async throws {
        var before = Flat.cooking
        before["active"] = active
        var after = before
        after["active"] = !active
        transport.answer("GET /api/modes", body: ["modes": [before]])
        transport.answer(command, body: after)

        _ = try await intent.perform()

        #expect(transport.sent.map { $0.url?.path() } == ["/api/health", "/api/modes", "/api/modes/cooking"])
        let changes = transport.bodies(for: command)
        #expect(changes.count == 1)
        #expect(changes.first?["active"] as? Bool == !active)
    }

    @Test func failsWithoutChangingCookingWhenTheReadFails() async {
        transport.answer("GET /api/modes", status: 504)

        await #expect(throws: FlatIntentError.self) { try await intent.perform() }
        #expect(transport.bodies(for: command).isEmpty)
    }

    @Test func failsWithoutChangingCookingWhenTheStateIsMissing() async {
        for modes in [[], [["id": "cooking"]], [["id": "cooking", "active": "unknown"]]] {
            transport.answer("GET /api/modes", body: ["modes": modes])
            await #expect(throws: FlatIntentError.self) { try await intent.perform() }
        }
        #expect(transport.bodies(for: command).isEmpty)
    }
}
