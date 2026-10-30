import Foundation
import Observation

@MainActor @Observable
final class EmpireStore {
    private(set) var data: EmpireData?
    private(set) var isLoading = false
    private(set) var error: String?
    /// The app of the "+" sheet whose access request is on its way, if any (one at a time).
    private(set) var requesting: String?
    private(set) var requestError: String?
    private(set) var approvals: [PendingAccount] = []
    private(set) var isLoadingApprovals = false
    private(set) var isDeciding = false
    private(set) var approvalsError: String?
    private(set) var lastSuccessfulLoad: Date?
    let session: EmpireSession
    let isSample: Bool
    private let sampleUser: Bool
    private let sampleCatalog: Bool
    private let client: EmpireAPI
    private var resetGeneration = 0
    private var dataGeneration = 0
    private var approvalsGeneration = 0
    private var foregroundRefreshing = false
    private var sampleApprovals: [PendingAccount]?
    #if DEBUG
    private var sampleApprovalsLoads = 0
    #endif

    init(session: EmpireSession, client: EmpireAPI = EmpireAPI(), sample: Bool = EmpireSamples.isEnabled,
         sampleUser: Bool = EmpireSamples.isUser, sampleCatalog: Bool = EmpireSamples.isCatalog) {
        self.session = session
        self.client = client
        #if DEBUG
        isSample = sample
        #else
        isSample = false
        #endif
        self.sampleUser = sampleUser || sampleCatalog
        self.sampleCatalog = sampleCatalog
        session.onAppDataReset { [weak self] in self?.clear() }
    }

    func reload() async {
        guard !isLoading, requesting == nil, !isDeciding, isSample || session.isSignedIn else { return }
        isLoading = true
        error = nil
        let context = context
        let fetch = dataGeneration
        defer { if isCurrent(context), fetch == dataGeneration { isLoading = false } }
        do {
            let loaded: EmpireData
            if isSample {
                // Refreshing a preview must preserve its in-memory requests and approval decisions.
                loaded = try data ?? loadSample()
            } else {
                loaded = try await client.empire(token: try token(for: context))
            }
            guard isCurrent(context), fetch == dataGeneration else { return }
            data = loaded
            lastSuccessfulLoad = .now
        } catch {
            guard isCurrent(context), fetch == dataGeneration else { return }
            handle(error, context: context) { self.error = $0 }
        }
    }

    func refreshOnForeground(now: Date = .now) async {
        guard !isSample, session.isSignedIn, !session.isBusy, !foregroundRefreshing,
              !isLoading, requesting == nil, !isDeciding else { return }
        foregroundRefreshing = true
        let context = context
        defer { if isCurrent(context) { foregroundRefreshing = false } }
        if session.lastRenewedAt.map({ now.timeIntervalSince($0) > 12 * 60 * 60 }) ?? true {
            await session.restore()
            guard isCurrent(context), session.isSignedIn, !session.needsRestoreRetry else { return }
        }
        if lastSuccessfulLoad.map({ now.timeIntervalSince($0) > 5 * 60 }) ?? true { await reload() }
    }

    /// Asks for access to an app of the "+" sheet. The hub answers the data afresh, so the sheet shows the state it
    /// now has ("Asked · waiting for approval"); a refusal shows the hub's sentence. True when the hub took it.
    @discardableResult
    func request(_ slug: String) async -> Bool {
        guard requesting == nil, !isDeciding, isSample || session.isSignedIn else { return false }
        invalidateDataLoad()
        requesting = slug
        requestError = nil
        let context = context
        defer { if isCurrent(context) { requesting = nil } }
        do {
            let loaded: EmpireData
            if isSample {
                let current = try data ?? loadSample()
                loaded = current.replacing(addable: current.addable.map { province in
                    province.slug == slug && province.canRequest ? province.with(access: .requested) : province
                })
            } else {
                loaded = try await client.request(service: slug, token: try token(for: context))
            }
            guard isCurrent(context) else { return false }
            data = loaded
            lastSuccessfulLoad = .now
            return true
        } catch {
            guard isCurrent(context) else { return false }
            handle(error, context: context) { self.requestError = $0 }
            return false
        }
    }

    func loadApprovals() async {
        guard !isLoadingApprovals, !isDeciding, isSample || session.isSignedIn else { return }
        isLoadingApprovals = true
        approvalsError = nil
        let context = context
        let fetch = approvalsGeneration
        defer { if isCurrent(context), fetch == approvalsGeneration { isLoadingApprovals = false } }
        do {
            let loaded = try await fetchApprovals(context)
            guard isCurrent(context), fetch == approvalsGeneration else { return }
            approvals = loaded
        } catch {
            guard isCurrent(context), fetch == approvalsGeneration else { return }
            handle(error, context: context) { self.approvalsError = $0 }
        }
    }

    /// Approves (granting `requested`, the apps the card shows) or declines an account (withdrawing only those
    /// requests of an approved account). Returns whether the decision
    /// itself went through; a failed refresh afterwards only shows its error. After a failed decision the list is
    /// asked for again: the decision may have gone through all the same (its answer lost), or the account was decided
    /// elsewhere, and a stale card must not stay.
    @discardableResult
    func decide(id: String, approve: Bool, requested: [String]) async -> Bool {
        guard !isDeciding, requesting == nil, isSample || session.isSignedIn else { return false }
        invalidateDataLoad()
        approvalsGeneration += 1
        isLoadingApprovals = false
        isDeciding = true
        approvalsError = nil
        let context = context
        defer { if isCurrent(context) { isDeciding = false } }
        let answer: DecisionAnswer?
        do {
            if isSample {
                var pending = sampleApprovals ?? (sampleUser ? [] : EmpireSamples.approvals)
                pending.removeAll { $0.id == id }
                sampleApprovals = pending
                if data == nil { data = try loadSample() }
                answer = DecisionAnswer(approvals: pending, pending: pending.count)
            } else {
                answer = try await client.decide(id: id, approve: approve, requested: requested,
                                                 token: try token(for: context))
            }
        } catch {
            guard isCurrent(context) else { return false }
            handle(error, context: context) { self.approvalsError = $0 }
            guard isCurrent(context) else { return false }
            await refreshAfterDecision(context: context, keepingError: true)
            return false
        }
        guard isCurrent(context) else { return true }
        if let answer {
            approvals = answer.approvals
            data = data?.replacing(pending: answer.pending)
        } else {
            await refreshAfterDecision(context: context, keepingError: false)    // the answer had no list
        }
        return true
    }

    /// The list, then the hub's count, each on its own so one failing does not stop the other. `keepingError`: an
    /// error of the decision itself is showing and stays the one shown.
    private func refreshAfterDecision(context: Context, keepingError: Bool) async {
        let report: (String) -> Void = { message in if !keepingError { self.approvalsError = message } }
        do {
            let loaded = try await fetchApprovals(context)
            guard isCurrent(context) else { return }
            approvals = loaded
        } catch {
            guard isCurrent(context) else { return }
            handle(error, context: context, report: report)
        }
        guard isCurrent(context) else { return }
        do {
            let loaded = isSample ? data : try await client.empire(token: try token(for: context))
            guard isCurrent(context) else { return }
            data = loaded
            lastSuccessfulLoad = .now
        } catch {
            guard isCurrent(context) else { return }
            handle(error, context: context, report: report)
        }
    }

    func clear() {
        resetGeneration += 1
        invalidateDataLoad()
        approvalsGeneration += 1
        data = nil
        approvals = []
        sampleApprovals = nil
        lastSuccessfulLoad = nil
        error = nil
        requestError = nil
        approvalsError = nil
        requesting = nil
        isLoadingApprovals = false
        isDeciding = false
        foregroundRefreshing = false
    }

    /// What an action started with: the session, the reset, and the login its requests use (a refusal names it, so an
    /// answer about an older login changes nothing: `EmpireSession.handleAuthFailure`).
    private var context: Context { Context(session: session.generation, reset: resetGeneration, token: session.token) }
    private struct Context { let session: Int; let reset: Int; let token: String? }
    private func isCurrent(_ context: Context) -> Bool {
        context.session == session.generation && context.reset == resetGeneration
    }

    private func token(for context: Context) throws -> String {
        guard session.isSignedIn, let token = context.token else { throw HTTPError.unauthorized }
        return token
    }

    private func handle(_ failure: Error, context: Context, report: (String) -> Void) {
        session.handleAuthFailure(failure, generation: context.session, token: context.token)
        guard isCurrent(context) else { return }
        report(failure.localizedDescription)
    }

    private func invalidateDataLoad() {
        dataGeneration += 1
        isLoading = false
    }

    private func loadSample() throws -> EmpireData {
        try sampleCatalog ? EmpireSamples.catalog() : EmpireSamples.load(user: sampleUser)
    }

    private func fetchApprovals(_ context: Context) async throws -> [PendingAccount] {
        if isSample {
            #if DEBUG
            // Screenshots: fail the first sample load; later loads use the sample list. A slow retry gives time to
            // see refresh progress without contacting a server.
            sampleApprovalsLoads += 1
            if sampleApprovalsLoads == 1 && LaunchArguments.current.contains("-sampleApprovalsFailure") {
                throw URLError(.notConnectedToInternet)
            }
            if sampleApprovalsLoads > 1 && LaunchArguments.current.contains("-sampleApprovalsSlow") {
                try await Task.sleep(for: .seconds(12))
            }
            #endif
            let pending = sampleApprovals ?? (sampleUser ? [] : EmpireSamples.approvals)
            sampleApprovals = pending
            return pending
        }
        return try await client.approvals(token: try token(for: context))
    }
}

private extension EmpireData {
    func replacing(projects: [Province]? = nil, addable: [Province]? = nil) -> EmpireData {
        EmpireData(version: version, me: me, projects: projects ?? self.projects, addable: addable ?? self.addable,
                   chronicle: chronicle, ideas: ideas, pending: pending)
    }

    func replacing(pending: Int?) -> EmpireData {
        EmpireData(version: version, me: me, projects: projects, addable: addable, chronicle: chronicle, ideas: ideas,
                   pending: pending)
    }
}
