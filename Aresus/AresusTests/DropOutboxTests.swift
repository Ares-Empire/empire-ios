import Foundation
import Testing
@testable import Aresus

@MainActor
struct DropOutboxTests {
    @Test func copiesHashesCreatesOnceAndUploadsFromDisk() async throws {
        let directory = testDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = await signedInSession()
        let fake = DropTransport()
        fake.responses = [.answer(201, try dropAnswer()), .answer(200, try dropAnswer(state: .waiting))]
        let outbox = DropOutbox(session: session, client: AresusAPI(transport: fake), directory: directory, automatic: false, uploads: ImmediateDropUploads(fake))
        let source = directory.appendingPathComponent("source.pdf")
        try Data("abc".utf8).write(to: source)
        let id = try await outbox.enqueue(DropFile(content: .file(source), suggestedName: "Sample.pdf"), name: "Sample.pdf", target: nil)
        try FileManager.default.removeItem(at: source)
        let local = try #require(outbox.items.only)
        #expect(local.id == id && local.serverID == nil)
        #expect(try Data(contentsOf: directory.appendingPathComponent(local.localFile)) == Data("abc".utf8))
        let values = try directory.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)
        await outbox.process()
        #expect(outbox.items.isEmpty)
        #expect(fake.requests.map(\.httpMethod) == ["POST", "PUT"])
        let request = try #require(fake.requests.first?.httpBody)
        let body = try AresusJSON.decoder().decode(NewDrop.self, from: request)
        #expect(body.size == 3 && body.sha256 == newDrop().sha256)
        #expect(fake.files == [directory.appendingPathComponent(local.localFile)])
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }

    @Test func offlineUploadSurvivesRelaunchWithoutAnotherCreate() async throws {
        let directory = testDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = await signedInSession()
        let fake = DropTransport()
        fake.responses = [.answer(201, try dropAnswer()), .failure(URLError(.notConnectedToInternet))]
        let outbox = DropOutbox(session: session, client: AresusAPI(transport: fake), directory: directory, automatic: false, uploads: ImmediateDropUploads(fake))
        let id = try await enqueue(outbox)
        await outbox.process()
        let failed = try #require(outbox.items.only)
        #expect(failed.serverID == 44 && failed.state == .onPhone && failed.lastError == "No connection.")
        #expect(failed.retryAt != nil && failed.attempts == 1)
        await outbox.process()
        #expect(fake.requests.count == 2) // The deadline prevents a busy retry loop.
        let restored = DropOutbox(session: session, client: AresusAPI(transport: fake), directory: directory, automatic: false, uploads: ImmediateDropUploads(fake))
        #expect(restored.items.only == failed)
        fake.responses = [.answer(200, try dropListAnswer()), .answer(200, try dropAnswer(state: .waiting))]
        await restored.retry(id)
        #expect(restored.items.isEmpty)
        #expect(fake.requests.map(\.httpMethod) == ["POST", "PUT", "GET", "PUT"])
    }

    @Test func checksum400IsRecomputedAndRetriedOnlyOnce() async throws {
        let directory = testDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fake = DropTransport()
        let sentence = Data(#"{"error":"The checksum does not match."}"#.utf8)
        fake.responses = [.answer(201, try dropAnswer()), .answer(400, sentence), .answer(200, try dropListAnswer()), .answer(400, sentence)]
        let outbox = DropOutbox(session: await signedInSession(), client: AresusAPI(transport: fake), directory: directory, automatic: false, uploads: ImmediateDropUploads(fake))
        _ = try await enqueue(outbox)
        await outbox.process()
        let item = try #require(outbox.items.only)
        #expect(item.state == .failed && item.checksumRetries == 1 && item.retryAt == nil)
        #expect(item.serverID == 44 && item.restarts == nil, "a 400 never starts a new drop")
        #expect(item.lastError == "The checksum does not match.")
        #expect(item.drop.sha256 == newDrop().sha256)
        #expect(fake.requests.map(\.httpMethod) == ["POST", "PUT", "GET", "PUT"])
        await outbox.process()
        #expect(fake.requests.count == 4)
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent(item.localFile).path))
    }

    @Test func aSingleBadChecksumCanRecover() async throws {
        let directory = testDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fake = DropTransport()
        fake.responses = [.answer(201, try dropAnswer()), .answer(400, Data()), .answer(200, try dropListAnswer()), .answer(200, try dropAnswer(state: .waiting))]
        let outbox = DropOutbox(session: await signedInSession(), client: AresusAPI(transport: fake), directory: directory, automatic: false, uploads: ImmediateDropUploads(fake))
        _ = try await enqueue(outbox)
        await outbox.process()
        #expect(outbox.items.isEmpty && fake.files.count == 2)
    }

    @Test(arguments: [413, 507])
    func permanentErrorsKeepTheFileAndServerSentence(status: Int) async throws {
        let directory = testDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fake = DropTransport()
        fake.responses = [.answer(201, try dropAnswer()), .answer(status, Data(#"{"error":"This file cannot be accepted."}"#.utf8))]
        let outbox = DropOutbox(session: await signedInSession(), client: AresusAPI(transport: fake), directory: directory, automatic: false, uploads: ImmediateDropUploads(fake))
        _ = try await enqueue(outbox)
        await outbox.process()
        #expect(outbox.items.only?.state == .failed)
        #expect(outbox.items.only?.lastError == "This file cannot be accepted.")
        await outbox.process()
        #expect(fake.requests.count == 2)
    }

    @Test(arguments: [DropState.landed, .waiting, .failed, .cancelled])
    func resendDiscardsBytesAlreadyOnTheServer(state: DropState) async throws {
        let directory = testDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fake = DropTransport()
        fake.responses = [.answer(200, try dropListAnswer(state: state))]
        let outbox = DropOutbox(session: await signedInSession(), client: AresusAPI(transport: fake),
                                directory: directory, automatic: false, uploads: ImmediateDropUploads(fake))
        let id = try await enqueue(outbox)
        var record = try #require(outbox.items.only)
        record.serverID = 44
        try DropJournal(directory: directory).save(record)
        var uploaded: [Drop] = []
        outbox.onUploaded = { uploaded.append($0) }
        await outbox.process()
        #expect(outbox.items.isEmpty && fake.files.isEmpty)
        #expect(fake.requests.map(\.httpMethod) == ["GET"])
        #expect(uploaded == (state == .cancelled ? [] : [try AresusJSON.decoder().decode(Drop.self, from: dropAnswer(state: state))]))
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent(record.localFile).path))
        #expect(try DropJournal(directory: directory).read(id) == nil)
    }

    @Test func offlineReconcileBeforeResendNeverUploadsBlindly() async throws {
        let directory = testDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fake = DropTransport(); fake.responses = [.failure(URLError(.notConnectedToInternet))]
        let outbox = DropOutbox(session: await signedInSession(), client: AresusAPI(transport: fake),
                                directory: directory, automatic: false, uploads: ImmediateDropUploads(fake))
        _ = try await enqueue(outbox)
        var record = try #require(outbox.items.only); record.serverID = 44
        try DropJournal(directory: directory).save(record)
        await outbox.process()
        let pending = try #require(outbox.items.only)
        #expect(pending.state == .onPhone && pending.retryAt != nil && pending.uploadSession == nil)
        #expect(pending.lastError == "No connection." && pending.attempts == 1)
        #expect(fake.requests.map(\.httpMethod) == ["GET"] && fake.files.isEmpty)
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent(record.localFile).path))
    }

    @Test(arguments: [DropState.waiting, .uploading])
    func upload409ReconcilesInsteadOfPermanentlyFailing(state: DropState) async throws {
        let directory = testDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fake = DropTransport()
        fake.responses = [.answer(201, try dropAnswer()), .answer(409, Data(#"{"error":"This drop cannot be changed in its current state."}"#.utf8)),
                          .answer(200, try dropListAnswer(state: state))]
        let outbox = DropOutbox(session: await signedInSession(), client: AresusAPI(transport: fake),
                                directory: directory, automatic: false, uploads: ImmediateDropUploads(fake))
        _ = try await enqueue(outbox)
        let record = try #require(outbox.items.only)
        var uploaded: [Drop] = []; outbox.onUploaded = { uploaded.append($0) }
        await outbox.process()
        #expect(fake.requests.map(\.httpMethod) == ["POST", "PUT", "GET"])
        if state == .waiting {
            #expect(outbox.items.isEmpty && uploaded.only?.state == .waiting)
            #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent(record.localFile).path))
        } else {
            let pending = try #require(outbox.items.only)
            #expect(pending.state == .onPhone && pending.retryAt != nil && pending.uploadSession == nil)
            #expect(pending.serverID == 44 && pending.restarts == nil, "a 409 never starts a new drop")
            #expect(uploaded.isEmpty)
        }
    }

    @Test func absentDropStillUsesPutFirstAndIts404StartsANewDrop() async throws {
        let directory = testDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fake = DropTransport()
        fake.responses = [.answer(200, Data(#"{"drops":[]}"#.utf8)), .answer(404, Data(#"{"error":"Unknown drop."}"#.utf8)),
                          .answer(201, try dropAnswer(id: 45)), .answer(200, try dropAnswer(state: .waiting, id: 45))]
        let outbox = DropOutbox(session: await signedInSession(), client: AresusAPI(transport: fake),
                                directory: directory, automatic: false, uploads: ImmediateDropUploads(fake))
        _ = try await enqueue(outbox)
        var record = try #require(outbox.items.only); record.serverID = 44
        try DropJournal(directory: directory).save(record)
        await outbox.process()
        // The bounded list proves nothing; only the PUT's own 404 does.
        #expect(fake.requests.map(\.httpMethod) == ["GET", "PUT", "POST", "PUT"])
        #expect(fake.requests.filter { $0.httpMethod == "PUT" }.compactMap(\.url?.path)
                == ["/api/aresus/drops/44/file", "/api/aresus/drops/45/file"])
        #expect(outbox.items.isEmpty)
    }

    /// The upload's 404: the server has no such drop (its `uploading` row expired after 24 hours), so the bytes never
    /// landed. The record forgets the id and goes again as a new drop, in the same pass.
    @Test func upload404SendsTheFileAgainAsANewDrop() async throws {
        let directory = testDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fake = DropTransport()
        fake.responses = [.answer(201, try dropAnswer()), .answer(404, Data(#"{"error":"Unknown drop."}"#.utf8)),
                          .answer(201, try dropAnswer(id: 45)), .answer(200, try dropAnswer(state: .waiting, id: 45))]
        let outbox = DropOutbox(session: await signedInSession(), client: AresusAPI(transport: fake),
                                directory: directory, automatic: false, uploads: ImmediateDropUploads(fake))
        _ = try await enqueue(outbox)
        let record = try #require(outbox.items.only)
        var uploaded: [Drop] = []; outbox.onUploaded = { uploaded.append($0) }
        await outbox.process()
        #expect(fake.requests.map(\.httpMethod) == ["POST", "PUT", "POST", "PUT"])
        #expect(fake.requests.filter { $0.httpMethod == "PUT" }.compactMap(\.url?.path)
                == ["/api/aresus/drops/44/file", "/api/aresus/drops/45/file"])
        let posts = try fake.requests.filter { $0.httpMethod == "POST" }
            .map { try AresusJSON.decoder().decode(NewDrop.self, from: $0.httpBody!) }
        #expect(posts.count == 2 && posts[0] == posts[1], "the same drop again: name, size, checksum, folder")
        let file = directory.appendingPathComponent(record.localFile)
        #expect(fake.files == [file, file], "the same bytes from the phone's copy")
        #expect(outbox.items.isEmpty && uploaded.map(\.id) == [45])
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }

    /// The new id is saved before its bytes go, as for any drop.
    @Test func upload404SavesTheNewServerID() async throws {
        let directory = testDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fake = DropTransport()
        fake.responses = [.answer(201, try dropAnswer()), .answer(404, Data(#"{"error":"Unknown drop."}"#.utf8)),
                          .answer(201, try dropAnswer(id: 45)), .failure(URLError(.notConnectedToInternet))]
        let outbox = DropOutbox(session: await signedInSession(), client: AresusAPI(transport: fake),
                                directory: directory, automatic: false, uploads: ImmediateDropUploads(fake))
        let id = try await enqueue(outbox)
        await outbox.process()
        let pending = try #require(outbox.items.only)
        #expect(pending.serverID == 45 && pending.restarts == 1)
        #expect(pending.state == .onPhone && pending.retryAt != nil && pending.lastError == "No connection.")
        #expect(try DropJournal(directory: directory).read(id)?.serverID == 45)
        #expect(fake.requests.map(\.httpMethod) == ["POST", "PUT", "POST", "PUT"])
    }

    /// A server that answers every upload with 404 gets a few new drops, never a loop; the record then fails as any
    /// refused upload. Retry, a person's tap, starts the limit again.
    @Test func upload404RestartsAtMostTwiceThenFails() async throws {
        let directory = testDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fake = DropTransport()
        let unknown = Data(#"{"error":"Unknown drop."}"#.utf8)
        fake.responses = [.answer(201, try dropAnswer()), .answer(404, unknown), .answer(201, try dropAnswer(id: 45)),
                          .answer(404, unknown), .answer(201, try dropAnswer(id: 46)), .answer(404, unknown)]
        let outbox = DropOutbox(session: await signedInSession(), client: AresusAPI(transport: fake),
                                directory: directory, automatic: false, uploads: ImmediateDropUploads(fake))
        let id = try await enqueue(outbox)
        await outbox.process()
        #expect(DropOutbox.maximumRestarts == 2)
        let failed = try #require(outbox.items.only)
        #expect(failed.state == .failed && failed.restarts == 2 && failed.serverID == 46 && failed.retryAt == nil)
        #expect(failed.lastError == "Unknown drop." && failed.uploadSession == nil)
        #expect(fake.requests.map(\.httpMethod) == ["POST", "PUT", "POST", "PUT", "POST", "PUT"])
        await outbox.process()
        #expect(fake.requests.count == 6, "a failed record waits for Retry")
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent(failed.localFile).path))
        fake.responses = [.answer(200, Data(#"{"drops":[]}"#.utf8)), .answer(404, unknown),
                          .answer(201, try dropAnswer(id: 47)), .answer(200, try dropAnswer(state: .waiting, id: 47))]
        await outbox.retry(id)
        #expect(fake.requests.map(\.httpMethod).suffix(4) == ["GET", "PUT", "POST", "PUT"])
        #expect(fake.requests.last?.url?.path == "/api/aresus/drops/47/file")
        #expect(outbox.items.isEmpty)
    }

    /// The three photos of 2026-11-08: their first upload failed, their rows expired a day later, and Retry got 404
    /// for good. Such a record, saved by the build before the restarts (no `restarts` key), decodes and goes on Retry.
    @Test func aRecordSavedBeforeTheRestartsDecodesAndIsSentAgainOnRetry() async throws {
        let directory = testDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let id = try #require(UUID(uuidString: "6F1C2A0E-3B4D-4E5F-8A9B-0C1D2E3F4A5B"))
        let saved = #"""
        {"id":"6F1C2A0E-3B4D-4E5F-8A9B-0C1D2E3F4A5B","drop":{"kind":"file","name":"Sample.pdf","size":3,\#
        "sha256":"ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",\#
        "target":{"root":"documents","folder":"Photos","new_folder":null},"receipt":null},\#
        "localFile":"6F1C2A0E-3B4D-4E5F-8A9B-0C1D2E3F4A5B.file","serverID":44,"created":784300000,"attempts":3,\#
        "lastError":"Unknown drop.","state":"failed","checksumRetries":0,"cancellationRequested":false,\#
        "uploadAttempt":"0A1B2C3D-4E5F-4A6B-8C7D-9E0F1A2B3C4D"}
        """#
        let record = try JSONDecoder().decode(DropOutboxItem.self, from: Data(saved.utf8))
        #expect(record.id == id && record.serverID == 44 && record.state == .failed && record.attempts == 3)
        #expect(record.restarts == nil && record.drop.target?.folder == "Photos")
        try Data(saved.utf8).write(to: directory.appendingPathComponent(id.uuidString + ".json"))
        try Data("abc".utf8).write(to: directory.appendingPathComponent(record.localFile))
        let fake = DropTransport()
        let outbox = DropOutbox(session: await signedInSession(), client: AresusAPI(transport: fake),
                                directory: directory, automatic: false, uploads: ImmediateDropUploads(fake))
        #expect(outbox.items == [record] && outbox.storageError == nil)
        await outbox.process()
        #expect(fake.requests.isEmpty, "a failed record waits for Retry")
        fake.responses = [.answer(200, Data(#"{"drops":[]}"#.utf8)), .answer(404, Data(#"{"error":"Unknown drop."}"#.utf8)),
                          .answer(201, try dropAnswer(id: 45)), .answer(200, try dropAnswer(state: .waiting, id: 45))]
        await outbox.retry(id)
        #expect(fake.requests.map(\.httpMethod) == ["GET", "PUT", "POST", "PUT"])
        #expect(fake.requests.last?.url?.path == "/api/aresus/drops/45/file")
        let body = try AresusJSON.decoder().decode(NewDrop.self, from: try #require(fake.requests[2].httpBody))
        #expect(body.target == Target(root: .documents, folder: "Photos", newFolder: nil) && body.sha256 == newDrop().sha256)
        #expect(outbox.items.isEmpty)
    }

    @Test func create400StopsAnd503WaitsWithCappedBackoff() async throws {
        let directory = testDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fake = DropTransport()
        fake.responses = [.answer(400, Data(#"{"error":"Bad name."}"#.utf8))]
        let outbox = DropOutbox(session: await signedInSession(), client: AresusAPI(transport: fake), directory: directory, automatic: false, uploads: ImmediateDropUploads(fake))
        let id = try await enqueue(outbox)
        await outbox.process()
        #expect(outbox.items.only?.state == .failed && fake.files.isEmpty)
        fake.responses = [.answer(503, Data(#"{"error":"Try later."}"#.utf8))]
        await outbox.retry(id)
        #expect(outbox.items.only?.state == .onPhone && outbox.items.only?.retryAt != nil)
        #expect(DropOutbox.retryDelay(attempts: 1) == 5)
        #expect(DropOutbox.retryDelay(attempts: 2) == 10)
        #expect(DropOutbox.retryDelay(attempts: 100) == 600)
    }

    @Test func removeSendsDeleteAndKeepsCancellationWhenOffline() async throws {
        let directory = testDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fake = DropTransport()
        fake.responses = [.answer(201, try dropAnswer()), .failure(URLError(.notConnectedToInternet)),
                          .failure(URLError(.notConnectedToInternet))]
        let outbox = DropOutbox(session: await signedInSession(), client: AresusAPI(transport: fake), directory: directory, automatic: false, uploads: ImmediateDropUploads(fake))
        let id = try await enqueue(outbox)
        await outbox.process()
        await outbox.remove(id)
        #expect(outbox.items.only?.cancellationRequested == true)
        #expect(fake.requests.last?.httpMethod == "DELETE")
        #expect(fake.requests.last?.url?.path == "/api/aresus/drops/44")
        fake.responses = [.answer(204, Data())]
        await outbox.retry(id)
        #expect(outbox.items.isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }

    @Test func logoutDeletesFilesAndDiscardsLateAnswers() async throws {
        let directory = testDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let session = await signedInSession()
        let fake = DropTransport()
        fake.responses = [.answer(201, try dropAnswer())]
        let gate = RequestGate()
        fake.gate = gate
        let outbox = DropOutbox(session: session, client: AresusAPI(transport: fake), directory: directory, automatic: false, uploads: ImmediateDropUploads(fake))
        _ = try await enqueue(outbox)
        let processing = Task { await outbox.process() }
        await gate.waitUntilPaused()
        session.logOut()
        #expect(outbox.items.isEmpty && !FileManager.default.fileExists(atPath: directory.path))
        gate.resume()
        await processing.value
        #expect(outbox.items.isEmpty && fake.requests.count == 1)
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test func removeDuringCreateCancelsTheReturnedID() async throws {
        let directory = testDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fake = DropTransport()
        fake.responses = [.answer(201, try dropAnswer()), .answer(204, Data())]
        let gate = RequestGate()
        fake.gate = gate
        let outbox = DropOutbox(session: await signedInSession(), client: AresusAPI(transport: fake), directory: directory, automatic: false, uploads: ImmediateDropUploads(fake))
        let id = try await enqueue(outbox)
        let processing = Task { await outbox.process() }
        await gate.waitUntilPaused()
        let removal = Task { await outbox.remove(id) }
        // Let remove mark the record while POST remains in flight.
        while outbox.items.only?.cancellationRequested == false { await Task.yield() }
        gate.resume()
        await processing.value
        await removal.value
        #expect(fake.requests.map(\.httpMethod) == ["POST", "DELETE"])
        #expect(outbox.items.isEmpty)
    }

    @Test func oldestFirstAndOnlyOneRequestAtATime() async throws {
        let directory = testDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fake = DropTransport()
        fake.responses = [.answer(201, try dropAnswer()), .answer(200, try dropAnswer(state: .waiting)),
                          .answer(201, try dropAnswer()), .answer(200, try dropAnswer(state: .waiting))]
        let outbox = DropOutbox(session: await signedInSession(), client: AresusAPI(transport: fake), directory: directory, automatic: false, uploads: ImmediateDropUploads(fake))
        _ = try await enqueue(outbox, name: "First.pdf")
        _ = try await enqueue(outbox, name: "Second.pdf")
        let gate = RequestGate()
        fake.gate = gate
        let processing = Task { await outbox.process() }
        await gate.waitUntilPaused()
        let concurrentPass = Task { await outbox.process() }
        await Task.yield()
        #expect(fake.requests.count == 1)
        gate.resume()
        await processing.value
        await concurrentPass.value
        let names = try fake.requests.filter { $0.httpMethod == "POST" }.map { try AresusJSON.decoder().decode(NewDrop.self, from: $0.httpBody!).name }
        #expect(names == ["First.pdf", "Second.pdf"])
        #expect(outbox.items.isEmpty)
    }

    @Test func damagedJournalDoesNotHideOtherQueuedFiles() async throws {
        let directory = testDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var item = localItem(serverID: 44)
        item.state = .uploading
        try JSONEncoder().encode(item).write(to: directory.appendingPathComponent(item.id.uuidString + ".json"))
        try Data("abc".utf8).write(to: directory.appendingPathComponent(item.localFile))
        try Data("broken JSON".utf8).write(to: directory.appendingPathComponent(UUID().uuidString + ".json"))
        let outbox = DropOutbox(session: await signedInSession(), directory: directory, automatic: false)
        #expect(outbox.items.only?.id == item.id && outbox.items.only?.serverID == 44)
        #expect(outbox.items.only?.state == .onPhone && outbox.storageError != nil)
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent(item.localFile).path))
    }

    @Test func unreadableAndInvalidImportsSendNothing() async throws {
        let directory = testDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fake = DropTransport()
        let outbox = DropOutbox(session: await signedInSession(), client: AresusAPI(transport: fake), directory: directory, automatic: false, uploads: ImmediateDropUploads(fake))
        await #expect(throws: DropLocalError.self) { try await enqueue(outbox, name: ".hidden") }
        await #expect(throws: DropLocalError.self) {
            try await outbox.enqueue(DropFile(content: .file(directory.appendingPathComponent("missing")), suggestedName: "Sample.pdf"), name: "Sample.pdf", target: nil)
        }
        #expect(outbox.items.isEmpty && fake.requests.isEmpty)
    }
}

@MainActor
func enqueue(_ outbox: DropOutbox, name: String = "Sample.pdf") async throws -> UUID {
    try await outbox.enqueue(DropFile(content: .data(Data("abc".utf8)), suggestedName: name), name: name, target: nil)
}

func testDirectory() -> URL { URL.temporaryDirectory.appendingPathComponent("DropsTests-\(UUID())", isDirectory: true) }
