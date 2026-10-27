import Foundation
import Observation

/// "Does this look right?" for a bank file Aresium does not know (brief 23; Patrik, 2026-10-27: most people don't know
/// what a CSV is, so they are never asked about columns first). The window shows the first payments as the app would
/// show them, read the engine's best way (`FileReading`). Yes saves that reading's layout and imports the file; No shows
/// the next reading, with a short line on what changed; after the last one, No opens the column check
/// (`ColumnCheckModel`). Cancel, at every step, leaves the file out. Only a layout the person confirmed is saved.
@MainActor @Observable
final class FileCheckModel {
    enum Step: Equatable {
        /// One of the engine's readings (its place in `readings`).
        case reading(Int)
        /// The column check: no reading fitted, or there was none.
        case columns
    }

    /// How many of a reading's first payments the window shows.
    static let shownPayments = 3

    let request: LayoutRequest
    private(set) var step: Step
    private(set) var isSaving = false
    private(set) var saveProblem: String?
    /// The column check, made when it is first shown.
    private(set) var columns: ColumnCheckModel?
    @ObservationIgnored private let phone: PhoneBackend
    @ObservationIgnored private let imports: ImportStore

    init(request: LayoutRequest, phone: PhoneBackend, imports: ImportStore) {
        self.request = request
        self.phone = phone
        self.imports = imports
        step = .reading(0)
        if request.readings.isEmpty { showColumns() }
    }

    var readings: [FileReading] { request.readings }

    /// The reading shown now, nil in the column check.
    var reading: FileReading? {
        guard case let .reading(index) = step, readings.indices.contains(index) else { return nil }
        return readings[index]
    }

    /// The shown reading's place, counted from 1 ("Suggestion 2 of 3"), nil in the column check.
    var number: Int? { if case let .reading(index) = step { index + 1 } else { nil } }

    /// The first payments as the window shows them.
    var payments: [BankTxn] { Array((reading?.preview ?? []).prefix(Self.shownPayments)) }

    /// What this reading changes, in one short line; none for the first one shown, and none for a change without a
    /// plain sentence.
    var change: String? {
        guard case let .reading(index) = step, index > 0, let reading else { return nil }
        return FileCheckWording.change(reading.reason)
    }

    /// Yes: the reading's layout is saved and the file read again with it. Returns whether the window can close.
    func yes() async -> Bool {
        guard let reading, !isSaving else { return false }
        isSaving = true
        saveProblem = nil
        defer { isSaving = false }
        do {
            try await phone.saveLayout(reading.layout)
            imports.layoutConfirmed(request)
            return true
        } catch {
            saveProblem = error.localizedDescription
            return false
        }
    }

    /// No: the next reading, or after the last one the column check.
    func no() {
        guard case let .reading(index) = step, !isSaving else { return }
        saveProblem = nil
        if readings.indices.contains(index + 1) { step = .reading(index + 1) } else { showColumns() }
    }

    /// Cancel: the file is not imported.
    func cancel() { imports.layoutSkipped(request) }

    private func showColumns() {
        if columns == nil { columns = ColumnCheckModel(request: request, phone: phone, imports: imports) }
        step = .columns
    }
}

/// The window's words that depend on the engine's answer (English here, German in the catalog).
nonisolated enum FileCheckWording {
    /// What a reading changes, as one short line under "Does this look right?"'s payments; nil when there is no plain
    /// sentence for it.
    static func change(_ reason: ReadingReason?, language: AppLanguage = .current) -> String? {
        switch reason {
        case .dateFormat: language.string("Day and month swapped")
        case .debitCredit, .invertSign: language.string("Money in and out swapped")
        case .counterpartyText: language.string("Name and payment text swapped")
        case .sign: language.string("Money in and out read another way")
        case .amount: language.string("Other amounts")
        case .counterparty: language.string("Other names")
        case .valueDate: language.string("The file's other date")
        case .other, nil: nil
        }
    }
}
