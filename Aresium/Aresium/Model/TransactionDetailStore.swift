import Foundation
import Observation

enum RecategorisationMode: String, CaseIterable {
    case switchCategory = "Switch", add = "Add"

    /// The segment's word in the app's language (the raw value is the website's English word).
    var title: String {
        switch self {
        case .switchCategory: String(localized: "Switch")
        case .add: String(localized: "Add")
        }
    }
}

@MainActor @Observable
final class TransactionDetailStore {
    private(set) var detail: TransactionDetail?
    private(set) var isLoading = false
    private(set) var loadError: String?
    private(set) var isSaving = false
    private(set) var saveError: String?
    var showsRecategorisation = false
    var mode = RecategorisationMode.switchCategory
    private(set) var target: String?
    // Keep insertion order: with dropCurrent, the server promotes categories[0].
    private(set) var extras: [String] = []
    /// Phone mode, after a Switch: "Also the N other payments from <shop>?", asked before the sheet closes.
    private(set) var followUp: MerchantFollowUp?
    /// Phone mode: the receipt joined to this payment (its page's Receipt section).
    private(set) var receipt: LedgerReceipt?
    private let transaction: Transaction
    private let dashboardStore: DashboardStore
    private var retryDropCurrent = false

    init(transaction: Transaction, dashboardStore: DashboardStore) {
        self.transaction = transaction
        self.dashboardStore = dashboardStore
    }

    /// The backend of the dashboard this payment was opened from (server or phone).
    private var backend: (any AresiumBackend)? { dashboardStore.backend }

    var isSample: Bool { dashboardStore.isSample }
    var choices: [Category] {
        guard let detail else { return [] }
        return dashboardStore.dashboard?.recategorisationChoices(amount: detail.amount) ?? []
    }
    func categoryColor(for name: String) -> String {
        dashboardStore.dashboard?.categories.first { $0.name == name }?.color ?? detail?.categoryColor ?? "#9ca3af"
    }
    var canSave: Bool {
        guard !isSaving, let detail else { return false }
        return mode == .add || (target != nil && target != detail.category)
    }
    var canRemoveCurrent: Bool {
        !isSaving && extras.contains { $0 != detail?.category }
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        let generation = dashboardStore.generation
        let token = dashboardStore.session.token
        do {
            let loaded: TransactionDetail
            if isSample { loaded = try TransactionDetail.sample(for: transaction) }
            else {
                guard let backend else { throw HTTPError.unauthorized }
                loaded = try await backend.transactionDetail(id: transaction.id, auth: BackendAuth(token: token) {
                    if self.isCurrent(generation, token: token) {
                        self.dashboardStore.session.handleAuthFailure(HTTPError.unauthorized, generation: generation, token: token)
                    }
                })
                guard isCurrent(generation, token: token) else { return }
            }
            detail = loaded
            if let phone = backend as? PhoneBackend { receipt = try? await phone.receipt(joinedTo: loaded.id) }
        } catch {
            guard isCurrent(generation, token: token) else { return }
            dashboardStore.session.handleAuthFailure(error, generation: generation, token: token)
            loadError = error.localizedDescription
        }
    }

    func beginRecategorisation() {
        guard !choices.isEmpty, !isSaving, let detail else { return }
        mode = .switchCategory
        target = nil
        extras = detail.tags
        saveError = nil
        showsRecategorisation = true
    }

    func select(_ name: String) {
        guard !isSaving, choices.contains(where: { $0.name == name }) else { return }
        if mode == .switchCategory { target = name }
        else if name != detail?.category {
            if extras.contains(name) { extras.removeAll { $0 == name } }
            else { extras.append(name) }
        }
    }

    func save(dropCurrent: Bool = false) async {
        guard canSave, let detail, !dropCurrent || (mode == .add && canRemoveCurrent) else { return }
        guard !isSample else {
            saveError = "Not available with sample data"
            return
        }
        retryDropCurrent = dropCurrent
        isSaving = true
        saveError = nil
        defer { isSaving = false }
        let generation = dashboardStore.generation
        let token = dashboardStore.session.token
        do {
            guard let backend else { throw HTTPError.unauthorized }
            let auth = BackendAuth(token: token) {
                if self.isCurrent(generation, token: token) {
                    self.dashboardStore.session.handleAuthFailure(HTTPError.unauthorized, generation: generation, token: token)
                }
            }
            let updated: TransactionDetail
            var followUp: MerchantFollowUp?
            if mode == .switchCategory, let target {
                let result = try await backend.switchCategory(id: detail.id, to: target, auth: auth)
                updated = result.detail
                followUp = result.followUp
            } else {
                updated = try await backend.setTags(id: detail.id, categories: extras, dropCurrent: dropCurrent, auth: auth)
            }
            guard isCurrent(generation, token: token) else { return }
            self.detail = updated
            // The merchant's other payments: asked in the open sheet, which closes with the answer.
            if let followUp { self.followUp = followUp } else { showsRecategorisation = false }
            await dashboardStore.reloadAfterTransactionChange()
            if followUp == nil { dashboardStore.onRecategorised?() }
        } catch {
            guard isCurrent(generation, token: token) else { return }
            dashboardStore.session.handleAuthFailure(error, generation: generation, token: token)
            saveError = error.localizedDescription
        }
    }

    func retrySave() async { await save(dropCurrent: retryDropCurrent) }

    /// The Receipt section's Unjoin: the receipt waits for its bank payment again (and counts on its own); a category
    /// this payment took from it goes.
    func unjoinReceipt() async {
        guard let receipt, let phone = backend as? PhoneBackend, !isSaving else { return }
        isSaving = true
        saveError = nil
        defer { isSaving = false }
        do {
            try await phone.unjoin(receipt: receipt.id)
            self.receipt = nil
            await dashboardStore.reloadAfterTransactionChange()
            if let id = detail?.id { detail = try await phone.transactionDetail(id: id, auth: BackendAuth(token: nil)) }
        } catch {
            saveError = error.localizedDescription
        }
    }

    /// The answer to "Also the N other payments from <shop>?" from the dialog: taken at once (so a dismissal that follows
    /// a button finds nothing left to answer), then carried out.
    func answer(moveOthers: Bool) {
        guard let followUp else { return }
        self.followUp = nil
        Task { await finish(followUp, moveOthers: moveOthers) }
    }

    /// The answer to "Also the N other payments from <shop>?": yes moves them (they follow the learned merchant), no
    /// leaves them. Either way the sheet closes.
    func answerFollowUp(moveOthers: Bool) async {
        guard let followUp else { return }
        self.followUp = nil
        await finish(followUp, moveOthers: moveOthers)
    }

    private func finish(_ followUp: MerchantFollowUp, moveOthers: Bool) async {
        guard moveOthers else {
            showsRecategorisation = false
            dashboardStore.onRecategorised?()
            return
        }
        isSaving = true
        defer { isSaving = false }
        do {
            try await followUp.apply()
            showsRecategorisation = false
            await dashboardStore.reloadAfterTransactionChange()
            dashboardStore.onRecategorised?()
        } catch {
            saveError = error.localizedDescription
        }
    }

    /// The answer still counts: the phone's store does not depend on a login (one made meanwhile in another app changes
    /// nothing); the server's answer belongs to the login it was asked with.
    private func isCurrent(_ generation: Int, token: String?) -> Bool {
        backend?.mode == .phone || dashboardStore.generation == generation
    }
}
