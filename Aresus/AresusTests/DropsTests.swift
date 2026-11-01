import Foundation
import Testing
@testable import Aresus

@MainActor
struct DropsTests {
    @Test func bundledSamplesAndAllStatesDecode() throws {
        let folders: FolderList = try sample("drop-folders")
        let answer: DropsAnswer = try sample("drops")
        #expect(folders.updated == at("2026-11-01T15:00:00Z"))
        #expect(folders.fallbackCount == 2 && folders.receipts == "Receipts")
        #expect(answer.drops.map(\.id) == [5, 4, 3, 2, 1])
        #expect(answer.drops[2].kind == .receipt && answer.drops[2].target == nil)
        #expect(answer.drops[1].target?.root == .documents && answer.drops[1].state == .failed)
        for state in DropState.allCases {
            var drop = answer.drops[0]
            drop.state = state
            #expect(try AresusJSON.decoder().decode(Drop.self, from: AresusJSON.encoder().encode(drop)) == drop)
        }
    }

    @Test func receiptAndNullFieldsMatchTheWire() throws {
        let receipt = Receipt(date: "2026-11-01", shop: "Sample Shop", item: "Lamp", totalCents: 1234,
                              tax: true, flat: false, keep: false, warrantyUntil: "2028-11-01")
        let drop = NewDrop(kind: .receipt, name: "Sample.pdf", size: 3, sha256: String(repeating: "a", count: 64), target: nil, receipt: receipt)
        let data = try AresusJSON.encoder().encode(drop)
        #expect(try AresusJSON.decoder().decode(NewDrop.self, from: data) == drop)
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["target"] is NSNull)
        let detail = try #require(json["receipt"] as? [String: Any])
        #expect(detail["total_cents"] as? Int == 1234)
        #expect(detail["warranty_until"] as? String == "2028-11-01")
        let target = Target(root: .documents, folder: "", newFolder: nil)
        let targetJSON = try #require(JSONSerialization.jsonObject(with: AresusJSON.encoder().encode(target)) as? [String: Any])
        #expect(targetJSON["new_folder"] is NSNull)
        var file = drop
        file.kind = .file
        file.receipt = nil
        let fileJSON = try #require(JSONSerialization.jsonObject(with: AresusJSON.encoder().encode(file)) as? [String: Any])
        #expect(fileJSON["receipt"] is NSNull)
    }

    @Test func apiUsesAllContractRoutesAndFileTransport() async throws {
        let fake = DropTransport()
        fake.responses = [.answer(200, try sampleData("drop-folders")), .answer(201, try dropAnswer()),
                          .answer(200, try dropAnswer(state: .waiting)), .answer(200, try sampleData("drops")), .answer(204, Data())]
        let api = AresusAPI(transport: fake)
        _ = try await api.folders(token: "fictional")
        _ = try await api.create(newDrop(), token: "fictional")
        let file = URL(fileURLWithPath: "/fictional/upload.file")
        _ = try await api.upload(44, fileURL: file, token: "fictional")
        _ = try await api.drops(token: "fictional")
        try await api.cancel(44, token: "fictional")
        #expect(fake.requests.map(\.httpMethod) == ["GET", "POST", "PUT", "GET", "DELETE"])
        #expect(fake.requests.map { $0.url!.path } == ["/api/aresus/drops/folders", "/api/aresus/drops", "/api/aresus/drops/44/file", "/api/aresus/drops", "/api/aresus/drops/44"])
        #expect(fake.files == [file])
        #expect(fake.requests[2].httpBody == nil)
        #expect(fake.requests[2].value(forHTTPHeaderField: "Content-Type") == "application/octet-stream")
        #expect(fake.requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer fictional" })
    }

    @Test func apiUsesCheckResponseAndPreservesSentences() async throws {
        let fake = DropTransport()
        fake.responses = [.answer(413, Data(#"{"error":"This file is too large."}"#.utf8)), .answer(401, Data())]
        let api = AresusAPI(transport: fake)
        do {
            _ = try await api.upload(44, fileURL: URL(fileURLWithPath: "/fictional"), token: "fictional")
            Issue.record("Expected rejection")
        } catch { #expect(error.localizedDescription == "This file is too large.") }
        var unauthorized = false
        await #expect(throws: HTTPError.self) { try await api.cancel(44, token: "fictional", onUnauthorized: { unauthorized = true }) }
        #expect(unauthorized)
    }

    @Test func mergedListHidesLocalDuplicatesAndOrdersBothGroups() throws {
        let server: DropsAnswer = try sample("drops")
        let first = localItem(serverID: nil, created: at("2026-11-01T17:00:00Z"))
        let second = localItem(serverID: 99, created: at("2026-11-01T18:00:00Z"))
        let hidden = localItem(serverID: server.drops[1].id, created: at("2026-11-01T16:00:00Z"))
        let merged = DropsStore.merge(outbox: [second, hidden, first], server: server.drops.reversed())
        #expect(merged == [.phone(first), .phone(second)] + server.drops.map(DropsItem.server))
    }

    @Test func recentsKeepEightUniqueTargetsAndLastPerSource() throws {
        let suite = "DropsTests-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let recents = DropRecentFolders(defaults: defaults)
        for number in 0..<10 { recents.use(Target(root: .documents, folder: "Folder \(number)", newFolder: nil), source: .file) }
        let target = Target(root: .downloads, folder: "", newFolder: "New")
        recents.use(target, source: .camera)
        recents.use(target, source: .photo)
        #expect(recents.targets.count == 8 && Set(recents.targets).count == 8)
        #expect(recents.targets[0] == target && recents.targets[1].folder == "Folder 9")
        #expect(recents.lastBySource[.file]?.folder == "Folder 9")
        #expect(recents.lastBySource[.camera] == target && recents.lastBySource[.photo] == target)
        let restored = DropRecentFolders(defaults: defaults)
        #expect(restored.targets == recents.targets && restored.lastBySource == recents.lastBySource)
        restored.clear()
        #expect(DropRecentFolders(defaults: defaults).targets.isEmpty)
    }
}

@MainActor
final class DropTransport: HTTPTransport {
    enum Response { case answer(Int, Data), failure(Error) }
    var responses: [Response] = []
    var requests: [URLRequest] = []
    var files: [URL] = []
    var gate: RequestGate?
    var gateMethod: String?

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        guard !responses.isEmpty else { throw HTTPError.invalidResponse }
        let result = responses.removeFirst()
        if let gate, gateMethod == nil || gateMethod == request.httpMethod {
            self.gate = nil
            await gate.pause()
        }
        switch result {
        case .answer(let status, let data):
            return (data, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
        case .failure(let error): throw error
        }
    }
    func upload(_ request: URLRequest, fromFile fileURL: URL) async throws -> (Data, HTTPURLResponse) {
        files.append(fileURL)
        return try await send(request)
    }
}

func newDrop() -> NewDrop {
    NewDrop(kind: .file, name: "Sample.pdf", size: 3, sha256: "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", target: nil, receipt: nil)
}

func dropAnswer(state: DropState = .uploading) throws -> Data {
    var drop = try sample("drops", as: DropsAnswer.self).drops[0]
    drop.id = 44                      // the id the request tests expect, whatever the samples hold
    drop.state = state
    return try AresusJSON.encoder().encode(drop)
}

func localItem(serverID: Int?, created: Date = .now) -> DropOutboxItem {
    let id = UUID()
    return DropOutboxItem(id: id, drop: newDrop(), localFile: id.uuidString + ".file", serverID: serverID, created: created)
}
