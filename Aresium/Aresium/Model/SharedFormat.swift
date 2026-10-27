import Foundation

/// "What is sent?": the format Send sends, as people read it. Built from exactly the layout and values that go out
/// (`BankFormatCard.shared`), so the page can never show less than the request carries: every column name with what it
/// holds, the date and number style, the separator, any other setting of the layout, the bank's name, the app's
/// version and language. Pure, so tests pin it.
nonisolated struct SharedFormat: Equatable, Sendable {
    struct Column: Equatable, Sendable {
        /// The file's column name ("Column 3" when the file has no header row).
        let name: String
        /// What it holds, nil when Aresium does not use it.
        let meaning: String?
    }

    struct Line: Equatable, Sendable {
        let title: String
        let value: String
    }

    /// The bank's name as it goes out (empty while nothing is typed).
    let bank: String
    let columns: [Column]
    /// How dates and amounts are written, the separator, then any other setting the layout has.
    let lines: [Line]
    let appVersion: String
    /// The language sent with it, by its own name ("English", "Deutsch").
    let language: String

    init(layout: CsvLayout, bank: String, appVersion: String, language sent: AppLanguage,
         wording language: AppLanguage = .current) {
        self.bank = bank
        self.appVersion = appVersion
        self.language = sent == .german ? "Deutsch" : "English"

        var meanings: [Int: [String]] = [:]
        func add(_ meaning: ColumnMeaning, _ columns: [Int]?) {
            for column in columns ?? [] {
                let title = meaning.title(language)
                if meanings[column]?.contains(title) != true { meanings[column, default: []].append(title) }
            }
        }
        let c = layout.columns
        add(.date, [c.date])
        add(.valueDate, c.valueDate.map { [$0] })
        add(.amount, c.amount.map { [$0] })
        add(.amount, c.addAmounts)
        add(.debit, c.debit.map { [$0] })
        add(.credit, c.credit.map { [$0] })
        add(.sign, c.sign.map { [$0] })
        add(.counterparty, c.counterparty)
        add(.counterparty, [c.payer, c.payee].compactMap { $0 })
        add(.text, c.text)
        add(.kind, c.kind.map { [$0] })
        add(.iban, c.iban.map { [$0] })
        add(.accountIban, c.accountIban.map { [$0] })
        add(.balance, c.balance.map { [$0] })
        add(.currency, c.currency.map { [$0] })
        add(.reference, c.reference.map { [$0] })
        add(.status, c.status.map { [$0] })
        for column in c.fees ?? [] { meanings[column, default: []].append(language.string("Fees")) }

        let width = max(layout.header.count, layout.columnCount ?? 0, (meanings.keys.max() ?? -1) + 1)
        columns = (0..<width).map { index in
            let header = layout.header.indices.contains(index)
                ? layout.header[index].trimmingCharacters(in: .whitespaces) : ""
            return Column(name: header.isEmpty ? language.string("Column \(index + 1)") : header,
                          meaning: meanings[index]?.joined(separator: " + "))
        }

        var lines = [
            Line(title: language.string("Dates"), value: LayoutDraft.example(of: layout.dateFormat)),
            Line(title: language.string("Amounts"), value: LayoutDraft.example(ofNumberFormat: layout.numberFormat)),
            Line(title: language.string("Separator"), value: Self.separatorName(layout.separator, language: language)),
        ]
        if layout.invertSign == true {
            lines.append(Line(title: language.string("Money in and out"), value: language.string("the other way round")))
        }
        if let words = layout.skipStatus, !words.isEmpty {
            lines.append(Line(title: language.string("Rows left out"), value: words.joined(separator: ", ")))
        }
        if let words = layout.keepStatus, !words.isEmpty {
            lines.append(Line(title: language.string("Only rows marked"), value: words.joined(separator: ", ")))
        }
        if let labels = layout.labelledText {
            let words = labels.labels + labels.counterparty + labels.text
            if !words.isEmpty {
                lines.append(Line(title: language.string("Labels in the text"), value: words.joined(separator: ", ")))
            }
        }
        if let currency = layout.currency {
            lines.append(Line(title: language.string("Currency"), value: currency))
        }
        self.lines = lines
    }

    /// The separator by its name: "Semicolon", "Comma", "Tab", "Vertical bar".
    static func separatorName(_ separator: String, language: AppLanguage = .current) -> String {
        switch separator {
        case ";": language.string("Semicolon")
        case ",": language.string("Comma")
        case "\t": language.string("Tab")
        case "|": language.string("Vertical bar")
        default: separator
        }
    }
}
