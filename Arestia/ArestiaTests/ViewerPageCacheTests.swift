import Foundation
import os
import Testing
@testable import Arestia

struct ViewerPageCacheTests {
    private let folder = URL.temporaryDirectory.appending(path: "viewer-\(UUID())")
    private let pairing = UUID()
    private let html = Data("<h1>Test flat</h1>".utf8)
    private var cache: ViewerPageCache { ViewerPageCache(folder: folder) }

    private func file(_ ext: String) -> URL {
        folder.appending(path: pairing.uuidString).appendingPathExtension(ext)
    }

    @Test func savesThePageAndMetadataForThePairing() async throws {
        let cache = cache
        defer { cache.removeAll() }
        let etag = #""test-page""#
        await cache.save(html, etag: etag, pairing: pairing, pin: Flat.pin)

        let kept = try #require(await cache.page(pairing: pairing, pin: Flat.pin))
        #expect(kept.html == html)
        #expect(kept.etag == etag)
        #expect(kept.sha256 == "d9f31ae56c7da24f9ed7a2aa5f668669c83af02a21e1589898e1808d863aa145")
        let metadata = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file("json"))) as? [String: Any])
        #expect(metadata["pairing"] as? String == pairing.uuidString)
        #expect(metadata["pin"] as? String == Flat.pin.hex)
        #expect(metadata["byteCount"] as? Int == html.count)
        #expect(metadata["savedAt"] is Double)
    }

    @Test func anotherPairingCannotReadThePageAndRemovesIt() async throws {
        let cache = cache
        defer { cache.removeAll() }
        await cache.save(html, etag: nil, pairing: pairing, pin: Flat.pin)
        #expect(await cache.page(pairing: UUID(), pin: Flat.pin) == nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
    }

    @Test func aDifferentPinCannotReadThePage() async throws {
        let cache = cache
        defer { cache.removeAll() }
        let otherPin = try #require(FlatdPin(String(repeating: "f", count: 64)))
        await cache.save(html, etag: nil, pairing: pairing, pin: Flat.pin)
        #expect(Flat.pin != otherPin)
        #expect(await cache.page(pairing: pairing, pin: otherPin) == nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
    }

    @Test func aCorruptedPageIsRemovedEvenAtTheSameSize() async throws {
        let cache = cache
        defer { cache.removeAll() }
        await cache.save(html, etag: nil, pairing: pairing, pin: Flat.pin)
        try Data(repeating: 0, count: html.count).write(to: file("html"))
        #expect(await cache.page(pairing: pairing, pin: Flat.pin) == nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
    }

    @Test func savingPurgesOldFilesAndCanStoreANullETag() async throws {
        let cache = cache
        defer { cache.removeAll() }
        await cache.save(html, etag: #""old""#, pairing: UUID(), pin: Flat.pin)
        try Data().write(to: folder.appending(path: "stray"))
        await cache.save(html, etag: nil, pairing: pairing, pin: Flat.pin)
        #expect(Set(try FileManager.default.contentsOfDirectory(atPath: folder.path))
                == [file("html").lastPathComponent, file("json").lastPathComponent])
        let metadata = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file("json"))) as? [String: Any])
        #expect(metadata["etag"] is NSNull)
        #expect(await cache.page(pairing: pairing, pin: Flat.pin)?.html == html)
    }

    @Test func removeAllDeletesTheFolderBeforeTheNextRead() async {
        let cache = cache
        await cache.save(html, etag: nil, pairing: pairing, pin: Flat.pin)
        cache.removeAll()
        #expect(await cache.page(pairing: pairing, pin: Flat.pin) == nil)
        #expect(!FileManager.default.fileExists(atPath: folder.path))
    }

    @Test func anOversizedPageIsNotKept() async {
        let cache = cache
        defer { cache.removeAll() }
        await cache.save(html, etag: nil, pairing: pairing, pin: Flat.pin)
        let oversized = Data(repeating: 65, count: ViewerPageCache.maxBytes + 1)
        await cache.save(oversized, etag: nil, pairing: pairing, pin: Flat.pin)
        #expect(await cache.page(pairing: pairing, pin: Flat.pin) == nil)
    }

    @Test func theFolderIsExcludedFromBackupsAndBothFilesAreProtected() async throws {
        let writes = OSAllocatedUnfairLock(initialState: [String: UInt]())
        let cache = ViewerPageCache(folder: folder) { data, url, options in
            writes.withLock { $0[url.pathExtension] = options.rawValue }
            try data.write(to: url, options: options)
        }
        defer { cache.removeAll() }
        await cache.save(html, etag: nil, pairing: pairing, pin: Flat.pin)
        #expect(try folder.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
        let options: Data.WritingOptions = [.atomic, .completeFileProtectionUntilFirstUserAuthentication]
        #expect(writes.withLock { $0 } == ["html": options.rawValue, "json": options.rawValue])
        for ext in ["html", "json"] {
            let attributes = try FileManager.default.attributesOfItem(atPath: file(ext).path)
            // The simulator can omit this attribute. The write above still checks what Foundation was given.
            if let attribute = attributes[.protectionKey] {
                let raw = (attribute as? FileProtectionType)?.rawValue ?? attribute as? String
                #expect(raw == FileProtectionType.completeUntilFirstUserAuthentication.rawValue)
            }
        }
    }
}
