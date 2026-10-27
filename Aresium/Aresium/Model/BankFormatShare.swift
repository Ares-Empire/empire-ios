import CryptoKit
import Foundation
import Observation
import os

// Sending an unknown bank's format to us (brief 23), so Aresium learns that bank for everyone with the next update.
// Only the format goes out: the layout the person confirmed, as the engine's `shareableLayout` gives it (separator,
// column names, which column means what, date and number style), with the bank's name they type, the app's version
// and language. Never a payment, an amount, an IBAN or a name; no account and no token. The inbox is the account
// server's `bank_formats` collection (ares-empire/docs/ACCOUNTS.md → Bank formats shared from Aresium); the way there
// (one try, then kept and sent by itself later) is the outbox both kinds share, `BankOutbox.swift`.

/// A confirmed unknown bank's format that may be sent (`shareableLayout` said ok).
nonisolated struct BankFormat: Equatable, Sendable {
    /// The layout as `shareableLayout` gave it: exactly what goes out.
    let layout: CsvLayout
    /// Which confirmed layout it is (a hash of its separator and header, `PhoneLedger.layoutID`), so the result never
    /// asks twice about the same one.
    let key: String
    /// The bank's name from the file, when the engine has one: the name field's suggestion.
    var suggestion: String?

    /// The key of a confirmed layout: SHA-256 of its separator and header, so the file of what was asked holds no
    /// header text.
    static func key(of layout: CsvLayout) -> String {
        SHA256.hash(data: Data(PhoneLedger.layoutID(layout).utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

/// The request's body for `POST /api/collections/bank_formats/records`: the bank's name as typed (one line, at most
/// 100 characters), the format, the app's version ("1.0 (12)") and language ("en" or "de"). It is also what a format
/// waiting to be sent keeps on the phone.
nonisolated struct BankFormatSubmission: Codable, Equatable, Sendable {
    let bank: String
    let layout: CsvLayout
    let appVersion: String
    let language: String

    enum CodingKeys: String, CodingKey { case bank, layout, appVersion = "app_version", language }

    init(format: BankFormat, bank typed: String, appVersion: String, language: AppLanguage) throws(BankSubmission.Invalid) {
        let bank = BankSubmission.cleanBank(typed)
        guard !bank.isEmpty else { throw .noBank }
        self.bank = bank
        layout = format.layout
        self.appVersion = BankSubmission.cleanVersion(appVersion)
        self.language = language.code
    }
}

/// The result's quiet card: "Help Aresium learn your bank", the bank's name (the file's suggestion when there is one)
/// and Send; "What is sent?" shows the format (`SharedFormat`); Not now never asks again for this layout.
@MainActor @Observable
final class BankFormatCard: Identifiable {
    typealias Phase = BankSendPhase

    let id = UUID()
    let format: BankFormat
    var bank: String {
        didSet { if bank != oldValue { problem = nil } }
    }
    private(set) var phase: Phase = .asking
    /// Why the name was not sent (it looks like personal data, or the server refused it): shown under the field until
    /// the name changes.
    private(set) var problem: String?
    /// The result goes once the card is answered (`ImportStore`).
    @ObservationIgnored var onAnswered: (() -> Void)?
    @ObservationIgnored private let outbox: BankOutbox
    @ObservationIgnored private var submissionID: UUID?
    @ObservationIgnored private let language: () -> AppLanguage

    init(format: BankFormat, outbox: BankOutbox, language: @escaping () -> AppLanguage = { .current }) {
        self.format = format
        self.outbox = outbox
        self.language = language
        bank = format.suggestion ?? ""
    }

    /// What the card shows: its phase, or for a format kept for later, how sending it later went while the card is
    /// still on screen.
    var shown: Phase { outbox.shown(phase, submission: submissionID, refused: Self.refusedLine()) }

    var canSend: Bool { phase == .asking && !BankSubmission.cleanBank(bank).isEmpty }

    /// Exactly what Send sends, for "What is sent?".
    var shared: SharedFormat {
        SharedFormat(layout: format.layout, bank: BankSubmission.cleanBank(bank),
                     appVersion: BankSubmission.cleanVersion(outbox.appVersion), language: language())
    }

    /// Send: a name that looks like personal data stays on the phone with a plain line; otherwise the layout counts as
    /// asked and the format goes out (kept for later when it could not).
    func send() async {
        guard canSend else { return }
        let submission: BankFormatSubmission
        do {
            submission = try BankFormatSubmission(format: format, bank: bank, appVersion: outbox.appVersion,
                                                  language: language())
        } catch { return }
        phase = .sending
        problem = nil
        if await outbox.looksPersonal(submission.bank) {
            phase = .asking
            problem = BankSubmission.personalLine(language: language())
            return
        }
        outbox.markAsked(format.key)
        let (id, outcome) = await outbox.submit(.format(submission))
        submissionID = id
        (phase, problem) = BankSendPhase.after(outcome, refused: Self.refusedLine(language: language()))
        // The name to type again, or a refusal: the card stays until the person acts; the other answers go after the
        // result's pause.
        if phase == .asking { return }
        if case .refused = phase { return }
        onAnswered?()
    }

    /// Not now (or the result closed): never asks again for this layout. Nothing is sent.
    func notNow() {
        guard phase == .asking else { return }
        outbox.markAsked(format.key)
    }

    /// When the server refused without a sentence.
    static func refusedLine(language: AppLanguage = .current) -> String {
        language.string("The format was not accepted.")
    }

    #if DEBUG
    /// Screenshots only (`-formatPhase`): show a state without sending.
    func debugPhase(_ phase: Phase) { self.phase = phase }
    /// Screenshots only (`-formatPhase badName`): the server's line under the name.
    func debugProblem(_ problem: String) { self.problem = problem }
    #endif
}
