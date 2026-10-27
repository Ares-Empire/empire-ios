import Foundation
import Observation

// "My bank is missing" (brief 25): when the guide does not know someone's bank, they can tell us its name in two taps
// (Tell us about your bank, then Send; the name is what they searched for). Only the name goes, with the app's version
// and language; no account and no token. The inbox is the account server's `bank_requests` collection (brief 26,
// ares-empire/docs/ACCOUNTS.md), the way there the outbox the bank formats use (`BankOutbox`). The look is
// `Screens/BankRequestView.swift`.

/// The request's body for `POST /api/collections/bank_requests/records`: the bank's name as typed (one line, at most
/// 100 characters), the app's version ("1.0 (12)") and language ("en" or "de"). It is also what a request waiting to be
/// sent keeps on the phone.
nonisolated struct BankRequestSubmission: Codable, Equatable, Sendable {
    let bank: String
    let appVersion: String
    let language: String

    enum CodingKeys: String, CodingKey { case bank, appVersion = "app_version", language }

    init(bank typed: String, appVersion: String, language: AppLanguage) throws(BankSubmission.Invalid) {
        let bank = BankSubmission.cleanBank(typed)
        guard !bank.isEmpty else { throw .noBank }
        self.bank = bank
        self.appVersion = BankSubmission.cleanVersion(appVersion)
        self.language = language.code
    }
}

/// "Tell us about your bank": the bank's name (prefilled with what the person searched for) and Send; then how it went.
/// A name that looks like personal data is not sent (a plain line under it); offline, a server error or too many: kept
/// and sent by itself later, as the formats are.
@MainActor @Observable
final class BankRequestForm {
    typealias Phase = BankSendPhase

    var bank: String {
        didSet { if bank != oldValue { problem = nil } }
    }
    private(set) var phase: Phase = .asking
    /// Why the name was not sent (it looks like personal data, or the server refused it): shown under the field until
    /// the name changes.
    private(set) var problem: String?
    @ObservationIgnored private let outbox: BankOutbox
    @ObservationIgnored private var submissionID: UUID?
    @ObservationIgnored private let language: () -> AppLanguage

    init(bank: String, outbox: BankOutbox, language: @escaping () -> AppLanguage = { .current }) {
        self.bank = bank
        self.outbox = outbox
        self.language = language
    }

    /// What the form shows: its phase, or for a request kept for later, how sending it later went while the form is
    /// still on screen.
    var shown: Phase { outbox.shown(phase, submission: submissionID, refused: Self.refusedLine()) }

    var canSend: Bool { phase == .asking && !BankSubmission.cleanBank(bank).isEmpty }

    func send() async {
        guard canSend else { return }
        let submission: BankRequestSubmission
        do {
            submission = try BankRequestSubmission(bank: bank, appVersion: outbox.appVersion, language: language())
        } catch { return }
        phase = .sending
        problem = nil
        if await outbox.looksPersonal(submission.bank) {
            phase = .asking
            problem = BankSubmission.personalLine(language: language())
            return
        }
        let (id, outcome) = await outbox.submit(.request(submission))
        submissionID = id
        (phase, problem) = BankSendPhase.after(outcome, refused: Self.refusedLine(language: language()))
    }

    /// When the server refused without a sentence.
    static func refusedLine(language: AppLanguage = .current) -> String {
        language.string("The name was not accepted.")
    }

    #if DEBUG
    /// Screenshots only (`-bankRequestPhase`): show a state without sending.
    func debugPhase(_ phase: Phase) { self.phase = phase }
    /// Screenshots only (`-bankRequestPhase personal`): the line under the name.
    func debugProblem(_ problem: String) { self.problem = problem }
    #endif
}
