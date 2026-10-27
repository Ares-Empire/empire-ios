#if DEBUG
import Foundation

/// DEBUG `-samplePhone`: phone mode without a login or network, its store (in a temporary folder) filled through the
/// real import from made-up files: a VR Bank CSV made here for the last nine months (made-up shops and amounts, so the
/// dashboard is full and current) and the engine's own made-up fixtures (`Preview Content/PhoneSample`). For
/// screenshots and UI checks; `-samplePhoneEmpty` is the first run.
@MainActor
enum PhoneSample {
    /// The categories the sample person ticked, and one of their own.
    static let chosen = ["groceries", "drugstore", "eating-out", "coffee-snacks", "rent", "utilities", "internet-phone",
                         "bus-train", "subscriptions", "cash", "salary", "parents-family", "clothes", "other"]
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
        var files = [ImportFile(name: "Umsaetze-Girokonto.csv", data: Data(vrBankCSV(now: .now).utf8))]
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

    /// A VR Bank export (its known layout) with made-up payments for the nine months up to `now`.
    static func vrBankCSV(now: Date, calendar: Calendar = .current) -> String {
        struct Row { let day: Date; let who: String; let kind: String; let text: String; let cents: Int }
        var rows: [Row] = []
        let thisMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
        let monthNames = ["Januar", "Februar", "März", "April", "Mai", "Juni", "Juli", "August", "September", "Oktober",
                          "November", "Dezember"]
        var seed = 7
        func next(_ range: Int) -> Int { seed = (seed * 1103 + 12345) % 65536; return seed % range }
        for back in (0..<9).reversed() {
            let month = calendar.date(byAdding: .month, value: -back, to: thisMonth)!
            let days = calendar.range(of: .day, in: .month, for: month)!.count
            let lastDay = back == 0 ? calendar.component(.day, from: now) : days
            let name = monthNames[calendar.component(.month, from: month) - 1]
            func on(_ day: Int) -> Date? {
                day <= lastDay ? calendar.date(byAdding: .day, value: day - 1, to: month) : nil
            }
            func add(_ day: Int, _ who: String, _ kind: String, _ text: String, _ cents: Int) {
                if let date = on(day) { rows.append(Row(day: date, who: who, kind: kind, text: text, cents: cents)) }
            }
            add(1, "Fiktiv Werke GmbH", "Gehalt/Rente", "Gehalt \(name)", 245_000)
            add(2, "Fiktiv Hausverwaltung", "Dauerauftrag", "Miete \(name)", -78_000)
            add(3, "Erika Mustermann", "Gutschrift", "Taschengeld \(name)", 15_000)
            add(5, "Stadtwerke Fiktivstadt", "Lastschrift", "Abschlag Strom \(name)", -4_500)
            add(6, "Vodafone GmbH", "Lastschrift", "Mobilfunk \(name)", -2_999)
            add(7, "MVG", "Lastschrift", "Deutschlandticket \(name)", -5_800)
            add(8, "Spotify", "Lastschrift", "Spotify Premium", -1_099)
            add(9, "Netflix", "Lastschrift", "Netflix Abo", -1_399)
            for week in 0..<5 {
                add(4 + week * 6, "REWE Markt GmbH", "Kartenzahlung", "REWE SAGT DANKE", -(2_000 + next(4_500)))
                add(6 + week * 6, "LIDL DIENSTLEISTUNG", "Kartenzahlung", "Lidl sagt Danke", -(900 + next(2_500)))
                add(5 + week * 6, "Baeckerei Fiktivmeister", "Kartenzahlung", "Bäckerei", -(250 + next(600)))
            }
            add(12, "dm-drogerie markt", "Kartenzahlung", "dm Fiktivstadt", -(800 + next(2_200)))
            add(15, "Restaurant Fiktiva", "Kartenzahlung", "Restaurant Fiktiva", -(1_800 + next(3_000)))
            add(18, "Geldautomat Fiktivbank", "Auszahlung", "Bargeldauszahlung", -10_000)
            add(21, "Fiktiv Boulderhalle", "Kartenzahlung", "Eintritt", -(1_200 + next(500)))
            add(24, "Fiktiv Laden", "Kartenzahlung", "Einkauf", -(500 + next(4_000)))
            if back % 3 == 1 { add(26, "Zalando SE", "Lastschrift", "Bestellung", -(3_000 + next(6_000))) }
        }
        rows.sort { $0.day < $1.day }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "dd.MM.yyyy"
        func euros(_ cents: Int) -> String {
            let value = abs(cents)
            let whole = String(value / 100)
            var grouped = ""
            for (index, digit) in whole.reversed().enumerated() {
                if index > 0 && index % 3 == 0 { grouped.append(".") }
                grouped.append(digit)
            }
            return String(grouped.reversed()) + "," + String(format: "%02d", value % 100)
        }
        var balance = 120_000
        var lines = ["IBAN Auftragskonto;Buchungstag;Valutadatum;Name Zahlungsbeteiligter;Buchungstext;Verwendungszweck;Betrag;Währung;Soll/Haben;Saldo nach Buchung"]
        for row in rows {
            balance += row.cents
            let day = formatter.string(from: row.day)
            lines.append(";\(day);\(day);\(row.who);\(row.kind);\(row.text);\(euros(row.cents));EUR;\(row.cents < 0 ? "S" : "H");\(euros(balance))")
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
#endif
