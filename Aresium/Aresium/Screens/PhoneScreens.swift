import SwiftUI
import UIKit
import UniformTypeIdentifiers

// Phone mode's own screens, built from Aresium's pieces: the dashboard's rows (`CategoryTile`, `DayTile`, the metrics
// of `ValueRow` and the payment list: 38 pt tiles, 14.5 pt titles, 12.5 pt lines; the website's `.cat-row` and
// `.txn-row`), the Settings pieces (`SettingsSection`, glass cards, `FormNote`, `FormButtonStyle`) and Aresium's palette.
// Ink only: the colours are the categories' own and the dashboard's expense and income. The logic is in Model/
// (ModeStore, CategoryPickerModel, PhoneDataModel). An unknown bank's file has its own window (FileCheck*.swift).

/// The file types phone mode imports: bank CSVs, CAMT XML, MT940 (`.sta`, `.mt940`, `.txt`) and ZIP (which gets "unzip
/// it first").
enum PhoneImportTypes {
    static var all: [UTType] { [.commaSeparatedText, .xml, .mt940, .plainText, .zip] }
}

extension UTType {
    /// MT940 statements (`.sta`, `.mt940`), declared in Info.plist (`UTImportedTypeDeclarations`), so the share sheet
    /// offers Aresium for them.
    static let mt940 = UTType(importedAs: "de.ares-empire.aresium.mt940", conformingTo: .plainText)
}

/// The line between rows that start with a 38 pt tile: it begins under the row's words, as iOS's own lists do.
struct TileRowDivider: View {
    var body: some View { SettingsDivider().padding(.leading, 48) }
}

// MARK: - the mode

/// While the phone's store opens (a moment at launch), or when it did not open: a calm centred state (a mark in a thin
/// circle, as `CalmDone`) with Try again.
struct ModeStatusScreen: View {
    let modes: ModeStore
    let palette: Palette

    var body: some View {
        Group {
            switch modes.state {
            case .failed(let message):
                state(symbol: "exclamationmark", title: Text("Aresium could not open your data"),
                      text: Text(verbatim: message))
            default:
                ProgressView().tint(palette.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func state(symbol: String, title: Text, text: Text) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                ZStack {
                    Circle().fill(palette.card2)
                    Circle().strokeBorder(palette.line, lineWidth: 1)
                    Image(systemName: symbol).font(.system(size: 21, weight: .medium)).foregroundStyle(palette.secondary)
                }
                .frame(width: 64, height: 64)
                .accessibilityHidden(true)
                title.font(AppFont.text(20, weight: .bold)).foregroundStyle(palette.ink)
                    .multilineTextAlignment(.center).padding(.top, 22)
                text.font(AppFont.text(14)).foregroundStyle(palette.secondary).lineSpacing(3)
                    .multilineTextAlignment(.center).padding(.top, 10)
                // The header's quiet button look (card and line), with words.
                Button { Task { await modes.retry() } } label: {
                    Text("Try again").font(AppFont.text(15, weight: .semibold)).foregroundStyle(palette.ink)
                        .padding(.horizontal, 24).frame(minHeight: 44)
                        .background(palette.card, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(palette.line))
                        .contentShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .padding(.top, 26)
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 32).padding(.vertical, 40)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .defaultScrollAnchor(.center)
    }
}

// MARK: - the first screen

/// Phone mode without data (brief 25, Patrik 2026-10-27): a calm empty state a little above the middle, as the store's
/// own states look (`ModeStatusScreen`: a mark in a thin circle, a title, a line): "No data yet", what Aresium does and
/// that it all stays on this iPhone, then Import data (the main button: Import's menu, `ImportMenu`, whose Choose file
/// opens the file picker; the category picker follows an import that added payments while none is chosen,
/// `ImportStore`) and Start tour (quiet, the header's button look),
/// then two quiet links: How do I get my file? and Restore from an export. It comes back after the tour while there is
/// no data (`MainScreen`). It is the main screen for now, so it ends with the band.
struct PhoneFirstScreen: View {
    let imports: ImportStore
    let palette: Palette
    let band: AresiumBand
    /// Why the last restore did not go through.
    var restoreProblem: String?
    /// Import data: Choose file, Scan receipt, Choose photo.
    let importChoices: ImportChoices
    let startTour: () -> Void
    /// The bank guide (`BankGuideSheet`).
    let openGuide: () -> Void
    let restore: () -> Void
    /// The scroll view's height: the content stands a little above its middle.
    @State private var visibleHeight: CGFloat = 0

    var body: some View {
        WordmarkScrollView {
            content
                .padding(.horizontal, 28).padding(.vertical, 24)
                .frame(maxWidth: .infinity)
                .frame(minHeight: visibleHeight * 0.82)
                .onGeometryChange(for: CGFloat.self) { $0.bounds(of: .scrollView)?.height ?? 0 } action: {
                    visibleHeight = $0
                }
        } band: { _ in band }
        .scrollBounceBehavior(.always)
    }

    private var content: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle().fill(palette.card2)
                Circle().strokeBorder(palette.line, lineWidth: 1)
                Image(systemName: "tray").font(.system(size: 22, weight: .medium)).foregroundStyle(palette.secondary)
            }
            .frame(width: 64, height: 64)
            .accessibilityHidden(true)
            Text("No data yet").font(AppFont.text(21, weight: .bold)).foregroundStyle(palette.ink)
                .multilineTextAlignment(.center).padding(.top, 22)
                .accessibilityAddTraits(.isHeader)
            Text("Aresium sorts the payments from your bank's file into categories and adds them up. Everything stays on this iPhone.")
                .font(AppFont.text(14)).foregroundStyle(palette.secondary).lineSpacing(3)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
            VStack(spacing: 10) {
                ImportMenu(choices: importChoices) {
                    BusyLabel(text: imports.isBusy ? Text("Reading the file…") : Text("Import data"), busy: imports.isBusy)
                }
                .buttonStyle(FormButtonStyle(accent: nil, busy: imports.isBusy))
                .allowsHitTesting(!imports.isBusy)
                // The header's quiet button look (card and line), with words.
                Button(action: startTour) {
                    Text("Start tour").font(AppFont.text(15, weight: .semibold)).foregroundStyle(palette.ink)
                        .lineLimit(1).minimumScaleFactor(0.85)
                        .padding(.horizontal, 16).frame(maxWidth: .infinity, minHeight: 50)
                        .background(palette.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(palette.line))
                        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: 360)
            .padding(.top, 28)
            VStack(spacing: 2) {
                GuideLink(tint: palette.secondary, action: openGuide)
                Button(action: restore) {
                    Text("Restore from an export").font(AppFont.text(13.5, weight: .semibold))
                        .foregroundStyle(palette.secondary)
                        .frame(minHeight: 32).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 18)
            if let restoreProblem { FormProblem(text: restoreProblem).padding(.top, 10).frame(maxWidth: 360) }
        }
    }
}

// MARK: - categories

/// The category picker: the default list by group, each category as the dashboard's rows draw it with a tick on the
/// right and, quietly before it, how many payments it has or would get if ticked; one's own names below; unticking a
/// category with payments asks where they go (`UntickSheet`). Pushed from Settings, or in a sheet after an import that
/// added payments while none is chosen, with a line on top that they are in.
struct CategoryPickerScreen: View {
    @State var model: CategoryPickerModel
    /// Opened after an import (`ImportStore.asksForCategories`): the line that the payments are in.
    var afterImport = false
    var done: (() -> Void)? = nil
    @FocusState private var typing: Bool
    @Environment(\.dynamicTypeSize) private var typeSize

    /// What the picker is for; with numbers on the rows, also what they mean.
    private var note: String {
        let note = String(localized: "Tick the categories you use. Aresium sorts payments only into these; what fits none of them waits as Not sorted.")
        guard model.showsCounts else { return note }
        return note + " " + String(localized: "The number by a category is how many of your payments it has, or would get once ticked.")
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if afterImport {
                        Text("Your payments are in. Aresium sorts them as you tick.")
                            .font(AppFont.text(14.5, weight: .semibold)).foregroundStyle(Ink.primary).lineSpacing(3)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4).padding(.top, 16)
                    }
                    FormNote(text: note)
                        .padding(.top, afterImport ? 8 : 16)
                    ForEach(model.groups) { group in
                        SettingsSection(group.title) {
                            ForEach(Array(group.items.enumerated()), id: \.element.id) { index, item in
                                if index > 0 { TileRowDivider() }
                                row(item)
                            }
                        }
                    }
                    SettingsSection(String(localized: "Your own")) {
                        ForEach(model.custom) { item in
                            row(item)
                            TileRowDivider()
                        }
                        addRow
                    }
                    if let problem = model.problem { FormProblem(text: problem).padding(.top, 12) }
                }
                .padding(.horizontal, 18).padding(.bottom, 34)
            }
            .task {
                await model.load()
                #if DEBUG
                await debugLaunch(proxy)
                #endif
            }
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .background { Ink.background.ignoresSafeArea() }
        .navigationTitle(Text("Categories"))
        .navigationSubtitle(Text("\(model.chosenCount) chosen"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let done {
                ToolbarItem(placement: .confirmationAction) { Button("Done", action: done) }
            }
        }
        .tint(Ink.primary)
        .sheet(item: Binding(get: { model.untick }, set: { if $0 == nil { model.cancelUntick() } })) { untick in
            UntickSheet(untick: untick) { model.resolve(moveTo: $0) }
        }
    }

    #if DEBUG
    /// Screenshots: `-sampleTick <id,id,…>` ticks those at once, `-sampleUntick <category id>` unticks one (the question
    /// where its payments go), `-scrollToCategory <id>` scrolls to its row, `-samplePickerDone` then closes the picker.
    private func debugLaunch(_ proxy: ScrollViewProxy) async {
        let arguments = LaunchArguments.current
        let ticked = Set((model.groups.flatMap(\.items) + model.custom).filter(\.chosen).map(\.id))
        for id in (LaunchArguments.value("-sampleTick") ?? "").split(separator: ",").map(String.init)
        where !ticked.contains(id) { await model.toggle(id) }
        if let index = arguments.firstIndex(of: "-sampleUntick"), arguments.indices.contains(index + 1) {
            await model.toggle(arguments[index + 1])
        }
        if let id = LaunchArguments.value("-scrollToCategory") {
            try? await Task.sleep(for: .milliseconds(300))
            proxy.scrollTo(id, anchor: .top)
        }
        if arguments.contains("-samplePickerDone") { done?() }
    }
    #endif

    private func row(_ item: CategoryGroup.Item) -> some View {
        let count = model.count(of: item.id)
        let name = Text(verbatim: item.name).font(AppFont.text(14.5, weight: .semibold)).foregroundStyle(Ink.primary)
        return Button { Task { await model.toggle(item.id) } } label: {
            HStack(spacing: 12) {
                CategoryTile(icon: item.look.icon, color: item.look.color)
                if typeSize.isAccessibilitySize {
                    // The largest text sizes: the number under the name, so the name keeps the row's width.
                    VStack(alignment: .leading, spacing: 2) {
                        name
                        if let count { countLabel(count) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    name.frame(maxWidth: .infinity, alignment: .leading)
                    if let count { countLabel(count) }
                }
                Image(systemName: item.chosen ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 21, weight: .regular))
                    .foregroundStyle(item.chosen ? Ink.primary : Ink.muted)
                    .contentTransition(.symbolEffect(.replace))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(SettingsRowStyle())
        .disabled(model.isWorking)
        .accessibilityAddTraits(item.chosen ? .isSelected : [])
    }

    /// How many payments a category has (or would get): a quiet number, read out as "34 payments".
    private func countLabel(_ count: Int) -> some View {
        Text(count, format: .number).font(AppFont.number(12.5, weight: .medium)).foregroundStyle(Ink.muted)
            .lineLimit(1).fixedSize()
            .accessibilityLabel(Text("\(count) payments"))
    }

    /// A name of one's own: a plus tile, the field, Add.
    private var addRow: some View {
        let canAdd = !model.newName.trimmingCharacters(in: .whitespaces).isEmpty && !model.isWorking
        return HStack(spacing: 12) {
            Image(systemName: "plus").font(.system(size: 16, weight: .medium)).foregroundStyle(Ink.secondary)
                .frame(width: 38, height: 38)
                .background(Ink.card2, in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(Ink.line))
                .accessibilityHidden(true)
            TextField("", text: $model.newName, prompt: Text("A category of your own").foregroundStyle(Ink.muted))
                .font(AppFont.text(15)).foregroundStyle(Ink.primary)
                .textInputAutocapitalization(.sentences)
                .focused($typing).submitLabel(.done).onSubmit(add)
            Button("Add", action: add)
                .font(AppFont.text(14.5, weight: .semibold)).foregroundStyle(canAdd ? Ink.primary : Ink.muted)
                .buttonStyle(.plain)
                .disabled(!canAdd)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    private func add() {
        Task { await model.addCustom() }
    }
}

/// Unticking a category that has payments: where they go, as rows of the picker (Not sorted first, then the other
/// ticked categories). Cancel keeps the category ticked.
private struct UntickSheet: View {
    let untick: CategoryPickerModel.Untick
    let resolve: (String?) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 12) {
                        CategoryTile(icon: untick.look.icon, color: untick.look.color)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: untick.name).font(AppFont.text(17, weight: .semibold))
                                .foregroundStyle(Ink.primary)
                            Text("\(untick.count) payments").font(AppFont.text(12.5)).foregroundStyle(Ink.muted)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .padding(.horizontal, 4).padding(.top, 16)
                    SettingsSection(String(localized: "Move its payments to")) {
                        target(untick.notSortedName, look: untick.notSortedLook, id: nil,
                               detail: Text("Aresium sorts them again"))
                        ForEach(untick.targets) { target in
                            TileRowDivider()
                            self.target(target.name, look: target.look, id: target.id)
                        }
                    }
                }
                .padding(.horizontal, 18).padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
            .background { Ink.background.ignoresSafeArea() }
            .navigationTitle(Text("Untick \(untick.name)?"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .tint(Ink.primary)
        .presentationDetents([.medium, .large])
        .presentationBackground(Ink.background)
    }

    private func target(_ name: String, look: CategoryLook, id: String?, detail: Text? = nil) -> some View {
        Button { resolve(id) } label: {
            HStack(spacing: 12) {
                CategoryTile(icon: look.icon, color: look.color)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: name).font(AppFont.text(14.5, weight: .semibold)).foregroundStyle(Ink.primary)
                    if let detail { detail.font(AppFont.text(12.5)).foregroundStyle(Ink.muted) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
        }
        .buttonStyle(SettingsRowStyle())
    }
}

// MARK: - Settings → Aresium

/// Aresium's own section in Settings, in phone mode: Categories, Export, Restore from an export, a line on where the data
/// is kept, and "Delete Aresium data on this iPhone" apart in the soft red.
struct PhoneSettingsSection: View {
    let modes: ModeStore
    @State var data: PhoneDataModel
    let palette: Palette
    @State private var confirmsDelete = false
    @State private var pickingExport = false
    #if DEBUG
    /// Screenshots: `-openReceipts` opens Receipts at once, `-openCategories` Categories.
    @State private var showsReceipts = LaunchArguments.current.contains("-openReceipts")
    @State private var showsCategories = LaunchArguments.current.contains("-openCategories")
    #else
    @State private var showsReceipts = false
    @State private var showsCategories = false
    #endif

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSection(String(localized: "Your data on this iPhone")) {
                if let phone = modes.phone {
                    Button { showsCategories = true } label: {
                        SettingsRow(title: String(localized: "Categories"), value: String(phone.summary.chosen.count))
                    }
                    .buttonStyle(SettingsRowStyle())
                    SettingsDivider()
                    Button { showsReceipts = true } label: {
                        SettingsRow(title: String(localized: "Receipts"), value: String(phone.summary.receipts))
                    }
                    .buttonStyle(SettingsRowStyle())
                    SettingsDivider()
                }
                Button { Task { await data.export() } } label: {
                    SettingsRow(title: String(localized: "Export"),
                                subtitle: String(localized: "All your Aresium data as one file"), trailing: .none)
                        .overlay(alignment: .trailing) {
                            if data.isWorking { ProgressView().tint(Ink.secondary).padding(.trailing, 16) }
                        }
                }
                .buttonStyle(SettingsRowStyle())
                .disabled(data.isWorking || modes.phone == nil)
                SettingsDivider()
                Button { pickingExport = true } label: {
                    SettingsRow(title: String(localized: "Restore from an export"),
                                subtitle: data.canRestore ? String(localized: "A file you exported from Aresium before")
                                    : String(localized: "Only while Aresium has no data on this iPhone"),
                                trailing: .none)
                        .opacity(data.canRestore ? 1 : 0.5)
                }
                .buttonStyle(SettingsRowStyle())
                .disabled(data.isWorking || !data.canRestore)
            }
            FormNote(text: String(localized: "Your payments are kept only on this iPhone and in its backup. An export is a copy you keep yourself."))
                .padding(.top, 10)
            VStack(spacing: 0) {
                Button { confirmsDelete = true } label: {
                    SettingsRow(title: String(localized: "Delete Aresium data on this iPhone"), trailing: .none,
                                tint: FormButtonStyle.dangerInk)
                }
                .buttonStyle(SettingsRowStyle())
                .disabled(data.isWorking || modes.phone == nil)
            }
            .glassCard()
            .padding(.top, 16)
            if let message = data.message { FormNote(text: message).padding(.top, 10) }
            if let problem = data.problem { FormProblem(text: problem).padding(.top, 10) }
        }
        .navigationDestination(isPresented: $showsCategories) {
            if let phone = modes.phone {
                CategoryPickerScreen(model: CategoryPickerModel(phone: phone) {
                    await modes.dashboard.reloadAfterTransactionChange()
                })
            }
        }
        .navigationDestination(isPresented: $showsReceipts) {
            if let phone = modes.phone {
                ReceiptListView(phone: phone, palette: palette) { await modes.dashboard.reloadAfterTransactionChange() }
            }
        }
        .confirmationDialog(Text("Delete Aresium data on this iPhone?"), isPresented: $confirmsDelete,
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive) { Task { await data.deleteAll() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your payments, receipts, categories and learned sorting on this iPhone go for good. Export them first to keep a copy.")
        }
        .sheet(item: Binding(get: { data.exportFile }, set: { if $0 == nil { data.exportClosed() } })) { file in
            ShareSheet(url: file.url) { data.exportClosed() }
        }
        .fileImporter(isPresented: $pickingExport, allowedContentTypes: [.json]) { result in
            if case let .success(url) = result { Task { await data.restore(from: url) } }
        }
    }
}

/// The system share sheet for one file.
struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    let finished: () -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in finished() }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
