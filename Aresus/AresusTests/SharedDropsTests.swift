import Foundation
import Testing
import UIKit
import UniformTypeIdentifiers
@testable import Aresus

@MainActor
final class HeldDropUploads: DropUploading {
    let identifier: String
    var completed: ((DropUploadID, Result<Drop, Error>, String?) async -> Void)?
    var tasks: [DropUploadID] = []
    var cancelled: [UUID] = []
    var requests: [URLRequest] = []
    var supportsDeferredRetry = false
    var deadlines: [Date?] = []
    init(identifier: String = "test-held-upload") { self.identifier = identifier }
    func submit(_ id: DropUploadID, request: URLRequest, file: URL, earliestBeginDate: Date?) async throws {
        #expect(FileManager.default.fileExists(atPath: file.path))
        tasks.append(id); requests.append(request); deadlines.append(earliestBeginDate)
    }
    func cancel(_ id: UUID) async { cancelled.append(id); tasks.removeAll { $0.record == id } }
    func activeIDs() async -> Set<UUID> { Set(tasks.map(\.record)) }
    func finish(_ result: Result<Drop, Error>) async throws {
        let ticket = try #require(tasks.first)
        tasks.removeFirst()
        await completed?(ticket, result, "fictional-empire-token")
    }
}

@MainActor
struct SharedDropsTests {
    @Test func migrationPreservesFilesIDsAndNewerGroupRecordsAndRunsOnce() async throws {
        let root = testDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let old = root.appendingPathComponent("old")
        let group = root.appendingPathComponent("group")
        let session = await signedInSession()
        let first = DropOutbox(session: session, directory: old, automatic: false, uploads: HeldDropUploads())
        let id = try await enqueue(first)
        var record = try #require(first.items.only)
        record.serverID = 44
        try DropJournal(directory: old).save(record)
        let migrated = DropOutbox(session: session, directory: group, automatic: false, legacyDirectory: old, uploads: HeldDropUploads())
        #expect(migrated.items.only?.id == id && migrated.items.only?.serverID == 44)
        #expect(try Data(contentsOf: group.appendingPathComponent(record.localFile)) == Data("abc".utf8))
        #expect(!FileManager.default.fileExists(atPath: old.path))
        // A partial older migration must not replace a record already advanced in the group.
        try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
        var stale = record; stale.serverID = nil
        try DropJournal(directory: old).save(stale)
        try Data("abc".utf8).write(to: old.appendingPathComponent(stale.localFile))
        try DropJournal(directory: group).migrate(from: old)
        migrated.reload()
        #expect(migrated.items.only?.serverID == 44)
        try DropJournal(directory: group).migrate(from: old)
        #expect(migrated.items.count == 1)
    }

    @Test func twoOutboxesSeeAddsAndCompletionsAfterReloadAndNeverCreateTwice() async throws {
        let directory = testDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = await signedInSession()
        let api = DropTransport()
        api.responses = [.answer(201, try dropAnswer())]
        let uploads = HeldDropUploads()
        let first = DropOutbox(session: session, client: AresusAPI(transport: api), directory: directory, automatic: false, uploads: uploads)
        let otherUploads = HeldDropUploads(identifier: "other-process")
        let second = DropOutbox(session: session, client: AresusAPI(transport: api), directory: directory, automatic: false, uploads: otherUploads)
        let id = try await enqueue(first)
        #expect(second.items.isEmpty)
        second.reload()
        #expect(second.items.only?.id == id)
        await first.process()
        await second.process()
        #expect(api.requests.count == 1 && uploads.tasks.count == 1 && otherUploads.tasks.isEmpty)
        let ticket = try #require(uploads.tasks.first)
        let uploaded = try AresusJSON.decoder().decode(Drop.self, from: dropAnswer(state: .waiting))
        // iOS delivers the first process's task to a newly opened process.
        await second.finished(ticket, result: .success(uploaded), token: session.token)
        #expect(first.items.count == 1)
        first.reload()
        #expect(first.items.isEmpty && second.items.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent(id.uuidString + ".file").path))
    }

    @Test func operationLeasePreventsASecondCreateWhileAnotherProcessWaitsForPOST() async throws {
        let directory = testDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = await signedInSession()
        let api = DropTransport(); api.responses = [.answer(201, try dropAnswer())]
        let gate = RequestGate(); api.gate = gate; api.gateMethod = "POST"
        let firstUploads = HeldDropUploads(), otherUploads = HeldDropUploads(identifier: "other-process")
        let first = DropOutbox(session: session, client: AresusAPI(transport: api), directory: directory, automatic: false, uploads: firstUploads)
        let second = DropOutbox(session: session, client: AresusAPI(transport: api), directory: directory, automatic: false, uploads: otherUploads)
        _ = try await enqueue(first)
        let pass = Task { await first.process() }
        await gate.waitUntilPaused()
        await second.process()
        #expect(api.requests.count == 1 && otherUploads.tasks.isEmpty)
        gate.resume()
        await pass.value
        #expect(api.requests.count == 1 && firstUploads.tasks.count == 1)
    }

    @Test func backgroundFailureRetryCancellationAndStaleCompletion() async throws {
        let directory = testDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let api = DropTransport(); api.responses = [.answer(201, try dropAnswer()), .answer(200, try dropListAnswer()), .answer(204, Data())]
        let uploads = HeldDropUploads()
        let outbox = DropOutbox(session: await signedInSession(), client: AresusAPI(transport: api), directory: directory,
                                automatic: false, uploads: uploads)
        let id = try await enqueue(outbox)
        await outbox.process()
        let oldTicket = try #require(uploads.tasks.first)
        try await uploads.finish(.failure(URLError(.networkConnectionLost)))
        #expect(outbox.items.only?.state == .onPhone && outbox.items.only?.retryAt != nil)
        await outbox.retry(id)
        #expect(uploads.tasks.count == 1 && api.requests.count == 2)
        let waiting = try AresusJSON.decoder().decode(Drop.self, from: dropAnswer(state: .waiting))
        await outbox.finished(oldTicket, result: .success(waiting), token: "fictional-empire-token")
        #expect(outbox.items.count == 1, "late completion of an older attempt cannot finish the retry")
        await outbox.remove(id)
        #expect(uploads.cancelled == [id] && outbox.items.isEmpty)
        #expect(api.requests.map(\.httpMethod) == ["POST", "GET", "DELETE"])
    }

    @Test func retryDeadlineIsHandedToBackgroundSessionBeforeClosing() async throws {
        let directory = testDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let api = DropTransport(); api.responses = [.answer(201, try dropAnswer()), .answer(200, try dropListAnswer())]
        let uploads = HeldDropUploads(); uploads.supportsDeferredRetry = true
        let outbox = DropOutbox(session: await signedInSession(), client: AresusAPI(transport: api), directory: directory,
                                automatic: false, uploads: uploads)
        _ = try await enqueue(outbox); await outbox.process()
        try await uploads.finish(.failure(HTTPError.server(503, "Try later.")))
        let item = try #require(outbox.items.only)
        #expect(item.uploadSession == uploads.identifier && item.state == .onPhone && item.attempts == 2)
        #expect(uploads.tasks.count == 1 && uploads.deadlines.last! == item.retryAt)
        #expect(api.requests.map(\.httpMethod) == ["POST", "GET"], "retrying bytes never creates another server drop")
    }

    @Test(arguments: [DropState.waiting, .uploading])
    func deferredRetry409CompletionReconcilesBeforeAnotherSubmission(state: DropState) async throws {
        let directory = testDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let api = DropTransport()
        api.responses = [.answer(201, try dropAnswer()), .answer(200, try dropListAnswer()),
                         .answer(200, try dropListAnswer(state: state)), .answer(200, try dropListAnswer())]
        let uploads = HeldDropUploads(); uploads.supportsDeferredRetry = true
        let outbox = DropOutbox(session: await signedInSession(), client: AresusAPI(transport: api), directory: directory,
                                automatic: false, uploads: uploads)
        _ = try await enqueue(outbox); await outbox.process()
        try await uploads.finish(.failure(URLError(.cancelled)))
        #expect(uploads.deadlines.last! != nil)
        var uploaded: [Drop] = []; outbox.onUploaded = { uploaded.append($0) }
        try await uploads.finish(.failure(HTTPError.server(409, "This drop cannot be changed in its current state.")))
        if state == .waiting {
            #expect(outbox.items.isEmpty && uploads.tasks.isEmpty && uploaded.only?.state == .waiting)
            #expect(api.requests.map(\.httpMethod) == ["POST", "GET", "GET"])
        } else {
            let pending = try #require(outbox.items.only)
            #expect(pending.state == .onPhone && pending.retryAt != nil && pending.uploadSession == uploads.identifier)
            #expect(uploads.tasks.count == 1 && uploads.deadlines.last! == pending.retryAt && pending.attempts == 3)
            #expect(api.requests.map(\.httpMethod) == ["POST", "GET", "GET", "GET"])
        }
    }

    @Test func background401EndsSharedSessionAndClearsQueue() async throws {
        let directory = testDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = await signedInSession()
        let api = DropTransport(); api.responses = [.answer(201, try dropAnswer())]
        let uploads = HeldDropUploads()
        let outbox = DropOutbox(session: session, client: AresusAPI(transport: api), directory: directory,
                                automatic: false, uploads: uploads)
        _ = try await enqueue(outbox); await outbox.process()
        try await uploads.finish(.failure(HTTPError.unauthorized))
        #expect(!session.isSignedIn && outbox.items.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test func reconnectKeepsRunningTaskAndRecoversAnInterruptedSubmission() async throws {
        let directory = testDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let api = DropTransport(); api.responses = [.answer(201, try dropAnswer())]
        let uploads = HeldDropUploads()
        let outbox = DropOutbox(session: await signedInSession(), client: AresusAPI(transport: api), directory: directory,
                                automatic: false, uploads: uploads)
        _ = try await enqueue(outbox); await outbox.process()
        await outbox.reconnect()
        #expect(outbox.items.only?.uploadSession == uploads.identifier)
        uploads.tasks = [] // daemon cancelled the task after a force quit, or the process died before task creation
        api.responses = [.answer(200, Data("{\"drops\":[".utf8) + (try dropAnswer()) + Data("]}".utf8))]
        await outbox.reconnect()
        #expect(outbox.items.only?.uploadSession == nil && outbox.items.only?.state == .onPhone)
        api.responses = [.answer(200, try dropListAnswer())]
        await outbox.process()
        #expect(uploads.tasks.count == 1 && api.requests.filter { $0.httpMethod == "POST" }.count == 1)
    }

    @Test func reconnectRecognizesBytesAcceptedBeforeForceQuit() async throws {
        let directory = testDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let api = DropTransport(); api.responses = [.answer(201, try dropAnswer())]
        let uploads = HeldDropUploads()
        let outbox = DropOutbox(session: await signedInSession(), client: AresusAPI(transport: api), directory: directory,
                                automatic: false, uploads: uploads)
        _ = try await enqueue(outbox); await outbox.process()
        uploads.tasks = []
        api.responses = [.answer(200, Data("{\"drops\":[".utf8) + (try dropAnswer(state: .waiting)) + Data("]}".utf8))]
        var handedOver = false
        outbox.onUploaded = { #expect($0.state == .waiting); handedOver = true }
        await outbox.reconnect()
        #expect(outbox.items.isEmpty && handedOver)
        #expect(api.requests.map(\.httpMethod) == ["POST", "GET"])
    }

    @Test func reconnectCleansStaleFailedAndIdleRecordsWithOneList() async throws {
        let directory = testDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let api = DropTransport()
        let outbox = DropOutbox(session: await signedInSession(), client: AresusAPI(transport: api), directory: directory,
                                automatic: false, uploads: HeldDropUploads())
        var records: [DropOutboxItem] = []
        var server: [Drop] = []
        for (index, state) in [DropOutboxItem.State.failed, .onPhone, .uploading].enumerated() {
            _ = try await enqueue(outbox)
            var record = try #require(outbox.items.last)
            record.serverID = 44 + index
            record.state = state
            record.lastError = "This drop cannot be changed in its current state."
            if state == .uploading { record.uploadSession = "test-held-upload" }
            try DropJournal(directory: directory).save(record)
            records.append(record)
            var drop = try AresusJSON.decoder().decode(Drop.self, from: dropAnswer(state: .landed))
            drop.id = 44 + index; server.append(drop)
        }
        api.responses = [.answer(200, try AresusJSON.encoder().encode(DropsAnswer(drops: server)))]
        var uploaded: [Drop] = []; outbox.onUploaded = { uploaded.append($0) }
        await outbox.reconnect()
        #expect(outbox.items.isEmpty && uploaded == server)
        #expect(api.requests.map(\.httpMethod) == ["GET"])
        for record in records {
            #expect(try DropJournal(directory: directory).read(record.id) == nil)
            #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent(record.localFile).path))
        }
    }

    @Test func reconnectOfflineBacksOffWithoutResettingToABlindRetry() async throws {
        let directory = testDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let api = DropTransport(); api.responses = [.failure(URLError(.notConnectedToInternet))]
        let uploads = HeldDropUploads()
        let outbox = DropOutbox(session: await signedInSession(), client: AresusAPI(transport: api), directory: directory,
                                automatic: false, uploads: uploads)
        _ = try await enqueue(outbox)
        var record = try #require(outbox.items.only)
        record.serverID = 44; record.state = .uploading; record.uploadSession = uploads.identifier; record.attempts = 3
        try DropJournal(directory: directory).save(record)
        await outbox.reconnect()
        let pending = try #require(outbox.items.only)
        #expect(pending.state == .onPhone && pending.uploadSession == nil && pending.lastError == "No connection.")
        #expect(try #require(pending.retryAt).timeIntervalSinceNow > 15)
        await outbox.process()
        #expect(api.requests.map(\.httpMethod) == ["GET"] && uploads.tasks.isEmpty)
    }

    /// A record that failed for good (too large, quota) and one waiting for its retry are only checked at launch: they
    /// go when the server has the file, and otherwise stay exactly as they were, also when the check itself fails.
    @Test(arguments: [false, true])
    func reconnectOnlyChecksIdleRecordsTheServerStillWaitsFor(offline: Bool) async throws {
        let directory = testDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let api = DropTransport()
        let uploads = HeldDropUploads()
        let outbox = DropOutbox(session: await signedInSession(), client: AresusAPI(transport: api), directory: directory,
                                automatic: false, uploads: uploads)
        let failedID = try await enqueue(outbox), waitingID = try await enqueue(outbox, name: "Other.pdf")
        var failed = try #require(outbox.items.first { $0.id == failedID })
        failed.serverID = 44; failed.state = .failed; failed.lastError = "This file is too large."; failed.attempts = 1
        try DropJournal(directory: directory).save(failed)
        var waiting = try #require(outbox.items.first { $0.id == waitingID })
        waiting.serverID = 45; waiting.state = .onPhone; waiting.attempts = 2
        waiting.retryAt = Date.now.addingTimeInterval(600); waiting.lastError = "No connection."
        try DropJournal(directory: directory).save(waiting)
        var first = try AresusJSON.decoder().decode(Drop.self, from: dropAnswer(state: .uploading))
        var second = first
        first.id = 44; second.id = 45
        api.responses = [offline ? .failure(URLError(.notConnectedToInternet))
            : .answer(200, try AresusJSON.encoder().encode(DropsAnswer(drops: [first, second])))]
        await outbox.reconnect()
        #expect(api.requests.map(\.httpMethod) == ["GET"] && uploads.tasks.isEmpty)
        #expect(outbox.items.first { $0.id == failedID } == failed)
        #expect(outbox.items.first { $0.id == waitingID } == waiting)
    }

    @Test func reconnectLeavesForeignUploadsAndLeasedRecordsAlone() async throws {
        let directory = testDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let api = DropTransport()
        let outbox = DropOutbox(session: await signedInSession(), client: AresusAPI(transport: api), directory: directory,
                                automatic: false, uploads: HeldDropUploads())
        let foreignID = try await enqueue(outbox), leasedID = try await enqueue(outbox, name: "Other.pdf")
        var foreign = try #require(outbox.items.first { $0.id == foreignID })
        foreign.serverID = 44; foreign.uploadSession = "another-process"; foreign.state = .uploading
        try DropJournal(directory: directory).save(foreign)
        var leased = try #require(outbox.items.first { $0.id == leasedID })
        leased.serverID = 45; leased.state = .failed
        try DropJournal(directory: directory).save(leased)
        let lease = try #require(DropJournal(directory: directory).claim(leasedID))
        await outbox.reconnect()
        withExtendedLifetime(lease) {}
        #expect(api.requests.isEmpty && outbox.items == [foreign, leased])
    }

    @Test(arguments: [DropState.waiting, .uploading])
    func background409DeliveryReconcilesAndFinishesEventsAfterward(state: DropState) async throws {
        let directory = testDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = await signedInSession()
        let api = DropTransport()
        let driver = DropBackgroundUploads(identifier: "test-conflict-\(UUID())")
        defer { driver.invalidate() }
        let outbox = DropOutbox(session: session, client: AresusAPI(transport: api), directory: directory,
                                automatic: false, uploads: driver)
        _ = try await enqueue(outbox)
        var record = try #require(outbox.items.only)
        let ticket = DropUploadID(record: record.id)
        record.serverID = 44; record.state = .uploading
        record.uploadSession = driver.identifier; record.uploadAttempt = ticket.attempt
        try DropJournal(directory: directory).save(record)
        // If it is still streaming, a failed follow-up GET prevents submitting any real network task in this test.
        api.responses = [.answer(200, try dropListAnswer(state: state)), .failure(URLError(.notConnectedToInternet))]
        await withCheckedContinuation { continuation in
            driver.finishedEvents = { continuation.resume() }
            driver.deliver(ticket, result: .failure(HTTPError.server(409, "This drop cannot be changed in its current state.")), token: session.token)
            driver.finishEvents()
        }
        if state == .waiting {
            #expect(outbox.items.isEmpty && api.requests.count == 1)
            #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent(record.localFile).path))
        } else {
            let pending = try #require(outbox.items.only)
            #expect(pending.state == .onPhone && pending.retryAt != nil && pending.uploadSession == nil)
            #expect(api.requests.map(\.httpMethod) == ["GET", "GET"])
        }
    }

    @Test func deferredRetryChecksAgainAndDiscardsAcceptedBytes() async throws {
        let directory = testDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let api = DropTransport()
        api.responses = [.answer(201, try dropAnswer()), .answer(200, try dropListAnswer(state: .waiting))]
        let uploads = HeldDropUploads(); uploads.supportsDeferredRetry = true
        let outbox = DropOutbox(session: await signedInSession(), client: AresusAPI(transport: api), directory: directory,
                                automatic: false, uploads: uploads)
        _ = try await enqueue(outbox); await outbox.process()
        var uploaded: [Drop] = []; outbox.onUploaded = { uploaded.append($0) }
        try await uploads.finish(.failure(URLError(.cancelled)))
        #expect(outbox.items.isEmpty && uploads.tasks.isEmpty && uploaded.only?.state == .waiting)
        #expect(api.requests.map(\.httpMethod) == ["POST", "GET"])
    }

    @Test func logoutDuringReconcileDiscardsItsLateAnswer() async throws {
        let directory = testDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = await signedInSession()
        let api = DropTransport(); api.responses = [.answer(200, try dropListAnswer(state: .landed))]
        let outbox = DropOutbox(session: session, client: AresusAPI(transport: api), directory: directory,
                                automatic: false, uploads: HeldDropUploads())
        _ = try await enqueue(outbox)
        var record = try #require(outbox.items.only); record.serverID = 44; record.state = .failed
        try DropJournal(directory: directory).save(record)
        let gate = RequestGate(); api.gate = gate
        var uploaded = false; outbox.onUploaded = { _ in uploaded = true }
        let reconnect = Task { await outbox.reconnect() }
        await gate.waitUntilPaused()
        session.logOut(); gate.resume(); await reconnect.value
        #expect(outbox.items.isEmpty && !uploaded && !FileManager.default.fileExists(atPath: directory.path))
    }

    @Test func unauthorizedReconcileClearsQueueWithoutUploading() async throws {
        let directory = testDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = await signedInSession()
        let api = DropTransport(); api.responses = [.answer(401, Data())]
        let outbox = DropOutbox(session: session, client: AresusAPI(transport: api), directory: directory,
                                automatic: false, uploads: HeldDropUploads())
        _ = try await enqueue(outbox)
        var record = try #require(outbox.items.only); record.serverID = 44
        try DropJournal(directory: directory).save(record)
        await outbox.process()
        #expect(!session.isSignedIn && outbox.items.isEmpty && api.requests.map(\.httpMethod) == ["GET"])
    }

    @Test func delegateParsesResponsesAndFinishesEventsAfterRecordUpdate() async throws {
        let configuration = DropBackgroundUploads.configuration(identifier: DropContainer.appUploadSession)
        #expect(configuration.sharedContainerIdentifier == DropContainer.appGroup)
        #expect(configuration.sessionSendsLaunchEvents && configuration.waitsForConnectivity)
        let response = HTTPURLResponse(url: AresusAPI.baseURL, statusCode: 200, httpVersion: nil, headerFields: nil)!
        let data = try dropAnswer(state: .waiting)
        #expect(try DropBackgroundUploads.result(data: data, response: response, error: nil).get().state == .waiting)
        let unauthorized = HTTPURLResponse(url: AresusAPI.baseURL, statusCode: 401, httpVersion: nil, headerFields: nil)!
        #expect(throws: HTTPError.self) { try DropBackgroundUploads.result(data: Data(), response: unauthorized, error: nil).get() }
        let driver = DropBackgroundUploads(identifier: "test-delegate-\(UUID())")
        defer { driver.invalidate() }
        var updated = false
        driver.completed = { _, _, _ in await Task.yield(); updated = true }
        await withCheckedContinuation { continuation in
            driver.finishedEvents = { #expect(updated); continuation.resume() }
            driver.deliver(DropUploadID(record: UUID()), result: .success(try! AresusJSON.decoder().decode(Drop.self, from: data)), token: nil)
            driver.finishEvents()
        }
    }

    @Test func folderCacheMigrationCannotResurrectFoldersAfterLogout() async throws {
        let root = testDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let old = root.appendingPathComponent("old-folders.json"), group = root.appendingPathComponent("group-folders.json")
        try sampleData("drop-folders").write(to: old)
        let session = await signedInSession()
        let store = DropsStore(session: session, directory: root.appendingPathComponent("outbox"), cacheURL: group,
                               defaults: nil, automatic: false, uploads: HeldDropUploads(), legacyCacheURL: old)
        #expect(store.folders != nil && FileManager.default.fileExists(atPath: group.path))
        #expect(!FileManager.default.fileExists(atPath: old.path))
        session.logOut()
        let reopened = DropsStore(session: await signedInSession(), directory: root.appendingPathComponent("outbox"), cacheURL: group,
                                  defaults: nil, automatic: false, uploads: HeldDropUploads(), legacyCacheURL: old)
        #expect(reopened.folders == nil)
    }

    @Test func recentsMigrateOnceAndKeepTheGroupsNewerSelection() throws {
        let oldName = "test-old-\(UUID())", groupName = "test-group-\(UUID())"
        let old = try #require(UserDefaults(suiteName: oldName)), group = try #require(UserDefaults(suiteName: groupName))
        defer { old.removePersistentDomain(forName: oldName); group.removePersistentDomain(forName: groupName) }
        let target = Target(root: .documents, folder: "Examples")
        DropRecentFolders(defaults: old).use(target, source: .photo)
        let migrated = DropRecentFolders(defaults: group, legacyDefaults: old)
        #expect(migrated.targets == [target] && migrated.lastBySource[.photo] == target)
        let newer = Target(root: .downloads, folder: "Newer")
        migrated.use(newer, source: .file)
        DropRecentFolders(defaults: old).use(Target(root: .documents, folder: "Stale"), source: .file)
        let reopened = DropRecentFolders(defaults: group, legacyDefaults: old)
        #expect(reopened.targets == [newer, target])
        reopened.clear()
        #expect(DropRecentFolders(defaults: group, legacyDefaults: old).targets.isEmpty)
    }
}

@MainActor
struct ShareItemsTests {
    private func fileProvider(_ url: URL, type: UTType, name: String?) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.suggestedName = name
        provider.registerFileRepresentation(forTypeIdentifier: type.identifier, fileOptions: [], visibility: .all) { completion in
            completion(url, false, nil)
            return nil
        }
        return provider
    }

    @Test func filesCopiedBeforeProviderAccessEndsAndKeepSuggestedNames() async throws {
        let root = testDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let original = root.appendingPathComponent("provider.pdf")
        try Data("fictional document".utf8).write(to: original)
        let temporary = SendTemporaryFiles(base: root.appendingPathComponent("group"))
        let answer = await ShareItems(temporary: temporary).read(providers: [fileProvider(original, type: .pdf, name: "Notes")])
        try FileManager.default.removeItem(at: original)
        let file = try #require(answer.files.only)
        #expect(file.suggestedName == "Notes.pdf" && file.source == .file && answer.unreadable == 0)
        guard case .file(let url) = file.content else { Issue.record("must be file-backed"); return }
        #expect(url.path.hasPrefix(temporary.base.path + "/"))
        #expect(try Data(contentsOf: url) == Data("fictional document".utf8))
    }

    @Test func imageDataAndSeveralAttachmentsBecomeFiles() async throws {
        let root = testDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let png = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).pngData { context in
            UIColor.systemBlue.setFill(); context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
        let image = NSItemProvider()
        image.suggestedName = "IMG_0001"
        image.registerDataRepresentation(forTypeIdentifier: UTType.png.identifier, visibility: .all) { completion in
            completion(png, nil); return nil
        }
        let data = NSItemProvider()
        data.suggestedName = "Read me"
        data.registerDataRepresentation(forTypeIdentifier: UTType.plainText.identifier, visibility: .all) { completion in
            completion(Data("fictional note".utf8), nil); return nil
        }
        // A picture with a name someone chose (from Files) keeps it, so it is sent as a file.
        let named = NSItemProvider()
        named.suggestedName = "Lake"
        named.registerDataRepresentation(forTypeIdentifier: UTType.png.identifier, visibility: .all) { completion in
            completion(png, nil); return nil
        }
        let item = NSExtensionItem(); item.attachments = [image, data, named]
        let answer = await ShareItems(temporary: SendTemporaryFiles(base: root)).read([item])
        #expect(answer.files.count == 3 && answer.unreadable == 0)
        #expect(answer.files.map(\.source) == [.photo, .file, .file])
        #expect(answer.files.first?.suggestedName == "IMG_0001.png")
        #expect(answer.files.last.map(SendDraft.defaultName) == "Lake.png")
        let photo = try #require(answer.files.first)
        #expect(SendDraft.defaultName(photo).hasSuffix(".png"))
        #expect(SendDraft.defaultName(photo) != "IMG_0001.png", "a camera's name becomes the capture-date name")
        for file in answer.files {
            guard case .file(let url) = file.content else { Issue.record("must be file-backed"); continue }
            #expect(FileManager.default.fileExists(atPath: url.path))
        }
    }

    @Test func unreadableItemsAreCountedAndOnlyTwentyAreRead() async throws {
        let root = testDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let good = NSItemProvider()
        good.suggestedName = "Example.txt"
        good.registerDataRepresentation(forTypeIdentifier: UTType.plainText.identifier, visibility: .all) { completion in
            completion(Data("fictional".utf8), nil); return nil
        }
        let broken = NSItemProvider()
        broken.registerFileRepresentation(forTypeIdentifier: UTType.pdf.identifier, fileOptions: [], visibility: .all) { completion in
            completion(nil, false, CocoaError(.fileReadUnknown)); return nil
        }
        let answer = await ShareItems(temporary: SendTemporaryFiles(base: root)).read(providers: [broken] + Array(repeating: good, count: 20))
        #expect(answer.files.count == 19 && answer.unreadable == 2)
    }

    @Test func defaultNamesHaveExtensionsAndCannotEscapeCopyFolder() {
        #expect(ShareItems.name(suggested: "", loaded: nil, type: UTType.pdf.identifier) == "File.pdf")
        #expect(ShareItems.name(suggested: "Sketch", loaded: "x.png", type: UTType.png.identifier) == "Sketch.png")
        #expect(ShareItems.name(suggested: "Plan.pdf", loaded: "x.pdf", type: UTType.pdf.identifier) == "Plan.pdf")
        #expect(!ShareItems.name(suggested: "../../outside", loaded: nil, type: UTType.pdf.identifier).contains("/"))
    }

    @Test func draftStartsWithFilesAddsDeduplicatesAndRemoves() {
        let first = DropFile(content: .file(URL(fileURLWithPath: "/fictional/first.pdf")), suggestedName: "First.pdf")
        let second = DropFile(content: .file(URL(fileURLWithPath: "/fictional/second.pdf")), suggestedName: "Second.pdf")
        let draft = SendDraft(files: [first])
        draft.choose(Target(root: .documents, folder: "Examples"))
        draft.useFiles([URL(fileURLWithPath: "/fictional/first.pdf"), URL(fileURLWithPath: "/fictional/second.pdf")], last: nil)
        #expect(draft.picked.count == 2 && draft.target?.folder == "Examples")
        draft.remove(draft.picked[0].id)
        #expect(draft.picked.only?.file.suggestedName == "second.pdf" && draft.name.name == "second.pdf")
        draft.remove(draft.picked[0].id)
        #expect(!draft.hasPicked && !draft.canSend)
        // Photos re-picked via PhotosPicker keep the asset identity despite having a new temporary URL.
        var photo = first; photo.identity = "fictional-photo-asset"; photo.source = .photo
        var copy = second; copy.identity = photo.identity; copy.source = .photo
        draft.use([PickedFile(file: photo, displayName: "First.pdf"), PickedFile(file: copy, displayName: "Second.pdf")], source: .photo, last: nil)
        #expect(draft.picked.count == 1)
    }
}
