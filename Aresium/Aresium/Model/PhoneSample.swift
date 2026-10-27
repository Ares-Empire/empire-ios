#if DEBUG
import Foundation

/// DEBUG `-samplePhone`: phone mode without a login or network, its store (in a temporary folder) filled through the
/// real import from made-up files: the tour's VR Bank CSV for the last nine months (`TourData`: made-up shops and
/// amounts, so the dashboard is full and current) and the engine's own made-up fixtures (`Preview Content/PhoneSample`).
/// For screenshots and UI checks; `-samplePhoneEmpty` is the first screen.
@MainActor
enum PhoneSample {
    /// The categories the sample person ticked, and one of their own (the tour's).
    static let chosen = TourData.chosen
    static let customName = "Climbing"

    /// A store in a temporary folder of its own (never the phone's real one), filled unless `empty`.
    static func backend(empty: Bool) async throws -> (backend: PhoneBackend, storage: PhoneStorage) {
        let root = FileManager.default.temporaryDirectory.appending(path: "aresium-sample-phone-" + UUID().uuidString,
                                                                     directoryHint: .isDirectory)
        let storage = PhoneStorage(root: root)
        let ledger = try await Task.detached { try storage.open() }.value
        let backend = PhoneBackend(ledger: ledger, engine: try AresiumEngine.bundled())
        try await backend.load()
        guard !empty else { return (backend, storage) }
        for id in chosen { try await ledger.choose(id) }
        try await backend.addCustom(named: customName)
        var files = [ImportFile(name: "Umsaetze-Girokonto.csv", data: Data(TourData.vrBankCSV(now: .now).utf8))]
        for name in ["sample-paypal.csv", "sample-camt.xml"] {
            let parts = name.split(separator: ".")
            if let url = Bundle.main.url(forResource: String(parts[0]), withExtension: String(parts[1])) {
                files.append(ImportFile(name: name, data: try Data(contentsOf: url)))
            }
        }
        _ = try await backend.importFiles(files, auth: BackendAuth(token: nil))
        return (backend, storage)
    }

    /// A made-up unknown bank's CSV (the engine's fixture), for the layout confirmation sheet (`-sampleLayout`).
    static func unknownBankFile() -> ImportFile? {
        guard let url = Bundle.main.url(forResource: "sample-unknown-bank", withExtension: "csv"),
              let data = try? Data(contentsOf: url) else { return nil }
        return ImportFile(name: "Fiktivbank-Umsaetze.csv", data: data)
    }
}
#endif
