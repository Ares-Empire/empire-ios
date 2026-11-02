import SwiftUI

/// A payment's page (brief 28; briefs 44 and 47 for its name). The name is its title and, in phone mode with own names
/// on, edited where it stands: a tap on it or on the pen beside it turns it into a field with the name selected and the
/// keyboard up (`PaymentRenameModel`, `RenamePlan`); Return, Done or the bar's Save saves, with "Also the other payments
/// from <bank name>?" when the shop has more; the bar's Cancel leaves the name as it was (asking first once something
/// was typed); "Use the bank's name" under the field while an own name shows. The category's chip (and the pen beside
/// it, and an extra category's chip) opens the change window, which says why the payment is in its category.
/// Money paid back (brief 203): a link's card opens the other payment's page, pushed on this sheet's own stack (the
/// arrow goes back; a link back to a page already open goes back to it), with Done closing the sheet from any page.
struct TransactionDetailSheet: View {
    @State var store: TransactionDetailStore
    let palette: Palette
    /// The name's page this page was opened from (its "All from" line would lead back there, so it shows none).
    var namePage: String? = nil
    /// The row's long press chose Rename: the page opens with the name's field ready (brief 47).
    var startsRenaming = false
    /// "All from <name>" (brief 44): the list this page was opened from closes it and shows the name's page on the
    /// dashboard's stack. Nil: no line (a page opened where no name's page can be shown).
    var openName: ((DashboardRoute) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    /// The payments opened from a link (brief 203), pushed over this one, by id.
    @State private var linked: [String] = []

    var body: some View {
        NavigationStack(path: $linked) {
            PaymentDetailPage(store: store, palette: palette, namePage: namePage, startsRenaming: startsRenaming,
                              openName: openName, isRoot: true, close: { dismiss() }, openLinked: openLinked)
                .navigationDestination(for: String.self) { id in
                    LinkedPaymentPage(id: id, dashboardStore: store.dashboardStore, palette: palette, openName: openName,
                                      close: { dismiss() }, openLinked: openLinked)
                }
        }
        .font(AppFont.text(14)).foregroundStyle(palette.ink).tint(palette.balance)
    }

    /// A link's card: the other payment's page; one already open (this sheet's first page, or one pushed) is gone back
    /// to, so following links never stacks the same two pages over and over.
    private func openLinked(_ id: String) {
        if id == store.paymentID {
            linked = []
        } else if let index = linked.firstIndex(of: id) {
            linked = Array(linked.prefix(through: index))
        } else {
            linked.append(id)
        }
    }
}

/// A payment opened from a link (brief 203): the same page on a store of its own.
private struct LinkedPaymentPage: View {
    @State private var store: TransactionDetailStore?
    let palette: Palette
    let openName: ((DashboardRoute) -> Void)?
    let close: () -> Void
    let openLinked: (String) -> Void

    init(id: String, dashboardStore: DashboardStore, palette: Palette, openName: ((DashboardRoute) -> Void)?,
         close: @escaping () -> Void, openLinked: @escaping (String) -> Void) {
        _store = State(initialValue: dashboardStore.bankPayment(id).map { dashboardStore.transactionDetailStore(for: $0) })
        self.palette = palette
        self.openName = openName
        self.close = close
        self.openLinked = openLinked
    }

    var body: some View {
        if let store {
            PaymentDetailPage(store: store, palette: palette, openName: openName, isRoot: false, close: close,
                              openLinked: openLinked)
        } else {
            EmptyMessage(text: String(localized: "This payment is no longer there."), palette: palette)
                .frame(maxHeight: .infinity, alignment: .top)
                .background { Wall(palette: palette) }
                .navigationTitle("Payment").navigationBarTitleDisplayMode(.inline)
        }
    }
}

/// One payment's page in the sheet's stack: everything the page shows and does (the name's field, the change window,
/// the receipt, the links of money paid back), with its own bar.
private struct PaymentDetailPage: View {
    @Bindable var store: TransactionDetailStore
    let palette: Palette
    var namePage: String? = nil
    var startsRenaming = false
    var openName: ((DashboardRoute) -> Void)? = nil
    /// The sheet's first page (the DEBUG launch arguments act on it only).
    let isRoot: Bool
    /// Done: the whole sheet closes, from any page.
    let close: () -> Void
    /// A link's card: the other payment's page.
    let openLinked: (String) -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    /// The name's field while it is open (brief 47).
    @State private var nameEditor: PaymentRenameModel?
    @State private var nameSelection: TextSelection?
    /// The field selects all of the name once it has the keyboard (a selection set before that is dropped).
    @State private var selectsName = false
    @FocusState private var nameFocused: Bool
    #if DEBUG
    /// Screenshots: `-openOriginal` opens the bank's own row at once and shows the page's end.
    @State private var originalExpanded = LaunchArguments.current.contains("-openOriginal")
    #else
    @State private var originalExpanded = false
    #endif
    #if DEBUG
    @State private var receiptRowsOpen = LaunchArguments.current.contains("-openReceiptText")
    #else
    @State private var receiptRowsOpen = false
    #endif

    var body: some View {
        @Bindable var paybacks = store.paybacks
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if store.isLoading { ProgressView("Loading…").frame(maxWidth: .infinity).padding(30) }
                if let error = store.loadError {
                    Text(error).foregroundStyle(palette.expenseText).padding(.vertical)
                    Button("Retry") { Task { await store.load() } }
                }
                if let detail = store.detail { record(detail) }
            }.padding(20)
        }
        .defaultScrollAnchor(showsEnd ? .bottom : .top)
        .tourScrollsToTarget()
        .background { Wall(palette: palette) }
        .tourSpotlight()
        // What a link's change did, with Undo (brief 203), above the tour's card when there is one.
        .undoBar($paybacks.undo, accent: nil)
        // The tour's card on the page itself, above the veil, where its inset is room to scroll (brief 59: on the
        // NavigationStack a ringed control low on the page could stay under the card at large text sizes).
        .tourCard()
        .navigationTitle("Payment").navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .sheet(isPresented: $store.showsRecategorisation) {
            RecategoriseSheet(window: store, palette: palette)
        }
        // Money paid back (brief 203): the window that makes or changes a link.
        .sheet(item: $paybacks.window) { window in
            PaybackSheet(window: window, store: store.dashboardStore, palette: palette)
        }
        // While the name is edited the page closes only with Save or Cancel, so nothing typed is lost by a swipe.
        .interactiveDismissDisabled(nameEditor != nil && (nameEditor?.hasChanges == true || store.isSaving
                                                          || nameEditor?.asks == true))
        .alert(renameQuestionTitle, isPresented: renameQuestionShown, presenting: nameEditor?.question) { question in
            Button("All \(question.allCount)") { Task { await nameEditor?.answer(all: true) } }
            Button("Only this one", role: .cancel) { Task { await nameEditor?.answer(all: false) } }
        } message: { question in
            Text("With All, new payments from \(question.bankName) get the name too.")
        }
        .alert(bankNameTitle, isPresented: bankNameShown, presenting: nameEditor?.bankNameQuestion) { question in
            Button("All \(question.count)") { Task { await nameEditor?.answerBankName(.all) } }
            if question.onlyThis != nil {
                Button("Only this one") { Task { await nameEditor?.answerBankName(.onlyThis) } }
            }
            Button("Cancel", role: .cancel) { Task { await nameEditor?.answerBankName(.cancel) } }
        } message: { question in
            Text("“\(question.shopName)” is your name for every payment from \(question.bankName).")
        }
        .onChange(of: nameEditor?.isDone == true) { _, done in if done { endRename() } }
        // A link made, changed or removed (here, on a payment opened from a link, or undone) builds the dashboard
        // again: the page reads its payment again, quietly.
        .onChange(of: store.dashboardStore.revision) { Task { await store.refresh() } }
        // Whether the payment can be linked: read off the main thread while the page shows (brief 203).
        .task { await store.paybacks.load() }
        .task {
            if store.detail == nil { await store.load() }
            if startsRenaming { beginRename() }
            // Sample-only routing for repeatable simulator screenshots, like the
            // existing -sampleCategory / -sampleMonth launch arguments.
            #if DEBUG
            guard isRoot else { return }
            let arguments = LaunchArguments.current
            // The change sheet open (server or phone sample): `-sampleRecategorise switch|add`, `-samplePick <category>`
            // chooses one in it.
            if let index = arguments.firstIndex(of: "-sampleRecategorise"), arguments.indices.contains(index + 1) {
                store.beginRecategorisation()
                store.mode = arguments[index + 1] == "add" ? .add : .switchCategory
                if let pick = LaunchArguments.value("-samplePick") { store.select(pick) }
                // `-otherCategoryPick <name>`: a category of the other side picked from Other category… (brief 70).
                if let pick = LaunchArguments.value("-otherCategoryPick") { store.pickFromOtherSide(pick) }
                await debugNewCategory()
                if arguments.contains("-sampleAddSave"), !store.isSample {
                    try? await Task.sleep(for: .milliseconds(900))
                    await store.save()
                    if let answer = LaunchArguments.value("-sampleRemoveAnswer"), store.removeCurrentQuestion != nil {
                        try? await Task.sleep(for: .milliseconds(900))
                        await store.answerRemoveCurrent(remove: answer == "remove")
                    }
                }
            }
            // Phone sample: a Switch to this category at once (the "also the N others" question follows).
            if !store.isSample, let index = arguments.firstIndex(of: "-samplePhoneSwitch"),
               arguments.indices.contains(index + 1) {
                store.beginRecategorisation()
                store.select(arguments[index + 1])
                // After the sheet has come up: a question asked while it still slides in is not shown.
                try? await Task.sleep(for: .milliseconds(900))
                await store.save()
            }
            // Phone sample: the joined receipt's Edit at once (`-editReceipt`).
            if !store.isSample, arguments.contains("-editReceipt"), store.receipt != nil {
                await store.editReceipt()
                store.receiptEditor?.debugType(total: LaunchArguments.value("-editReceiptTotal"))
            }
            // Phone sample: the name's field open at once (`-openRename`; `-renameText`, `-renameSave`,
            // `-renameBankName` in it), or the "All from" line tapped (`-openAllFrom`).
            if arguments.contains("-openRename") {
                beginRename()
                await debugFillName()
            }
            if arguments.contains("-openAllFrom"), let openName, let line = store.nameRoute(namePage: namePage) {
                try? await Task.sleep(for: .milliseconds(600))
                openName(line.route)
            }
            await debugPayback()
            #endif
        }
    }

    #if DEBUG
    /// Screenshots of a new category from the change window (brief 60), with `-sampleRecategorise switch|add` on a
    /// phone sample's payment of money out: `-newCategory`, `-newCategoryName <text>`, `-newCategoryCreate`
    /// (`NewCategoryModel.debugLaunch`), then `-newCategorySave` taps Save (the shop question follows when the shop has
    /// more payments) and `-newCategoryAnswer only|all` answers it.
    private func debugNewCategory() async {
        let created = await store.newCategory.debugLaunch(begin: store.beginNewCategory) { await store.createCategory() }
        guard created, LaunchArguments.current.contains("-newCategorySave") else { return }
        try? await Task.sleep(for: .milliseconds(600))
        await store.save()
        guard let answer = LaunchArguments.value("-newCategoryAnswer"), store.followUp != nil else { return }
        try? await Task.sleep(for: .milliseconds(900))
        store.answer(moveOthers: answer == "all")
    }
    #endif

    #if DEBUG
    /// Screenshots of money paid back (brief 203, phone sample): `-openPayback` opens the window (`-paybackSearch`,
    /// `-paybackPick`, `-paybackAmount` in it, `PaybackSheet`), `-editPayback` the first link's euros, `-openLinked`
    /// the first link's payment, `-scrollToPayback` the page's links in view.
    private func debugPayback() async {
        let arguments = LaunchArguments.current
        guard !store.isSample, arguments.contains("-openPayback") || arguments.contains("-editPayback")
                || arguments.contains("-openLinked") else { return }
        for _ in 0..<60 where store.detail == nil || !store.paybacks.isLoaded {
            try? await Task.sleep(for: .milliseconds(100))
        }
        guard let detail = store.detail else { return }
        let links = PaybackSectionContent(detail: detail, state: store.paybacks.state).links
        try? await Task.sleep(for: .milliseconds(600))
        if arguments.contains("-openPayback") { store.paybacks.begin(detail: detail) }
        if arguments.contains("-editPayback"), let link = links.first { store.paybacks.edit(link, detail: detail) }
        if arguments.contains("-openLinked"), let link = links.first { openLinked(link.payment) }
    }
    #endif

    /// DEBUG `-openOriginal`: the page opens at its end, where the bank's own row is.
    private var showsEnd: Bool {
        #if DEBUG
        isRoot && (LaunchArguments.current.contains("-openOriginal") || LaunchArguments.current.contains("-scrollToPayback"))
        #else
        false
        #endif
    }

    // MARK: the bar

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        if let editor = nameEditor {
            // While the name is edited: Cancel and Save, as in every iOS edit (the page's Done would leave the edit).
            ToolbarItem(placement: .cancellationAction) {
                DiscardingCancel(asks: editor.hasChanges, question: Text("Discard your changes?")) { endRename() }
                    .disabled(store.isSaving)
            }
            ToolbarItem(placement: .confirmationAction) {
                // The spinner in the word's place while it saves; the word muted by hand while it cannot save (the
                // bar's glass button shows no difference by itself).
                Button { Task { await editor.save() } } label: {
                    if editor.working == .save {
                        ProgressView().tint(palette.ink)
                    } else {
                        Text("Save").foregroundStyle(editor.canSave ? palette.ink : palette.muted)
                    }
                }
                .disabled(!editor.canSave)
                .whileWorking(store.isSaving, tapped: editor.working == .save)
                .accessibilityIdentifier("saveName")
            }
        } else {
            ToolbarItem(placement: .topBarTrailing) { Button("Done") { close() } }
        }
    }

    // MARK: the name (brief 47)

    /// The name's field opens with the name selected and the keyboard up.
    private func beginRename() {
        guard store.offersRename, !store.isSaving, nameEditor == nil else { return }
        nameEditor = PaymentRenameModel(store: store)
        selectsName = true
        nameFocused = true
    }

    /// Once the field has the keyboard: all of the name selected, so typing replaces it.
    private func selectName() async {
        guard selectsName, nameFocused, let editor = nameEditor else { return }
        selectsName = false
        await Task.yield()
        nameSelection = TextSelection(range: editor.text.startIndex..<editor.text.endIndex)
    }

    private func endRename() {
        nameFocused = false
        nameEditor = nil
        nameSelection = nil
        selectsName = false
    }

    /// The title: the name, with its pen while it can be edited where it stands; the bank's name small under an own name.
    @ViewBuilder private func title(_ detail: TransactionDetail) -> some View {
        if let editor = nameEditor, let info = store.renameInfo {
            nameField(editor, info: info)
        } else {
            VStack(alignment: .leading, spacing: 3) {
                if store.offersRename {
                    // A tap on the name or on its pen: nothing else on the title takes taps.
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Button { beginRename() } label: {
                            Text(detail.place).font(AppFont.text(22, weight: .bold)).foregroundStyle(palette.ink)
                                .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityHint(Text("Rename"))
                        .accessibilityIdentifier("paymentName")
                        PenButton(label: Text("Rename"), palette: palette) { beginRename() }
                            .accessibilityIdentifier("renamePayment")
                    }
                } else {
                    Text(detail.place).font(AppFont.text(22, weight: .bold)).accessibilityAddTraits(.isHeader)
                }
                // An own name (brief 44): the bank's name stays, small, under it.
                if let bankName = detail.bankName {
                    Text(bankName).font(AppFont.text(13.5)).foregroundStyle(palette.secondary)
                        .accessibilityLabel(Text("Bank's name: \(bankName)"))
                }
            }
        }
    }

    /// The name as a field where the title stands (its text in the title's place, a field's box around it), what renaming
    /// changes, and "Use the bank's name" while an own name shows.
    private func nameField(_ editor: PaymentRenameModel, info: PaymentRenameInfo) -> some View {
        @Bindable var editor = editor
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                TextField(text: $editor.text, selection: $nameSelection,
                          prompt: Text(verbatim: info.bankName).foregroundStyle(palette.muted)) {
                    Text("Name")
                }
                .font(AppFont.text(22, weight: .bold)).foregroundStyle(palette.ink)
                .focused($nameFocused)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit { Task { await editor.save() } }
                .onChange(of: editor.text) { _, _ in editor.limitText() }
                .onChange(of: nameFocused) { _, _ in Task { await selectName() } }
                .accessibilityIdentifier("nameField")
                if !editor.text.isEmpty {
                    // The field's clear button, as UIKit's: back to the bank's name as the placeholder.
                    Button { editor.text = "" } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 17)).foregroundStyle(palette.muted)
                            .minimumTapArea()
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Clear"))
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(palette.card2, in: shape)
            .overlay(shape.strokeBorder(palette.line))
            .contentShape(shape)
            .onTapGesture { nameFocused = true }
            .padding(.horizontal, -10)          // the name stays where it stood; the box reaches into the margin
            .disabled(store.isSaving)
            VStack(alignment: .leading, spacing: 3) {
                Text("Your bank's name: \(info.bankName)").foregroundStyle(palette.secondary)
                Text("Only the name you see changes. Categories and sorting stay as they are.")
                    .foregroundStyle(palette.muted)
            }
            .font(AppFont.text(12.5))
            .fixedSize(horizontal: false, vertical: true)
            if let error = store.saveError, !store.showsRecategorisation {
                Text(error).font(AppFont.text(13)).foregroundStyle(palette.expenseText)
                    .accessibilityIdentifier("renameError")
            }
            if info.ownName != nil {
                Button { Task { await editor.useBankName() } } label: {
                    BusyLabel(text: Text("Use the bank's name"), busy: editor.working == .bankName, tint: palette.ink)
                }
                .buttonStyle(.bordered).tint(palette.ink)
                .whileWorking(store.isSaving, tapped: editor.working == .bankName)
                .padding(.top, 2)
                .accessibilityIdentifier("useBankName")
            }
        }
        .padding(.bottom, 10)
    }

    /// As the category change asks: the count is on the button, so the sentence reads right for one payment or many.
    private var renameQuestionTitle: Text {
        guard let question = nameEditor?.question else { return Text(verbatim: "") }
        return Text("Also the other payments from \(question.bankName)?")
    }

    private var renameQuestionShown: Binding<Bool> {
        // A button answers first, so the dismissal that follows finds nothing left to answer.
        Binding(get: { nameEditor?.question != nil }, set: { shown in
            if !shown, nameEditor?.question != nil { Task { await nameEditor?.answer(all: false) } }
        })
    }

    private var bankNameTitle: Text {
        guard let question = nameEditor?.bankNameQuestion else { return Text(verbatim: "") }
        return Text("Use the bank's name for all \(question.count) payments?")
    }

    private var bankNameShown: Binding<Bool> {
        Binding(get: { nameEditor?.bankNameQuestion != nil }, set: { shown in
            if !shown, nameEditor?.bankNameQuestion != nil { Task { await nameEditor?.answerBankName(.cancel) } }
        })
    }

    #if DEBUG
    /// Screenshots: `-renameText <text>` types a name, `-renameSave` then saves (the question, when it asks),
    /// `-renameBankName` taps "Use the bank's name".
    private func debugFillName() async {
        guard let editor = nameEditor else { return }
        try? await Task.sleep(for: .milliseconds(700))
        if let text = LaunchArguments.value("-renameText") {
            editor.text = text
            nameSelection = nil
        }
        try? await Task.sleep(for: .milliseconds(900))
        if LaunchArguments.current.contains("-renameSave") { await editor.save() }
        if LaunchArguments.current.contains("-renameBankName") { await editor.useBankName() }
    }
    #endif

    // MARK: the page

    @ViewBuilder private func record(_ detail: TransactionDetail) -> some View {
        let page = PaymentPage(detail)
        VStack(alignment: .leading, spacing: 7) {
            // The tour's rename step (brief 59) rings the name and its pen, and the field while it is open.
            title(detail).tourAnchor(.paymentName)
            Text(detail.signedAmount).font(AppFont.number(28, weight: .bold))
                .foregroundStyle(detail.amount < 0 ? palette.expenseText : palette.balance)
            Text(page.date).font(AppFont.text(13.5)).foregroundStyle(palette.secondary)
        }.padding(.bottom, 20)
        if let openName, let line = store.nameRoute(namePage: namePage) {
            Button { openName(line.route) } label: { AllFromLine(name: detail.place, group: line.group, palette: palette) }
                .buttonStyle(.plain)
                .accessibilityIdentifier("allFromName")
                .padding(.bottom, 12)
        }
        lines(of: detail, page: page)
        if let receipt = store.receipt { receiptSection(receipt) }
        // Money paid back (brief 203): the links, what still counts, and the quiet action; below what the page had.
        PaybackSection(detail: detail, links: store.paybacks, palette: palette, open: openLinked)
        if let rows = detail.originalRows {
            DisclosureGroup(page.originalTitle, isExpanded: $originalExpanded) {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(rows) { row in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(row.label).foregroundStyle(palette.muted)
                            Text(row.value).foregroundStyle(palette.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.font(AppFont.number(11)).padding(.top, 12).textSelection(.enabled)
            }.font(AppFont.text(13)).padding(.top, 20)
        }
    }

    /// The page's rows: the label beside its value, the labels in one column as wide as the longest (German's
    /// "Verwendungszweck" too); at the accessibility text sizes each label above its value.
    @ViewBuilder private func lines(of detail: TransactionDetail, page: PaymentPage) -> some View {
        let lines = Line.all(detail: detail, page: page)
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(lines) { line in
                    VStack(alignment: .leading, spacing: 5) {
                        label(line)
                        value(line, detail: detail, page: page)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 10)
                    .overlay(alignment: .bottom) { divider }
                }
            }
        } else {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 0) {
                ForEach(lines) { line in
                    GridRow {
                        label(line).fixedSize().padding(.vertical, 10)
                        value(line, detail: detail, page: page).frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 10)
                    }
                    divider.gridCellUnsizedAxes(.horizontal)
                }
            }
        }
    }

    private func label(_ line: Line) -> some View {
        Text(line.label).font(AppFont.text(12, weight: .semibold)).foregroundStyle(palette.muted)
    }

    @ViewBuilder private func value(_ line: Line, detail: TransactionDetail, page: PaymentPage) -> some View {
        Group {
            switch line {
            case .category:
                // The chip and its pen open the change window (brief 47: the Change button and the reason sentence went;
                // the reason is the window's first line). Without categories to change to, the chip alone.
                if store.choices.isEmpty {
                    CategoryChip(name: detail.category, color: detail.categoryColor)
                } else {
                    HStack(alignment: .center, spacing: 4) {
                        Button { store.beginRecategorisation() } label: {
                            CategoryChip(name: detail.category, color: detail.categoryColor).minimumTapArea()
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint(Text("Change category"))
                        .accessibilityIdentifier("categoryChip")
                        PenButton(label: Text("Change category"), palette: palette) { store.beginRecategorisation() }
                            .accessibilityIdentifier("changeCategory")
                    }
                    .tourAnchor(.change)
                }
            case .tags:
                // The extra categories: a tap opens the change window at Add, where they are chosen.
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(detail.tags, id: \.self) { name in
                        let chip = CategoryChip(name: name, color: store.categoryColor(for: name))
                        if store.choices.isEmpty {
                            chip
                        } else {
                            Button { store.beginRecategorisation(mode: .add) } label: { chip.minimumTapArea() }
                                .buttonStyle(.plain)
                                .accessibilityHint(Text("Change category"))
                        }
                    }
                }
            case .account:
                if let account = page.account {
                    VStack(alignment: .leading, spacing: 3) {
                        if let name = account.name { Text(name) }
                        if let iban = account.iban {
                            Text(verbatim: iban).font(AppFont.number(12, weight: .regular)).foregroundStyle(palette.secondary)
                        }
                        if let note = account.note {
                            Text(note).font(AppFont.text(12.5)).foregroundStyle(palette.secondary)
                        }
                    }
                }
            case let .row(row):
                Text(row.value)
            }
        }.font(AppFont.text(13.5)).textSelection(.enabled)
    }

    private var divider: some View { Rectangle().fill(palette.grid).frame(height: 1) }

    /// Phone mode: the receipt joined to this payment (so it counts once): its shop and day, its lines folded, Edit
    /// (the check window filled from it, brief 33) and Unjoin.
    private func receiptSection(_ receipt: LedgerReceipt) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Receipt").font(AppFont.text(12, weight: .semibold)).foregroundStyle(palette.muted)
            Text(verbatim: ReceiptPageWording.title(receipt)).font(AppFont.text(13.5))
            Text(verbatim: ReceiptPageWording.line(receipt, withState: false)).font(AppFont.text(12.5))
                .foregroundStyle(palette.secondary)
            if !receipt.rows.isEmpty {
                ReceiptTextDisclosure(rows: receipt.rows, isExpanded: $receiptRowsOpen).padding(.horizontal, -4)
                    .padding(.top, 6)
            }
            if let error = store.saveError, !store.showsRecategorisation {
                Text(error).font(AppFont.text(12.5)).foregroundStyle(palette.expenseText)
            }
            HStack(spacing: 8) {
                Button("Edit") { Task { await store.editReceipt() } }
                Button("Unjoin") { Task { await store.unjoinReceipt() } }
            }
            .buttonStyle(.bordered).disabled(store.isSaving).padding(.top, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 20)
        .sheet(isPresented: Binding(get: { store.receiptEditor?.editing != nil },
                                    set: { if !$0 { store.receiptEditor?.endEdit() } })) {
            if let editor = store.receiptEditor { ReceiptEditSheet(page: editor, palette: palette) }
        }
    }

    /// One row of the page, in order: the category, the other categories it is also in, the account, then the plain rows.
    /// (Brief 44's Name row went with brief 47: the name is edited where it stands.)
    private enum Line: Identifiable {
        case category, tags, account
        case row(DetailRow)

        var id: String {
            switch self {
            case .category: "category"
            case .tags: "tags"
            case .account: "account"
            case let .row(row): "row:" + row.label
            }
        }

        var label: String {
            switch self {
            case .category: String(localized: "Category")
            case .tags: String(localized: "Also in")
            case .account: String(localized: "Account")
            case let .row(row): row.label
            }
        }

        static func all(detail: TransactionDetail, page: PaymentPage) -> [Line] {
            [.category] + (detail.tags.isEmpty ? [] : [.tags])
                + (page.account == nil ? [] : [.account]) + page.rows.map(Line.row)
        }
    }
}

/// The payment page's "All from <name>" line (brief 44): the name's count and money, as a dashboard row in a card; it
/// opens the name's page.
struct AllFromLine: View {
    let name: String
    let group: PaymentNameGroup
    let palette: Palette

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        HStack(spacing: 12) {
            Image(systemName: "rectangle.stack").font(.system(size: 17, weight: .medium)).foregroundStyle(palette.secondary)
                .frame(width: 38, height: 38)
                .background(palette.card2, in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(palette.line))
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: NameWording.allFrom(name)).font(AppFont.text(14.5, weight: .semibold)).lineLimit(1)
                Text(verbatim: NameWording.summary(group)).font(AppFont.text(12.5)).foregroundStyle(palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right").font(.system(size: 11, weight: .medium)).foregroundStyle(palette.muted)
        }
        .foregroundStyle(palette.ink)
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(palette.card, in: shape)
        .overlay(shape.stroke(palette.line))
        .contentShape(shape)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

/// The small pen beside what a tap changes (brief 47: the payment's name, its category): muted ink, drawn small (15 pt
/// at the default text size), a real button that takes taps over 44 × 44 pt, named for VoiceOver.
struct PenButton: View {
    let label: Text
    let palette: Palette
    let action: () -> Void
    /// Small beside the text it changes, and growing with it at the larger text sizes.
    @ScaledMetric(relativeTo: .body) private var size: CGFloat = 15

    var body: some View {
        Button(action: action) {
            Image(systemName: "pencil").font(.system(size: size, weight: .medium)).foregroundStyle(palette.muted)
                .minimumTapArea()
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

struct CategoryChip: View {
    let name: String
    let color: String
    var body: some View {
        Text(CategoryName.shown(name)).font(AppFont.text(12.5, weight: .semibold)).foregroundStyle(Color(hex: color))
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(Color(hex: color).opacity(0.12), in: Capsule())
            .overlay(Capsule().stroke(Color(hex: color).opacity(0.20)))
    }
}
