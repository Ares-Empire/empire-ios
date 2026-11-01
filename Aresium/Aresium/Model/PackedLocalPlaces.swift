import Foundation
import zlib

/// One aligned, immutable allocation. JSC retains this owner until its no-copy ArrayBuffer is collected.
nonisolated final class PackedLocalPlaces: @unchecked Sendable {
    let bytes: UnsafeMutableRawPointer
    let count: Int

    private init(count: Int) {
        self.count = count
        bytes = .allocate(byteCount: count, alignment: 16)
    }

    deinit { bytes.deallocate() }

    private static let bundledCache = PackedLocalPlacesCache()

    /// Every phone context (including the tour) borrows the same immutable native bytes. Each JSC ArrayBuffer
    /// retains its own reference to this owner; collecting one context cannot invalidate another context's views.
    static func bundled(in bundle: Bundle = .main) async throws -> PackedLocalPlaces {
        guard let url = bundle.url(forResource: "de.places.bin", withExtension: "gz") else {
            throw EngineError.missingBundle
        }
        return try await bundledCache.read(url)
    }

    /// Read and inflate on the caller's worker, directly into the final allocation. The gzip trailer gives the
    /// uncompressed size; zlib verifies the checksum and we require exactly one complete gzip member.
    static func read(_ url: URL) throws -> PackedLocalPlaces {
        try inflate(Data(contentsOf: url))
    }

    static func inflate(_ compressed: Data) throws -> PackedLocalPlaces {
        guard compressed.count >= 18, compressed.count <= Int(uInt.max) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let size = compressed.suffix(4).enumerated().reduce(0) { $0 | (Int($1.element) << ($1.offset * 8)) }
        guard size >= 128, size <= 64_000_000 else { throw CocoaError(.fileReadCorruptFile) }
        let allocation = PackedLocalPlaces(count: size)
        var stream = z_stream()
        guard inflateInit2_(&stream, 31, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            throw CocoaError(.fileReadCorruptFile)
        }
        defer { inflateEnd(&stream) }
        try compressed.withUnsafeBytes { input in
            stream.next_in = UnsafeMutablePointer(mutating: input.bindMemory(to: Bytef.self).baseAddress!)
            stream.avail_in = uInt(input.count)
            stream.next_out = allocation.bytes.assumingMemoryBound(to: Bytef.self)
            stream.avail_out = uInt(size)
            guard zlib.inflate(&stream, Z_FINISH) == Z_STREAM_END,
                  stream.total_out == size, stream.avail_in == 0 else { throw CocoaError(.fileReadCorruptFile) }
        }
        return allocation
    }
}

/// Serial first load prevents simultaneous engines from inflating duplicate allocations. Weak entries let the
/// native storage go once all JSC contexts and loading callers release it, without a clearing policy or timer.
actor PackedLocalPlacesCache {
    private final class Entry {
        weak var places: PackedLocalPlaces?
        init(_ places: PackedLocalPlaces) { self.places = places }
    }
    private var entries: [URL: Entry] = [:]

    func read(_ url: URL) throws -> PackedLocalPlaces {
        if let places = entries[url]?.places { return places }
        let places = try PickerTiming.measure("localPlaces.load") { try PackedLocalPlaces.read(url) }
        entries[url] = Entry(places)
        return places
    }
}
