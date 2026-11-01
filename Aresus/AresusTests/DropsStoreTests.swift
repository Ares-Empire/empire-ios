import Foundation
import Testing
@testable import Aresus

@MainActor
struct DropsStoreTests {
    @Test func folderCacheWorksOfflineAndEachPartKeepsLastGoodAnswer() async throws {
        let directory = testDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = directory.appendingPathComponent("cached-folders.json")
        let session = await signedInSession()
        let fake = DropTransport()
        fake.responses = [.answer(200, try sampleData("drop-folders")), .answer(200, try sampleData("drops")),
                          .failure(URLError(.notConnectedToInternet)), .answer(503, Data(#"{"error":"Try later."}"#.utf8))]
        let store = DropsStore(session: session, client: AresusAPI(transport: fake), directory: directory.appendingPathComponent("outbox"),
                               cacheURL: cache, defaults: nil, automatic: false)
        await store.refresh()
        let folders = try #require(store.folders)
        let drops = store.serverDrops
        #expect(folders.updated != nil && drops.count == 5)
        await store.refresh(olderThan: 60)
        #expect(fake.requests.count == 2)
        await store.refresh()
        #expect(store.folders == folders && store.serverDrops == drops)
        #expect(store.errors[.folders] == "No connection." && store.errors[.drops] == "Try later.")
        let offline = DropsStore(session: session, directory: directory.appendingPathComponent("other-outbox"), cacheURL: cache,
                                 defaults: nil, automatic: false)
        #expect(offline.folders == folders)
        session.logOut()
        #expect(store.items.isEmpty && store.folders == nil && store.errors.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: cache.path))
    }

    @Test func sendNamesAndRecentsThenPublishUploadedDrop() async throws {
        let directory = testDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fake = DropTransport()
        fake.responses = [.answer(201, try dropAnswer()), .answer(200, try dropAnswer(state: .waiting)),
                          .answer(201, try dropAnswer()), .answer(200, try dropAnswer(state: .waiting))]
        let store = DropsStore(session: await signedInSession(), client: AresusAPI(transport: fake), directory: directory,
                               cacheURL: nil, defaults: nil, automatic: false)
        let target = Target(root: .documents, folder: "House", newFolder: "Plans")
        let file = DropFile(content: .data(Data("abc".utf8)), suggestedName: "Sketch.pdf")
        try await store.send(files: [file, file], target: target)
        #expect(store.outbox?.items.map { $0.drop.name } == ["Sketch.pdf", "Sketch (2).pdf"])
        #expect(store.items.count == 2 && store.recentFolders.targets == [target])
        #expect(store.recentFolders.lastBySource[.file] == target)
        await store.outbox?.process()
        #expect(store.outbox?.items.isEmpty == true)
        #expect(store.serverDrops.only?.state == .waiting)
    }

    @Test func sampleModeUsesSamplesWithoutNetworkingOrLocalFiles() async throws {
        let session = EmpireSession(app: .aresus, storage: MemoryTokens(), restoreOnLaunch: false)
        let directory = testDirectory()
        let fake = DropTransport()
        let store = DropsStore(session: session, client: AresusAPI(transport: fake), samples: AresusSamples(allGood: false),
                               directory: directory, cacheURL: directory.appendingPathComponent("folders.json"), defaults: nil)
        await store.refresh()
        #expect(store.serverDrops.count == 5 && store.folders?.fallbackCount == 2)
        #expect(store.outbox == nil && fake.requests.isEmpty && !FileManager.default.fileExists(atPath: directory.path))
        let target = Target(root: .downloads, folder: "", newFolder: nil)
        try await store.send(files: [DropFile(content: .data(Data("abc".utf8)), suggestedName: "Sample.pdf")], target: target)
        #expect(store.serverDrops.count == 6 && store.recentFolders.targets == [target])
        await store.remove(store.items[0])
        #expect(store.serverDrops.count == 5 && fake.requests.isEmpty)
    }

    @Test func leavingSamplesUsesTheRealOutboxAndPreservesAnEditedPhotoName() async throws {
        let directory = testDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DropsStore(session: await signedInSession(), samples: AresusSamples(allGood: false),
                               directory: directory, cacheURL: nil, defaults: nil, automatic: false)
        await store.refresh()
        store.leaveSample()
        let target = Target(root: .documents, folder: "", newFolder: nil)
        let file = DropFile(content: .data(Data("abc".utf8)), suggestedName: "IMG_0001.heic", name: "My photo.heic", source: .photo)
        try await store.send(files: [file], target: target)
        #expect(!store.isSample && store.serverDrops.isEmpty)
        #expect(store.outbox?.items.only?.drop.name == "My photo.heic")
        #expect(store.recentFolders.lastBySource[.photo] == target)
    }

    @Test func logoutWhileLoadingCannotRestoreCachedData() async throws {
        let directory = testDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fake = DropTransport()
        fake.responses = [.answer(200, try sampleData("drop-folders"))]
        let gate = RequestGate()
        fake.gate = gate
        let session = await signedInSession()
        let cache = directory.appendingPathComponent("folders.json")
        let store = DropsStore(session: session, client: AresusAPI(transport: fake), directory: directory.appendingPathComponent("outbox"),
                               cacheURL: cache, defaults: nil, automatic: false)
        let pending = Task { await store.load(.folders) }
        await gate.waitUntilPaused()
        session.logOut()
        gate.resume()
        await pending.value
        #expect(store.folders == nil && store.loading.isEmpty && !FileManager.default.fileExists(atPath: cache.path))
    }
}
