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
/// - **Search:** the device's own (`search`, and `tabSearch` for the tabs' fields) at once; the server's passages by
///   words and meaning (`bestMatches`, `GET /search`) once typing pauses.
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
        case queued                     // durable on the phone; sending belongs to the store
        case failed(String)
        case empty
    }

    struct Failure: Error, Equatable { let message: String }

    let session: EmpireSession
    let isSample: Bool
    private let backend: any VaultBackend
    private let persistence: any VaultPersistence
    private let spotlight: any SpotlightIndexing
    private let worker: VaultWorker
    private let preparation: any VaultPreparing

    // the vault
    private(set) var vault: Vault?
    private(set) var index = VaultIndex.empty
    private(set) var search = VaultSearch.empty
    private(set) var tabSearch = TabSearch.empty
    /// The Search tab's best matches from the server.
    let bestMatches: BestMatches
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
    /// Also shown inside the quick-note sheet, which covers the tabs' notice.
    private(set) var quickNoteQueueProblem: String?
    private var quickNotesNeedSave = false
    // If the app is killed after the server accepts a note but before this queue is saved, it can be replayed on
    // restart. Exactly-once delivery would need the server to accept a note id.
    private var quickNotesMayReplay = false

    /// The last thing worth saying about an edit, shown briefly over the tabs.
    private(set) var notice: Notice?

    private var failedQuickNotes: Set<UUID> = []
    var waitingQuickNoteCount: Int {
        pendingQuickNotes.count { $0.needsConfirmation || ($0.problem == nil && failedQuickNotes.contains($0.id)) }
    }

    /// True while the vault saved on the phone is read at launch, off the main thread (a moment). The screen shows the
    /// launch wall meanwhile, so the launch goes straight from iOS's launch screen to the tabs.
    private(set) var isLoadingSaved = true
    private var loadingTask: Task<Void, Never>?
    private var quickNotesTask: Task<Void, Never>?
    private var flushID: UUID?
    private var backgroundTask: QuickNoteBackgroundTask?
    /// Advanced when an answer is accepted for preparation; refreshes remember the value before their request.
    private var vaultRevision = 0
    private var etag: String?
    private var vaultAccount: String?
    private var resetGeneration = 0
    private var foregroundUpdating = false
    private var lastOperation: Task<Void, Never>?
    private var spotlightTask: Task<Void, Never>?

    init(session: EmpireSession, backend: any VaultBackend, persistence: any VaultPersistence,
         spotlight: any SpotlightIndexing, savedAccount: @escaping () -> String?, sample: Bool = false,
         searchTiming: BestMatches.Timing = BestMatches.Timing(), preparation: (any VaultPreparing)? = nil) {
        self.session = session
        self.backend = backend
        self.persistence = persistence
        let worker = VaultWorker(persistence: persistence)
        self.worker = worker
        self.preparation = preparation ?? worker
        self.spotlight = spotlight
        #if DEBUG
        let sampleMode = sample
        #else
        let sampleMode = false
        #endif
        isSample = sampleMode
        bestMatches = BestMatches(timing: searchTiming) { [backend, session] query in
            try await Self.passages(for: query, backend: backend, session: session, sample: sampleMode)
        }
        session.onAppDataReset { [weak self] in self?.clear() }
        VaultTiming.measure("disk.load") {
            pendingQuickNotes = persistence.loadQuickNotes()
            let context = context
            let account = isSample ? Self.sampleAccount : savedAccount()
            let queuedOnLaunch = Set(pendingQuickNotes.map(\.id))
            loadingTask = Task {
                await self.loadFromDisk(account: account, context: context, queuedOnLaunch: queuedOnLaunch)
                self.isLoadingSaved = false
            }
        }
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
    /// is deleted (another account logged in, or every Empire app logged out, while this app was closed); so is a vault
    /// whose account cannot be told.
    private func loadFromDisk(account: String?, context: Context, queuedOnLaunch: Set<UUID>) async {
        let revision = vaultRevision
        let cached = await worker.load()
        guard isCurrent(context), revision == vaultRevision else { return }
        if let cached {
            guard let account, cached.account == account else {
                // Discard the old account's queue, preserving any new note queued during the asynchronous load.
                pendingQuickNotes.removeAll { queuedOnLaunch.contains($0.id) }
                failedQuickNotes.subtract(queuedOnLaunch)
                saveQuickNotes()
                worker.deleteVault()
                updateSpotlight(nil)
                await worker.settled()
                return
            }
            // Indexed when it was loaded, unless that was in the other language.
            await apply(cached.vault, etag: cached.etag, account: cached.account, context: context,
                        revision: revision, save: false, reindex: spotlight.language != AppLanguage.current)
        } else if account == nil {
            updateSpotlight(nil)
        }
    }

    /// Asks the server for the vault (`If-None-Match` with the ETag of the one shown), then sends waiting quick notes.
    func refresh() async {
        await loadingSettled()
        guard canAct, !isRefreshing else { return }
        isRefreshing = true
        let context = context
        defer { if isCurrent(context) { isRefreshing = false } }
        let revision = vaultRevision
        let account = currentAccount
        let sameAccount = vault != nil && account == vaultAccount
        let token = session.token           // what the request goes with (the API reads it before suspending)
        do {
            let fetched = try await backend.vault(ifNoneMatch: sameAccount ? etag : nil)
            guard isCurrent(context), revision == vaultRevision else { return }
            isOffline = false
            loadError = nil
            lastRefresh = .now
            if case let .fresh(vault, etag) = fetched {
                await apply(vault, etag: etag, account: account, context: context, revision: nextVaultRevision())
            }
        } catch {
            guard isCurrent(context) else { return }
            session.handleAuthFailure(error, generation: context.session, token: token)
            guard isCurrent(context), revision == vaultRevision else { return }
            if Self.isOffline(error) {
                isOffline = true
            } else {
                loadError = error.localizedDescription
            }
            return
        }
        guard isCurrent(context) else { return }
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
        await loadingSettled()
        guard !foregroundUpdating else { return }
        retryQuickNotesSave()
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

    // MARK: - search

    /// The server's passages for a query (`BestMatches` asks, and waits for nobody). A 401 or 403 ends the login or
    /// closes the app like every other request; any other failure only means no best matches: nothing is shown, and
    /// the offline state stays as the vault's requests left it. A logout cancels the request (`clear()`).
    private static func passages(for query: String, backend: any VaultBackend, session: EmpireSession,
                                 sample: Bool) async throws -> SearchAnswer {
        guard sample || session.isSignedIn else { throw CancellationError() }
        let generation = session.generation
        let token = session.token
        do {
            return try await backend.search(query, limit: BestMatches.asked)
        } catch {
            session.handleAuthFailure(error, generation: generation, token: token)
            throw error
        }
    }

    // MARK: - edits (one per op of API.md → Edits)

    /// Confirms a draft position (removes "(draft)").
    @discardableResult
    func confirmPosition(_ id: String, version: String, reportsFailure: Bool = true) async -> EditOutcome {
        await perform(.confirmPosition(position: id, version: version), reportsFailure: reportsFailure)
    }

    /// Same view, better words: no history entry.
    @discardableResult
    func rewordPosition(_ id: String, text: String, version: String, reportsFailure: Bool = true) async -> EditOutcome {
        await perform(.rewordPosition(position: id, text: text, version: version), reportsFailure: reportsFailure)
    }

    /// A changed view: the old sentence goes to "How my view changed" with why.
    @discardableResult
    func changePosition(_ id: String, text: String, why: String, version: String,
                        reportsFailure: Bool = true) async -> EditOutcome {
        await perform(.changePosition(position: id, text: text, why: why, version: version), reportsFailure: reportsFailure)
    }

    /// No longer held: into the history with why, removed from the list (the server renumbers the rest).
    @discardableResult
    func dropPosition(_ id: String, why: String, version: String,
                        reportsFailure: Bool = true) async -> EditOutcome {
        await perform(.dropPosition(position: id, why: why, version: version), reportsFailure: reportsFailure)
    }

    /// A new position on a topic overview, or on "Positions" (across topics).
    @discardableResult
    func addPosition(to note: String, text: String, evidence: [String], version: String,
                     reportsFailure: Bool = true) async -> EditOutcome {
        await perform(.addPosition(note: note, text: text, evidence: evidence, version: version), reportsFailure: reportsFailure)
    }

    @discardableResult
    func setConfidence(_ confidence: Confidence, of note: String, version: String,
                       reportsFailure: Bool = true) async -> EditOutcome {
        await perform(.setConfidence(note: note, confidence: confidence, version: version), reportsFailure: reportsFailure)
    }

    /// Patrik agrees with one of Claude's callouts: it becomes a normal paragraph. Names the note's version as shown.
    @discardableResult
    func adoptCallout(_ callout: Int, of note: String, version: String,
                       reportsFailure: Bool = true) async -> EditOutcome {
        await perform(.adoptCallout(note: note, callout: callout, version: version), reportsFailure: reportsFailure)
    }

    @discardableResult
    func dismissCallout(_ callout: Int, of note: String, version: String,
                       reportsFailure: Bool = true) async -> EditOutcome {
        await perform(.dismissCallout(note: note, callout: callout, version: version),
                             reportsFailure: reportsFailure)
    }

    /// The free editor: the whole body, against the version it was loaded at.
    @discardableResult
    func saveNote(_ note: String, markdown: String, version: String, reportsFailure: Bool = true) async -> EditOutcome {
        await perform(.editNote(note: note, version: version, markdown: markdown), reportsFailure: reportsFailure)
    }

    /// Ticks a "discuss later" mark (or any Inbox note) off, or opens it again.
    @discardableResult
    func setInboxStatus(of note: String, processed: Bool, version: String,
                        reportsFailure: Bool = true) async -> EditOutcome {
        await perform(.setInboxStatus(note: note, status: processed ? "processed" : "new", version: version),
                      reportsFailure: reportsFailure)
    }

    /// Offer the reverse edit only once the server has marked this very note as discussed.
    func markDiscussed(of note: String, version: String) async -> UndoOffer? {
        var savedVersion: String?
        let outcome = await perform(.setInboxStatus(note: note, status: "processed", version: version),
                                    reportsFailure: true) { result in
            savedVersion = result.vault.notes.first { $0.id == note }?.version
        }
        guard outcome == .applied, let savedVersion else { return nil }
        return UndoOffer(message: String(localized: "Marked as discussed.")) { [self] in
            await setInboxStatus(of: note, processed: false, version: savedVersion)
        }
    }

    /// One passage of a note (a paragraph, a list item, a quote) as Markdown, for editing it on its own. Loaded fresh;
    /// when the note changed since it was shown, its lines may have moved, so that counts as "changed elsewhere".
    func passage(of note: String, lines: LineRange) async -> Result<(text: String, source: NoteSource), Failure> {
        switch await source(of: note) {
        case let .failure(failure):
            return .failure(failure)
        case let .success(source):
            guard source.version == index.note(note)?.version, let text = Self.slice(source.markdown, lines) else {
                await refresh()
                return .failure(Failure(message: Self.changedElsewhere))
            }
            return .success((text, source))
        }
    }

    /// Saves an edited passage: the loaded body with exactly those lines replaced, against that body's version.
    @discardableResult
    func savePassage(_ text: String, of note: String, lines: LineRange, in source: NoteSource,
                     reportsFailure: Bool = true) async -> EditOutcome {
        guard let markdown = Self.replace(lines, in: source.markdown, with: text) else {
            return .failed(Self.changedElsewhere)
        }
        return await perform(.editNote(note: note, version: source.version, markdown: markdown),
                             reportsFailure: reportsFailure)
    }

    /// Lines `[start, end)` of a body; nil when the range does not fit it.
    nonisolated static func slice(_ markdown: String, _ lines: LineRange) -> String? {
        let all = markdown.components(separatedBy: "\n")
        guard lines.start >= 0, lines.start < lines.end, lines.end <= all.count else { return nil }
        return all[lines.start..<lines.end].joined(separator: "\n")
    }

    /// The body with lines `[start, end)` replaced by `text` (its own lines); nil when the range does not fit.
    nonisolated static func replace(_ lines: LineRange, in markdown: String, with text: String) -> String? {
        var all = markdown.components(separatedBy: "\n")
        guard lines.start >= 0, lines.start < lines.end, lines.end <= all.count else { return nil }
        let replacement = text.trimmingCharacters(in: .newlines).components(separatedBy: "\n")
        all.replaceSubrange(lines.start..<lines.end, with: replacement)
        return all.joined(separator: "\n")
    }

    /// The note's body as Markdown, for the free editor.
    func source(of note: String) async -> Result<NoteSource, Failure> {
        guard canAct else { return .failure(Failure(message: unavailableMessage)) }
        let context = context
        let token = session.token
        do {
            let source = try await backend.source(note: note)
            guard isCurrent(context) else { return .failure(Failure(message: "")) }
            return .success(source)
        } catch {
            session.handleAuthFailure(error, generation: context.session, token: token)
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
    private func perform(_ edit: Edit, reportsFailure: Bool, onApplied: ((EditResult) -> Void)? = nil) async -> EditOutcome {
        guard canAct else {
            if reportsFailure { show(unavailableMessage, .problem) }
            return .failed(unavailableMessage)
        }
        let context = context
        let outcome = await serially { await self.send(edit, context: context, onApplied: onApplied) }
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

    private func send(_ edit: Edit, context: Context, onApplied: ((EditResult) -> Void)?) async -> EditOutcome {
        guard isCurrent(context) else { return .failed("") }
        let token = session.token           // sent now, maybe well after the edit was queued
        do {
            let result = try await backend.send(edit)
            guard isCurrent(context) else { return .failed("") }
            onApplied?(result)
            await accept(result, context: context, revision: nextVaultRevision())
            return .applied
        } catch VaultAPIError.conflict {
            return .conflict
        } catch let VaultAPIError.invalid(message) {
            return .invalid(message)
        } catch {
            session.handleAuthFailure(error, generation: context.session, token: token)
            guard isCurrent(context) else { return .failed("") }
            if Self.isOffline(error) {
                isOffline = true
                return .failed(Self.offlineMessage)
            }
            return .failed(error.localizedDescription)
        }
    }

    /// An edit's answer: its vault replaces the app's (it has no ETag, so the next refresh downloads the vault again).
    private func accept(_ result: EditResult, context: Context, revision: Int) async {
        await apply(result.vault, etag: nil, account: currentAccount, context: context, revision: revision)
        guard isCurrent(context), revision == vaultRevision else { return }
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
    func queueQuickNote(_ text: String, about: String? = nil, kind: QuickNoteKind = .note, version: String? = nil,
                        now: Date = .now) -> QuickNoteOutcome {
        // A "discuss later" mark may come without words; a note needs some.
        guard kind == .discuss || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .empty }
        let note = PendingQuickNote(text: text, created: now, about: about, kind: kind, version: version)
        pendingQuickNotes.append(note)
        do {
            try persistQuickNotes(pendingQuickNotes)
        } catch {
            pendingQuickNotes.removeAll { $0.id == note.id }
            reportQueueWriteFailure(error.localizedDescription)
            return .failed(error.localizedDescription)
        }
        startQuickNotes()
        return .queued
    }

    /// The owner agreed to attach an older queued note to the version shown in the confirmation.
    @discardableResult
    func confirmQuickNote(_ id: UUID, version: String) -> Bool {
        guard let index = pendingQuickNotes.firstIndex(where: { $0.id == id }),
              pendingQuickNotes[index].needsConfirmation else { return false }
        var confirmed = pendingQuickNotes
        confirmed[index].version = version
        confirmed[index].problem = nil
        do {
            try persistQuickNotes(confirmed)
        } catch {
            reportQueueWriteFailure(String(localized: "This iPhone could not update its list of notes: \(error.localizedDescription)"))
            return false
        }
        pendingQuickNotes = confirmed
        startQuickNotes()
        return true
    }

    /// A quick note the server refused (or one Patrik no longer wants sent) is deleted from the phone.
    @discardableResult
    func deleteQuickNote(_ id: UUID) -> Bool {
        let remaining = pendingQuickNotes.filter { $0.id != id }
        do {
            try persistQuickNotes(remaining)
        } catch {
            reportQueueWriteFailure(String(localized: "This note could not be deleted on this iPhone: \(error.localizedDescription)"))
            return false
        }
        failedQuickNotes.remove(id)
        pendingQuickNotes = remaining
        return true
    }

    /// Starts a store-owned task. Its lifetime is independent of the sheet's task or dismissal.
    private func startQuickNotes() {
        guard quickNotesTask == nil else { return }
        let id = UUID()
        flushID = id
        // Ask synchronously, before Save returns and the user can leave the app.
        let hasReadyNotes = pendingQuickNotes.contains { $0.problem == nil && !$0.needsConfirmation }
        let background = canAct && hasReadyNotes ? QuickNoteBackgroundTask() : nil
        backgroundTask = background
        quickNotesTask = Task {
            defer {
                background?.end()
                if self.flushID == id {
                    self.quickNotesTask = nil
                    self.flushID = nil
                    self.backgroundTask = nil
                }
            }
            await self.runQuickNotes()
        }
    }

    /// Refreshes and other edits can wait for the very same flush; there is only one sender.
    func flushQuickNotes() async {
        startQuickNotes()
        await quickNotesTask?.value
    }

    func quickNotesSettled() async { await quickNotesTask?.value }
    func sendingSettled() async { await lastOperation?.value }

    /// Sends in order, stopping at a connection/server failure. Refused notes stay aside.
    private func runQuickNotes() async {
        await loadingSettled()
        guard !Task.isCancelled else { return }
        retryQuickNotesSave()
        guard !Task.isCancelled, !isFlushing,
              pendingQuickNotes.contains(where: { $0.problem == nil && !$0.needsConfirmation }) else { return }
        guard canAct else {
            if session.needsRestoreRetry {
                failedQuickNotes.formUnion(pendingQuickNotes.map(\.id))
                isOffline = true
            }
            return
        }
        isFlushing = true
        let context = context
        defer { if isCurrent(context) { isFlushing = false } }
        while !Task.isCancelled, isCurrent(context), canAct,
              let next = pendingQuickNotes.first(where: { $0.problem == nil && !$0.needsConfirmation }) {
            let done = await serially { await self.send(next, context: context) }
            if !done { break }
        }
    }

    /// True when the note left the queue (sent, or refused and kept aside); false: try again later.
    private func send(_ note: PendingQuickNote, context: Context) async -> Bool {
        guard isCurrent(context), canAct, pendingQuickNotes.contains(where: { $0.id == note.id }) else { return false }
        let token = session.token
        do {
            let result = try await backend.send(.quickNote(text: note.text, about: note.about, kind: note.kind,
                                                          version: note.version))
            guard isCurrent(context) else { return false }
            pendingQuickNotes.removeAll { $0.id == note.id }
            failedQuickNotes.remove(note.id)
            quickNotesMayReplay = true
            saveQuickNotes()
            await accept(result, context: context, revision: nextVaultRevision())
            if isCurrent(context), let problem = quickNoteQueueProblem { show(problem, .problem) }
            return true
        } catch VaultAPIError.conflict where note.about != nil {
            guard isCurrent(context) else { return false }
            if let index = pendingQuickNotes.firstIndex(where: { $0.id == note.id }) {
                pendingQuickNotes[index].problem = String(localized: "This changed elsewhere.")
            }
            show(String(localized: "This changed elsewhere."), .problem)
            saveQuickNotes()
            return true
        } catch let VaultAPIError.invalid(message) {
            guard isCurrent(context) else { return false }
            failedQuickNotes.insert(note.id)
            if let index = pendingQuickNotes.firstIndex(where: { $0.id == note.id }) {
                pendingQuickNotes[index].problem = message
            }
            show(String(localized: "A quick note was not saved: \(message)"), .problem)
            saveQuickNotes()
            return true
        } catch {
            session.handleAuthFailure(error, generation: context.session, token: token)
            guard isCurrent(context) else { return false }
            failedQuickNotes.insert(note.id)
            if Self.isOffline(error) { isOffline = true }
            return false
        }
    }

    private func saveQuickNotes() {
        // Server outcomes and account resets take effect in memory even when the disk must catch up later.
        quickNotesNeedSave = true
        do {
            try persistQuickNotes(pendingQuickNotes)
        } catch {
            let message = quickNotesMayReplay
                ? String(localized: "Sent, but this iPhone could not update its list; the note may be sent again after a restart: \(error.localizedDescription)")
                : String(localized: "This iPhone could not update its list of notes: \(error.localizedDescription)")
            reportQueueWriteFailure(message)
        }
    }

    private func retryQuickNotesSave() {
        if quickNotesNeedSave { saveQuickNotes() }
    }

    /// Every successful queue write includes any earlier server outcomes, so it also finishes their retry.
    private func persistQuickNotes(_ notes: [PendingQuickNote]) throws {
        try persistence.saveQuickNotes(notes)
        quickNotesNeedSave = false
        quickNotesMayReplay = false
        quickNoteQueueProblem = nil
    }

    private func reportQueueWriteFailure(_ message: String) {
        quickNoteQueueProblem = message
        show(message, .problem)
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
        vaultRevision += 1
        quickNotesTask?.cancel()
        quickNotesTask = nil
        flushID = nil
        backgroundTask?.end()
        backgroundTask = nil
        failedQuickNotes = []
        vault = nil
        index = .empty
        search = .empty
        tabSearch = .empty
        bestMatches.reset()
        etag = nil
        vaultAccount = nil
        isRefreshing = false
        loadError = nil
        isOffline = false
        lastRefresh = nil
        pendingQuickNotes = []
        quickNotesMayReplay = false
        isFlushing = false
        foregroundUpdating = false
        notice = nil
        saveQuickNotes()
        worker.deleteVault()
        updateSpotlight(nil)
    }

    // MARK: - plumbing

    private func nextVaultRevision() -> Int {
        vaultRevision += 1
        return vaultRevision
    }

    private func apply(_ vault: Vault, etag: String?, account: String?, context: Context, revision: Int,
                       save: Bool = true, reindex: Bool = true) async {
        let prepared = await preparation.prepare(vault, previous: self.vault)
        guard isCurrent(context), revision == vaultRevision else { return }
        VaultTiming.measure(save ? "vault.apply" : "disk.assign") {
            self.vault = prepared.vault
            self.etag = etag
            vaultAccount = account
            if let index = prepared.index, let search = prepared.search, let tabSearch = prepared.tabSearch {
                self.index = index
                self.search = search
                self.tabSearch = tabSearch
                if reindex { updateSpotlight(vault.notes) }
            }
            // Enqueue before leaving the main actor. A later accepted vault or logout is written after this one.
            if save { worker.save(CachedVault(vault: vault, etag: etag, account: account)) }
        }
        await worker.settled()
    }

    func loadingSettled() async { await loadingTask?.value }
    func persistenceSettled() async { await worker.settled() }

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
