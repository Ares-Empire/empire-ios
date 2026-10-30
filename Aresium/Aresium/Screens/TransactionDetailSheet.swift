import SwiftUI

struct TransactionDetailSheet: View {
    @State var store: TransactionDetailStore
    let palette: Palette
    /// The name's page this page was opened from (its "All from" line would lead back there, so it shows none).
    var namePage: String? = nil
    /// "All from <name>" (brief 44): the list this page was opened from closes it and shows the name's page on the
    /// dashboard's stack. Nil: no line (a page opened where no name's page can be shown).
    var openName: ((DashboardRoute) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
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
        NavigationStack {
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
            .navigationTitle("Payment").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
            .sheet(isPresented: $store.showsRecategorisation) {
                RecategoriseSheet(store: store, palette: palette)
            }
            .sheet(isPresented: $store.showsRename) {
                RenameSheet(store: store, palette: palette)
            }
        }
        .tourCard()
        .font(AppFont.text(14)).foregroundStyle(palette.ink).tint(palette.balance)
        .task {
            if store.detail == nil { await store.load() }
            // Sample-only routing for repeatable simulator screenshots, like the
            // existing -sampleCategory / -sampleMonth launch arguments.
            #if DEBUG
            let arguments = LaunchArguments.current
            // The change sheet open (server or phone sample): `-sampleRecategorise switch|add`, `-samplePick <category>`
            // chooses one in it.
            if let index = arguments.firstIndex(of: "-sampleRecategorise"), arguments.indices.contains(index + 1) {
                store.beginRecategorisation()
                store.mode = arguments[index + 1] == "add" ? .add : .switchCategory
                if let pick = LaunchArguments.value("-samplePick") { store.select(pick) }
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
            // Phone sample: Rename at once (`-openRename`; `-renameText`, `-renameSave` in the window), or the
            // "All from" line tapped (`-openAllFrom`).
            if arguments.contains("-openRename") { store.beginRename() }
            if arguments.contains("-openAllFrom"), let openName, let line = store.nameRoute(namePage: namePage) {
                try? await Task.sleep(for: .milliseconds(600))
                openName(line.route)
            }
            #endif
        }
    }

    /// DEBUG `-openOriginal`: the page opens at its end, where the bank's own row is.
    private var showsEnd: Bool {
        #if DEBUG
        LaunchArguments.current.contains("-openOriginal")
        #else
        false
        #endif
    }

    @ViewBuilder private func record(_ detail: TransactionDetail) -> some View {
        let page = PaymentPage(detail)
        VStack(alignment: .leading, spacing: 7) {
            VStack(alignment: .leading, spacing: 3) {
                Text(detail.place).font(AppFont.text(22, weight: .bold))
                // An own name (brief 44): the bank's name stays, small, under it.
                if let bankName = detail.bankName {
                    Text(bankName).font(AppFont.text(13.5)).foregroundStyle(palette.secondary)
                        .accessibilityLabel(Text("Bank's name: \(bankName)"))
                }
            }
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
        let lines = Line.all(detail: detail, page: page, rename: store.offersRename)
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
            case .name:
                // Where the shown name comes from, and Rename (brief 44), as the category's reason and Change below.
                VStack(alignment: .leading, spacing: 8) {
                    Text(NameWording.source(detail.ownNameSource,
                                            bankName: store.renameInfo?.bankName ?? detail.bankName ?? detail.place))
                        .font(AppFont.text(12.5)).foregroundStyle(palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Rename") { store.beginRename() }.buttonStyle(.bordered)
                        .disabled(store.isSaving)
                        .accessibilityIdentifier("renamePayment")
                }
            case .category:
                VStack(alignment: .leading, spacing: 8) {
                    CategoryChip(name: detail.category, color: detail.categoryColor)
                    if let reason = page.categoryReason {
                        Text(reason).font(AppFont.text(12.5)).foregroundStyle(palette.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !store.choices.isEmpty {
                        // Apple's regular size (brief 41; the small one was about 28 pt tall): drawn 32 pt tall, it
                        // takes taps about 5 pt beyond its edges by itself (measured on iOS 27.0).
                        Button("Change") { store.beginRecategorisation() }.buttonStyle(.bordered)
                            .accessibilityIdentifier("changeCategory")
                            .tourAnchor(.change)
                    }
                }
            case .tags:
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(detail.tags, id: \.self) { name in
                        CategoryChip(name: name, color: store.categoryColor(for: name))
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

    /// One row of the page, in order: the name (phone mode, own names on), the category, the other categories it is also
    /// in, the account, then the plain rows.
    private enum Line: Identifiable {
        case name, category, tags, account
        case row(DetailRow)

        var id: String {
            switch self {
            case .name: "name"
            case .category: "category"
            case .tags: "tags"
            case .account: "account"
            case let .row(row): "row:" + row.label
            }
        }

        var label: String {
            switch self {
            case .name: String(localized: "Name")
            case .category: String(localized: "Category")
            case .tags: String(localized: "Also in")
            case .account: String(localized: "Account")
            case let .row(row): row.label
            }
        }

        static func all(detail: TransactionDetail, page: PaymentPage, rename: Bool) -> [Line] {
            (rename ? [.name] : []) + [.category] + (detail.tags.isEmpty ? [] : [.tags])
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
