import Foundation
import Observation

// Several payments changed at once, the screens' side (brief 82, Patrik 2026-11-01: "make expenses / incomes selectable
// and then moveable / changable at the same time … like in Mail when selecting mails"; the data is brief 81's
// `BatchChanges.swift`). A category's month list turns into selection with the header's icon: what is ticked
// (`PaymentSelection`, kept in `DashboardPlace`), the header's and the bar's words and states, the change window for the
// selection (`SelectionCategoryChange`, read by the one `RecategoriseSheet`) and the name for all of them
// (`SelectionRename`). The look is `Screens/SelectionScreens.swift`.

/// A category's month list while its payments are selected: the list (the route on top of the dashboard's stack) and the
/// row ids ticked (`DashboardStore.selectionIDs(for:)`: a summed row stands for its payments). Kept in `DashboardPlace`, so
/// the header, the rows and the bar read one state; it ends when the list leaves the top of the stack.
struct PaymentSelection: Equatable {
    var route: DashboardRoute
    var ids: Set<String> = []

    /// Whether this is that list's selection (the same list, also while a rename gave its route another name).
    func belongs(to list: DashboardRoute) -> Bool { route.isSameList(as: list) }

    /// A row's circle: ticked when every payment it stands for is; nil for a row that cannot be selected (a withdrawal's
    /// covered row).
    func isTicked(_ entry: PaymentListEntry, in store: DashboardStore) -> Bool? {
        let members = store.selectionIDs(for: entry)
        guard !members.isEmpty else { return nil }
        return members.isSubset(of: ids)
    }

    /// A tap on a row: its payments ticked, or unticked.
    mutating func toggle(_ entry: PaymentListEntry, in store: DashboardStore) {
        let members = store.selectionIDs(for: entry)
        if members.isSubset(of: ids) { ids.subtract(members) } else { ids.formUnion(members) }
    }

    /// The list's payments that can be ticked now.
    func selectable(in store: DashboardStore) -> Set<String> {
        guard let month = route.month else { return [] }
        let list = store.paymentList(category: route.category, month: month, side: route.side)
        return Set(store.selectableRows(in: list).map(\.id))
    }

    /// What is ticked of the list as it is now (a payment that left it meanwhile is not).
    func live(in store: DashboardStore) -> Set<String> { ids.intersection(selectable(in: store)) }

    /// Every payment of the list ticked: the header's left button says None.
    func allTicked(in store: DashboardStore) -> Bool {
        let all = selectable(in: store)
        return !all.isEmpty && all.isSubset(of: ids)
    }

    /// The header's All (every payment of the list), or None.
    mutating func toggleAll(in store: DashboardStore) {
        ids = allTicked(in: store) ? [] : selectable(in: store)
    }
}

extension DashboardRoute {
    /// The same category's month list: the same month and side, and the same category (by its stable id where both
    /// know it, since a rename gives the route another name, not another list).
    func isSameList(as other: DashboardRoute) -> Bool {
        guard isCategoryList, other.isCategoryList, month == other.month, side == other.side else { return false }
        if let id = categoryID, let otherID = other.categoryID { return id == otherID }
        return category == other.category
    }
}

extension DashboardStore {
    /// The header's select icon (brief 82): a category's month list (Current and Overview, Not sorted included) in phone
    /// mode with a row to select. Not a name's page, the Cash page, a month's page or a day's.
    func offersSelection(on route: DashboardRoute) -> Bool {
        guard route.isCategoryList, let month = route.month else { return false }
        return offersSelection(category: route.category, month: month, side: route.side)
    }
}

// MARK: - words and states

/// The selection's words in the app's language (English here, German in the catalog).
nonisolated enum SelectionWording {
    /// The header's title: "3 selected", or "Select payments" while nothing is ticked.
    static func title(_ count: Int, language: AppLanguage = .current) -> String {
        count == 0 ? language.string("Select payments") : language.string("\(count) selected")
    }

    /// The header's left button: All, or None once every payment is ticked.
    static func allButton(allTicked: Bool, language: AppLanguage = .current) -> String {
        allTicked ? language.string("None") : language.string("All")
    }

    /// The change window's title for a selection: "10 payments".
    static func payments(_ count: Int, language: AppLanguage = .current) -> String {
        language.string("\(count) payments")
    }

    /// The name's alert: "Name for 10 payments" (the bank payments that take it).
    static func nameTitle(_ count: Int, language: AppLanguage = .current) -> String {
        language.string("Name for \(count) payments")
    }

    /// The name's alert's line when receipts or cash entries are ticked too: they keep the shop typed on them.
    static func keepShop(_ skipped: Int, language: AppLanguage = .current) -> String? {
        skipped > 0 ? language.string("Receipts and cash entries keep their shop.") : nil
    }

    /// The undo bar's line after an action: brief 81's words, counting the shop's other payments when they went too.
    @MainActor static func done(_ result: BatchChangeResult, applied: BatchChangeResult? = nil,
                     language: AppLanguage = .current) -> String {
        guard let applied else { return result.message }
        return BatchWording.result(result.action, count: result.changed.total + applied.changed.total,
                                   category: result.category, skipped: result.skipped, language: language)
    }
}

/// The bar at the bottom while selecting: Category and Name, each off while it cannot act. Name is off while no bank
/// payment is ticked (receipts and cash entries keep their typed Shop) and is not offered while Own names is off (as a
/// payment's page then has no pen).
struct SelectionBarState: Equatable {
    let category: Bool
    let name: Bool
    let offersName: Bool

    init(summary: PaymentSelectionSummary, ownNames: Bool) {
        category = summary.canSwitch
        name = summary.canRename
        offersName = ownNames
    }
}

/// "Also the other 14 payments from these 3 shops?" after a name for a selection: the single rename's question
/// (`RenamePlan.Question`) for all of them, All 24 / Only these. All gives the shops the name (new payments from them get
/// it too), Only these names the selected payments alone.
nonisolated struct SelectionRenameQuestion: Equatable, Identifiable {
    let name: String
    /// The bank payments selected (the ones named either way).
    let selected: Int
    /// The shops' other payments.
    let others: Int
    let shopCount: Int
    /// The name the selected payments show, when they are one shop's and show one name.
    let shop: String?
    var id: String { name }

    func title(language: AppLanguage = .current) -> String {
        if shopCount > 1 {
            return others == 1 ? language.string("Also the other payment from these \(shopCount) shops?")
                : language.string("Also the other \(others) payments from these \(shopCount) shops?")
        }
        if let shop { return language.string("Also the other \(others) payments from \(shop)?") }
        return language.string("Also the other \(others) payments from this shop?")
    }

    func message(language: AppLanguage = .current) -> String {
        if shopCount > 1 { return language.string("With All, new payments from these shops get the name too.") }
        if let shop { return language.string("With All, new payments from \(shop) get the name too.") }
        return language.string("With All, new payments from this shop get the name too.")
    }

    /// The single rename's "All N+1"; "Only these" as the category question for a selection asks it (brief 83).
    func allTitle(language: AppLanguage = .current) -> String { language.string("All \(selected + others)") }
    func onlyTitle(language: AppLanguage = .current) -> String { language.string("Only these") }
}

/// How an action on a selection ended.
enum SelectionOutcome {
    /// Done: selecting ends and the undo bar says what happened, with Undo.
    case done(message: String, undo: BatchUndo)
    /// Not done: a line says why; the payments stay selected.
    case failed(String)
}

// MARK: - the change window for a selection

/// The change window (`RecategoriseSheet`) for the payments ticked in a category's month list: their side's categories
/// (`offeredCategories`), Switch and Add, Other category… and New category as for one payment (`CategoryWindow`'s
/// shared picking). Save switches them (brief 81), or for Add asks brief 83's "Also remove them from Groceries?" first;
/// then the shops' other payments, as the single window asks (`CategoryQuestionWording`). When it is done, `finished`
/// gets what happened and its undo.
@MainActor @Observable
final class SelectionCategoryChange: CategoryWindow, Identifiable {
    let id = UUID()
    let ids: Set<String>
    /// The list's category: the one the payments are in now (Add never adds it, and asks about removing it).
    let listCategory: String
    let side: DashboardSide
    let dashboardStore: DashboardStore
    let picks = CategoryPicks()
    let summary: PaymentSelectionSummary
    private(set) var isSaving = false
    private(set) var saveError: String?
    private(set) var question: RecategorisationQuestion?
    @ObservationIgnored private var request: BatchAddRequest?
    @ObservationIgnored private var followUp: (result: BatchChangeResult, question: BatchMerchantFollowUp)?
    @ObservationIgnored private let finished: (SelectionOutcome) -> Void
    @ObservationIgnored private var offeredCache: (revision: Int, chosen: [ChosenCategory]?, mode: RecategorisationMode,
                                                   categories: [Category])?

    init(ids: Set<String>, route: DashboardRoute, store: DashboardStore,
         finished: @escaping (SelectionOutcome) -> Void) {
        self.ids = ids
        listCategory = route.category
        side = route.side
        dashboardStore = store
        summary = store.selectionSummary(ids)
        self.finished = finished
        if let phone = store.phone, let catalog = phone.catalog {
            picks.list = PhoneCategoryList(catalog: catalog, chosen: phone.summary.chosen)
        }
        picks.begin(mode: .switchCategory, extras: [])
    }

    var heading: CategoryWindowHeading? {
        CategoryWindowHeading(title: SelectionWording.payments(summary.count),
                              amount: summary.side == .income ? summary.total : -summary.total,
                              current: listCategory,
                              currentColor: dashboardStore.category(listCategory, side: side)?.color ?? "#9ca3af",
                              selection: true)
    }
    var loadError: String? { nil }
    func retryLoad() async {}

    /// Their side's categories (brief 81's `offeredCategories`), built once per dashboard, choice of categories and mode.
    var offered: [Category] {
        let revision = dashboardStore.revision, chosen = dashboardStore.phone?.summary.chosen
        if let cache = offeredCache, cache.revision == revision, cache.chosen == chosen, cache.mode == mode {
            return cache.categories
        }
        let categories = dashboardStore.offeredCategories(for: ids, mode: mode)
        offeredCache = (revision, chosen, mode, categories)
        return categories
    }
    var paymentSide: CategorySide? { summary.side.map { $0 == .income ? .income : .spend } }
    var currentCategory: String? { listCategory }
    var isSample: Bool { dashboardStore.isSample }

    var canSave: Bool {
        guard !isSaving, !newCategory.isMaking, summary.canSwitch else { return false }
        return mode == .switchCategory ? target != nil : !extras.isEmpty
    }

    func working(_ work: () async throws -> Void) async {
        isSaving = true
        saveError = nil
        defer { isSaving = false }
        do { try await work() } catch { saveError = error.localizedDescription }
    }

    /// Save: Switch moves them (and learns their shops); Add asks first whether to remove them from the list's category.
    func save() async {
        guard canSave, let phone = dashboardStore.phone else { return }
        question = nil
        await working {
            try await picks.storeOtherSides(in: phone)
            switch mode {
            case .switchCategory:
                guard let target else { return }
                received(try await dashboardStore.switchCategory(ids: ids, to: target))
            case .add:
                let request = try dashboardStore.prepareAddCategories(ids: ids, names: extras,
                                                                     currentCategory: listCategory)
                if let asked = request.question {
                    self.request = request
                    question = .remove(asked)
                } else {
                    received(try await request.save())
                }
            }
        }
    }

    func retrySave() async { await save() }

    /// "Also remove them from Groceries?": Remove or Keep both, then saved.
    func answerRemoveCurrent(remove: Bool) async {
        guard case .remove = question, let request else { return }
        question = nil
        self.request = nil
        await working { received(try await request.save(removeCurrent: remove)) }
    }

    /// The shops' other payments: All moves them too, Only these leaves them. Either way the window closes.
    func answer(moveOthers: Bool) {
        guard case .merchant = question, let followUp else { return }
        question = nil
        self.followUp = nil
        guard moveOthers else { return finished(.done(message: SelectionWording.done(followUp.result),
                                                      undo: followUp.result.undo)) }
        Task {
            isSaving = true
            defer { isSaving = false }
            do {
                let applied = try await followUp.question.apply()
                finished(.done(message: SelectionWording.done(followUp.result, applied: applied),
                               undo: followUp.result.undo))
            } catch {
                // The selection's own change is saved: it is reported with its undo, and why the others were not moved.
                finished(.done(message: SelectionWording.done(followUp.result) + " · " + error.localizedDescription,
                               undo: followUp.result.undo))
            }
        }
    }

    private func received(_ result: BatchChangeResult) {
        if let asked = result.followUp {
            followUp = (result, asked)
            question = .merchant(id: UUID(), wording: asked.wording)
        } else {
            finished(.done(message: SelectionWording.done(result), undo: result.undo))
        }
    }
}

// MARK: - one name for a selection

/// Name in the selection's bar (brief 82): Apple's alert with a name's field ("Name for 10 payments"), empty or with the
/// name all of them show; Rename then asks about the shops' other payments when there are any (`renameInfo`), as the
/// single rename asks. Receipts and cash entries keep their typed Shop. `finished` gets what happened and its undo.
@MainActor @Observable
final class SelectionRename {
    let ids: Set<String>
    /// The bank payments that take the name.
    let count: Int
    /// The receipts and cash entries ticked, which keep their Shop.
    let skipped: Int
    /// The name all the bank payments show, when they show one; else empty.
    let start: String
    var text: String
    /// The name's alert shows.
    var isAsking = true
    private(set) var question: SelectionRenameQuestion?
    private(set) var isWorking = false
    @ObservationIgnored private let store: DashboardStore
    @ObservationIgnored private let finished: (SelectionOutcome) -> Void

    init(ids: Set<String>, store: DashboardStore, finished: @escaping (SelectionOutcome) -> Void) {
        self.ids = ids
        self.store = store
        self.finished = finished
        let summary = store.selectionSummary(ids)
        count = summary.bankPayments
        skipped = summary.counts.receipts + summary.counts.cashEntries
        let names = Set(store.selectionRows(ids).filter { $0.receiptId == nil }.map(\.place))
        start = names.count == 1 ? names.first ?? "" : ""
        text = start
    }

    /// Rename is on once a name is typed that differs from the one they all show.
    var canRename: Bool {
        let name = PaymentNames.normalized(text)
        return !isWorking && !name.isEmpty && name != PaymentNames.normalized(start)
    }

    /// Rename (or the keyboard's Return): asks about the shops' other payments when there are any, else names these.
    func rename() async {
        isAsking = false
        guard canRename else { return }
        let name = PaymentNames.normalized(text)
        isWorking = true
        defer { isWorking = false }
        do {
            let info = try await store.renameInfo(ids: ids)
            guard info.otherPaymentCount > 0 else {
                return finish(try await store.rename(ids: ids, to: name, scope: .payments))
            }
            question = SelectionRenameQuestion(name: name, selected: info.bankPaymentCount,
                                               others: info.otherPaymentCount, shopCount: info.shopCount,
                                               shop: info.shopCount == 1 && !start.isEmpty ? start : nil)
        } catch {
            finished(.failed(error.localizedDescription))
        }
    }

    /// All: the shops get the name (new payments from them too). Only these: the selected payments alone.
    func answer(all: Bool) async {
        guard let question else { return }
        self.question = nil
        isWorking = true
        defer { isWorking = false }
        do { finish(try await store.rename(ids: ids, to: question.name, scope: all ? .shops : .payments)) }
        catch { finished(.failed(error.localizedDescription)) }
    }

    private func finish(_ result: BatchChangeResult) {
        finished(.done(message: SelectionWording.done(result), undo: result.undo))
    }
}
