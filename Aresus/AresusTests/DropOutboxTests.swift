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
        fake.responses = [.answer(200, try dropAnswer(state: .waiting))]
        await restored.retry(id)
        #expect(restored.items.isEmpty)
        #expect(fake.requests.map(\.httpMethod) == ["POST", "PUT", "PUT"])
    }

    @Test func checksum400IsRecomputedAndRetriedOnlyOnce() async throws {
        let directory = testDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fake = DropTransport()
        let sentence = Data(#"{"error":"The checksum does not match."}"#.utf8)
        fake.responses = [.answer(201, try dropAnswer()), .answer(400, sentence), .answer(400, sentence)]
        let outbox = DropOutbox(session: await signedInSession(), client: AresusAPI(transport: fake), directory: directory, automatic: false, uploads: ImmediateDropUploads(fake))
        _ = try await enqueue(outbox)
        await outbox.process()
        let item = try #require(outbox.items.only)
        #expect(item.state == .failed && item.checksumRetries == 1 && item.retryAt == nil)
        #expect(item.lastError == "The checksum does not match.")
        #expect(item.drop.sha256 == newDrop().sha256)
        #expect(fake.requests.map(\.httpMethod) == ["POST", "PUT", "PUT"])
        await outbox.process()
        #expect(fake.requests.count == 3)
        #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent(item.localFile).path))
    }

    @Test func aSingleBadChecksumCanRecover() async throws {
        let directory = testDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fake = DropTransport()
        fake.responses = [.answer(201, try dropAnswer()), .answer(400, Data()), .answer(200, try dropAnswer(state: .waiting))]
        let outbox = DropOutbox(session: await signedInSession(), client: AresusAPI(transport: fake), directory: directory, automatic: false, uploads: ImmediateDropUploads(fake))
        _ = try await enqueue(outbox)
        await outbox.process()
        #expect(outbox.items.isEmpty && fake.files.count == 2)
    }

    @Test(arguments: [413, 507, 404, 409])
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
