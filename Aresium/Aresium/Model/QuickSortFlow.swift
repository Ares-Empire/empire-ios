import Foundation
import Observation

// The quick sort's flow (brief 99; the groups and words are `QuickSort.swift`, the look `Screens/QuickSortScreens.swift`):
// the groups as they were when it opened, gone through in order, one card at a time. A card is a change window for one
// name's payments (`QuickSortCard`, a `CategoryWindow`, so its tiles, Other category… and New category are the change
// window's own); a tap on a tile sorts all of them at once with brief 81's switch and the next card comes. Skip leaves a
// card Not sorted; Undo puts back the last card sorted (brief 81's undo) and shows it again. The person can stop any
// time: what was sorted stays sorted.

@MainActor @Observable
final class QuickSortFlow: Identifiable {
    /// What became of a card.
    enum Outcome: Equatable {
        case sorted(payments: Int)
        case skipped
        /// Nothing of it was Not sorted any more when its turn came (sorted elsewhere meanwhile): passed by itself.
        case gone
    }

    let id = UUID()
    let store: DashboardStore
    /// The cards, biggest first, as they were when the flow opened; the order never changes under the person.
    let groups: [QuickSortGroup]
    /// One per card gone past, in order: the current card is `outcomes.count`.
    private(set) var outcomes: [Outcome] = []
    /// The card shown; nil at the end.
    private(set) var card: QuickSortCard?
    /// The last card sorted, while its undo can still work (brief 81's undo is single use, and any later save on the
    /// ledger makes it unavailable, so only the last sort is ever offered).
    private(set) var lastSorted: Int?
    @ObservationIgnored private var lastUndo: BatchUndo?
    private(set) var isUndoing = false
    /// Why an undo could not be done ("Cannot undo because the data changed."); goes with the next tap.
    private(set) var problem: String?
    /// The card came back with Undo: it slides in from the left, not the right.
    private(set) var cameBack = false

    init(store: DashboardStore, groups: [QuickSortGroup]? = nil) {
        self.store = store
        self.groups = groups ?? store.quickSortGroups
        showCard()
    }

    var position: Int { outcomes.count }
    var isFinished: Bool { position >= groups.count }
    var sortedPayments: Int {
        outcomes.reduce(0) { total, outcome in
            if case let .sorted(payments) = outcome { return total + payments }
            return total
        }
    }
    var sortedNames: Int { outcomes.filter { if case .sorted = $0 { true } else { false } }.count }
    var skipped: Int { outcomes.filter { $0 == .skipped }.count }
    /// How far through the cards, 0 to 1.
    var fraction: Double { groups.isEmpty ? 1 : Double(position) / Double(groups.count) }

    /// "3 of 12 · 41 sorted" (at the end, the last card's number).
    var progress: String {
        QuickSortWording.progress(card: min(position + 1, max(groups.count, 1)), of: groups.count, sorted: sortedPayments)
    }

    var canUndo: Bool { lastSorted != nil && !isUndoing && card?.isSaving != true }
    var canSkip: Bool { card != nil && !isUndoing && card?.isSaving != true && card?.newCategory.isMaking != true }

    /// Skip: this name stays Not sorted; the next card.
    func skip() {
        guard canSkip else { return }
        problem = nil
        cameBack = false
        outcomes.append(.skipped)
        showCard()
    }

    /// Undo: the last card sorted is Not sorted again (its learned name forgotten too) and shows again; the cards after
    /// it come again in order. Refused when the data changed since: the line says so, and nothing is undone.
    func undo() async {
        guard canUndo, let index = lastSorted, let undo = lastUndo else { return }
        isUndoing = true
        problem = nil
        defer { isUndoing = false }
        lastSorted = nil
        lastUndo = nil
        do {
            let outcome = try await undo.perform()
            guard outcome == .undone else {
                problem = outcome.message
                return
            }
            cameBack = true
            outcomes.removeSubrange(index...)
            showCard()
        } catch {
            problem = error.localizedDescription
        }
    }

    /// A card was sorted (`QuickSortCard.save`): counted, its undo kept, the next card.
    fileprivate func sorted(_ result: BatchChangeResult, applied: BatchChangeResult?) {
        problem = nil
        cameBack = false
        lastSorted = position
        lastUndo = result.undo
        outcomes.append(.sorted(payments: result.changed.total + (applied?.changed.total ?? 0)))
        showCard()
    }

    /// The card at the current place, passing by itself any whose payments were all sorted meanwhile.
    private func showCard() {
        while position < groups.count {
            let group = groups[position]
            let ids = QuickSort.live(group, in: store.dashboard)
            guard ids.isEmpty else {
                card = QuickSortCard(group: group, ids: ids, store: store) { [weak self] result, applied in
                    self?.sorted(result, applied: applied)
                }
                return
            }
            outcomes.append(.gone)
        }
        card = nil
    }

    /// The end's words: "84 payments sorted", "From 9 names · 3 skipped".
    var summaryTitle: String { QuickSortWording.summaryTitle(sorted: sortedPayments) }
    var summaryLine: String {
        QuickSortWording.summaryLine(names: sortedNames, skipped: skipped, left: store.quickSortTally.payments)
    }
}

/// One card's change window: the name's Not sorted payments in one direction, their side's categories as the change
/// window offers them (brief 81's `offeredCategories`), Other category… and New category (brief 80's behaviour for a
/// typed name that exists). A tile sorts at once (`sort`): no Save, no question. Brief 81's question about the shop's
/// other payments is applied by itself only when it moves this name's own Not sorted payments
/// (`QuickSort.takesFollowUp`); otherwise it is not asked.
@MainActor @Observable
final class QuickSortCard: CategoryWindow, Identifiable {
    let group: QuickSortGroup
    /// The group's payments still Not sorted when the card showed.
    let ids: Set<String>
    let dashboardStore: DashboardStore
    let picks = CategoryPicks()
    /// Their side's categories, read once when the card shows: the grid keeps its tiles while the dashboard is built
    /// again under it (a category made here or picked from the other side comes in through `picks`).
    let offered: [Category]
    private(set) var isSaving = false
    private(set) var saveError: String?
    @ObservationIgnored private let done: (BatchChangeResult, BatchChangeResult?) -> Void

    init(group: QuickSortGroup, ids: Set<String>, store: DashboardStore,
         done: @escaping (BatchChangeResult, BatchChangeResult?) -> Void) {
        self.group = group
        self.ids = ids
        dashboardStore = store
        self.done = done
        offered = store.offeredCategories(for: ids)
        if let phone = store.phone, let catalog = phone.catalog {
            picks.list = PhoneCategoryList(catalog: catalog, chosen: phone.summary.chosen)
        }
        picks.begin(mode: .switchCategory, extras: [])
    }

    var id: String { group.id }

    /// The name as its newest payment's row shows it ("Cash spent" for a hand entry without a shop).
    var title: String {
        ReceiptRowWording.title(group.newest, movement: dashboardStore.cashMovement(group.newest.receiptId))
    }

    var heading: CategoryWindowHeading? {
        CategoryWindowHeading(title: title, amount: group.signedTotal, current: CategoryName.uncategorised,
                              currentColor: PhoneDashboard.uncategorised.color, selection: true)
    }
    var loadError: String? { nil }
    func retryLoad() async {}
    var paymentSide: CategorySide? { group.side }
    var currentCategory: String? { CategoryName.uncategorised }
    var isSample: Bool { dashboardStore.isSample }
    var canSave: Bool { !isSaving && !newCategory.isMaking && target != nil && !ids.isEmpty }
    var question: RecategorisationQuestion? { nil }
    func answerRemoveCurrent(remove: Bool) async {}
    func answer(moveOthers: Bool) {}

    func working(_ work: () async throws -> Void) async {
        isSaving = true
        saveError = nil
        defer { isSaving = false }
        do { try await work() } catch { saveError = error.localizedDescription }
    }

    /// A tile: every payment of the card into it, by hand, and the name learned for new imports.
    func sort(_ name: String) async {
        guard !isSaving, !newCategory.isMaking else { return }
        select(name)
        await save()
    }

    /// Other category…'s list: offered for this side from now on (brief 69), and sorted into at once.
    func sortFromOtherSide(_ name: String) async {
        guard !isSaving, !newCategory.isMaking else { return }
        pickFromOtherSide(name)
        guard target == name else { return }
        await save()
    }

    /// New category's Create: made (or an existing one of that name used, brief 80), then sorted into at once.
    func createAndSort() async {
        guard await createCategory() != nil else { return }
        await save()
    }

    /// Brief 81's switch over every month (`BatchSpan.allMonths`): manual, learned, one save and one rebuild, with its
    /// undo. Then the flow's next card.
    func save() async {
        guard canSave, let phone = dashboardStore.phone, let target else { return }
        await working {
            try await picks.storeOtherSides(in: phone)
            let result = try await dashboardStore.switchCategory(ids: ids, to: target, span: .allMonths)
            var applied: BatchChangeResult?
            if let followUp = result.followUp,
               QuickSort.takesFollowUp(followUp.ids, of: group, in: dashboardStore.dashboard) {
                // Its own payments are sorted either way; a failure here leaves only the newcomers Not sorted.
                applied = try? await followUp.apply()
            }
            done(result, applied)
        }
    }

    func retrySave() async { await save() }
}
