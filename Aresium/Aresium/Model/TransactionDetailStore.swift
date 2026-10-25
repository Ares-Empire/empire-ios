import Foundation
import Observation

enum RecategorisationMode: String, CaseIterable {
    case switchCategory = "Switch", add = "Add"
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
    private let transaction: Transaction
    private let dashboardStore: DashboardStore
    private let client: APIClient
    private var retryDropCurrent = false

    init(transaction: Transaction, dashboardStore: DashboardStore, client: APIClient) {
        self.transaction = transaction
        self.dashboardStore = dashboardStore
        self.client = client
    }

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
                guard let token else { throw HTTPError.unauthorized }
                loaded = try await client.transactionDetail(id: transaction.id, token: token) {
                    if self.isCurrent(generation, token: token) {
                        self.dashboardStore.session.handleAuthFailure(HTTPError.unauthorized, generation: generation, token: token)
                    }
                }
                guard isCurrent(generation, token: token) else { return }
            }
            detail = loaded
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
            guard let token else { throw HTTPError.unauthorized }
            let onUnauthorized = {
                if self.isCurrent(generation, token: token) {
                    self.dashboardStore.session.handleAuthFailure(HTTPError.unauthorized, generation: generation, token: token)
                }
            }
            let updated: TransactionDetail
            if mode == .switchCategory, let target {
                updated = try await client.switchCategory(id: detail.id, category: target,
                                                          token: token, onUnauthorized: onUnauthorized)
            } else {
                updated = try await client.setTransactionTags(id: detail.id, categories: extras, dropCurrent: dropCurrent,
                                                              token: token, onUnauthorized: onUnauthorized)
            }
            guard isCurrent(generation, token: token) else { return }
            self.detail = updated
            showsRecategorisation = false
            await dashboardStore.reloadAfterTransactionChange()
        } catch {
            guard isCurrent(generation, token: token) else { return }
            dashboardStore.session.handleAuthFailure(error, generation: generation, token: token)
            saveError = error.localizedDescription
        }
    }

    func retrySave() async { await save(dropCurrent: retryDropCurrent) }

    private func isCurrent(_ generation: Int, token: String?) -> Bool {
        dashboardStore.generation == generation
    }
}
