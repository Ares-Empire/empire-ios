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
    private var categoryList: PhoneCategoryList?
    private var pickedOtherSide: Set<String> = []
    private var retryDropCurrent = false

    init(transaction: Transaction, dashboardStore: DashboardStore) {
        self.transaction = transaction
        self.dashboardStore = dashboardStore
    }

    /// The backend of the dashboard this payment was opened from (server or phone).
    private var backend: (any AresiumBackend)? { dashboardStore.backend }

    var isSample: Bool { dashboardStore.isSample }
    /// The change window's categories, from the dashboard. One made in this opening of the window comes last, just
    /// before the New category tile where it was asked for (brief 60), so it shows picked where the person looks.
    var choices: [Category] {
        guard let detail else { return [] }
        let all = dashboardStore.dashboard?.recategorisationChoices(amount: detail.amount) ?? []
        guard !madeHere.isEmpty else { return all }
        let made = madeHere.compactMap { name in dashboardStore.dashboard?.categories.first { $0.name == name } }
        return all.filter { !madeHere.contains($0.name) } + made
    }
    func categoryColor(for name: String) -> String {
        dashboardStore.dashboard?.categories.first { $0.name == name }?.color ?? detail?.categoryColor ?? "#9ca3af"
    }
    var canSave: Bool {
        guard !isSaving, !newCategory.isMaking, let detail else { return false }
        return mode == .add || (target != nil && target != detail.category)
    }
    var canRemoveCurrent: Bool {
        !isSaving && !newCategory.isMaking && extras.contains { $0 != detail?.category }
    }

    // MARK: a new category from the change window (brief 60)

    /// The New category alert, its busy state and its name problem (`NewCategoryModel`, shared with the receipt window
    /// and Add cash).
    let newCategory = NewCategoryModel()
    /// The names made or picked from the other side in this opening, in their insertion order (`choices`).
    private var madeHere: [String] = []

    /// Phone mode offers a new category for either direction, with the payment's home side.
    var offersNewCategory: Bool { detail != nil && dashboardStore.phone != nil }

    /// Other home categories not offered here yet, in the engine's order for their home direction.
    var otherSideChoices: [Category] {
        guard let detail, let list = categoryList, dashboardStore.phone != nil else { return [] }
        let side = CategorySide(amount: detail.amount)
        let offered = Set(list.offered(for: side.direction))
        return (dashboardStore.dashboard?.recategorisationChoices(amount: detail.amount > 0 ? -1 : 1) ?? []).filter {
            guard let id = list.id(named: $0.name) else { return false }
            return list.side(of: id) != nil && list.side(of: id) != side && !offered.contains(id)
                && !pickedOtherSide.contains($0.name)
        }
    }

    /// The payment's side: money in is income's, money out spending's (where its window's categories come from).
    var paymentSide: CategorySide? { detail.map { CategorySide(amount: $0.amount) } }

    /// Other category… (brief 70): the tile before New category, in Switch and Add, phone mode only, while the other
    /// side has a category not offered here yet.
    var offersOtherCategory: Bool { offersNewCategory && !otherSideChoices.isEmpty }

    /// The other side's list's line ("From spending" for money in); nil where there is no list.
    var otherSideListLine: String? {
        guard offersOtherCategory, let paymentSide else { return nil }
        return CategorySideWording.otherSideList(for: paymentSide)
    }

    /// A tile offered here only from the other side: one stored as offered here (not the payment's current category),
    /// or one picked from the list in this opening. Its long press takes it back (`stopOffering`).
    func offeredFromOtherSide(_ name: String) -> Bool {
        guard let detail, let list = categoryList, dashboardStore.phone != nil, name != detail.category else { return false }
        if pickedOtherSide.contains(name) { return true }
        guard let id = list.id(named: name), let side = list.side(of: id) else { return false }
        return side != CategorySide(amount: detail.amount) && list.hasOtherSide(id)
    }

    /// The long press's one entry on such a tile: "Not for money in" (or out); nil on every other tile.
    func stopOfferingEntry(for name: String) -> String? {
        guard offeredFromOtherSide(name), let paymentSide else { return nil }
        return CategorySideWording.notFor(paymentSide)
    }

    /// Picks locally; Save widens the category's menu, and Cancel has no stored effect.
    func pickFromOtherSide(_ name: String) {
        guard !isSaving, !newCategory.isMaking, otherSideChoices.contains(where: { $0.name == name }) else { return }
        pickedOtherSide.insert(name)
        if !madeHere.contains(name) { madeHere.append(name) }
        select(name)
    }

    /// Removes an addition to this direction at once. A home category and the payment's current category stay offered.
    /// One picked from the other side in this opening was never stored: it only leaves the window (and the list has it
    /// again).
    func stopOffering(_ name: String) async {
        if pickedOtherSide.contains(name), !isSaving, !newCategory.isMaking {
            pickedOtherSide.remove(name)
            madeHere.removeAll { $0 == name }
            if target == name { target = nil }
            extras.removeAll { $0 == name }
            return
        }
        guard !isSaving, !newCategory.isMaking, let detail, let phone = dashboardStore.phone,
              let list = categoryList, let id = list.id(named: name), list.hasOtherSide(id),
              let side = list.side(of: id), side != CategorySide(amount: detail.amount), name != detail.category else { return }
        isSaving = true
        saveError = nil
        defer { isSaving = false }
        do {
            try await phone.setOtherSide(false, for: id)
            categoryList = try await phone.categories()
            madeHere.removeAll { $0 == name }
            pickedOtherSide.remove(name)
            if target == name { target = nil }
            extras.removeAll { $0 == name }
            await dashboardStore.reloadIfCategoriesChanged()
        } catch { saveError = error.localizedDescription }
    }

    /// The tile: the alert with the name's field (empty, or the name a problem was found in).
    func beginNewCategory() {
        guard offersNewCategory, !isSaving else { return }
        newCategory.begin()
    }

    /// The alert's Create (or the keyboard's Return): the category is made (`NewCategoryModel`), the dashboard is built
    /// again so the window's choices have it, and it is picked: the target in Switch, one of the extras in Add. Nothing
    /// about the payment is saved before Save.
    func createCategory() async {
        guard offersNewCategory, let phone = dashboardStore.phone, !isSaving else { return }
        await newCategory.create(in: phone, side: CategorySide(amount: detail?.amount ?? transaction.amount)) { _, name in
            if !madeHere.contains(name) { madeHere.append(name) }
            categoryList = try? await phone.categories()
            await dashboardStore.reloadAfterTransactionChange()
            // Not offered only when the dashboard could not be built again: the category is made (Settings →
            // Categories shows it), but the window cannot offer it yet.
            guard choices.contains(where: { $0.name == name }) else { return dashboardStore.error }
            if mode == .switchCategory || !extras.contains(name) { select(name) }
            return nil
        }
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
                categoryList = try await phone.categories()
                receipt = try? await phone.receipt(joinedTo: loaded.id)
                renameInfo = try await phone.renameInfo(id: loaded.id)
                // The change window's choices come from the dashboard: one made since it was built is offered too.
                await dashboardStore.reloadIfCategoriesChanged()
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
        madeHere = []
        pickedOtherSide = []
        newCategory.reset()
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
            if let phone = dashboardStore.phone {
                let savedNames = mode == .switchCategory ? target.map { [$0] } ?? [] : extras
                let list = try await phone.categories()
                for name in savedNames where pickedOtherSide.contains(name) {
                    guard let id = list.id(named: name) else { throw LedgerError.notFound }
                    try await phone.setOtherSide(true, for: id)
                }
                categoryList = try await phone.categories()
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
