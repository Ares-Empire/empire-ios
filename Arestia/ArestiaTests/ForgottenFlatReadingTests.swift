import Foundation
import Testing
@testable import Arestia

// Codex's review of the renaming, round 3, finding 2: a reading of flatd's list never gives back a forgotten flat's
// blind or fans; Forget anywhere before the reading's last check of the pairing leaves it with nothing.

/// A device as flatd v1.3 sends it after a rename: its own name, the config's as `default_label`.
private func named(_ object: [String: Any], _ label: String) -> [String: Any] {
    var object = object
    object["default_label"] = object["label"]
    object["label"] = label
    return object
}

/// Counts from any thread.
private nonisolated final class Tally: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func next() -> Int { lock.withLock { count += 1; return count } }
    var value: Int { lock.withLock { count } }
}

/// flatd's answers, with Forget run the moment one route's answer has arrived and before the caller sees it.
private nonisolated final class ForgetAfterAnswer: PreparingTransport, @unchecked Sendable {
    let inner: FakeTransport
    let route: String
    let forget: @Sendable () async -> Void

    init(_ inner: FakeTransport, after route: String, forget: @escaping @Sendable () async -> Void) {
        self.inner = inner
        self.route = route
        self.forget = forget
    }

    func prepare(_ request: URLRequest, reply: Attempt<HTTPReply>) throws -> any SuspendedRequest {
        inner.prepare(request, reply: reply) { answer in
            if (request.httpMethod ?? "GET") + " " + (request.url?.path(percentEncoded: true) ?? "") == self.route {
                await self.forget()
            }
            return answer
        }
    }
}

struct ForgottenFlatReadingTests {
    let chosen = SavedDevice.id(for: "rollo:blind_1", of: Flat.id)

    func flatd() -> FakeTransport {
        let transport = FakeTransport()
        transport.answer("GET /api/devices",
                         body: ["devices": [Flat.fan(1), named(Flat.rollo(1, position: 100), "Kitchen blind")]])
        return transport
    }

    /// Forget lands after flatd's list arrived and before the names are reconciled with it: the Blind control and the
    /// fans get nothing of the forgotten flat, and no names are written back for it.
    @Test func forgetBetweenTheListAndTheNamesShowsNothing() async throws {
        for reading in ["blind", "fans"] {
            let connection = Flat.connection()
            await connection.remember(try Flat.devices([Flat.fan(1), Flat.rollo(1)]), for: Flat.id)
            let transport = ForgetAfterAnswer(flatd(), after: "GET /api/devices") { try? await connection.forgetSavedPairing() }
            let actions = FlatActions(reach: FlatdReach(connection: connection, transport: transport, rediscover: { [] }))
            await #expect(throws: FlatdError.notPaired) {
                if reading == "blind" { _ = try await actions.rolloControl(chosen) } else { _ = try await actions.fans() }
            }
            #expect(connection.pairing == nil && connection.devicesVersion == nil)
        }
    }

    /// The same with another flat paired at once after Forget: the list read is the retired pairing's, never shown
    /// under the new one, and the new pairing's names are not the old flat's.
    @Test func anotherFlatPairedMeanwhileGetsNothingOfTheOld() async throws {
        let connection = Flat.connection()
        await connection.remember(try Flat.devices([Flat.fan(1), Flat.rollo(1)]), for: Flat.id)
        let other = Flat.pairing(id: UUID())
        let transport = ForgetAfterAnswer(flatd(), after: "GET /api/devices") {
            try? await connection.forgetSavedPairing()
            try? connection.save(other)
        }
        let actions = FlatActions(reach: FlatdReach(connection: connection, transport: transport, rediscover: { [] }))
        await #expect(throws: FlatdError.notPaired) { _ = try await actions.rollo(chosen) }
        #expect(connection.known == nil)
    }

    /// Forget at every step of the Blind control's reading (after each time it reads the Keychain): whenever it came
    /// before the reading's last check, the reading gives nothing; only a Forget after that last check leaves the
    /// answer, which was then the paired flat's.
    @Test func forgetAtAnyStepBeforeTheLastCheckGivesNothing() async throws {
        func reading(forgetAfter step: Int?) async throws -> (Result<RolloControlState, Error>, Int) {
            let keys = MemoryKeys()
            let file = Flat.nameFile()
            let connection = FlatdConnection(defaults: nil, names: file, keychain: keys, lock: .processOnly)
            try connection.save(Flat.pairing())
            await connection.remember(try Flat.devices([Flat.fan(1), Flat.rollo(1)]), for: Flat.id)
            let reads = Tally()
            keys.afterRead = {
                // Forget's effect, names first (as `forget` does), at this point of the reading.
                if reads.next() == step {
                    try? file.remove()
                    try? keys.delete()
                }
            }
            let actions = FlatActions(reach: FlatdReach(connection: connection, transport: flatd(), rediscover: { [] }))
            do {
                return (.success(try await actions.rolloControl(chosen)), reads.value)
            } catch {
                return (.failure(error), reads.value)
            }
        }
        let (untouched, steps) = try await reading(forgetAfter: nil)
        #expect(try untouched.get() == .blind(name: "Kitchen blind", isOpen: false))
        #expect(steps >= 4)
        for step in 1..<steps {
            let (result, _) = try await reading(forgetAfter: step)
            switch result {
            case let .success(state):
                Issue.record("Forget after reading \(step) of \(steps) still gave \(state)")
            case let .failure(error):
                #expect(error as? FlatdError == .notPaired, "Forget after reading \(step) of \(steps)")
            }
        }
        let (last, _) = try await reading(forgetAfter: steps)
        #expect(try last.get() == .blind(name: "Kitchen blind", isOpen: false))
    }

    /// No names can be kept (the cache is unavailable): the names flatd just sent, which is not a retired pairing.
    @Test func anUnavailableCacheShowsFlatdsNames() async throws {
        let unwritable = DeviceNameFile(url: FileManager.default.temporaryDirectory
            .appending(path: "arestia-tests-missing-" + UUID().uuidString).appending(path: "device-names.json"))
        for names in [nil, unwritable] {
            let connection = FlatdConnection(defaults: nil, names: names, keychain: MemoryKeys(), lock: .processOnly)
            try connection.save(Flat.pairing())
            let actions = FlatActions(reach: FlatdReach(connection: connection, transport: flatd(), rediscover: { [] }))
            #expect(try await actions.rolloControl(chosen) == .blind(name: "Kitchen blind", isOpen: false))
            #expect(connection.known == nil)
        }
    }
}
