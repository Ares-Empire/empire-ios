import Foundation
import Observation

/// What a CSV column holds, as the person picks it on the layout confirmation sheet (the guesser's roles,
/// aresium/src/engine/readers/guess.ts).
nonisolated enum ColumnMeaning: String, CaseIterable, Identifiable, Sendable {
    case ignore, date, valueDate, amount, debit, credit, sign, counterparty, text, kind, iban, accountIban, balance,
         currency, reference, status

    var id: String { rawValue }

    /// Text and counterparty may come from several columns; everything else from one.
    var allowsSeveral: Bool { self == .ignore || self == .counterparty || self == .text }

    func title(_ language: AppLanguage = .current) -> String {
        switch self {
        case .ignore: language.string("Not used")
        case .date: language.string("Booking date")
        case .valueDate: language.string("Value date")
        case .amount: language.string("Amount")
        case .debit: language.string("Money out")
        case .credit: language.string("Money in")
        case .sign: language.string("In or out mark")
        case .counterparty: language.string("Counterparty")
        case .text: language.string("Payment text")
        case .kind: language.string("Booking type")
        case .iban: language.string("Their IBAN")
        case .accountIban: language.string("Your IBAN")
        case .balance: language.string("Balance")
        case .currency: language.string("Currency")
        case .reference: language.string("Reference")
        case .status: language.string("Status")
        }
    }
}

/// The layout the person builds from the engine's guess: one meaning per column, the date format and the number format.
/// `layout` is the `CsvLayout` to save, once a date and an amount (or money out and money in) are picked.
nonisolated struct LayoutDraft: Equatable, Sendable {
    static let dateFormats = ["DD.MM.YYYY", "DD.MM.YY", "YYYY-MM-DD", "DD/MM/YYYY", "MM/DD/YYYY", "DD-MM-YYYY", "YYYYMMDD"]
    /// Number formats: "de" 1.234,56 · "en" 1,234.56.
    static let numberFormats = ["de", "en"]
    /// A date format as a date people read (31 December 2026), so the menu needs no format codes: "DD.MM.YYYY" →
    /// "31.12.2026", "MM/DD/YYYY" → "12/31/2026".
    static func example(of dateFormat: String) -> String {
        dateFormat.replacingOccurrences(of: "YYYY", with: "2026").replacingOccurrences(of: "YY", with: "26")
            .replacingOccurrences(of: "MM", with: "12").replacingOccurrences(of: "DD", with: "31")
    }
    /// A number format as an amount: "de" → "1.234,56", "en" → "1,234.56".
    static func example(ofNumberFormat format: String) -> String { format == "en" ? "1,234.56" : "1.234,56" }
    /// Rows not booked yet, when a status column is picked (the guesser's own list).
    static let pendingStatus = ["vorgemerkt", "pending", "offen", "reverted", "declined", "failed", "storniert"]

    let guess: LayoutGuess
    private(set) var meanings: [ColumnMeaning]
    var dateFormat: String
    var numberFormat: String

    init(guess: LayoutGuess) {
        self.guess = guess
        let width = max(guess.header.count, (guess.columns.map(\.index).max() ?? -1) + 1)
        var meanings = Array(repeating: ColumnMeaning.ignore, count: width)
        if let columns = guess.layout?.columns {
            func put(_ meaning: ColumnMeaning, _ index: Int?) {
                if let index, meanings.indices.contains(index) { meanings[index] = meaning }
            }
            put(.date, columns.date)
            put(.valueDate, columns.valueDate)
            put(.amount, columns.amount)
            put(.debit, columns.debit)
            put(.credit, columns.credit)
            put(.sign, columns.sign)
            columns.counterparty?.forEach { put(.counterparty, $0) }
            columns.text?.forEach { put(.text, $0) }
            put(.kind, columns.kind)
            put(.iban, columns.iban)
            put(.accountIban, columns.accountIban)
            put(.balance, columns.balance)
            put(.currency, columns.currency)
            put(.reference, columns.reference)
            put(.status, columns.status)
        }
        self.meanings = meanings
        dateFormat = guess.layout?.dateFormat
            ?? guess.columns.first { $0.kind == "date" }?.dateFormat ?? Self.dateFormats[0]
        numberFormat = guess.layout?.numberFormat ?? "de"
    }

    func meaning(of column: Int) -> ColumnMeaning { meanings.indices.contains(column) ? meanings[column] : .ignore }

    /// Gives a column a meaning. A meaning of one column moves there from the column that had it; one amount column
    /// and money out/in exclude each other. Picking the date column takes its date format.
    mutating func set(_ meaning: ColumnMeaning, for column: Int) {
        guard meanings.indices.contains(column) else { return }
        func clear(_ meaning: ColumnMeaning) {
            for index in meanings.indices where meanings[index] == meaning { meanings[index] = .ignore }
        }
        if !meaning.allowsSeveral { clear(meaning) }
        if meaning == .amount { clear(.debit); clear(.credit) }
        if meaning == .debit || meaning == .credit { clear(.amount); clear(.sign) }
        meanings[column] = meaning
        if meaning == .date, let format = guess.columns.first(where: { $0.index == column })?.dateFormat {
            dateFormat = format
        }
    }

    /// What the layout still needs: a date, and an amount (one column, or money out and money in).
    var missing: [ColumnMeaning] {
        var missing: [ColumnMeaning] = []
        if !meanings.contains(.date) { missing.append(.date) }
        if !meanings.contains(.amount) && !(meanings.contains(.debit) && meanings.contains(.credit)) {
            missing.append(.amount)
        }
        return missing
    }

    /// The layout to save and read with, or nil while something is missing.
    var layout: CsvLayout? {
        guard missing.isEmpty, let date = meanings.firstIndex(of: .date) else { return nil }
        func one(_ meaning: ColumnMeaning) -> Int? { meanings.firstIndex(of: meaning) }
        func all(_ meaning: ColumnMeaning) -> [Int]? {
            let indices = meanings.indices.filter { meanings[$0] == meaning }
            return indices.isEmpty ? nil : indices
        }
        let amount = one(.amount)
        let columns = CsvLayout.Columns(
            date: date, valueDate: one(.valueDate), amount: amount,
            debit: amount == nil ? one(.debit) : nil, credit: amount == nil ? one(.credit) : nil,
            sign: amount == nil ? nil : one(.sign), counterparty: all(.counterparty), text: all(.text), kind: one(.kind),
            iban: one(.iban), accountIban: one(.accountIban), balance: one(.balance), currency: one(.currency),
            reference: one(.reference), status: one(.status))
        var layout = guess.layout ?? CsvLayout(separator: guess.separator, header: guess.header, dateFormat: dateFormat,
                                               numberFormat: numberFormat, columns: columns)
        layout.separator = guess.separator
        layout.header = guess.header
        layout.columnCount = guess.headerRow < 0 ? meanings.count : nil
        layout.dateFormat = dateFormat
        layout.numberFormat = numberFormat
        layout.columns = columns
        layout.skipStatus = columns.status == nil ? nil : (guess.layout?.skipStatus ?? Self.pendingStatus)
        if columns.status == nil { layout.keepStatus = nil }
        return layout
    }
}

/// The layout confirmation sheet's model: the draft, a preview of the first rows read with it (by the engine), and
/// Confirm (the layout is saved and the file read again) or Cancel (the file is not imported).
@MainActor @Observable
final class LayoutConfirmModel {
    let request: LayoutRequest
    private(set) var draft: LayoutDraft
    private(set) var preview: [BankTxn]
    private(set) var previewProblem: String?
    private(set) var isSaving = false
    private(set) var saveProblem: String?
    @ObservationIgnored private let phone: PhoneBackend
    @ObservationIgnored private let imports: ImportStore
    @ObservationIgnored private var previewTask: Task<Void, Never>?
    /// How many rows the preview shows.
    static let previewRows = 5

    init(request: LayoutRequest, phone: PhoneBackend, imports: ImportStore) {
        self.request = request
        self.phone = phone
        self.imports = imports
        draft = LayoutDraft(guess: request.guess)
        preview = Array(request.guess.preview.prefix(Self.previewRows))
    }

    var columns: [ColumnInfo] { request.guess.columns }
    var canConfirm: Bool { draft.layout != nil && !isSaving }

    func set(_ meaning: ColumnMeaning, for column: Int) {
        draft.set(meaning, for: column)
        refreshPreview()
    }

    func setDateFormat(_ format: String) {
        draft.dateFormat = format
        refreshPreview()
    }

    func setNumberFormat(_ format: String) {
        draft.numberFormat = format
        refreshPreview()
    }

    /// Reads the first rows again with the changed layout (the newest change wins).
    func refreshPreview() {
        previewTask?.cancel()
        guard let layout = draft.layout else {
            preview = []
            previewProblem = nil
            return
        }
        previewTask = Task {
            do {
                let rows = try await phone.preview(request.file, layout: layout)
                guard !Task.isCancelled else { return }
                preview = Array(rows.prefix(Self.previewRows))
                previewProblem = rows.isEmpty ? String(localized: "No payments could be read with these columns.") : nil
            } catch {
                guard !Task.isCancelled else { return }
                preview = []
                previewProblem = error.localizedDescription
            }
        }
    }

    /// Saves the layout and reads the file again with it. Returns whether the sheet can close.
    func confirm() async -> Bool {
        guard let layout = draft.layout, !isSaving else { return false }
        isSaving = true
        saveProblem = nil
        defer { isSaving = false }
        do {
            try await phone.saveLayout(layout)
            imports.layoutConfirmed(request)
            return true
        } catch {
            saveProblem = error.localizedDescription
            return false
        }
    }

    func cancel() { imports.layoutSkipped(request) }
}

/// One payment of the column check's preview as its row shows it: the day of the month for the tile, the whole date in
/// the app's language (so the person sees the date column read right), who and what, and the amount with its sign.
nonisolated struct PreviewPayment: Equatable, Sendable {
    /// The day of the month, nil when the booking date is not `YYYY-MM-DD`.
    let day: Int?
    /// "3 Oct 2026" / "3. Okt. 2026", or the engine's text when it is not a date.
    let date: String
    let title: String
    /// The payment text when the title is the counterparty.
    let detail: String?
    let amount: Double

    init(_ payment: BankTxn, language: AppLanguage = .current) {
        let parsed = Self.parse(payment.day)
        day = parsed.map { Self.calendar.component(.day, from: $0) }
        date = parsed.map {
            $0.formatted(Date.FormatStyle(date: .omitted, time: .omitted, locale: language.locale, calendar: Self.calendar,
                                          timeZone: Self.calendar.timeZone).day().month(.abbreviated).year())
        } ?? payment.day
        let counterparty = payment.counterparty?.trimmingCharacters(in: .whitespaces) ?? ""
        let text = payment.description.trimmingCharacters(in: .whitespaces)
        title = counterparty.isEmpty ? text : counterparty
        detail = counterparty.isEmpty || text.isEmpty || text == counterparty ? nil : text
        amount = Double(payment.amount) ?? 0
    }

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private static func parse(_ day: String) -> Date? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}
