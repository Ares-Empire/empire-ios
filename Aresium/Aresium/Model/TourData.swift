import Foundation

/// The made-up data of the tour (and of the DEBUG phone samples, `PhoneSample`): the categories a made-up person ticked,
/// one of their own, and a VR Bank export (its known layout) with made-up payments for the nine months up to today,
/// read through the real import. Made-up shops and amounts only; no real payment is anywhere in it.
nonisolated enum TourData {
    /// The categories the made-up person ticked.
    static let chosen = ["groceries", "drugstore", "eating-out", "coffee-snacks", "rent", "utilities", "internet-phone",
                         "bus-train", "subscriptions", "cash", "salary", "parents-family", "clothes", "other"]

    /// The category the tour points at first ("Tap a category"): it has a few shops, each paid several times.
    static let firstCategory = "groceries"

    /// The made-up person's own category, in the app's language.
    static func customName(_ language: AppLanguage = .current) -> String { language.string("Climbing") }

    /// The made-up bank file for the nine months up to `now`; `fillThisMonth` dates this month's payments within the
    /// days gone by, so the current month is full on any day (the tour opens on "this month").
    static func bankFile(now: Date, fillThisMonth: Bool = true, calendar: Calendar = .current) -> ImportFile {
        ImportFile(name: "Umsaetze-Girokonto.csv",
                   data: Data(vrBankCSV(now: now, fillThisMonth: fillThisMonth, calendar: calendar).utf8))
    }

    /// A VR Bank export with made-up payments for the nine months up to `now`.
    static func vrBankCSV(now: Date, fillThisMonth: Bool = false, calendar: Calendar = .current) -> String {
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
            let today = calendar.component(.day, from: now)
            let lastDay = back == 0 ? today : days
            let name = monthNames[calendar.component(.month, from: month) - 1]
            func on(_ day: Int) -> Date? {
                // This month, filled: the month's days are pressed into the days gone by (all on the 1st, on the 1st).
                if back == 0 && fillThisMonth {
                    let pressed = max(1, Int((Double(min(day, days)) * Double(today) / Double(days)).rounded(.up)))
                    return calendar.date(byAdding: .day, value: min(pressed, today) - 1, to: month)
                }
                return day <= lastDay ? calendar.date(byAdding: .day, value: day - 1, to: month) : nil
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
            // A third grocer, twice a month (brief 59): the tour's list keeps two names with several payments after
            // its switch step moved the first shop out, so its icon of adding up has something to add. Fixed amounts,
            // so the seeded amounts of the other rows stay as they were.
            add(8, "ALDI SUED", "Kartenzahlung", "ALDI SUED Fiktivstadt", -(1_640 + back * 37))
            add(20, "ALDI SUED", "Kartenzahlung", "ALDI SUED Fiktivstadt", -(2_180 - back * 23))
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
