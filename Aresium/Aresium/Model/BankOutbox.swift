import Foundation
import Observation
import os

// What Aresium sends us about banks, without an account: an unknown bank's format (brief 23, the import result's
// "Help Aresium learn your bank", `BankFormatShare.swift`) and the name of a bank the guide does not know (brief 25,
// "Tell us about your bank", `BankRequest.swift`). Both go to an open collection of the account server
// (ares-empire/docs/ACCOUNTS.md: `bank_formats`, `bank_requests`) without a token, and both take the same way: one try
// when the person taps Send, then kept in one small file and sent by itself later (`BankOutbox`). Never a payment, an
// amount, an IBAN or a person's name: a bank's name that looks like personal data is refused before it goes
// (`BankNameCheck`), and the server checks again.

/// One thing on its way to us: its request's body, and which collection takes it.
nonisolated enum BankSubmission: Equatable, Sendable {
    /// A confirmed unknown bank's format (`bank_formats`).
    case format(BankFormatSubmission)
    /// "Tell us about your bank": a bank the guide does not know (`bank_requests`).
    case request(BankRequestSubmission)

    enum Kind: String, Codable, Sendable {
        case format, request

        /// The account server's collection for this kind.
        var collection: String {
            switch self {
            case .format: "bank_formats"
            case .request: "bank_requests"
            }
        }
    }

    var kind: Kind {
        switch self {
        case .format: .format
        case .request: .request
        }
    }

    /// The bank's name as it is sent.
    var bank: String {
        switch self {
        case let .format(format): format.bank
        case let .request(request): request.bank
        }
    }

    /// "en" or "de": the request's `Accept-Language`, so a refusal comes in the language the person reads.
    var language: String {
        switch self {
        case let .format(format): format.language
        case let .request(request): request.language
        }
    }

    func body() throws -> Data {
        switch self {
        case let .format(format): try JSONEncoder().encode(format)
        case let .request(request): try JSONEncoder().encode(request)
        }
    }

    // MARK: the parts both kinds share

    /// No name typed (only spaces and line breaks).
    enum Invalid: Error, Equatable { case noBank }

    /// The server's limits for the bank's name and the app's version (the same in both collections).
    static let maxBankLength = 100
    static let maxVersionLength = 40

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

    /// The plain line under the name when it looks like personal data (it is not sent).
    static func personalLine(language: AppLanguage = .current) -> String {
        language.string("Only the bank's name, please: no account number, IBAN, email, date or amount.")
    }
}

/// How one sending went.
nonisolated enum BankSendOutcome: Equatable, Sendable {
    /// The server took it.
    case sent
    /// A 400: the server refused it (its sentence, in the request's language). Final: never sent again.
    case refused(String?)
    /// A 400 about the bank's name only (`data.bank`, e.g. "Type only the bank's name."): never sent again by itself,
    /// but a card or form still on screen lets the person type the name again.
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

/// What the format card and the request form show: the question, sending, and how it went.
nonisolated enum BankSendPhase: Equatable, Sendable {
    case asking, sending, sent
    /// Not sent yet (no connection, a server error, too many): it goes by itself later.
    case kept
    /// The server refused it (a 400): its sentence.
    case refused(String)

    /// After the person's Send: the phase, and the line under the name when the server refused only the name (the
    /// person can type it again). `refused` is the line for a refusal without the server's sentence.
    static func after(_ outcome: BankSendOutcome, refused: String) -> (phase: BankSendPhase, problem: String?) {
        switch outcome {
        case .sent: (.sent, nil)
        case let .refused(message): (.refused(message ?? refused), nil)
        case let .badName(message): (.asking, message ?? refused)
        case .offline, .failed, .tooMany: (.kept, nil)
        }
    }
}

/// The account server's open inboxes for formats and bank requests. No `Authorization` (no account needed), the
/// request's own language in `Accept-Language`.
struct BankOutboxAPI {
    var transport: any HTTPTransport = URLSessionTransport()
    static let collections = URL(string: "https://auth.ares-empire.de/api/collections/")!

    static func url(_ kind: BankSubmission.Kind) -> URL {
        collections.appending(path: "\(kind.collection)/records")
    }

    func request(_ submission: BankSubmission) throws -> URLRequest {
        var request = URLRequest(url: Self.url(submission.kind))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(submission.language, forHTTPHeaderField: "Accept-Language")
        request.httpBody = try submission.body()
        request.timeoutInterval = 30
        return request
    }

    func send(_ submission: BankSubmission) async -> BankSendOutcome {
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

/// Whether a bank's name as typed looks like personal data (an IBAN, an email address, a date, an amount, a long
/// number), by the engine's own rule (`AresiumEngine.personalData`): the one its format check, `shareableLayout`,
/// applies to a format's words, so the app has one rule for both. The engine is loaded the first time a name is
/// checked. If it cannot run, the name passes: the server checks every name again.
@MainActor
final class BankNameCheck {
    private let makeEngine: @Sendable () throws -> AresiumEngine
    private var engine: AresiumEngine?
    private static let log = Logger(subsystem: "de.ares-empire.aresium", category: "formats")

    init(makeEngine: @escaping @Sendable () throws -> AresiumEngine = { try AresiumEngine.bundled() }) {
        self.makeEngine = makeEngine
    }

    func looksPersonal(_ name: String) async -> Bool {
        do {
            let engine = try await loaded()
            return try await engine.personalData(in: name) != nil
        } catch {
            Self.log.error("a bank's name could not be checked: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    private func loaded() async throws -> AresiumEngine {
        if let engine { return engine }
        let make = makeEngine
        // Off the main actor: loading the bundle takes a moment.
        let made = try await Task.detached { try make() }.value
        engine = made
        return made
    }
}

/// Formats and bank requests on their way to us, and the format layouts already asked about. One per app
/// (`ContentView`).
///
/// - Sending: the person's Send tries once at once. Without a connection, or after a server error, it is kept in a small
///   file (`PhoneStorage.bankOutboxURL`: only the request's body and how many tries failed) and sent by itself at the
///   next start or return to the foreground (`sendWaiting`), at most 3 tries in all (a try without a connection does
///   not count). A 400 is final: it is dropped (a card or form still on screen shows the server's sentence, `finished`).
///   A 429 waits for the next start. The same for both kinds.
/// - Asking (formats only): the result offers a format only once per confirmed layout; Send, Not now and closing the
///   result all count.
/// - The file goes with Aresium's data (`PhoneStorage.delete`): a format or a bank's name not sent yet names the
///   person's bank.
/// - Sample mode only pretends: a short pause, then "sent"; nothing is written or sent.
@MainActor @Observable
final class BankOutbox {
    /// What became of things sent in this run, by submission: a card or form still on screen shows the final answer of
    /// one it kept for later.
    private(set) var finished: [UUID: BankSendOutcome] = [:]

    @ObservationIgnored private let file: URL?
    @ObservationIgnored private let api: BankOutboxAPI
    @ObservationIgnored let appVersion: String
    @ObservationIgnored private let names: BankNameCheck
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let sampleDelay: Duration
    /// Sample mode: what was asked, in memory only.
    @ObservationIgnored private var sampleAsked: Set<String> = []
    @ObservationIgnored private var isSending = false
    @ObservationIgnored private var lastRound: Date?
    /// A 429 came: nothing more is sent until the next start (a new outbox).
    @ObservationIgnored private(set) var waitsForNextStart = false

    /// At most this many tries per submission (the first, from Send, included).
    static let maximumTries = 3
    /// The start and the first foreground come together: one round of sending covers both.
    static let roundInterval: TimeInterval = 60

    private static let log = Logger(subsystem: "de.ares-empire.aresium", category: "formats")

    /// - Parameter file: where waiting submissions and the asked layouts are kept; nil only for the sample.
    init(file: URL?, api: BankOutboxAPI = BankOutboxAPI(),
         appVersion: String = SupportDevice.appVersion(Bundle.main.infoDictionary),
         names: BankNameCheck = BankNameCheck(), now: @escaping () -> Date = Date.init,
         sampleDelay: Duration = .seconds(1.2)) {
        self.file = file
        self.api = api
        self.appVersion = appVersion
        self.names = names
        self.now = now
        self.sampleDelay = sampleDelay
    }

    /// Sample mode (and the app while tests run): pretends, writes nothing, sends nothing.
    static func sample(sampleDelay: Duration = .seconds(1.2)) -> BankOutbox {
        BankOutbox(file: nil, sampleDelay: sampleDelay)
    }

    var isSample: Bool { file == nil }

    // MARK: asking (formats)

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

    /// Whether a typed bank's name looks like personal data (checked before Send sends anything).
    func looksPersonal(_ bank: String) async -> Bool {
        await names.looksPersonal(BankSubmission.cleanBank(bank))
    }

    /// The person's Send: it goes out at once, and is kept for later when it could not. Returns the submission's id (for
    /// `finished`) and how this first try went.
    func submit(_ submission: BankSubmission) async -> (id: UUID, outcome: BankSendOutcome) {
        let id = UUID()
        if isSample {
            try? await Task.sleep(for: sampleDelay)
            return (id, .sent)
        }
        let outcome = await api.send(submission)
        Self.log.notice("sending a bank \(submission.kind.rawValue, privacy: .public): \(outcome.name, privacy: .public)")
        switch outcome {
        case .sent, .refused:
            finished[id] = outcome
        case .badName:
            break                                   // the card or form asks for the name again
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

    /// What a card or form shows: its own phase, or, for one it kept for later, how sending it later went while it is
    /// still on screen. `refused` is the line for a refusal without the server's sentence.
    func shown(_ phase: BankSendPhase, submission id: UUID?, refused: String) -> BankSendPhase {
        guard phase == .kept, let id, let outcome = finished[id] else { return phase }
        switch outcome {
        case .sent: return .sent
        case let .refused(message): return .refused(message ?? refused)
        default: return phase
        }
    }

    /// At the start and on every return to the foreground: sends what was kept for later, one after the other. Stops
    /// at the first one without a connection or with a 429 (that one waits for the next start).
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
            Self.log.notice("sending a waiting bank \(item.submission.kind.rawValue, privacy: .public) again: \(outcome.name, privacy: .public)")
            switch outcome {
            case .sent, .refused:
                finished[item.id] = outcome
                update(item.id) { _ in nil }
            case let .badName(message):
                finished[item.id] = .refused(message)       // final here: the card or form that sent it may be gone
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

    /// What is waiting to be sent (tests, and nothing else reads them).
    var waiting: [Waiting] { isSample ? [] : load().waiting }

    // MARK: the file

    /// Something kept for later: the request's body and how many tries failed so far. In the file as `{id, tries,
    /// kind, submission}`; an entry without `kind` was written by brief 23's build, which kept only formats.
    nonisolated struct Waiting: Codable, Equatable, Sendable {
        let id: UUID
        var tries: Int
        let submission: BankSubmission

        init(id: UUID, tries: Int, submission: BankSubmission) {
            self.id = id
            self.tries = tries
            self.submission = submission
        }

        private enum CodingKeys: String, CodingKey { case id, tries, kind, submission }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(UUID.self, forKey: .id)
            tries = try container.decode(Int.self, forKey: .tries)
            switch try container.decodeIfPresent(BankSubmission.Kind.self, forKey: .kind) ?? .format {
            case .format: submission = .format(try container.decode(BankFormatSubmission.self, forKey: .submission))
            case .request: submission = .request(try container.decode(BankRequestSubmission.self, forKey: .submission))
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(tries, forKey: .tries)
            try container.encode(submission.kind, forKey: .kind)
            switch submission {
            case let .format(format): try container.encode(format, forKey: .submission)
            case let .request(request): try container.encode(request, forKey: .submission)
            }
        }
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

    /// Changes (or, with nil, removes) one kept submission, read fresh from the file: one deleted meanwhile (Settings →
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
            Self.log.error("the bank outbox file did not read; starting empty")
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
            Self.log.error("the bank outbox file was not written: \(String(describing: error), privacy: .public)")
        }
    }
}
