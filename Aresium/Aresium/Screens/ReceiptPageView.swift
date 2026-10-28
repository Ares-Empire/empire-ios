import SwiftUI

// A receipt's page and the lists that lead to it (brief 31), in the payment page's look (TransactionDetailSheet: the
// shop, the amount, the day written out, then labelled rows in one column) on the windows' ink (`Ink`). The logic is
// `ReceiptPageModel` and `PhoneBackend`'s receipt work.

/// The receipt's page: shop, amount, day, Card or Cash and where it stands, its category with Change, the bank payment
/// it is joined to (Unjoin) or Join with a payment…, "As on the receipt", Delete receipt; Edit in the bar opens the check
/// window filled from it (brief 33). A cash receipt or spent entry has Paid from (Automatic or a source, with where the
/// cash came from); a hand entry's page is the same page with Edit opening Add cash's window and Delete entry.
struct ReceiptPageView: View {
    @State var model: ReceiptPageModel
    let palette: Palette
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var confirmsDelete = false
    @State private var choosingPayment = false
    @State private var choosingSource = false
    #if DEBUG
    @State private var rowsOpen = LaunchArguments.current.contains("-openReceiptText")
    #else
    @State private var rowsOpen = false
    #endif

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let receipt = model.receipt { page(receipt) }
                else if let problem = model.problem { FormProblem(text: problem) }
                else { ProgressView().tint(Ink.secondary).frame(maxWidth: .infinity).padding(30) }
            }
            .padding(20)
        }
        .scrollIndicators(.hidden)
        .background { Ink.background.ignoresSafeArea() }
        .navigationTitle(isEntry ? Text("Cash entry") : Text("Receipt")).navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { Task { await model.beginEdit() } } label: { Text("Edit") }
                    .disabled(model.receipt == nil || model.isWorking)
            }
        }
        .navigationDestination(isPresented: $choosingPayment) { ReceiptJoinList(model: model, palette: palette) }
        .navigationDestination(isPresented: $choosingSource) {
            PaidFromList(sources: { model.cash == nil ? nil : model.sources }, day: model.receipt?.date ?? "",
                         selected: model.receipt?.paidFrom) { source in
                Task { await model.setPaidFrom(source) }
            }
        }
        .sheet(isPresented: Binding(get: { model.editing != nil }, set: { if !$0 { model.endEdit() } })) {
            ReceiptEditSheet(page: model, palette: palette)
        }
        .confirmationDialog(isEntry ? Text("Delete this entry?") : Text("Delete this receipt?"), isPresented: $confirmsDelete,
                            titleVisibility: .visible) {
            Button(role: .destructive) { Task { await model.delete() } } label: {
                isEntry ? Text("Delete entry") : Text("Delete receipt")
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if !isEntry { Text("Its bank payment, if it has one, counts as before.") }
            else if model.receipt?.direction == .in { Text("What was paid from it is taken from other cash again.") }
            else { Text("It no longer counts in its category.") }
        }
        .task {
            if model.receipt == nil { await model.load() }
            #if DEBUG
            // Screenshots: `-openPaidFrom` opens Paid from once the page has loaded.
            if LaunchArguments.current.contains("-openPaidFrom"), model.hasPaidFrom { choosingSource = true }
            // Screenshots: `-editReceipt` opens Edit at once (`-editReceiptTotal <text>` types a new total in it).
            if LaunchArguments.current.contains("-editReceipt"), model.editing == nil {
                await model.beginEdit()
                model.debugType(total: LaunchArguments.value("-editReceiptTotal"))
            }
            #endif
        }
        .onChange(of: model.isDeleted) { _, deleted in if deleted { dismiss() } }
    }

    /// A hand entry (Add cash), not a scanned receipt.
    private var isEntry: Bool { model.receipt?.kind == .manual }

    @ViewBuilder private func page(_ receipt: LedgerReceipt) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(verbatim: ReceiptPageWording.title(receipt)).font(AppFont.text(22, weight: .bold)).foregroundStyle(Ink.primary)
            Text(verbatim: ReceiptPageWording.amount(receipt)).font(AppFont.number(28, weight: .bold))
                .foregroundStyle(receipt.direction == .in ? palette.income : palette.expenseText)
            Text(verbatim: PaymentWording.date(receipt.date) ?? receipt.date).font(AppFont.text(13.5))
                .foregroundStyle(Ink.secondary)
        }
        .padding(.bottom, 20)
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 0) {
            if receipt.direction == .in {
                // Cash received: what it still holds, after what was paid from it.
                line(String(localized: "Left")) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(verbatim: Money.precise(model.movement?.left ?? receipt.totalValue))
                        Text(verbatim: ReceiptPageWording.standing(receipt)).font(AppFont.text(12.5))
                            .foregroundStyle(Ink.secondary)
                    }
                }
            } else {
                line(String(localized: "Paid by")) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(verbatim: ReceiptPageWording.method(receipt.method))
                        Text(verbatim: isEntry ? String(localized: "Entered by hand") : ReceiptPageWording.standing(receipt))
                            .font(AppFont.text(12.5)).foregroundStyle(Ink.secondary)
                        if let euros = ReceiptPageWording.euros(receipt) {
                            Text(verbatim: euros).font(AppFont.text(12.5)).foregroundStyle(Ink.secondary)
                        }
                    }
                }
            }
            if model.hasPaidFrom {
                line(String(localized: "Paid from")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(verbatim: model.paidFromChoice)
                        if let from = model.paidFromLine {
                            Text(verbatim: from).font(AppFont.text(12.5)).foregroundStyle(Ink.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Button("Change") { choosingSource = true }
                            .buttonStyle(.bordered).controlSize(.small).disabled(model.isWorking)
                    }
                }
            }
            if receipt.state != .joined {
                line(String(localized: "Category")) {
                    VStack(alignment: .leading, spacing: 8) {
                        CategoryChip(name: model.categoryName ?? PhoneDashboard.uncategorised.name, color: model.categoryColor)
                        Menu {
                            Picker(String(localized: "Category"), selection: Binding(
                                get: { receipt.category },
                                set: { category in Task { await model.setCategory(category) } })) {
                                ForEach(model.choices) { choice in Text(verbatim: choice.name).tag(choice.id) }
                            }
                        } label: {
                            Text("Change")
                        }
                        .buttonStyle(.bordered).controlSize(.small).disabled(model.isWorking)
                    }
                }
            }
            if let payment = model.payment {
                line(String(localized: "Bank payment")) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(verbatim: payment.place)
                        Text(verbatim: [PaymentWording.date(payment.bookingDate) ?? payment.bookingDate,
                                        Money.transaction(payment.amountValue)].joined(separator: " · "))
                            .font(AppFont.text(12.5)).foregroundStyle(Ink.secondary)
                        Button("Unjoin") { Task { await model.unjoin() } }
                            .buttonStyle(.bordered).controlSize(.small).disabled(model.isWorking)
                    }
                }
            }
        }
        .font(AppFont.text(13.5)).foregroundStyle(Ink.primary)
        if let problem = model.problem { FormProblem(text: problem).padding(.top, 14) }
        if !receipt.rows.isEmpty {
            ReceiptTextDisclosure(rows: receipt.rows, isExpanded: $rowsOpen).padding(.top, 20).padding(.horizontal, -4)
        }
        VStack(spacing: 10) {
            if receipt.state == .waiting, receipt.kind == .receipt {
                Button {
                    choosingPayment = true
                } label: {
                    Text("Join with a payment…")
                }
                .buttonStyle(QuietButtonStyle())
            }
            Button(role: .destructive) {
                confirmsDelete = true
            } label: {
                (isEntry ? Text("Delete entry") : Text("Delete receipt")).foregroundStyle(FormButtonStyle.dangerInk)
            }
            .buttonStyle(FormButtonStyle(kind: .destructive, accent: nil))
        }
        .disabled(model.isWorking)
        .padding(.top, 28)
    }

    /// One labelled row; at the accessibility text sizes the label stands above its value.
    @ViewBuilder private func line(_ label: String, @ViewBuilder value: () -> some View) -> some View {
        if typeSize.isAccessibilitySize {
            GridRow {
                VStack(alignment: .leading, spacing: 5) {
                    Text(verbatim: label).font(AppFont.text(12, weight: .semibold)).foregroundStyle(Ink.muted)
                    value()
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 10)
                .gridCellColumns(2)
            }
        } else {
            GridRow {
                Text(verbatim: label).font(AppFont.text(12, weight: .semibold)).foregroundStyle(Ink.muted)
                    .fixedSize().padding(.vertical, 10)
                value().frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 10)
            }
        }
        Rectangle().fill(Ink.line).frame(height: 1).gridCellUnsizedAxes(.horizontal)
    }
}

/// Edit: the check window filled from the saved receipt, then (when the corrected values have bank payments to ask
/// about) "Is this the same payment?" in the same sheet. Cancel leaves the receipt as it was; the window closes only
/// with Cancel, so typed values are not lost by a swipe.
struct ReceiptEditSheet: View {
    let page: ReceiptPageModel
    let palette: Palette

    var body: some View {
        NavigationStack {
            Group {
                switch page.editing?.phase {
                case .checking(let check)?:
                    ReceiptCheckView(model: check, palette: palette) { await page.saveEdit(check) }
                case .asking(let question)?:
                    ReceiptQuestionView(question: question, palette: palette, problem: page.problem) { paymentID in
                        await page.answerEdit(question, with: paymentID)
                    }
                case .entry(let entry)?:
                    CashEntryView(model: entry) { await page.saveEntry(entry) }
                case nil:
                    Color.clear
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background { Ink.background.ignoresSafeArea() }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !isAsking {                      // the question is answered in the window; a swipe lets it wait
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { page.endEdit() }
                    }
                }
            }
        }
        .tint(Ink.primary)
        .presentationBackground(Ink.background)
        .interactiveDismissDisabled(!isAsking)
    }

    private var isAsking: Bool {
        if case .asking? = page.editing?.phase { true } else { false }
    }

    private var title: Text {
        switch page.editing?.phase {
        case .asking?: Text("Receipt")
        case .entry?: Text("Edit entry")
        default: Text("Edit receipt")
        }
    }
}

/// The receipt's page as a sheet (from a dashboard row), with Done.
struct ReceiptPageSheet: View {
    let model: ReceiptPageModel
    let palette: Palette
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ReceiptPageView(model: model, palette: palette)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button { dismiss() } label: { Text("Done", tableName: "Shared") }
                    }
                }
        }
        .tint(Ink.primary)
        .presentationBackground(Ink.background)
    }
}

/// "Join with a payment…": the bank payments that may be this receipt's; a tap joins it.
struct ReceiptJoinList: View {
    let model: ReceiptPageModel
    let palette: Palette
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                FormNote(text: String(localized: "Payments from the receipt's day to a week later. Tap the one this receipt belongs to."))
                    .padding(.top, 16)
                if let options = model.joinOptions {
                    if options.isEmpty {
                        Text("No bank payment fits yet. The receipt waits for the bank statement.")
                            .font(AppFont.text(14)).foregroundStyle(Ink.secondary).padding(.top, 22).padding(.horizontal, 4)
                    } else {
                        let same = options.filter { $0.candidate?.why == .severalSame }.count
                        SettingsSection(String(localized: "Bank payments")) {
                            ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                                if index > 0 { TileRowDivider() }
                                Button {
                                    Task {
                                        await model.join(option.payment.id)
                                        if model.problem == nil { dismiss() }
                                    }
                                } label: {
                                    VStack(alignment: .leading, spacing: 0) {
                                        FileCheckPaymentRow(payment: PreviewPayment(option.payment), palette: palette)
                                        if let difference = ReceiptWording.difference(option.candidate, sameAmount: same) {
                                            Text(verbatim: difference).font(AppFont.text(12.5)).foregroundStyle(Ink.secondary)
                                                .padding(.leading, 64).padding(.trailing, 14).padding(.bottom, 10)
                                                .padding(.top, -4)
                                        }
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain).disabled(model.isWorking)
                            }
                        }
                        .padding(.top, 22)
                    }
                } else {
                    ProgressView().tint(Ink.secondary).frame(maxWidth: .infinity).padding(30)
                }
                if let problem = model.problem { FormProblem(text: problem).padding(.top, 12) }
            }
            .padding(.horizontal, 18).padding(.bottom, 24)
        }
        .background { Ink.background.ignoresSafeArea() }
        .navigationTitle(Text("Join with a payment")).navigationBarTitleDisplayMode(.inline)
        .task { await model.loadJoinOptions() }
    }
}

/// A list of receipts, each opening its page: Settings → Receipts (all, with where each stands), and a withdrawal's
/// "Covered by receipts" row (the receipts that took its cash).
struct ReceiptListView: View {
    let phone: PhoneBackend
    let palette: Palette
    /// Only these receipts (a covered row's); nil: all.
    var only: [String]? = nil
    let changed: () async -> Void
    @State private var receipts: [LedgerReceipt]?
    @State private var problem: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                FormNote(text: only == nil
                         ? String(localized: "Receipts you scanned or picked and cash you entered, newest first. Of a receipt only what was read is kept, never the photo.")
                         : String(localized: "This cash was spent with these receipts and entries, so it is counted with them."))
                    .padding(.top, 16)
                if let receipts {
                    if receipts.isEmpty {
                        Text("No receipts yet. Import → Scan receipt or Choose photo adds one.")
                            .font(AppFont.text(14)).foregroundStyle(Ink.secondary).padding(.top, 22).padding(.horizontal, 4)
                    } else {
                        SettingsSection(String(localized: "Receipts")) {
                            ForEach(Array(receipts.enumerated()), id: \.element.id) { index, receipt in
                                if index > 0 { TileRowDivider() }
                                NavigationLink {
                                    ReceiptPageView(model: ReceiptPageModel(id: receipt.id, phone: phone) {
                                        await changed()
                                    }, palette: palette)
                                } label: {
                                    ReceiptSummaryRow(receipt: receipt, palette: palette, showsState: true)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.top, 22)
                    }
                } else if let problem {
                    FormProblem(text: problem).padding(.top, 16)
                } else {
                    ProgressView().tint(Ink.secondary).frame(maxWidth: .infinity).padding(30)
                }
            }
            .padding(.horizontal, 18).padding(.bottom, 24)
        }
        .background { Ink.background.ignoresSafeArea() }
        .navigationTitle(only == nil ? Text("Receipts") : Text("Accounted for")).navigationBarTitleDisplayMode(.inline)
        .onAppear { Task { await load() } }          // also back from a page that changed or deleted one
    }

    private func load() async {
        do {
            let all = try await phone.receipts()
            receipts = only.map { ids in all.filter { ids.contains($0.id) } } ?? all
        } catch {
            problem = error.localizedDescription
        }
    }
}

/// A withdrawal's "Covered by receipts" row as a sheet, with Done.
struct CoveredReceiptsSheet: View {
    let phone: PhoneBackend
    let receiptIDs: [String]
    let palette: Palette
    let changed: () async -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ReceiptListView(phone: phone, palette: palette, only: receiptIDs, changed: changed)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button { dismiss() } label: { Text("Done", tableName: "Shared") }
                    }
                }
        }
        .tint(Ink.primary)
        .presentationBackground(Ink.background)
    }
}
