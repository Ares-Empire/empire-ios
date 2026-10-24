import Foundation
import Observation

/// One store for the app: the vault and its lookups, the edits, the quick notes waiting to be sent. Views read it and
/// call its actions; nothing here knows about views.
///
/// - **Offline first:** the last vault is loaded from disk at once (when it belongs to the saved login), then refreshed
///   at launch, in the foreground and on pull to refresh, with `If-None-Match` (304: nothing to download).
/// - **Edits** (one method per op of the contract) go to the server one at a time; each answer's vault replaces the
///   app's. 409: "changed elsewhere", and the vault is reloaded; 422: the server's reason; `pushed: false`: a note that
///   the edit reaches the laptops later.
/// - **Quick notes** are kept on the device first and sent when the server is reachable.
/// - Every request remembers the login it started with; answers that arrive after a logout are dropped. Failures go to
///   `EmpireSession.handleAuthFailure` (401 ends the login everywhere, 403 closes this app); the session then calls
///   `clear()` through `onAppDataReset`, which forgets the vault, the quick notes and the Spotlight entries.
@MainActor @Observable
final class VaultStore {
    struct Notice: Equatable, Identifiable {
        enum Tone: Equatable { case info, problem }
        let id = UUID()
        let text: String
        let tone: Tone
    }

    nonisolated enum EditOutcome: Equatable, Sendable {
        case applied
        case conflict                   // changed elsewhere; the vault was reloaded
        case invalid(String)            // the server's reason (422)
        case failed(String)
    }

    nonisolated enum QuickNoteOutcome: Equatable, Sendable {
        case sent
        case waiting                    // kept on the phone, sent once the server is reachable
        case empty
    }

    struct Failure: Error, Equatable { let message: String }

    let session: EmpireSession
    let isSample: Bool
    private let backend: any VaultBackend
    private let persistence: any VaultPersistence
    private let spotlight: any SpotlightIndexing
    /// The account of the login saved on the device (read once at launch, before the login is renewed).
    private let savedAccount: () -> String?

    // the vault
    private(set) var vault: Vault?
    private(set) var index = VaultIndex.empty
    private(set) var search = VaultSearch.empty
    private(set) var isRefreshing = false
    /// The last refresh failed for another reason than the connection.
    private(set) var loadError: String?
    /// The last attempt could not reach the server (or the account server): the vault shown may be old.
    private(set) var isOffline = false
    /// When the server last sent or confirmed the vault.
    private(set) var lastRefresh: Date?

    // edits and quick notes
    private(set) var operationsRunning = 0
    private(set) var pendingQuickNotes: [PendingQuickNote] = []
    private(set) var isFlushing = false

    /// The last thing worth saying about an edit, shown briefly over the tabs.
    private(set) var notice: Notice?

    private var etag: String?
    private var vaultAccount: String?
    private var resetGeneration = 0
    private var foregroundUpdating = false
    private var lastOperation: Task<Void, Never>?
    private var spotlightTask: Task<Void, Never>?

    init(session: EmpireSession, backend: any VaultBackend, persistence: any VaultPersistence,
         spotlight: any SpotlightIndexing, savedAccount: @escaping () -> String?, sample: Bool = false) {
        self.session = session
        self.backend = backend
        self.persistence = persistence
        self.spotlight = spotlight
        self.savedAccount = savedAccount
        #if DEBUG
        isSample = sample
        #else
        isSample = false
        #endif
        session.onAppDataReset { [weak self] in self?.clear() }
        loadFromDisk()
    }

    /// An edit or a quick note is on its way to the server.
    var isSending: Bool { operationsRunning > 0 }

    private var canAct: Bool { isSample || session.isSignedIn }

    /// The account requests are made with now.
    private var currentAccount: String? {
        isSample ? Self.sampleAccount : session.token.flatMap(EmpireToken.accountID)
    }

    static let sampleAccount = "sample"

    // MARK: - loading

    /// The vault and quick notes saved on the device, if they belong to the login saved on the device. Anything else
    /// is deleted (another account logged in, or every Empire app logged out, while this app was closed).
    private func loadFromDisk() {
        let account = isSample ? Self.sampleAccount : savedAccount()
        if let cached = persistence.loadVault() {
            guard cached.account == account else {
                try? persistence.deleteAll()
                return
            }
            apply(cached.vault, etag: cached.etag, account: cached.account, save: false, reindex: false)
        }
        pendingQuickNotes = persistence.loadQuickNotes()
    }

    /// Asks the server for the vault (`If-None-Match` with the ETag of the one shown), then sends waiting quick notes.
    func refresh() async {
        guard canAct, !isRefreshing else { return }
        isRefreshing = true
        let context = context
        defer { if isCurrent(context) { isRefreshing = false } }
        let account = currentAccount
        let sameAccount = vault != nil && account == vaultAccount
        do {
            let fetched = try await backend.vault(ifNoneMatch: sameAccount ? etag : nil)
            guard isCurrent(context) else { return }
            isOffline = false
            loadError = nil
            lastRefresh = .now
            if case let .fresh(vault, etag) = fetched {
                apply(vault, etag: etag, account: account)
            }
        } catch {
            guard isCurrent(context) else { return }
            session.handleAuthFailure(error, generation: context.session)
            guard isCurrent(context) else { return }
            if Self.isOffline(error) {
                isOffline = true
            } else {
                loadError = error.localizedDescription
            }
            return
        }
        isRefreshing = false
        await flushQuickNotes()
    }

    /// Brings the app up to date: after the launch's login restore, back in the foreground, on pull to refresh.
    /// - The login is renewed first when it is older than `renewAfter` or was left waiting for the account server (an
    ///   offline launch keeps showing the saved vault until then).
    /// - `minimumAge`: no request when the server confirmed the vault less than this ago (the foreground).
    /// - `renewsLogin`: false right after the launch restored the login itself.
    func update(now: Date = .now, minimumAge: TimeInterval? = nil, renewAfter: TimeInterval = 12 * 3600,
                renewsLogin: Bool = true) async {
        guard !foregroundUpdating else { return }
        foregroundUpdating = true
        // Not tied to the login it started with: renewing a waiting login starts a new session on purpose.
        defer { foregroundUpdating = false }
        if !isSample {
            guard !session.isBusy else { return }
            let renewalDue = session.lastRenewedAt.map { now.timeIntervalSince($0) > renewAfter } ?? true
            if renewsLogin, session.needsRestoreRetry || (session.isSignedIn && renewalDue) {
                await session.restore()
            }
            guard session.isSignedIn else {
                if session.needsRestoreRetry { isOffline = true }
                return
            }
        }
        if let minimumAge, vault != nil, !isOffline, let lastRefresh, now.timeIntervalSince(lastRefresh) < minimumAge {
            await flushQuickNotes()
            return
        }
        await refresh()
    }

    // MARK: - edits (one per op of API.md → Edits)

    /// Confirms a draft position (removes "(draft)").
    @discardableResult
    func confirmPosition(_ id: String, reportsFailure: Bool = true) async -> EditOutcome {
        await perform(.confirmPosition(position: id), reportsFailure: reportsFailure)
    }

    /// Same view, better words: no history entry.
    @discardableResult
    func rewordPosition(_ id: String, text: String, reportsFailure: Bool = true) async -> EditOutcome {
        await perform(.rewordPosition(position: id, text: text), reportsFailure: reportsFailure)
    }

    /// A changed view: the old sentence goes to "How my view changed" with why.
    @discardableResult
    func changePosition(_ id: String, text: String, why: String, reportsFailure: Bool = true) async -> EditOutcome {
        await perform(.changePosition(position: id, text: text, why: why), reportsFailure: reportsFailure)
    }

    /// No longer held: into the history with why, removed from the list (the server renumbers the rest).
    @discardableResult
    func dropPosition(_ id: String, why: String, reportsFailure: Bool = true) async -> EditOutcome {
        await perform(.dropPosition(position: id, why: why), reportsFailure: reportsFailure)
    }

    /// A new position on a topic overview, or on "Positions" (across topics).
    @discardableResult
    func addPosition(to note: String, text: String, evidence: [String], reportsFailure: Bool = true) async -> EditOutcome {
        await perform(.addPosition(note: note, text: text, evidence: evidence), reportsFailure: reportsFailure)
    }

    @discardableResult
    func setConfidence(_ confidence: Confidence, of note: String, reportsFailure: Bool = true) async -> EditOutcome {
        await perform(.setConfidence(note: note, confidence: confidence), reportsFailure: reportsFailure)
    }

    /// Patrik agrees with one of Claude's callouts: it becomes a normal paragraph. Names the note's version as shown.
    @discardableResult
    func adoptCallout(_ callout: Int, of note: String, reportsFailure: Bool = true) async -> EditOutcome {
        guard let version = index.note(note)?.version else { return .failed(Self.missingNote) }
        return await perform(.adoptCallout(note: note, callout: callout, version: version), reportsFailure: reportsFailure)
    }

    @discardableResult
    func dismissCallout(_ callout: Int, of note: String, reportsFailure: Bool = true) async -> EditOutcome {
        guard let version = index.note(note)?.version else { return .failed(Self.missingNote) }
        return await perform(.dismissCallout(note: note, callout: callout, version: version),
                             reportsFailure: reportsFailure)
    }

    /// The free editor: the whole body, against the version it was loaded at.
    @discardableResult
    func saveNote(_ note: String, markdown: String, version: String, reportsFailure: Bool = true) async -> EditOutcome {
        await perform(.editNote(note: note, version: version, markdown: markdown), reportsFailure: reportsFailure)
    }

    /// The note's body as Markdown, for the free editor.
    func source(of note: String) async -> Result<NoteSource, Failure> {
        guard canAct else { return .failure(Failure(message: unavailableMessage)) }
        let context = context
        do {
            let source = try await backend.source(note: note)
            guard isCurrent(context) else { return .failure(Failure(message: "")) }
            return .success(source)
        } catch {
            session.handleAuthFailure(error, generation: context.session)
            if Self.isOffline(error) {
                isOffline = true
                return .failure(Failure(message: Self.offlineMessage))
            }
            return .failure(Failure(message: error.localizedDescription))
        }
    }

    /// Sends one edit (after any edit or quick note already on its way) and swaps in the vault it returns.
    /// `reportsFailure`: false when the caller (a sheet) shows the failure itself; what the server says about a saved
    /// edit (`pushed: false`, warnings) is always shown.
    private func perform(_ edit: Edit, reportsFailure: Bool) async -> EditOutcome {
        guard canAct else {
            if reportsFailure { show(unavailableMessage, .problem) }
            return .failed(unavailableMessage)
        }
        let context = context
        let outcome = await serially { await self.send(edit, context: context) }
        guard isCurrent(context) else { return outcome }
        switch outcome {
        case .applied:
            break
        case .conflict:
            if reportsFailure { show(Self.changedElsewhere, .problem) }
            await refresh()
        case let .invalid(message), let .failed(message):
            if reportsFailure { show(message, .problem) }
        }
        await flushQuickNotes()
        return outcome
    }

    private func send(_ edit: Edit, context: Context) async -> EditOutcome {
        guard isCurrent(context) else { return .failed("") }
        do {
            let result = try await backend.send(edit)
            guard isCurrent(context) else { return .failed("") }
            accept(result)
            return .applied
        } catch VaultAPIError.conflict {
            return .conflict
        } catch let VaultAPIError.invalid(message) {
            return .invalid(message)
        } catch {
            session.handleAuthFailure(error, generation: context.session)
            guard isCurrent(context) else { return .failed("") }
            if Self.isOffline(error) {
                isOffline = true
                return .failed(Self.offlineMessage)
            }
            return .failed(error.localizedDescription)
        }
    }

    /// An edit's answer: its vault replaces the app's (it has no ETag, so the next refresh downloads the vault again).
    private func accept(_ result: EditResult) {
        apply(result.vault, etag: nil, account: currentAccount)
        isOffline = false
        if let text = Self.savedNotice(for: result) { show(text, .info) }
    }

    /// What to say about a saved edit: nothing, unless the push waits or the vault's check warned.
    static func savedNotice(for result: EditResult, language: AppLanguage = .current) -> String? {
        var parts: [String] = []
        if !result.pushed {
            parts.append(language.string("Saved. It reaches the laptops once the server can push it to GitHub."))
        }
        if !result.warnings.isEmpty {
            parts.append(language.string("The vault's check warns: \(result.warnings.joined(separator: "; "))"))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    // MARK: - quick notes

    /// A quick note for the Inbox, verbatim. Kept on the phone first, so nothing is lost offline; sent at once when the
    /// server is reachable.
    @discardableResult
    func addQuickNote(_ text: String, now: Date = .now) async -> QuickNoteOutcome {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .empty }
        let note = PendingQuickNote(text: text, created: now)
        pendingQuickNotes.append(note)
        saveQuickNotes()
        await flushQuickNotes()
        return pendingQuickNotes.contains { $0.id == note.id } ? .waiting : .sent
    }

    /// A quick note the server refused (or one Patrik no longer wants sent) is deleted from the phone.
    func deleteQuickNote(_ id: UUID) {
        pendingQuickNotes.removeAll { $0.id == id }
        saveQuickNotes()
    }

    /// Sends the waiting quick notes in order; stops at the first that cannot reach the server (tried again later).
    func flushQuickNotes() async {
        guard canAct, !isFlushing, pendingQuickNotes.contains(where: { $0.problem == nil }) else { return }
        isFlushing = true
        let context = context
        defer { if isCurrent(context) { isFlushing = false } }
        while isCurrent(context), canAct, let next = pendingQuickNotes.first(where: { $0.problem == nil }) {
            let done = await serially { await self.send(next, context: context) }
            if !done { break }
        }
    }

    /// True when the note left the queue (sent, or refused and kept aside); false: try again later.
    private func send(_ note: PendingQuickNote, context: Context) async -> Bool {
        guard isCurrent(context), canAct, pendingQuickNotes.contains(where: { $0.id == note.id }) else { return false }
        do {
            let result = try await backend.send(.quickNote(text: note.text))
            guard isCurrent(context) else { return false }
            pendingQuickNotes.removeAll { $0.id == note.id }
            saveQuickNotes()
            accept(result)
            return true
        } catch let VaultAPIError.invalid(message) {
            guard isCurrent(context) else { return false }
            if let index = pendingQuickNotes.firstIndex(where: { $0.id == note.id }) {
                pendingQuickNotes[index].problem = message
            }
            saveQuickNotes()
            show(String(localized: "A quick note was not saved: \(message)"), .problem)
            return true
        } catch {
            session.handleAuthFailure(error, generation: context.session)
            guard isCurrent(context) else { return false }
            if Self.isOffline(error) { isOffline = true }
            return false
        }
    }

    private func saveQuickNotes() {
        // Kept in memory regardless; a failed write only loses the queue if the app is closed before it is sent.
        try? persistence.saveQuickNotes(pendingQuickNotes)
    }

    // MARK: - notices

    func dismissNotice() { notice = nil }

    private func show(_ text: String, _ tone: Notice.Tone) { notice = Notice(text: text, tone: tone) }

    static var changedElsewhere: String {
        String(localized: "This changed elsewhere in the meantime. The app loaded the current version; please try again.")
    }

    static var offlineMessage: String {
        String(localized: "The server cannot be reached. Try again when you're online.")
    }

    private static var missingNote: String { String(localized: "This note is no longer in the vault.") }

    private var unavailableMessage: String {
        session.needsRestoreRetry ? Self.offlineMessage : String(localized: "Log in to change the vault.")
    }

    // MARK: - forgetting

    /// Everything this app knows about the account (logout, or this app denied): also on the disk and in Spotlight.
    func clear() {
        resetGeneration += 1
        vault = nil
        index = .empty
        search = .empty
        etag = nil
        vaultAccount = nil
        isRefreshing = false
        loadError = nil
        isOffline = false
        lastRefresh = nil
        pendingQuickNotes = []
        isFlushing = false
        foregroundUpdating = false
        notice = nil
        try? persistence.deleteAll()
        updateSpotlight(nil)
    }

    // MARK: - plumbing

    private func apply(_ vault: Vault, etag: String?, account: String?, save: Bool = true, reindex: Bool = true) {
        let changed = vault != self.vault
        self.vault = vault
        self.etag = etag
        vaultAccount = account
        if changed {
            index = VaultIndex(vault: vault)
            search = VaultSearch(vault: vault)
            if reindex { updateSpotlight(vault.notes) }
        }
        // A failed write only means the next launch starts without this vault.
        if save { try? persistence.saveVault(CachedVault(vault: vault, etag: etag, account: account)) }
    }

    /// Spotlight changes run in order, so a removal at logout is never overtaken by an earlier indexing.
    private func updateSpotlight(_ notes: [Note]?) {
        let previous = spotlightTask
        let spotlight = spotlight
        spotlightTask = Task {
            await previous?.value
            if let notes {
                try? await spotlight.replace(with: notes)
            } else {
                try? await spotlight.removeAll()
            }
        }
    }

    /// Waits until Spotlight has the latest change (tests).
    func spotlightSettled() async { await spotlightTask?.value }

    /// Edits and quick notes reach the server one at a time, in order, so every answer's vault is newer than the one
    /// before it.
    private func serially<T: Sendable>(_ operation: @escaping () async -> T) async -> T {
        let previous = lastOperation
        operationsRunning += 1
        let task = Task {
            await previous?.value
            return await operation()
        }
        lastOperation = Task { _ = await task.value }
        let result = await task.value
        operationsRunning -= 1
        return result
    }

    private struct Context { let session: Int; let reset: Int }
    private var context: Context { Context(session: session.generation, reset: resetGeneration) }
    private func isCurrent(_ context: Context) -> Bool {
        context.session == session.generation && context.reset == resetGeneration
    }

    /// The server could not be reached at all (no network, the connection dropped, the host not found or timed out).
    static func isOffline(_ error: Error) -> Bool {
        guard let error = error as? URLError else { return false }
        let codes: Set<URLError.Code> = [.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost,
                                         .cannotConnectToHost, .dnsLookupFailed, .internationalRoamingOff, .dataNotAllowed]
        return codes.contains(error.code)
    }
}
