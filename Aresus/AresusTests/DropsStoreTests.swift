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
                               cacheURL: cache, defaults: nil, automatic: false, uploads: ImmediateDropUploads(fake))
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
                               cacheURL: nil, defaults: nil, automatic: false, uploads: ImmediateDropUploads(fake))
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
                               directory: directory, cacheURL: directory.appendingPathComponent("folders.json"), defaults: nil, uploads: ImmediateDropUploads(fake))
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

    // MARK: deleting (brief 93: Mail's Delete, every state)

    private func store(_ fake: DropTransport, directory: URL) async -> DropsStore {
        DropsStore(session: await signedInSession(), client: AresusAPI(transport: fake), directory: directory,
                   cacheURL: nil, defaults: nil, automatic: false, uploads: ImmediateDropUploads(fake))
    }

    private func server(_ store: DropsStore, _ state: DropState) throws -> DropsItem {
        try #require(store.items.first { if case .server(let drop) = $0 { drop.state == state } else { false } })
    }

    @Test func aDeletedDropLeavesTheListAtOnceAndA404CountsAsDeleted() async throws {
        let directory = testDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fake = DropTransport()
        fake.responses = [.answer(200, try sampleData("drops")), .answer(204, Data()),
                          .answer(404, Data(#"{"error":"Unknown drop."}"#.utf8)), .answer(200, try sampleData("drops"))]
        let gate = RequestGate()
        fake.gate = gate
        fake.gateMethod = "DELETE"
        let store = await store(fake, directory: directory)
        await store.load(.drops)
        let waiting = try server(store, .waiting)
        let deleting = Task { await store.remove(waiting) }
        await gate.waitUntilPaused()
        #expect(!store.items.contains(waiting), "out of the list before the server answers")
        gate.resume()
        await deleting.value
        #expect(!store.items.contains(waiting) && !store.serverDrops.contains { $0.id == 2 } && store.errors[.drops] == nil)
        let landed = try server(store, .landed)
        await store.remove(landed)
        #expect(!store.items.contains(landed) && store.errors[.drops] == nil, "a 404: already gone, so deleted")
        #expect(fake.requests.map { "\($0.httpMethod!) \($0.url!.path)" }
                == ["GET /api/aresus/drops", "DELETE /api/aresus/drops/2", "DELETE /api/aresus/drops/3"])
        // A list the server sent before it deleted them still holds them: they stay out.
        await store.load(.drops)
        #expect(store.items.count == 3 && !store.items.contains(waiting) && !store.items.contains(landed))
    }

    @Test func aDropTheServerRefusesComesBackWithTheReason() async throws {
        let directory = testDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fake = DropTransport()
        fake.responses = [.answer(200, try sampleData("drops")), .answer(409, Data(#"{"error":"Not now."}"#.utf8)),
                          .failure(URLError(.notConnectedToInternet))]
        let store = await store(fake, directory: directory)
        await store.load(.drops)
        let cancelled = try server(store, .cancelled)
        await store.remove(cancelled)
        #expect(store.items.contains(cancelled) && store.errors[.drops] == "Not now.")
        await store.remove(cancelled)
        #expect(store.items.contains(cancelled) && store.errors[.drops] == "No connection.")
        #expect(store.items.count == 5)
    }

    @Test func deletingOnThePhoneStopsTheUploadAndTellsTheServerOnceOnline() async throws {
        let directory = testDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fake = DropTransport()
        fake.responses = [.answer(201, try dropAnswer()), .failure(URLError(.notConnectedToInternet)),
                          .failure(URLError(.notConnectedToInternet))]
        let store = await store(fake, directory: directory)
        try await store.send(files: [DropFile(content: .data(Data("abc".utf8)), suggestedName: "Sketch.pdf")], target: nil)
        await store.outbox?.process()                   // created as 44; the upload waits for a connection
        let item = try #require(store.items.only)
        await store.remove(item)
        #expect(store.items.isEmpty, "out of the list at once, though the server was not reached")
        let waiting = try #require(store.outbox?.items.only)
        #expect(waiting.cancellationRequested && waiting.state != .failed && store.errors[.drops] == nil)
        fake.responses = [.answer(404, Data())]
        await store.outbox?.retry(waiting.id)
        #expect(store.outbox?.items.isEmpty == true, "a 404 counts as deleted")
        #expect(fake.requests.map(\.httpMethod) == ["POST", "PUT", "DELETE", "DELETE"])
    }

    @Test func aPhoneItemNeverSentGoesWithoutARequest() async throws {
        let directory = testDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fake = DropTransport()
        let store = await store(fake, directory: directory)
        try await store.send(files: [DropFile(content: .data(Data("abc".utf8)), suggestedName: "Notes.txt")], target: nil)
        await store.remove(try #require(store.items.only))
        #expect(store.items.isEmpty && store.outbox?.items.isEmpty == true && fake.requests.isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }

    @Test func aRefusedDeleteBringsThePhonesItemBack() async throws {
        let directory = testDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fake = DropTransport()
        fake.responses = [.answer(201, try dropAnswer()), .failure(URLError(.notConnectedToInternet)),
                          .answer(409, Data(#"{"error":"Not now."}"#.utf8))]
        let store = await store(fake, directory: directory)
        try await store.send(files: [DropFile(content: .data(Data("abc".utf8)), suggestedName: "Sketch.pdf")], target: nil)
        await store.outbox?.process()
        await store.remove(try #require(store.items.only))
        let back = try #require(store.items.only)
        let row = DropRow(back, language: .english)
        #expect(row.line == "Not sent: Not now." && row.canRetry && row.canRemove)
        #expect(store.outbox?.items.only?.cancellationRequested == false && store.errors[.drops] == "Not now.")
    }

    @Test func aServerRowStillUploadingFromThisPhoneGoesWithItsUpload() async throws {
        let directory = testDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fake = DropTransport()
        let list = Data(#"{"drops":["#.utf8) + (try dropAnswer()) + Data("]}".utf8)
        fake.responses = [.answer(201, try dropAnswer()), .failure(URLError(.notConnectedToInternet)),
                          .answer(200, list), .answer(204, Data())]
        let store = await store(fake, directory: directory)
        try await store.send(files: [DropFile(content: .data(Data("abc".utf8)), suggestedName: "Sketch.pdf")], target: nil)
        await store.outbox?.process()
        await store.load(.drops)
        let item = try #require(store.items.only)
        guard case .server(let drop) = item else { Issue.record("expected the server's row"); return }
        #expect(drop.id == 44)
        await store.remove(item)
        #expect(store.items.isEmpty && store.outbox?.items.isEmpty == true)
        #expect(fake.requests.last.map { "\($0.httpMethod!) \($0.url!.path)" } == "DELETE /api/aresus/drops/44")
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
                               cacheURL: cache, defaults: nil, automatic: false, uploads: ImmediateDropUploads(fake))
        let pending = Task { await store.load(.folders) }
        await gate.waitUntilPaused()
        session.logOut()
        gate.resume()
        await pending.value
        #expect(store.folders == nil && store.loading.isEmpty && !FileManager.default.fileExists(atPath: cache.path))
    }
}
