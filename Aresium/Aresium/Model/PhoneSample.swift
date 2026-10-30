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
    static func backend(empty: Bool, storage suppliedStorage: PhoneStorage? = nil) async throws -> (backend: PhoneBackend, storage: PhoneStorage) {
        let root = FileManager.default.temporaryDirectory.appending(path: "aresium-sample-phone-" + UUID().uuidString,
                                                                     directoryHint: .isDirectory)
        let storage = suppliedStorage ?? PhoneStorage(root: root)
        let ledger = try await Task.detached { try storage.open() }.value
        let backend = PhoneBackend(ledger: ledger, engine: try await AresiumEngine.bundledForPhone(),
                                   defaults: UserDefaults(suiteName: "aresium.phone.sample")!)
        try await backend.load()
        guard !empty else { return (backend, storage) }
        for id in chosen { try await ledger.choose(id) }
        try await backend.addCustom(named: customName)
        // `-sampleOwn <name,name,…>`: more own categories after Climbing, each with the look its name gives it.
        for name in (LaunchArguments.value("-sampleOwn") ?? "").split(separator: ",") {
            try await backend.addCustom(named: String(name))
        }
        var files = [ImportFile(name: "Umsaetze-Girokonto.csv", data: Data(TourData.vrBankCSV(now: .now).utf8)),
                     ImportFile(name: "Umsaetze-Girokonto-Februar.csv", data: Data(paypalBankLine.utf8))]
        for name in ["sample-paypal.csv", "sample-camt.xml"] {
            let parts = name.split(separator: ".")
            if let url = Bundle.main.url(forResource: String(parts[0]), withExtension: String(parts[1])) {
                files.append(ImportFile(name: name, data: try Data(contentsOf: url)))
            }
        }
        _ = try await backend.importFiles(files, auth: BackendAuth(token: nil))
        return (backend, storage)
    }

    /// The bank's side of the sample PayPal export's purchase at Märchenladen (made up, in the VR Bank layout): with the
    /// PayPal export imported too it is an own transfer, so the sample has one to open
    /// (`-sampleCategory "Own transfers" -sampleMonth 2026-02 -samplePhoneTransaction PayPal`).
    private static let paypalBankLine = """
        IBAN Auftragskonto;Buchungstag;Valutadatum;Name Zahlungsbeteiligter;Buchungstext;Verwendungszweck;Betrag;Währung;Soll/Haben;Saldo nach Buchung
        ;03.02.2026;03.02.2026;PayPal Europe S.a.r.l. et Cie S.C.A;Lastschrift;Ihr Einkauf bei Märchenladen;18,90;EUR;S;

        """

    /// `-sampleReceipts`: made-up receipts kept through the real flow (`saveReceipt`): a card receipt waiting for its bank
    /// payment (Groceries), a cash one after this month's withdrawal (Eating out; Cash shows its covered row), one joined
    /// to the month's first REWE payment, and a card receipt in pounds (only in Settings → Receipts until joined).
    static func addReceipts(_ phone: PhoneBackend, now: Date = .now) async throws {
        let calendar = ReceiptDay.calendar
        let today = ReceiptDay.day(now)
        func day(_ offset: Int, from start: String = today) -> String {
            let date = calendar.date(byAdding: .day, value: offset, to: ReceiptDay.date(start) ?? now) ?? now
            return min(ReceiptDay.day(date), today)
        }
        let payments = try await phone.ledger.payments()
        let month = String(today.prefix(7))
        func draft(_ shop: String, _ date: String, _ total: Double, _ method: ReceiptMethod, _ category: String?,
                   currency: String = "EUR", rows: [String]) -> ReceiptDraft {
            ReceiptDraft(date: date, shop: shop, total: total, currency: currency, method: method, category: category,
                         categorySource: category == nil ? .none : .starter, rows: rows, from: "text")
        }
        _ = try await phone.saveReceipt(draft(ReceiptSample.shop, day(-1), 27.65, .card, "groceries",
                                              rows: ReceiptSample.textRows))
        if let withdrawal = payments.last(where: { $0.counterparty?.contains("Geldautomat") == true }) {
            _ = try await phone.saveReceipt(draft("Cafe Fiktiva", day(2, from: withdrawal.bookingDate), 8.40, .cash,
                                                  "eating-out", rows: ["CAFE FIKTIVA", "Cappuccino 3,40", "Croissant 2,20",
                                                                       "Apfelschorle 2,80", "8,40"]))
        }
        if let rewe = payments.first(where: { $0.bookingDate.hasPrefix(month) && $0.counterparty == "REWE Markt GmbH" }) {
            let total = -rewe.amountValue
            let amount = ReceiptAmount.field(total, language: .german)
            _ = try await phone.saveReceipt(draft("REWE", rewe.bookingDate, total, .card, "groceries",
                                                  rows: ["REWE Markt GmbH", "Fiktivstraße 1", "SUMME EUR \(amount)",
                                                         "Geg. Mastercard EUR \(amount)"]))
        }
        _ = try await phone.saveReceipt(draft("Fictional Bookshop", day(-3), 12.40, .card, nil, currency: "GBP",
                                              rows: ["FICTIONAL BOOKSHOP", "1 Example Lane, London", "TOTAL £12.40",
                                                     "CARD PAYMENT"]))
    }

    /// `-sampleCash`: made-up cash entered by hand (brief 33), around the sample's withdrawal on the 18th of each month:
    /// this month a gift from grandma (€50, Parents & family), a flea market paid from it (€12, Clothes), an ice cream
    /// after the withdrawal (€6.50, Eating out, automatic); last month a bike sold (€80, not sorted) and a cinema ticket
    /// paid from it (€11, automatic).
    static func addCash(_ phone: PhoneBackend, now: Date = .now) async throws {
        let calendar = ReceiptDay.calendar
        let today = ReceiptDay.day(now)
        let thisMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        func day(_ number: Int, monthsBack: Int = 0) -> String {
            let month = calendar.date(byAdding: .month, value: -monthsBack, to: thisMonth) ?? thisMonth
            let date = calendar.date(byAdding: .day, value: number - 1, to: month) ?? month
            return min(ReceiptDay.day(date), today)
        }
        let gift = try await phone.addCashEntry(CashEntryDraft(direction: .in, amount: 50, date: day(3),
                                                               what: "Geburtstag Oma", category: "parents-family"))
        try await phone.addCashEntry(CashEntryDraft(direction: .out, amount: 12, date: day(6), what: "Flohmarkt",
                                                    category: "clothes", paidFrom: gift.id))
        try await phone.addCashEntry(CashEntryDraft(direction: .out, amount: 6.50, date: day(20), what: "Eis mit Freunden",
                                                    category: "eating-out"))
        try await phone.addCashEntry(CashEntryDraft(direction: .in, amount: 80, date: day(10, monthsBack: 1),
                                                    what: "Fahrrad verkauft"))
        try await phone.addCashEntry(CashEntryDraft(direction: .out, amount: 11, date: day(12, monthsBack: 1),
                                                    what: "Kino", category: "other"))
    }

    /// `-sampleReceiptQuestion`: bank payments the made-up receipt (27,65 on 26 Oct 2026) may be: two of its exact amount
    /// and one €20 more at the same shop, so saving it asks "Is this the same payment?".
    static func addQuestionPayments(_ phone: PhoneBackend) async throws {
        let csv = """
            IBAN Auftragskonto;Buchungstag;Valutadatum;Name Zahlungsbeteiligter;Buchungstext;Verwendungszweck;Betrag;Währung;Soll/Haben;Saldo nach Buchung
            ;26.10.2026;26.10.2026;MUSTERMARKT LINDE;Kartenzahlung;Girocard 4711;27,65;EUR;S;
            ;27.10.2026;27.10.2026;MUSTERMARKT LINDE;Kartenzahlung;Girocard 4712;27,65;EUR;S;
            ;27.10.2026;27.10.2026;MUSTERMARKT LINDE;Kartenzahlung;Girocard 4713;47,65;EUR;S;

            """
        _ = try await phone.importFiles([ImportFile(name: "Umsaetze-Fragen.csv", data: Data(csv.utf8))],
                                        auth: BackendAuth(token: nil))
    }

    /// `-sampleImportQuestion`: two made-up card receipts wait for their bank payments, then a made-up bank file brings
    /// two payments of each one's amount, so after that import both are asked ("Is this the same payment?"), one after
    /// the other: Later on the first shows the second.
    static func addImportQuestions(_ phone: PhoneBackend, now: Date = .now) async throws {
        let calendar = ReceiptDay.calendar
        func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: now) ?? now }
        func bank(_ date: Date) -> String {
            let parts = ReceiptDay.day(date).split(separator: "-")
            return "\(parts[2]).\(parts[1]).\(parts[0])"
        }
        let receipts: [(shop: String, day: Int, total: Double, category: String)] = [
            ("Mustermarkt Linde", -3, 31.17, "groceries"), ("Pizzeria Fiktiva", -2, 23.43, "eating-out"),
        ]
        var rows = ["IBAN Auftragskonto;Buchungstag;Valutadatum;Name Zahlungsbeteiligter;Buchungstext;Verwendungszweck;Betrag;Währung;Soll/Haben;Saldo nach Buchung"]
        for (index, receipt) in receipts.enumerated() {
            let amount = ReceiptAmount.field(receipt.total, language: .german)
            _ = try await phone.saveReceipt(ReceiptDraft(
                date: ReceiptDay.day(day(receipt.day)), shop: receipt.shop, total: receipt.total, currency: "EUR",
                method: .card, category: receipt.category, categorySource: .starter,
                rows: [receipt.shop.uppercased(), "SUMME EUR \(amount)", "Geg. girocard EUR \(amount)"], from: "text"))
            for (offset, card) in [(receipt.day, 4720 + 2 * index), (receipt.day + 1, 4721 + 2 * index)] {
                let date = bank(day(min(offset, 0)))
                rows.append(";\(date);\(date);\(receipt.shop.uppercased());Kartenzahlung;Girocard \(card);\(amount);EUR;S;")
            }
        }
        let csv = rows.joined(separator: "\n") + "\n"
        _ = try await phone.importFiles([ImportFile(name: "Umsaetze-Belege.csv", data: Data(csv.utf8))],
                                        auth: BackendAuth(token: nil))
    }

    /// A made-up unknown bank's CSV (the engine's fixture), for the layout confirmation sheet (`-sampleLayout`).
    static func unknownBankFile() -> ImportFile? {
        guard let url = Bundle.main.url(forResource: "sample-unknown-bank", withExtension: "csv"),
              let data = try? Data(contentsOf: url) else { return nil }
        return ImportFile(name: "Fiktivbank-Umsaetze.csv", data: data)
    }
}
#endif
