import Foundation

/// Which mode Aresium is in: phone mode (the default, no account needed: the data stays on this iPhone and the shared
/// engine computes there), or server mode for an account the Aresium server keeps the data of (`GET /api/mode`,
/// aresium/docs/API-DATA.md → Mode: Patrik's owner list).
nonisolated enum AresiumMode: String, Codable, Sendable {
    case server, phone
}

/// The login a request goes with: the token it sends (nil: none) and what to do when the server refuses it (401).
/// Phone mode needs neither.
struct BackendAuth {
    let token: String?
    var onUnauthorized: () -> Void = {}
}

/// After a Switch: the payment's new detail and, in phone mode, the question about the merchant's other payments.
struct SwitchResult {
    let detail: TransactionDetail
    var followUp: MerchantFollowUp?
}

/// The shop's other payments after Switch or an extras change. Switch moves eligible non-manual rows; extras
/// change only additions/removals, regardless of their primary source. `wording` is shared with selections.
struct MerchantFollowUp: Identifiable {
    let id = UUID()
    let shop: String
    let category: String
    let count: Int
    var added: [String] = []
    var removed: [String] = []
    let apply: () async throws -> Void

    var wording: CategoryQuestionWording {
        CategoryQuestionWording(count: count, selectedCount: 1, shopCount: 1, shop: shop, category: category,
                                added: added, removed: removed)
    }
}

/// How a batch of files is sent: the server takes requests of at most 25 MB; the phone reads them all in one go.
struct ImportPlan {
    let batches: [[ImportFile]]
    let refused: [ImportFile]
}

/// One file's result, in either mode.
enum ImportFileResult {
    case server(ImportResponse.Result)
    case phone(PhoneImportResult)

    var name: String {
        switch self {
        case let .server(result): result.name
        case let .phone(result): result.name
        }
    }

    /// The payments this file added.
    var added: Int {
        switch self {
        case let .server(result): result.added
        case let .phone(result): result.added
        }
    }

    /// The file could not be imported; it stays for Retry.
    var failed: Bool {
        switch self {
        case let .server(result): result.error?.isEmpty == false
        case let .phone(result): result.error?.isEmpty == false
        }
    }

    /// An unknown CSV layout the person confirms before the file is read (phone mode).
    var layoutGuess: LayoutGuess? {
        if case let .phone(result) = self { result.layout } else { nil }
    }

    /// The engine's readings of that unknown CSV (phone mode).
    var readings: [FileReading] {
        if case let .phone(result) = self { result.readings } else { [] }
    }

    /// A file read with a layout the person confirmed, whose format may be sent to us (phone mode).
    var bankFormat: BankFormat? {
        if case let .phone(result) = self { result.format } else { nil }
    }

    var displayMessage: String {
        switch self {
        case let .server(result): result.displayMessage
        case let .phone(result): result.displayMessage
        }
    }
}

/// Where Aresium's data comes from: the server (server mode, today's `APIClient`) or the phone's own store and engine
/// (phone mode). `DashboardStore`, `TransactionDetailStore` and `ImportStore` work through it and never know which.
/// Phone-only work (categories, learning, layouts, export, deleting) is `PhoneBackend`'s with `PhoneLedger`.
@MainActor
protocol AresiumBackend: AnyObject {
    var mode: AresiumMode { get }
    /// Whether requests can be made now: the server needs the login; the phone's store is there while it is open.
    func isReady(_ session: EmpireSession) -> Bool

    func dashboard(auth: BackendAuth) async throws -> Dashboard
    func transactionDetail(id: String, auth: BackendAuth) async throws -> TransactionDetail
    /// Switch: moves the payment to one category.
    func switchCategory(id: String, to category: String, auth: BackendAuth) async throws -> SwitchResult
    /// Add: also lists the payment under these categories; `dropCurrent` moves it out of its current one (the first
    /// becomes its category).
    func setTags(id: String, categories: [String], dropCurrent: Bool, auth: BackendAuth) async throws -> TransactionDetail

    /// The file extensions this mode can import (lower case).
    var importExtensions: Set<String> { get }
    func importPlan(_ files: [ImportFile], maximumBytes: Int) throws -> ImportPlan
    func importFiles(_ files: [ImportFile], auth: BackendAuth) async throws -> [ImportFileResult]
    /// The banner's line for a finished import.
    func importSummary(_ results: [ImportFileResult]) -> String
    /// Payments this mode imports wait for a category the person has not chosen yet (phone mode before any is ticked):
    /// the category picker opens after an import that added some (`ImportStore.asksForCategories`). The server sorts by
    /// itself.
    var waitsForCategories: Bool { get }
    /// An import's results as the store holds them now: phone mode counts each file's new payments as sorted or not
    /// again (the category picker sorts them after the import); the server's stay as they were.
    func recount(_ results: [ImportFileResult]) async throws -> [ImportFileResult]
}

/// Server mode: today's `APIClient` behind the interface, behaviour unchanged (aresium/docs/API-DATA.md).
final class ServerBackend: AresiumBackend {
    let client: APIClient

    init(client: APIClient = APIClient()) { self.client = client }

    var mode: AresiumMode { .server }
    func isReady(_ session: EmpireSession) -> Bool { session.isSignedIn && session.token != nil }

    func dashboard(auth: BackendAuth) async throws -> Dashboard {
        try await client.dashboard(token: try token(auth)) { auth.onUnauthorized() }
    }

    func transactionDetail(id: String, auth: BackendAuth) async throws -> TransactionDetail {
        try await client.transactionDetail(id: id, token: try token(auth)) { auth.onUnauthorized() }
    }

    func switchCategory(id: String, to category: String, auth: BackendAuth) async throws -> SwitchResult {
        SwitchResult(detail: try await client.switchCategory(id: id, category: category, token: try token(auth)) {
            auth.onUnauthorized()
        })
    }

    func setTags(id: String, categories: [String], dropCurrent: Bool, auth: BackendAuth) async throws -> TransactionDetail {
        try await client.setTransactionTags(id: id, categories: categories, dropCurrent: dropCurrent,
                                            token: try token(auth)) { auth.onUnauthorized() }
    }

    var importExtensions: Set<String> { ImportFileReader.serverExtensions }

    func importPlan(_ files: [ImportFile], maximumBytes: Int) throws -> ImportPlan {
        let plan = try ImportRequestPlan(files: files, maximumBytes: maximumBytes)
        return ImportPlan(batches: plan.batches, refused: plan.refused)
    }

    func importFiles(_ files: [ImportFile], auth: BackendAuth) async throws -> [ImportFileResult] {
        try await client.importFiles(files, token: try token(auth)) { auth.onUnauthorized() }.results.map { .server($0) }
    }

    func importSummary(_ results: [ImportFileResult]) -> String {
        ImportResponse(results: results.compactMap { if case let .server(result) = $0 { result } else { nil } }).summary
    }

    var waitsForCategories: Bool { false }
    func recount(_ results: [ImportFileResult]) async throws -> [ImportFileResult] { results }

    private func token(_ auth: BackendAuth) throws -> String {
        guard let token = auth.token else { throw HTTPError.unauthorized }
        return token
    }
}
