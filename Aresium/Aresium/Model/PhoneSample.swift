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
        // `-sampleChooseAll` (brief 70): every default category ticked, so the other side's list is as long as it gets.
        if LaunchArguments.current.contains("-sampleChooseAll"), let catalog = backend.catalog {
            for category in catalog.defaults where !chosen.contains(category.id) { try await ledger.choose(category.id) }
        }
        // Seed the same requested ticks before import too, so screenshot fixtures can change their offers or payments.
        for id in (LaunchArguments.value("-sampleTick") ?? "").split(separator: ",").map(String.init) {
            try await ledger.choose(id)
        }
        try await backend.addCustom(named: customName, side: .spend)
        if let size = LaunchArguments.value("-sampleSize").flatMap(Int.init), size > 0 {
            _ = try await backend.importFiles([sizedFile(size: size)], auth: BackendAuth(token: nil))
            backend.setOwnNames(true)
            return (backend, storage)
        }
        // `-sampleOwn <name,name,…>`: more own categories after Climbing, each with the look its name gives it.
        for name in (LaunchArguments.value("-sampleOwn") ?? "").split(separator: ",") {
            try await backend.addCustom(named: String(name), side: .spend)
        }
        // Category sides (brief 70): `-sampleOwnIncome <name,name,…>` own categories for money in, `-sampleOtherSide
        // <id,id,…>` categories offered for the other direction too (ids, or one's own by name).
        for name in (LaunchArguments.value("-sampleOwnIncome") ?? "").split(separator: ",") {
            try await backend.addCustom(named: String(name), side: .income)
        }
        for key in (LaunchArguments.value("-sampleOtherSide") ?? "").split(separator: ",").map(String.init) {
            let list = try await backend.categories()
            try await backend.setOtherSide(true, for: list.id(named: key) ?? key)
        }
        // Reproduce a spending-only category from an existing store (brief 80).
        for id in (LaunchArguments.value("-sampleNoOtherSide") ?? "").split(separator: ",").map(String.init) {
            try await backend.setOtherSide(false, for: id)
        }
        if let key = LaunchArguments.value("-sampleRenameCategory"), let name = LaunchArguments.value("-categoryName") {
            let id = try await backend.categories().id(named: key) ?? key
            try await backend.rename(id, to: name)
        }
        var files = [ImportFile(name: "Umsaetze-Girokonto.csv", data: Data(TourData.vrBankCSV(now: .now).utf8)),
                     ImportFile(name: "Umsaetze-Girokonto-Februar.csv", data: Data(paypalBankLine.utf8))]
        if LaunchArguments.current.contains("-sampleLongName") {
            files.append(ImportFile(name: "Umsaetze-Lange-Namen.csv", data: Data(longNameLines(now: .now).utf8)))
        }
        if LaunchArguments.current.contains("-sampleDay31") {
            files.append(ImportFile(name: "Umsaetze-Monatsende.csv", data: Data(day31Line(now: .now).utf8)))
        }
        if LaunchArguments.current.contains("-sampleRefund") {
            files.append(ImportFile(name: "Umsaetze-Retoure.csv", data: Data(refundLine(now: .now).utf8)))
        }
        if LaunchArguments.current.contains("-sampleShopLines") {
            files.append(ImportFile(name: "Umsaetze-Kleiderkreisel.csv", data: Data(shopLines(now: .now).utf8)))
        }
        if LaunchArguments.current.contains("-sampleQuickSort") {
            files.append(ImportFile(name: "Umsaetze-Privat.csv", data: Data(quickSortLines(now: .now).utf8)))
        }
        let paybackGroup = LaunchArguments.current.contains("-samplePaybackGroup")
        if paybackGroup {
            files.append(ImportFile(name: "Umsaetze-Geteilt.csv", data: Data(paybackGroupLines(now: .now).utf8)))
        }
        let fixedCosts = LaunchArguments.current.contains("-sampleFixedCosts")
        if fixedCosts {
            for id in FixedCostSample.categories.values where !chosen.contains(id) { try await ledger.choose(id) }
            files.append(ImportFile(name: "Umsaetze-Vorjahr.csv", data: Data(fixedCostLines(now: .now).utf8)))
        }
        for name in ["sample-paypal.csv", "sample-camt.xml"] {
            let parts = name.split(separator: ".")
            if let url = Bundle.main.url(forResource: String(parts[0]), withExtension: String(parts[1])) {
                files.append(ImportFile(name: name, data: try Data(contentsOf: url)))
            }
        }
        _ = try await backend.importFiles(files, auth: BackendAuth(token: nil))
        // The made-up payback, linked as in the tour; `-sampleNoPayback` leaves it to be linked by hand (brief 203).
        if !LaunchArguments.current.contains("-sampleNoPayback") { try await TourData.linkSamplePayback(in: backend) }
        if paybackGroup { try await sortPaybackGroup(backend) }
        if fixedCosts { try await sortFixedCosts(backend) }
        // Confirmation screenshots: give a category made-up primary payments, never changing the real store.
        if let key = LaunchArguments.value("-sampleCategoryPayments"),
           let id = try await backend.categories().id(named: key) ?? (backend.summary.chosen.contains { $0.id == key } ? key : nil) {
            let count = LaunchArguments.value("-sampleCategoryPaymentCount").flatMap(Int.init) ?? 12
            let payments = try await ledger.payments().filter { $0.categorySource != .structural }.prefix(max(0, count))
            for payment in payments { try await ledger.setCategory(payment.id, category: id, source: .manual) }
            try await backend.refresh()
        }
        // Own names (brief 44): on unless `-ownNames off` (the sample's settings outlive a launch); `-sampleNames` names
        // the bakery's shop and one dinner.
        backend.setOwnNames(LaunchArguments.value("-ownNames") != "off")
        if LaunchArguments.current.contains("-sampleNames") { try await addNames(backend) }
        return (backend, storage)
    }

    /// Exact payment count over the preceding year, made-up bank lines only. Uses the real reader and ledger.
    static func sizedFile(size: Int, now: Date = .now) -> ImportFile {
        let calendar = ReceiptDay.calendar
        var lines = ["IBAN Auftragskonto;Buchungstag;Valutadatum;Name Zahlungsbeteiligter;Buchungstext;Verwendungszweck;Betrag;Währung;Soll/Haben;Saldo nach Buchung"]
        let shops = ["REWE Markt GmbH", "LIDL DIENSTLEISTUNG", "Fiktiva Cafe", "Fictional Employer", "Fiktiv Shop"]
        for index in 0..<size {
            let day = ReceiptDay.day(calendar.date(byAdding: .day, value: -(index % 365), to: now) ?? now)
            let parts = day.split(separator: "-")
            let date = "\(parts[2]).\(parts[1]).\(parts[0])"
            lines.append(";\(date);\(date);\(shops[index % shops.count]);Lastschrift;Fictional payment \(index);\(10 + index % 80),50;EUR;\(index % 5 == 3 ? "H" : "S");")
        }
        return ImportFile(name: "Umsaetze-Fiktiv.csv", data: Data((lines.joined(separator: "\n") + "\n").utf8))
    }

    /// `-sampleLongName` (brief 47, the long press's menu with a long bank name): three made-up purchases this month
    /// under one long marketplace-style bank name, as PayPal writes some.
    private static func longNameLines(now: Date) -> String {
        let calendar = ReceiptDay.calendar
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "dd.MM.yyyy"
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        let days = [1, 3, 5].map { formatter.string(from: calendar.date(byAdding: .day, value: $0, to: start) ?? start) }
        let name = "FKV Fiktiv Secondhand-Marktplatz - Kleiderkreisel Europe"
        return """
            IBAN Auftragskonto;Buchungstag;Valutadatum;Name Zahlungsbeteiligter;Buchungstext;Verwendungszweck;Betrag;Währung;Soll/Haben;Saldo nach Buchung
            ;\(days[0]);\(days[0]);\(name);Lastschrift;Bestellung 1001;14,50;EUR;S;
            ;\(days[1]);\(days[1]);\(name);Lastschrift;Bestellung 1002;22,00;EUR;S;
            ;\(days[2]);\(days[2]);\(name);Lastschrift;Bestellung 1003;9,90;EUR;S;

            """
    }

    /// `-sampleDay31` (brief 55, the day's tile at its widest, "31."): one made-up REWE purchase on the newest 31st up to
    /// today, so Groceries and REWE's month show it.
    private static func day31Line(now: Date) -> String {
        let calendar = ReceiptDay.calendar
        let thisMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        let last = (0..<12).lazy.compactMap { back -> Date? in
            guard let month = calendar.date(byAdding: .month, value: -back, to: thisMonth),
                  let day = calendar.date(byAdding: .day, value: 30, to: month),
                  calendar.component(.day, from: day) == 31, day <= now else { return nil }
            return day
        }.first ?? now
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "dd.MM.yyyy"
        let day = formatter.string(from: last)
        return """
            IBAN Auftragskonto;Buchungstag;Valutadatum;Name Zahlungsbeteiligter;Buchungstext;Verwendungszweck;Betrag;Währung;Soll/Haben;Saldo nach Buchung
            ;\(day);\(day);REWE Markt GmbH;Kartenzahlung;REWE SAGT DANKE;31,40;EUR;S;

            """
    }

    /// `-sampleRefund` (brief 55, a name's month with only a refund): a made-up Zalando refund on the 1st of this month,
    /// a month without a Zalando purchase (the sample orders from it every third month).
    private static func refundLine(now: Date) -> String {
        let calendar = ReceiptDay.calendar
        let first = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "dd.MM.yyyy"
        let day = formatter.string(from: first)
        return """
            IBAN Auftragskonto;Buchungstag;Valutadatum;Name Zahlungsbeteiligter;Buchungstext;Verwendungszweck;Betrag;Währung;Soll/Haben;Saldo nach Buchung
            ;\(day);\(day);Zalando SE;Gutschrift;Retoure;40,00;EUR;H;

            """
    }

    /// `-sampleShopLines` (brief 77, the search finding a name through the bank's other line): made-up second-hand
    /// purchases and one sale at a marketplace whose bank line changed during the year (brief 76's example): "MGP Vinted
    /// - Kleiderkreisel" four and three months ago, "Vinted, UAB" since. One shop, so it shows the newest line, and a
    /// search for "Kleider" finds it by the older one. Made-up dates and amounts.
    private static func shopLines(now: Date) -> String {
        let calendar = ReceiptDay.calendar
        let thisMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "dd.MM.yyyy"
        func day(monthsBack: Int, _ day: Int) -> String {
            let month = calendar.date(byAdding: .month, value: -monthsBack, to: thisMonth) ?? thisMonth
            return formatter.string(from: calendar.date(byAdding: .day, value: day - 1, to: month) ?? month)
        }
        let old = "MGP Vinted - Kleiderkreisel", new = "Vinted, UAB"
        let rows = [(day(monthsBack: 4, 13), old, "Bestellung 2201", "18,50", "S"),
                    (day(monthsBack: 3, 9), old, "Bestellung 2202", "24,00", "S"),
                    (day(monthsBack: 2, 16), new, "Bestellung 2203", "12,90", "S"),
                    (day(monthsBack: 1, 12), new, "Verkauf Jacke", "35,00", "H"),
                    (day(monthsBack: 1, 22), new, "Bestellung 2204", "29,40", "S")]
        let lines = rows.map { ";\($0.0);\($0.0);\($0.1);\($0.4 == "H" ? "Gutschrift" : "Lastschrift");\($0.2);\($0.3);EUR;\($0.4);" }
        return (["IBAN Auftragskonto;Buchungstag;Valutadatum;Name Zahlungsbeteiligter;Buchungstext;Verwendungszweck;Betrag;Währung;Soll/Haben;Saldo nach Buchung"]
                + lines).joined(separator: "\n") + "\n"
    }

    /// `-sampleQuickSort` (brief 99, the quick sort's cards): made-up personal payments no rule can sort, as a new
    /// person's first import has them: a made-up relative's monthly transfers in and one payment back to her, a made-up
    /// friend paid for a garage every month, and a made-up drinks shop a few times. Made-up names, dates and amounts.
    private static func quickSortLines(now: Date) -> String {
        let calendar = ReceiptDay.calendar
        let thisMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "dd.MM.yyyy"
        let today = calendar.component(.day, from: now)
        func day(monthsBack: Int, _ day: Int) -> String {
            let month = calendar.date(byAdding: .month, value: -monthsBack, to: thisMonth) ?? thisMonth
            let shown = monthsBack == 0 ? min(day, today) : day
            return formatter.string(from: calendar.date(byAdding: .day, value: shown - 1, to: month) ?? month)
        }
        let months = ["Januar", "Februar", "März", "April", "Mai", "Juni", "Juli", "August", "September", "Oktober",
                      "November", "Dezember"]
        func monthName(_ back: Int) -> String {
            let month = calendar.date(byAdding: .month, value: -back, to: thisMonth) ?? thisMonth
            return months[calendar.component(.month, from: month) - 1]
        }
        var rows: [(String, String, String, String, String, String)] = []
        for back in 0..<7 {
            rows.append((day(monthsBack: back, 2), "Lena Beispiel", "Gutschrift", "Für dich \(monthName(back))", "150,00", "H"))
            rows.append((day(monthsBack: back, 4), "Jonas Fiktiv", "Überweisung", "Garage \(monthName(back))", "45,00", "S"))
        }
        rows.append((day(monthsBack: 1, 19), "Lena Beispiel", "Überweisung", "Kinokarten", "24,00", "S"))
        for (back, amount) in [(1, "18,40"), (2, "22,90"), (4, "15,60")] {
            rows.append((day(monthsBack: back, 11), "Fiktiv Getraenkequelle", "Kartenzahlung", "Getränke", amount, "S"))
        }
        let lines = rows.map { ";\($0.0);\($0.0);\($0.1);\($0.2);\($0.3);\($0.4);EUR;\($0.5);" }
        return (["IBAN Auftragskonto;Buchungstag;Valutadatum;Name Zahlungsbeteiligter;Buchungstext;Verwendungszweck;Betrag;Währung;Soll/Haben;Saldo nach Buchung"]
                + lines).joined(separator: "\n") + "\n"
    }

    /// `-samplePaybackGroup` (brief 206, money paid back for several payments at once): made-up shared costs last month.
    /// Two dinners out (Eating out, with the month's Restaurant Fiktiva: three expenses to select) and two made-up
    /// friends paying their part back; a made-up language course and a made-up parent's two transfers towards it
    /// (Parents & family, with her monthly pocket money: two payments in to select). Made-up names, dates and amounts.
    private static func paybackGroupLines(now: Date) -> String {
        let calendar = ReceiptDay.calendar
        let thisMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        let lastMonth = calendar.date(byAdding: .month, value: -1, to: thisMonth) ?? thisMonth
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "dd.MM.yyyy"
        func day(_ number: Int) -> String {
            formatter.string(from: calendar.date(byAdding: .day, value: number - 1, to: lastMonth) ?? lastMonth)
        }
        let rows: [(Int, String, String, String, String, String)] = [
            (3, PaybackGroupNames.pizzeria, "Kartenzahlung", "Pizza mit Freunden", "48,00", "S"),
            (10, PaybackGroupNames.grill, "Kartenzahlung", "Grillabend", "36,00", "S"),
            (11, "Fiona Fiktiv", "Gutschrift", "Grillabend Anteil", "40,00", "H"),
            (18, "Felix Fiktiv", "Gutschrift", "Essen zurück", "100,00", "H"),
            (6, PaybackGroupNames.parent, "Gutschrift", PaybackGroupNames.allowance, "150,00", "H"),
            (8, "Fiktiv Sprachschule", "Lastschrift", "Sprachkurs Herbst", "200,00", "S"),
            (13, PaybackGroupNames.parent, "Gutschrift", PaybackGroupNames.allowance, "100,00", "H"),
        ]
        let lines = rows.map { ";\(day($0.0));\(day($0.0));\($0.1);\($0.2);\($0.3);\($0.4);EUR;\($0.5);" }
        return (["IBAN Auftragskonto;Buchungstag;Valutadatum;Name Zahlungsbeteiligter;Buchungstext;Verwendungszweck;Betrag;Währung;Soll/Haben;Saldo nach Buchung"]
                + lines).joined(separator: "\n") + "\n"
    }

    private enum PaybackGroupNames {
        static let pizzeria = "Pizzeria Fiktivo"
        static let grill = "Fiktiv Grillhaus"
        static let allowance = "Zuschuss Sprachkurs"
        /// The tour's made-up parent (her pocket money every month).
        static let parent = "Erika Mustermann"
    }

    /// The dinners into Eating out and the parent's transfers into Parents & family, by hand, so the lists to select
    /// from hold them whatever the sorting makes of the made-up names.
    private static func sortPaybackGroup(_ backend: PhoneBackend) async throws {
        for payment in try await backend.ledger.payments() {
            let category: String
            if payment.counterparty == PaybackGroupNames.pizzeria || payment.counterparty == PaybackGroupNames.grill {
                category = "eating-out"
            } else if payment.counterparty == PaybackGroupNames.parent, payment.text.contains(PaybackGroupNames.allowance) {
                category = "parents-family"
            } else {
                continue
            }
            try await backend.ledger.setCategory(payment.id, category: category, source: .manual)
        }
        try await backend.refresh()
    }

    /// `-sampleFixedCosts` (brief 209, the fixed costs page): an older made-up statement and contracts over the last 14
    /// months, so a yearly payment is seen twice. The months before the tour's nine carry its regular payments (salary,
    /// pocket money, the rent at €750 before its raise to €780, the bills, cash) and groceries, so the average month stays
    /// a normal one; over all 14 months two subscriptions at one shop (StreamFiktiv €7.99 and €12.99), a yearly liability
    /// insurance (€498.96, so €41.58 a month), a quarterly account fee (€15) and a gym cancelled four months ago (€29.90,
    /// Ended). Made-up names, dates and amounts; this month's payments only up to today.
    private static func fixedCostLines(now: Date) -> String {
        let calendar = ReceiptDay.calendar
        let thisMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "dd.MM.yyyy"
        let monthNames = ["Januar", "Februar", "März", "April", "Mai", "Juni", "Juli", "August", "September", "Oktober",
                          "November", "Dezember"]
        var lines = ["IBAN Auftragskonto;Buchungstag;Valutadatum;Name Zahlungsbeteiligter;Buchungstext;Verwendungszweck;Betrag;Währung;Soll/Haben;Saldo nach Buchung"]
        var seed = 11
        func next(_ range: Int) -> Int { seed = (seed * 1103 + 12345) % 65536; return seed % range }
        func euros(_ cents: Int) -> String { String(format: "%ld,%02ld", cents / 100, cents % 100) }
        func add(_ back: Int, _ day: Int, _ who: String, _ kind: String, _ text: String, _ euros: String, _ sign: String) {
            let month = calendar.date(byAdding: .month, value: -back, to: thisMonth) ?? thisMonth
            guard let date = calendar.date(byAdding: .day, value: day - 1, to: month), date <= now else { return }
            let shown = formatter.string(from: date)
            lines.append(";\(shown);\(shown);\(who);\(kind);\(text);\(euros);EUR;\(sign);")
        }
        for back in 0...13 {
            let month = calendar.date(byAdding: .month, value: -back, to: thisMonth) ?? thisMonth
            let name = monthNames[calendar.component(.month, from: month) - 1]
            // The months before the tour's statement (it starts eight months back): its regular payments go on.
            if back >= 9 {
                add(back, 1, "Fiktiv Werke GmbH", "Gehalt/Rente", "Gehalt \(name)", "2.450,00", "H")
                add(back, 2, "Fiktiv Hausverwaltung", "Dauerauftrag", "Miete \(name)", "750,00", "S")
                add(back, 3, "Erika Mustermann", "Gutschrift", "Taschengeld \(name)", "150,00", "H")
                add(back, 5, "Stadtwerke Fiktivstadt", "Lastschrift", "Abschlag Strom \(name)", "45,00", "S")
                add(back, 6, "Vodafone GmbH", "Lastschrift", "Mobilfunk \(name)", "29,99", "S")
                add(back, 7, "MVG", "Lastschrift", "Deutschlandticket \(name)", "58,00", "S")
                add(back, 8, "Spotify", "Lastschrift", "Spotify Premium", "10,99", "S")
                add(back, 9, "Netflix", "Lastschrift", "Netflix Abo", "13,99", "S")
                add(back, 18, "Geldautomat Fiktivbank", "Auszahlung", "Bargeldauszahlung", "100,00", "S")
                // Groceries at changing amounts (a fixed seed, as the tour's), so they never look like a contract.
                for week in 0..<4 {
                    add(back, 4 + week * 7, "REWE Markt GmbH", "Kartenzahlung", "REWE SAGT DANKE", euros(2_000 + next(4_500)), "S")
                    add(back, 6 + week * 7, "LIDL DIENSTLEISTUNG", "Kartenzahlung", "Lidl sagt Danke", euros(900 + next(2_500)), "S")
                }
            }
            add(back, 11, "StreamFiktiv", "Lastschrift", "StreamFiktiv Abo", "7,99", "S")
            add(back, 14, "StreamFiktiv", "Lastschrift", "StreamFiktiv Abo", "12,99", "S")
            if back >= 4 { add(back, 10, "Fiktiv Fitness GmbH", "Lastschrift", "Mitgliedsbeitrag \(name)", "29,90", "S") }
            if back == 13 || back == 1 {
                add(back, 15, "Fiktiv Versicherung AG", "Lastschrift", "Haftpflichtversicherung Jahresbeitrag", "498,96", "S")
            }
            if back % 3 == 1 { add(back, 28, "Fiktiv Bank", "Entgelt", "Kontoführung Quartal", "15,00", "S") }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// The contracts' categories (by hand, so the page shows the same tiles whatever the sorting makes of the names).
    private enum FixedCostSample {
        static let categories = ["StreamFiktiv": "subscriptions", "Fiktiv Versicherung AG": "insurance",
                                 "Fiktiv Bank": "fees", "Fiktiv Fitness GmbH": "sports-fitness"]
    }

    private static func sortFixedCosts(_ backend: PhoneBackend) async throws {
        for payment in try await backend.ledger.payments() {
            guard let name = payment.counterparty, let category = FixedCostSample.categories[name] else { continue }
            try await backend.ledger.setCategory(payment.id, category: category, source: .manual)
        }
        try await backend.refresh()
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
    /// `-sampleShopReceipt` (brief 47, the receipt page's "All from" card): a cash receipt this month from the shop of
    /// the sample's weekly LIDL payments, so its name has more payments. Made up.
    static func addShopReceipt(_ phone: PhoneBackend, now: Date = .now) async throws {
        let calendar = ReceiptDay.calendar
        let start = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        let date = min(ReceiptDay.day(calendar.date(byAdding: .day, value: 1, to: start) ?? start), ReceiptDay.day(now))
        _ = try await phone.saveReceipt(ReceiptDraft(date: date, shop: "LIDL DIENSTLEISTUNG", total: 7.85, currency: "EUR",
                                                     method: .cash, category: "groceries", categorySource: .starter,
                                                     rows: ["LIDL", "Brot 2,49", "Milch 1,19", "Äpfel 4,17", "SUMME 7,85"],
                                                     from: "text"))
    }

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
