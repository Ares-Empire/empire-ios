import Foundation
import Testing
@testable import Arestia

// Codex's review of the 3D page, finding 4: a page Forget left behind (the app ended before its removal ran) goes at
// the next launch without a pairing.

private func cacheFolder() -> URL {
    FileManager.default.temporaryDirectory.appending(path: "arestia-viewer-tests-" + UUID().uuidString)
}

@MainActor
struct ForgottenPageCleanupTests {
    func session(_ connection: FlatdConnection, cache: ViewerPageCache) -> FlatSession {
        FlatSession(connection: connection, viewerCache: cache, reloadControls: {}) { pairing, changed in
            FlatStore(pairing: pairing, connection: connection, transport: FakeTransport(), eventSource: FakeEvents(),
                      rediscover: { [] }, reloadControls: {}, pairingChanged: changed)
        }
    }

    /// Forget deleted the pairing and queued the page's removal, but the app ended before it ran: the files stayed.
    /// The next launch, with the Keychain saying for certain that no pairing is saved, removes them. While the Keychain
    /// cannot be read it leaves them (the pairing may well be there).
    @Test func aLaunchWithoutAPairingRemovesWhatForgetLeftBehind() async throws {
        let folder = cacheFolder()
        let cache = ViewerPageCache(folder: folder)
        #expect(await cache.save(Data("<p>made up</p>".utf8), etag: nil, pairing: Flat.id, pin: Flat.pin) != nil)
        let keys = MemoryKeys()
        let connection = FlatdConnection(defaults: nil, names: nil, keychain: keys, lock: .processOnly)

        keys.failsToRead = true
        let unsure = session(connection, cache: cache)
        #expect(unsure.store == nil)
        #expect(await cache.page(pairing: Flat.id, pin: Flat.pin) != nil)
        unsure.end()

        keys.failsToRead = false
        let launched = session(connection, cache: cache)
        #expect(launched.store != nil && launched.store?.pairingID == nil)
        #expect(await cache.page(pairing: Flat.id, pin: Flat.pin) == nil)   // queued behind the removal
        #expect(!FileManager.default.fileExists(atPath: folder.path(percentEncoded: false)))
        launched.end()
    }

    /// With a pairing saved, a launch keeps its page.
    @Test func aLaunchWithAPairingKeepsItsPage() async throws {
        let cache = ViewerPageCache(folder: cacheFolder())
        #expect(await cache.save(Data("<p>made up</p>".utf8), etag: nil, pairing: Flat.id, pin: Flat.pin) != nil)
        let launched = session(Flat.connection(), cache: cache)
        #expect(launched.store?.pairingID == Flat.id)
        #expect(await cache.page(pairing: Flat.id, pin: Flat.pin) != nil)
        launched.end()
    }
}
