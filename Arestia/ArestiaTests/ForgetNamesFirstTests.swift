import Foundation
import Testing
@testable import Arestia

// Codex's review of the renaming, round 3, finding 5: Forget removes the names file first, and a removal that fails
// stops Forget with the pairing kept, so Settings says so.

struct ForgetRemovesTheNamesFirstTests {
    /// The names file cannot be removed (its folder is read-only): Forget fails, says so, and keeps the pairing, so it
    /// can be tried again; nothing of the flat is half gone. Once the file can go, Forget takes both.
    @MainActor @Test func aNamesFileThatCannotBeRemovedStopsForget() async throws {
        let file = Flat.nameFile()
        let connection = FlatdConnection(defaults: UserDefaults(suiteName: "arestia-tests-" + UUID().uuidString)!,
                                         names: file, keychain: MemoryKeys(), lock: .processOnly)
        try connection.save(Flat.pairing())
        await connection.remember(try Flat.devices([Flat.fan(1)]), for: Flat.id)
        let (session, _, _, _) = Flat.session(connection: connection)
        let store = try #require(session.store)
        let folder = file.url.deletingLastPathComponent().path(percentEncoded: false)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: folder)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder) }

        await #expect(throws: (any Error).self) { try await connection.forgetSavedPairing() }
        #expect(await !session.forget())                                      // Settings says it could not forget
        #expect(session.store === store && !store.isRetired)
        #expect(connection.pairing?.id == Flat.id)
        #expect(connection.knownDevices.map(\.label) == ["Fan 1"])

        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder)
        #expect(await session.forget())
        #expect(connection.pairing == nil && connection.devicesVersion == nil)
        #expect(!FileManager.default.fileExists(atPath: file.url.path(percentEncoded: false)))
    }

    /// The Keychain keeps the item: the names went first, which is harmless (the pairing's next snapshot keeps them
    /// again), and the pairing stays.
    @Test func aKeychainThatKeepsTheItemKeepsThePairing() async throws {
        let keys = MemoryKeys()
        let connection = FlatdConnection(defaults: nil, names: Flat.nameFile(), keychain: keys, lock: .processOnly)
        try connection.save(Flat.pairing())
        await connection.remember(try Flat.devices([Flat.fan(1)]), for: Flat.id)
        keys.failsToDelete = true
        await #expect(throws: (any Error).self) { try await connection.forgetSavedPairing() }
        #expect(connection.pairing?.id == Flat.id && connection.known == nil)
        await connection.remember(try Flat.devices([Flat.fan(1)]), for: Flat.id)
        #expect(connection.knownDevices.map(\.label) == ["Fan 1"])
    }
}
