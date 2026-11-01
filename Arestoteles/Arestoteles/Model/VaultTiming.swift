import Foundation

/// Opt-in measurements of synchronous work on the main actor; async waits are deliberately excluded.
@MainActor
enum VaultTiming {
    struct Sample { let name: String; let milliseconds: Double }
    static var samples: [Sample] = []
    static let enabled = ProcessInfo.processInfo.environment["VAULT_TIMINGS"] == "1"

    static func measure<T>(_ name: String, _ work: () throws -> T) rethrows -> T {
        guard enabled else { return try work() }
        let clock = ContinuousClock()
        let start = clock.now
        defer {
            let elapsed = start.duration(to: clock.now).components
            samples.append(Sample(name: name, milliseconds: Double(elapsed.seconds) * 1000
                                  + Double(elapsed.attoseconds) / 1e15))
        }
        return try work()
    }
}
