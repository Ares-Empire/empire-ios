import Foundation

/// Which mode an account uses (`GET /api/mode`, aresium/docs/API-DATA.md → Mode): Patrik's accounts keep their data on
/// the server; everyone else's stays on their iPhone and the shared engine computes there.
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

/// "Also the N other payments from <shop>?": asked once after a Switch in phone mode, when other payments of the same
/// merchant were not set by hand. `apply` moves them.
struct MerchantFollowUp: Identifiable {
    let id = UUID()
    let shop: String
    let category: String
    let count: Int
    let apply: () async throws -> Void
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
    /// Phone mode: the account whose store this is (the widget snapshot names it). Server mode: nil (the session's).
    var account: String? { get }
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
}

/// Server mode: today's `APIClient` behind the interface, behaviour unchanged (aresium/docs/API-DATA.md).
final class ServerBackend: AresiumBackend {
    let client: APIClient

    init(client: APIClient = APIClient()) { self.client = client }

    var mode: AresiumMode { .server }
    var account: String? { nil }
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

    private func token(_ auth: BackendAuth) throws -> String {
        guard let token = auth.token else { throw HTTPError.unauthorized }
        return token
    }
}
