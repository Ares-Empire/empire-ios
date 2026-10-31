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
    /// Nil for server mode; remains available when own names are hidden.
    private(set) var renameInfo: PaymentRenameInfo?
    var canRename: Bool { renameInfo?.canRename == true }
    /// The Receipt section's Edit (brief 33): the receipt's page model, whose edit sheet is open.
    private(set) var receiptEditor: ReceiptPageModel?
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
            if let phone = backend as? PhoneBackend {
                receipt = try? await phone.receipt(joinedTo: loaded.id)
                renameInfo = try await phone.renameInfo(id: loaded.id)
            }
        } catch {
            guard isCurrent(generation, token: token) else { return }
            dashboardStore.session.handleAuthFailure(error, generation: generation, token: token)
            loadError = error.localizedDescription
        }
    }

    /// The page's load, which also reads what a rename needs (`renameInfo`). Phone samples use their real temporary
    /// ledger.
    func prepareRename() async {
        if detail == nil { await load() }
    }

    /// The payment this page is for (the row it was opened from).
    var paymentID: String { transaction.id }

    /// The page's name can be edited where it stands (a tap on it or its pen, brief 47): phone mode, a stored bank
    /// payment, own names on (`offersRename`, which the row's long press follows).
    var offersRename: Bool { canRename && dashboardStore.offersRename(for: transaction) }

    /// The page's "All from <name>" line: the payments of the name shown now (a rename on this page moves it), when
    /// there are others (`DashboardStore.shownNameGroup`, as the row's long press and swipe).
    func nameRoute(namePage: String? = nil) -> (route: DashboardRoute, group: PaymentNameGroup)? {
        guard let detail, let key = detail.nameKey ?? transaction.nameKey, key != namePage,
              let group = dashboardStore.shownNameGroup(id: transaction.id, key: key) else { return nil }
        return (DashboardRoute(name: PaymentNameRoute(key: key, title: detail.place)), group)
    }

    /// Saves the chosen scope and rebuilds the dashboard/widget. Errors and busy state mirror category changes.
    func rename(to name: String, scope: PaymentNameScope) async {
        await rename([PaymentNameStep(name: name, scope: scope)])
    }

    /// Saves each step in turn (All N+1 also drops this payment's own name; back to the bank's name may drop two), then
    /// rebuilds the dashboard and the widget once.
    func rename(_ steps: [PaymentNameStep]) async {
        guard canRename, !isSaving, !steps.isEmpty, let phone = backend as? PhoneBackend else { return }
        isSaving = true
        saveError = nil
        defer { isSaving = false }
        do {
            #if DEBUG
            await DebugLaunch.holdWork()
            #endif
            for step in steps { detail = try await phone.rename(id: transaction.id, name: step.name, scope: step.scope) }
            renameInfo = try await phone.renameInfo(id: transaction.id)
            await dashboardStore.reloadAfterTransactionChange()
            dashboardStore.onRenamed?()
        } catch { saveError = error.localizedDescription }
    }

    /// The change window, in Switch (the category's chip or pen) or in Add (an extra category's chip, brief 47).
    func beginRecategorisation(mode: RecategorisationMode = .switchCategory) {
        guard !choices.isEmpty, !isSaving, let detail else { return }
        self.mode = mode
        target = nil
        extras = detail.tags
        saveError = nil
        showsRecategorisation = true
    }

    /// A payment row's long press → Change category (brief 41): the change sheet the page's Change opens, at once, with
    /// the same flow after it. It shows the payment as soon as it has loaded, or why it could not, with Retry.
    func beginRecategorisationFromRow() async {
        showsRecategorisation = true
        if detail == nil { await load() }
        guard detail != nil else { return }                      // the sheet shows the load error
        guard !choices.isEmpty else {                            // the page would show no Change either
            showsRecategorisation = false
            return
        }
        beginRecategorisation()
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

    /// The Receipt section's Edit: the check window filled from the joined receipt (`ReceiptPageModel.beginEdit`). After
    /// a change the dashboard is built again and this page shows the payment as it is now (a new total or day may have
    /// unjoined the receipt).
    func editReceipt() async {
        guard let receipt, let phone = backend as? PhoneBackend, !isSaving else { return }
        saveError = nil
        let editor = ReceiptPageModel(id: receipt.id, phone: phone) { [weak self] in await self?.receiptChanged() }
        receiptEditor = editor
        await editor.beginEdit()
        if editor.editing == nil {
            saveError = editor.problem
            receiptEditor = nil
        }
    }

    private func receiptChanged() async {
        await dashboardStore.reloadAfterTransactionChange()
        guard let phone = backend as? PhoneBackend, let id = detail?.id else { return }
        if let reloaded = try? await phone.transactionDetail(id: id, auth: BackendAuth(token: nil)) { detail = reloaded }
        receipt = try? await phone.receipt(joinedTo: id)
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
