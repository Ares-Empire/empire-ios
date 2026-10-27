import CryptoKit
import Foundation
import Observation
import os

// Sending an unknown bank's format to us (brief 23), so Aresium learns that bank for everyone with the next update.
// Only the format goes out: the layout the person confirmed, as the engine's `shareableLayout` gives it (separator,
// column names, which column means what, date and number style), with the bank's name they type, the app's version
// and language. Never a payment, an amount, an IBAN or a name; no account and no token. The inbox is the account
// server's `bank_formats` collection (ares-empire/docs/ACCOUNTS.md → Bank formats shared from Aresium).

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

    /// The server's limits (accounts/pb_migrations/1793500000_bank_formats.js).
    static let maxBankLength = 100
    static let maxVersionLength = 40

    enum Invalid: Error, Equatable { case noBank }

    init(format: BankFormat, bank typed: String, appVersion: String, language: AppLanguage) throws(Invalid) {
        let bank = Self.cleanBank(typed)
        guard !bank.isEmpty else { throw .noBank }
        self.bank = bank
        layout = format.layout
        self.appVersion = Self.cleanVersion(appVersion)
        self.language = language.code
    }

    /// The name as it is sent: one line (line breaks and runs of spaces become one space), trimmed, at most 100
    /// characters.
    static func cleanBank(_ typed: String) -> String {
        let words = typed.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).joined(separator: " ")
        return String(words.prefix(maxBankLength)).trimmingCharacters(in: .whitespaces)
    }

    /// Only the characters the server takes in a version (letters, digits, space and `.()+_-`), at most 40.
    static func cleanVersion(_ version: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 .()+_-")
        return String(String(version.unicodeScalars.filter(allowed.contains)).prefix(maxVersionLength))
    }
}

/// How one sending went.
nonisolated enum BankFormatOutcome: Equatable, Sendable {
    /// The server took it.
    case sent
    /// A 400: the server refused this format (its sentence, in the request's language). Final: never sent again.
    case refused(String?)
    /// A 400 about the bank's name only ("Type only the bank's name."): never sent again by itself, but a card still
    /// on screen lets the person type the name again.
    case badName(String?)
    /// A 429: too many from this address for now. Sent again at the next start.
    case tooMany
    /// No connection: sent again later; does not count as a try.
    case offline
    /// A server error or another failure: counts as a try.
    case failed

    /// For the device log: the kind only, never the server's sentence.
    var name: String {
        switch self {
        case .sent: "sent"
        case .refused: "refused"
        case .badName: "badName"
        case .tooMany: "tooMany"
        case .offline: "offline"
        case .failed: "failed"
        }
    }
}

/// The account server's `bank_formats` inbox. No `Authorization` (no account needed), the request's own language in
/// `Accept-Language`, so a refusal's sentence comes in the language the person reads.
struct BankFormatAPI {
    var transport: any HTTPTransport = URLSessionTransport()
    static let url = URL(string: "https://auth.ares-empire.de/api/collections/bank_formats/records")!

    func request(_ submission: BankFormatSubmission) throws -> URLRequest {
        var request = URLRequest(url: Self.url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(submission.language, forHTTPHeaderField: "Accept-Language")
        request.httpBody = try JSONEncoder().encode(submission)
        request.timeoutInterval = 30
        return request
    }

    func send(_ submission: BankFormatSubmission) async -> BankFormatOutcome {
        do {
            let (data, response) = try await transport.send(try request(submission))
            switch response.statusCode {
            case 200..<300: return .sent
            case 400:
                let sentence = (try? JSONDecoder().decode(ServerMessage.self, from: data))?.sentence
                return SupportAPI.refusedFields(data) == ["bank"] ? .badName(sentence) : .refused(sentence)
            case 429: return .tooMany
            default: return .failed
            }
        } catch let error as URLError where Self.noConnection.contains(error.code) {
            return .offline
        } catch {
            return .failed
        }
    }

    /// Failures that mean the phone had no way to the server (a slow answer, `timedOut`, counts as a try).
    private static let noConnection: Set<URLError.Code> = [
        .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed,
        .dataNotAllowed, .internationalRoamingOff, .callIsActive,
    ]
}

/// Bank formats on their way to us, and the layouts already asked about. One per app (`ContentView`).
///
/// - Sending: the person's Send tries once at once. Without a connection, or after a server error, the format is kept
///   in a small file (`PhoneStorage.bankFormatsURL`: only the request's body, `BankFormatSubmission`, and how many tries
///   failed) and sent by itself at the next start or return to the foreground (`sendWaiting`), at most 3 tries in all
///   (a try without a connection does not count). A 400 is final: the format is dropped (a card still on screen shows
///   the server's sentence, `finished`). A 429 waits for the next start.
/// - Asking: the result offers a format only once per confirmed layout; Send, Not now and closing the result all count.
/// - Sample mode only pretends: a short pause, then "sent"; nothing is written or sent.
@MainActor @Observable
final class BankFormatOutbox {
    /// What became of formats sent in this run, by submission: a card still on screen shows the final answer of one it
    /// kept for later.
    private(set) var finished: [UUID: BankFormatOutcome] = [:]

    @ObservationIgnored private let file: URL?
    @ObservationIgnored private let api: BankFormatAPI
    @ObservationIgnored let appVersion: String
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let sampleDelay: Duration
    /// Sample mode: what was asked, in memory only.
    @ObservationIgnored private var sampleAsked: Set<String> = []
    @ObservationIgnored private var isSending = false
    @ObservationIgnored private var lastRound: Date?
    /// A 429 came: nothing more is sent until the next start (a new outbox).
    @ObservationIgnored private(set) var waitsForNextStart = false

    /// At most this many tries per format (the first, from the card, included).
    static let maximumTries = 3
    /// The start and the first foreground come together: one round of sending covers both.
    static let roundInterval: TimeInterval = 60

    private static let log = Logger(subsystem: "de.ares-empire.aresium", category: "formats")

    /// - Parameter file: where formats waiting to be sent and the asked layouts are kept; nil only for the sample.
    init(file: URL?, api: BankFormatAPI = BankFormatAPI(),
         appVersion: String = SupportDevice.appVersion(Bundle.main.infoDictionary), now: @escaping () -> Date = Date.init,
         sampleDelay: Duration = .seconds(1.2)) {
        self.file = file
        self.api = api
        self.appVersion = appVersion
        self.now = now
        self.sampleDelay = sampleDelay
    }

    /// Sample mode (and the app while tests run): pretends, writes nothing, sends nothing.
    static func sample(sampleDelay: Duration = .seconds(1.2)) -> BankFormatOutbox {
        BankFormatOutbox(file: nil, sampleDelay: sampleDelay)
    }

    var isSample: Bool { file == nil }

    // MARK: asking

    func hasAsked(_ key: String) -> Bool {
        isSample ? sampleAsked.contains(key) : load().asked.contains(key)
    }

    /// Never offers this layout again.
    func markAsked(_ key: String) {
        if isSample { sampleAsked.insert(key); return }
        var saved = load()
        guard !saved.asked.contains(key) else { return }
        saved.asked.append(key)
        save(saved)
    }

    /// The send card for the first of these formats not asked about yet; nil when there is none.
    func card(for formats: [BankFormat]) -> BankFormatCard? {
        guard let format = formats.first(where: { !hasAsked($0.key) }) else { return nil }
        return BankFormatCard(format: format, outbox: self)
    }

    // MARK: sending

    /// The person's Send: the layout counts as asked, and the format goes out at once; kept for later when it could not.
    /// Returns the submission's id (for `finished`) and how this first try went.
    func submit(_ submission: BankFormatSubmission, key: String) async -> (id: UUID, outcome: BankFormatOutcome) {
        markAsked(key)
        let id = UUID()
        if isSample {
            try? await Task.sleep(for: sampleDelay)
            return (id, .sent)
        }
        let outcome = await api.send(submission)
        Self.log.notice("sending a bank format: \(outcome.name, privacy: .public)")
        switch outcome {
        case .sent, .refused:
            finished[id] = outcome
        case .badName:
            break                                   // the card asks for the name again
        case .offline:
            keep(Waiting(id: id, tries: 0, submission: submission))
        case .failed:
            keep(Waiting(id: id, tries: 1, submission: submission))
        case .tooMany:
            waitsForNextStart = true
            keep(Waiting(id: id, tries: 0, submission: submission))
        }
        return (id, outcome)
    }

    /// At the start and on every return to the foreground: sends the formats kept for later, one after the other.
    /// Stops at the first one without a connection or with a 429 (that one waits for the next start).
    func sendWaiting() async {
        guard !isSample, !isSending, !waitsForNextStart else { return }
        if let lastRound, now().timeIntervalSince(lastRound) < Self.roundInterval { return }
        let waiting = load().waiting
        guard !waiting.isEmpty else { return }
        isSending = true
        lastRound = now()
        defer { isSending = false }
        for item in waiting {
            let outcome = await api.send(item.submission)
            Self.log.notice("sending a waiting bank format again: \(outcome.name, privacy: .public)")
            switch outcome {
            case .sent, .refused:
                finished[item.id] = outcome
                update(item.id) { _ in nil }
            case let .badName(message):
                finished[item.id] = .refused(message)       // final here: the card that sent it may be gone
                update(item.id) { _ in nil }
            case .failed:
                update(item.id) { item in
                    let tries = item.tries + 1
                    return tries >= Self.maximumTries ? nil : Waiting(id: item.id, tries: tries, submission: item.submission)
                }
            case .offline:
                return
            case .tooMany:
                waitsForNextStart = true
                return
            }
        }
    }

    /// The formats waiting to be sent (tests, and nothing else reads them).
    var waiting: [Waiting] { isSample ? [] : load().waiting }

    // MARK: the file

    /// A format kept for later: the request's body and how many tries failed so far.
    nonisolated struct Waiting: Codable, Equatable, Sendable {
        let id: UUID
        var tries: Int
        let submission: BankFormatSubmission
    }

    private nonisolated struct Saved: Codable, Equatable {
        var asked: [String] = []
        var waiting: [Waiting] = []
    }

    private func keep(_ item: Waiting) {
        var saved = load()
        saved.waiting.append(item)
        save(saved)
    }

    /// Changes (or, with nil, removes) one kept format, read fresh from the file: one deleted meanwhile (Settings →
    /// Delete Aresium data) stays deleted.
    private func update(_ id: UUID, _ change: (Waiting) -> Waiting?) {
        var saved = load()
        guard let index = saved.waiting.firstIndex(where: { $0.id == id }) else { return }
        if let changed = change(saved.waiting[index]) { saved.waiting[index] = changed } else { saved.waiting.remove(at: index) }
        save(saved)
    }

    private func load() -> Saved {
        guard let file, let data = try? Data(contentsOf: file) else { return Saved() }
        do { return try JSONDecoder().decode(Saved.self, from: data) }
        catch {
            Self.log.error("the bank formats file did not read; starting empty")
            return Saved()
        }
    }

    private func save(_ saved: Saved) {
        guard let file else { return }
        do {
            if saved == Saved() {
                if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
                return
            }
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(saved).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            Self.log.error("the bank formats file was not written: \(String(describing: error), privacy: .public)")
        }
    }
}

/// The result's quiet card: "Help Aresium learn your bank", the bank's name (the file's suggestion when there is one)
/// and Send; "What is sent?" shows the format (`SharedFormat`); Not now never asks again for this layout.
@MainActor @Observable
final class BankFormatCard: Identifiable {
    enum Phase: Equatable {
        case asking, sending, sent
        /// Not sent yet (no connection, a server error, too many): it goes by itself later.
        case kept
        /// The server refused it (a 400): its sentence.
        case refused(String)
    }

    let id = UUID()
    let format: BankFormat
    var bank: String {
        didSet { if bank != oldValue { problem = nil } }
    }
    private(set) var phase: Phase = .asking
    /// The server refused the name as typed (its sentence): shown under the field until the name changes.
    private(set) var problem: String?
    /// The result goes once the card is answered (`ImportStore`).
    @ObservationIgnored var onAnswered: (() -> Void)?
    @ObservationIgnored private let outbox: BankFormatOutbox
    @ObservationIgnored private var submissionID: UUID?
    @ObservationIgnored private let language: () -> AppLanguage

    init(format: BankFormat, outbox: BankFormatOutbox, language: @escaping () -> AppLanguage = { .current }) {
        self.format = format
        self.outbox = outbox
        self.language = language
        bank = format.suggestion ?? ""
    }

    /// What the card shows: its phase, or for a format kept for later, how sending it later went while the card is
    /// still on screen.
    var shown: Phase {
        guard phase == .kept, let submissionID, let outcome = outbox.finished[submissionID] else { return phase }
        switch outcome {
        case .sent: return .sent
        case let .refused(message): return .refused(message ?? Self.refusedLine())
        default: return phase
        }
    }

    var canSend: Bool { phase == .asking && !BankFormatSubmission.cleanBank(bank).isEmpty }

    /// Exactly what Send sends, for "What is sent?".
    var shared: SharedFormat {
        SharedFormat(layout: format.layout, bank: BankFormatSubmission.cleanBank(bank),
                     appVersion: BankFormatSubmission.cleanVersion(outbox.appVersion), language: language())
    }

    func send() async {
        guard canSend else { return }
        let submission: BankFormatSubmission
        do {
            submission = try BankFormatSubmission(format: format, bank: bank, appVersion: outbox.appVersion,
                                                  language: language())
        } catch { return }
        phase = .sending
        problem = nil
        let (id, outcome) = await outbox.submit(submission, key: format.key)
        submissionID = id
        switch outcome {
        case .sent: phase = .sent
        case let .refused(message): phase = .refused(message ?? Self.refusedLine())
        case let .badName(message):
            phase = .asking
            problem = message ?? Self.refusedLine()
            return
        case .offline, .failed, .tooMany: phase = .kept
        }
        // A refusal stays until the person closes the result; the other answers go after the result's pause.
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
