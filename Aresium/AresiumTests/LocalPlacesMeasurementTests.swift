import Foundation
import Darwin
import JavaScriptCore
import Testing
import zlib
@testable import Aresium

/// Opt-in app-host measurement, deliberately separate from ordinary tests. All inputs are fictional.
/// Supply TEST_RUNNER_LOCAL_PLACES_MEASURE=1, TEST_RUNNER_LOCAL_PLACES_SCRIPT and TEST_RUNNER_LOCAL_PLACES_GZIP.
@Suite(.serialized, .enabled(if: ProcessInfo.processInfo.environment["LOCAL_PLACES_MEASURE"] == "1"))
struct LocalPlacesMeasurementTests {
    @Test func memoryAndSorting() async throws {
        try await measure()
    }

    @concurrent private func measure() async throws {
        let environment = ProcessInfo.processInfo.environment
        let scriptURL = URL(fileURLWithPath: try #require(environment["LOCAL_PLACES_SCRIPT"]))
        let gzipURL = URL(fileURLWithPath: try #require(environment["LOCAL_PLACES_GZIP"]))
        let engine = try AresiumEngine(script: String(contentsOf: scriptURL, encoding: .utf8))
        // Measurement-only access to the actual host's VM; no production API added for instrumentation.
        let context = try #require(Mirror(reflecting: engine).children.first { $0.label == "context" }?.value as? JSContext)
        context.evaluateScript("""
        globalThis.__measureSort = (json, local) => {
          const input = JSON.parse(json);
          return JSON.stringify(AresiumEngine.sortPayments(input.payments, {
            categories: input.categories, learned: {}, localPlaces: local ? globalThis.__measurePlaces : undefined
          }));
        };
        """)
        func footprint() throws -> Double {
            var info = task_vm_info_data_t()
            var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
            let status = withUnsafeMutablePointer(to: &info) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                    task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
                }
            }
            #expect(status == KERN_SUCCESS)
            return Double(info.phys_footprint) / 1_000_000
        }
        func collect() { for _ in 0..<3 { JSGarbageCollect(context.jsGlobalContextRef) } }
        func sort(_ json: String, local: Bool) throws -> Double {
            let start = CFAbsoluteTimeGetCurrent()
            try autoreleasepool {
                let result = context.objectForKeyedSubscript("__measureSort")?.call(withArguments: [json, local])?.toString()
                #expect(context.exception == nil)
                #expect(result != nil)
                // Match the host bridge: consume the JSON answer on the Swift side too.
                _ = try JSONDecoder().decode([SortResult].self, from: Data(try #require(result).utf8))
            }
            return (CFAbsoluteTimeGetCurrent() - start) * 1000
        }
        let categories = try await engine.catalog().defaults.map { ["id": $0.id] }
        let inputs = try [1250, 5000].map { count in
            let payments: [[String: Any]] = (0..<count).map { i in
                ["counterparty": ["Quarzfunken", "REWE", "Fiktiverladen", "Zur Quarzmühle"][i % 4],
                 "description": "Fictional purchase", "source": "bank", "account": "fictional",
                 "amount": -Double(100 + i % 999) / 10, "currency": "EUR", "date": "2026-10-01"]
            }
            return String(decoding: try JSONSerialization.data(withJSONObject: ["payments": payments, "categories": categories]), as: UTF8.self)
        }
        // Warm engine/bridge and fault input pages before the memory baseline.
        for _ in 0..<3 { for input in inputs { _ = try sort(input, local: false) } }
        collect()
        try await Task.sleep(for: .seconds(1))
        let initial = try footprint()
        print("LOCAL PLACES initial-MB=\(initial) script=\(scriptURL.lastPathComponent) runtime=\(ProcessInfo.processInfo.operatingSystemVersionString) model=\(environment["SIMULATOR_MODEL_IDENTIFIER"] ?? "unknown")")
        if environment["LOCAL_PLACES_SKIP_LIST"] == "1" {
            // Same number of sort calls as a candidate run, so allocator/JIT growth has a no-list control.
            for run in 1...10 {
                for (index, count) in [1250, 5000].enumerated() {
                    print("LOCAL PLACES baseline run=\(run) count=\(count) sort-ms=\(try sort(inputs[index], local: false))")
                }
            }
            collect()
            for second in 1...10 {
                try await Task.sleep(for: .seconds(1))
                collect()
                if [1, 5, 10].contains(second) {
                    let released = try footprint()
                    print("LOCAL PLACES baseline release-after-seconds=\(second) released-MB=\(released) retained-from-initial-MB=\(released-initial)")
                }
            }
            return
        }
        for run in 1...(Int(environment["LOCAL_PLACES_ROUNDS"] ?? "1") ?? 1) {
            collect()
            try await Task.sleep(for: .milliseconds(250))
            let before = try footprint()
            let start = CFAbsoluteTimeGetCurrent()
            var readMS = 0.0, inflateMS = 0.0, parseMS = 0.0
            try autoreleasepool {
                let compressed = try Data(contentsOf: gzipURL)
                let readEnd = CFAbsoluteTimeGetCurrent()
                let text = try Self.gunzip(compressed)
                let inflateEnd = CFAbsoluteTimeGetCurrent()
                let parser = context.evaluateScript("(json) => { globalThis.__measurePlaces = JSON.parse(json); }")
                parser?.call(withArguments: [text])
                #expect(context.exception == nil)
                let parseEnd = CFAbsoluteTimeGetCurrent()
                readMS = (readEnd - start) * 1000
                inflateMS = (inflateEnd - readEnd) * 1000
                parseMS = (parseEnd - inflateEnd) * 1000
            }
            let loadMS = (CFAbsoluteTimeGetCurrent() - start) * 1000
            let peak = try footprint()
            #expect(context.evaluateScript("__measurePlaces.version === 1 && __measurePlaces.rows.length > 200000")?.toBool() == true)
            collect()
            try await Task.sleep(for: .milliseconds(250))
            let loaded = try footprint()
            print("LOCAL PLACES run=\(run) before-MB=\(before) peak-MB=\(peak) loaded-MB=\(loaded) added-MB=\(loaded-before) read-ms=\(readMS) inflate-ms=\(inflateMS) parse-ms=\(parseMS) load-ms=\(loadMS)")
            for (index, count) in [1250, 5000].enumerated() {
                for sample in 1...5 {
                    for local in sample % 2 == 0 ? [true, false] : [false, true] {
                        let ms = try sort(inputs[index], local: local)
                        print("LOCAL PLACES run=\(run) sample=\(sample) count=\(count) local=\(local) sort-ms=\(ms)")
                    }
                }
            }
            autoreleasepool { context.evaluateScript("globalThis.__measurePlaces = undefined; void 0;") }
            #expect(context.evaluateScript("typeof globalThis.__measurePlaces")?.toString() == "undefined")
            collect()
            for second in 1...10 {
                try await Task.sleep(for: .seconds(1))
                collect()
                if [1, 5, 10].contains(second) {
                    let released = try footprint()
                    print("LOCAL PLACES run=\(run) release-after-seconds=\(second) released-MB=\(released) retained-from-initial-MB=\(released-initial)")
                }
            }
        }
    }

    private nonisolated static func gunzip(_ data: Data) throws -> String {
        var stream = z_stream()
        guard inflateInit2_(&stream, 31, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else {
            throw CocoaError(.fileReadCorruptFile)
        }
        defer { inflateEnd(&stream) }
        var decoded = Data()
        try data.withUnsafeBytes { input in
            stream.next_in = UnsafeMutablePointer(mutating: input.bindMemory(to: Bytef.self).baseAddress!)
            stream.avail_in = uInt(input.count)
            var status: Int32 = Z_OK
            repeat {
                var buffer = [UInt8](repeating: 0, count: 65_536)
                let produced = buffer.withUnsafeMutableBufferPointer { output in
                    stream.next_out = output.baseAddress!
                    stream.avail_out = uInt(output.count)
                    status = inflate(&stream, Z_NO_FLUSH)
                    return output.count - Int(stream.avail_out)
                }
                guard status == Z_OK || status == Z_STREAM_END else { throw CocoaError(.fileReadCorruptFile) }
                decoded.append(contentsOf: buffer.prefix(produced))
            } while status != Z_STREAM_END
        }
        return String(decoding: decoded, as: UTF8.self)
    }
}
