import Foundation
import JavaScriptCore
import Testing
@testable import Aresium

/// Test resources only: generated with `npm run engine` in the aresium worktree.
/// Copy dist's bundle/sources/CSV and src/engine/fixtures's inputs/answers into Engine/.
/// JIT comparison: rerun with TEST_RUNNER_JSC_useJIT=false and
/// TEST_RUNNER_JSC_dumpOptions=1; JSC's option dump verifies the effective setting.
@Suite(.serialized)
@MainActor
struct EngineTests {
    private static let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()

    @Test func dashboardMatchesServerExactlyAndDecodes() throws {
        let engine = try EngineHarness(bundle: resourceText("aresium-engine.js"))
        let result = try engine.dashboard(resourceText("dashboard.sample-source.json"))
        let expected = try Data(contentsOf: Self.directory.appendingPathComponent("server-dashboard.sample.json"))
        try expectSameJSON(Data(result.utf8), expected)
        let dashboard = try Dashboard.decode(Data(result.utf8))
        #expect(dashboard.version == 2)
        #expect(dashboard.months.count == 10)
        #expect(dashboard.transactions.count > 0)
    }

    @Test(arguments: [("vrbank.csv", "parseVrBankCsv"), ("camt.xml", "parseCamt"), ("paypal.csv", "parsePaypalCsv")])
    func parsersMatchNodeExactly(file: String, parser: String) throws {
        let engine = try EngineHarness(bundle: resourceText("aresium-engine.js"))
        let result = try engine.parse(parser, text: resourceText(file))
        try expectSameJSON(Data(result.utf8), resourceData(file + ".expected.json"))
    }

    @Test func javascriptExceptionsBecomeSwiftErrors() throws {
        let engine = try EngineHarness(bundle: resourceText("aresium-engine.js"))
        #expect(throws: EngineFailure.self) { try engine.evaluate("throw new Error('Fictional exception')") }
        #expect(throws: EngineFailure.self) { try engine.parse("parseCamt", text: "<Fictional/>") }
    }

    @Test func timings() throws {
        let bundle = try resourceText("aresium-engine.js")
        let requestedJIT = ProcessInfo.processInfo.environment["JSC_useJIT"] ?? "default"
        print("ENGINE environment JSC_useJIT=\(requestedJIT), JSC_dumpOptions=\(ProcessInfo.processInfo.environment["JSC_dumpOptions"] ?? "unset")")
        // Bundle load includes creating a fresh context and evaluating the bundle.
        // Operation timings include JSON input parsing, the engine call, JSON output
        // serialisation and transfer back to Swift. File reads and Swift decoding are excluded.
        try report("bundle-load") { _ = try EngineHarness(bundle: bundle) }
        let engine = try EngineHarness(bundle: bundle)
        let sample = try resourceText("dashboard.sample-source.json")
        let timing = try resourceText("timing-source-5000.json")
        var source = try #require(try JSONSerialization.jsonObject(with: Data(timing.utf8)) as? [String: Any])
        let transactions = try #require(source["transactions"] as? [[String: Any]])
        #expect(transactions.count == 5000)
        #expect((source["months"] as? [Any])?.count == 24)
        source["transactions"] = Array(transactions.prefix(1246))
        let subset = String(decoding: try JSONSerialization.data(withJSONObject: source, options: [.sortedKeys]), as: UTF8.self)
        let csv = try resourceText("timing-vr-5000.csv")
        // Each warmed operation has one untimed call, then the median of five calls.
        for (name, json) in [("dashboard-sample", sample), ("dashboard-1246", subset), ("dashboard-5000", timing)] {
            _ = try engine.dashboard(json)
            try report(name) { _ = try engine.dashboard(json) }
        }
        let parsed = try engine.parse("parseVrBankCsv", text: csv)
        let parsedFile = try #require(try JSONSerialization.jsonObject(with: Data(parsed.utf8)) as? [String: Any])
        #expect((parsedFile["transactions"] as? [Any])?.count == 5000)
        try report("parse-vr-5000") { _ = try engine.parse("parseVrBankCsv", text: csv) }
    }

    private func report(_ name: String, operation: () throws -> Void) throws {
        var milliseconds: [Double] = []
        for _ in 0..<5 {
            let start = ProcessInfo.processInfo.systemUptime
            try operation()
            milliseconds.append((ProcessInfo.processInfo.systemUptime - start) * 1000)
        }
        let median = milliseconds.sorted()[2]
        print("ENGINE timing \(name): median \(String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), median)) ms (5 runs)")
        #expect(median.isFinite && median > 0)
    }

    private func resourceData(_ name: String) throws -> Data {
        let bundle = Bundle(for: EngineResourceAnchor.self)
        let url = bundle.url(forResource: name, withExtension: nil, subdirectory: "Engine")
            ?? bundle.url(forResource: name, withExtension: nil)
        return try Data(contentsOf: #require(url, "Missing engine test resource: \(name)"))
    }

    private func resourceText(_ name: String) throws -> String {
        String(decoding: try resourceData(name), as: UTF8.self)
    }

    private func expectSameJSON(_ actual: Data, _ expected: Data) throws {
        // Structural comparison ignores object key order; Double equality is exact,
        // with no rounding or tolerance. Booleans remain distinct from numbers.
        let decoder = JSONDecoder()
        #expect(try decoder.decode(EngineJSON.self, from: actual) == decoder.decode(EngineJSON.self, from: expected))
    }
}

private final class EngineResourceAnchor: NSObject {}

private enum EngineFailure: Error {
    case exception(String)
    case missingValue(String)
}

@MainActor
private final class EngineHarness {
    private let context: JSContext
    private var exception: String?

    init(bundle: String) throws {
        context = try #require(JSContext())
        context.exceptionHandler = { [weak self] _, value in
            self?.exception = value?.toString() ?? "Unknown JavaScript exception"
        }
        try evaluate(bundle)
        try evaluate("""
        globalThis.engineDashboardJSON = function(json) {
            return JSON.stringify(AresiumEngine.buildDashboard(JSON.parse(json)));
        };
        globalThis.engineParseJSON = function(parser, text) {
            return JSON.stringify(AresiumEngine[parser](text));
        };
        """)
    }

    func evaluate(_ script: String) throws {
        exception = nil
        context.evaluateScript(script)
        if let exception { throw EngineFailure.exception(exception) }
    }

    func dashboard(_ source: String) throws -> String {
        try call("engineDashboardJSON", arguments: [source])
    }

    func parse(_ parser: String, text: String) throws -> String {
        try call("engineParseJSON", arguments: [parser, text])
    }

    private func call(_ function: String, arguments: [String]) throws -> String {
        exception = nil
        let value = context.objectForKeyedSubscript(function)?.call(withArguments: arguments)
        if let exception { throw EngineFailure.exception(exception) }
        guard let value, value.isString, let text = value.toString() else { throw EngineFailure.missingValue(function) }
        return text
    }
}

private indirect enum EngineJSON: Decodable, Equatable {
    case null, bool(Bool), number(Double), string(String), array([EngineJSON]), object([String: EngineJSON])

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() { self = .null }
        else if let bool = try? value.decode(Bool.self) { self = .bool(bool) }
        else if let number = try? value.decode(Double.self) { self = .number(number) }
        else if let string = try? value.decode(String.self) { self = .string(string) }
        else if let array = try? value.decode([EngineJSON].self) { self = .array(array) }
        else { self = .object(try value.decode([String: EngineJSON].self)) }
    }
}
