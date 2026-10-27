import SwiftUI
import UIKit
import UniformTypeIdentifiers

// Phone mode's own screens, built from Aresium's pieces: the dashboard's rows (`CategoryTile`, `DayTile`, the metrics
// of `ValueRow` and the payment list: 38 pt tiles, 14.5 pt titles, 12.5 pt lines; the website's `.cat-row` and
// `.txn-row`), the Settings pieces (`SettingsSection`, glass cards, `FormNote`, `FormButtonStyle`) and Aresium's palette.
// Ink only: the colours are the categories' own and the dashboard's expense and income. The logic is in Model/
// (ModeStore, CategoryPickerModel, LayoutConfirmModel, PhoneDataModel).

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
private struct TileRowDivider: View {
    var body: some View { SettingsDivider().padding(.leading, 48) }
}

// MARK: - the mode

/// While the account's mode is asked, when it cannot be asked the first time, or when the phone's store did not open: a
/// calm centred state (a mark in a thin circle, as `CalmDone`) with Try again.
struct ModeStatusScreen: View {
    let modes: ModeStore
    let palette: Palette

    var body: some View {
        Group {
            switch modes.state {
            case .needsConnection:
                state(symbol: "wifi.slash", title: Text("Aresium needs a connection the first time"),
                      text: Text("After that, your data on this iPhone works without one."))
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

// MARK: - first run

/// Phone mode with nothing imported yet: what Aresium does with the data, then the two steps (choose categories, import
/// a bank file) and, quietly, restoring an export. It is the main screen for now, so it ends with the band.
struct PhoneFirstRun: View {
    let phone: PhoneBackend
    let imports: ImportStore
    let palette: Palette
    let band: AresiumBand
    /// Why the last restore did not go through.
    var restoreProblem: String?
    let chooseCategories: () -> Void
    let restore: () -> Void
    @State private var pickingFiles = false

    var body: some View {
        WordmarkScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(String(localized: "On this iPhone").uppercased()).font(AppFont.text(11, weight: .semibold))
                    .tracking(1.3).foregroundStyle(palette.muted)
                    .accessibilityAddTraits(.isHeader)
                Text("Set up Aresium").font(AppFont.text(21, weight: .bold)).foregroundStyle(palette.ink)
                    .padding(.top, 4)
                Text("Aresium reads your bank's export files and sorts every payment into your categories. It all stays on this iPhone: nothing about your money goes to a server.")
                    .font(AppFont.text(14)).foregroundStyle(palette.secondary).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
                VStack(spacing: 0) {
                    Button(action: chooseCategories) {
                        FirstRunStep(number: 1, title: Text("Choose categories"),
                                     detail: phone.hasChosenCategories ? Text("\(phone.summary.chosen.count) chosen")
                                                                       : Text("Nothing is ticked yet"),
                                     state: phone.hasChosenCategories ? .done : .next, palette: palette)
                    }
                    .buttonStyle(SettingsRowStyle())
                    TileRowDivider()
                    Button { pickingFiles = true } label: {
                        FirstRunStep(number: 2, title: Text("Import a bank file"),
                                     detail: imports.isBusy ? Text("Reading the file…")
                                                            : Text("A CSV, CAMT or MT940 file from your bank"),
                                     state: phone.hasChosenCategories ? .next : .later, busy: imports.isBusy,
                                     palette: palette)
                    }
                    .buttonStyle(SettingsRowStyle())
                    .disabled(!phone.hasChosenCategories || imports.isBusy)
                }
                .glassCard(edge: palette.red ? palette.line : nil)
                .padding(.top, 22)
                Text("Export it in your bank's app or on its website, then pick it here or share it to Aresium.")
                    .font(AppFont.text(12.5)).foregroundStyle(palette.muted).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10).padding(.horizontal, 4)
                Button(action: restore) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Restore from an export").font(AppFont.text(14, weight: .semibold))
                            .foregroundStyle(palette.secondary)
                        Text("A file you exported from Aresium before").font(AppFont.text(12)).foregroundStyle(palette.muted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, 34).padding(.horizontal, 4)
                if let restoreProblem { FormProblem(text: restoreProblem).padding(.top, 10) }
            }
            .padding(.horizontal, 18).padding(.top, 14)
        } band: { _ in band }
        .scrollBounceBehavior(.always)
        .fileImporter(isPresented: $pickingFiles, allowedContentTypes: PhoneImportTypes.all, allowsMultipleSelection: true) { result in
            switch result {
            case let .success(urls): if !urls.isEmpty { Task { await imports.receive(urls) } }
            case let .failure(error): imports.show(error.localizedDescription, success: false)
            }
        }
    }
}

/// One step of the first run, as a row of the dashboard: its number in a day tile (filled with ink while it is the
/// next step, a check once done), the title and one line.
private struct FirstRunStep: View {
    enum State { case next, done, later }

    let number: Int
    let title: Text
    let detail: Text
    let state: State
    var busy = false
    let palette: Palette

    var body: some View {
        HStack(spacing: 12) {
            tile
            VStack(alignment: .leading, spacing: 2) {
                title.font(AppFont.text(14.5, weight: .semibold)).foregroundStyle(palette.ink)
                detail.font(AppFont.text(12.5)).foregroundStyle(palette.muted)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            if busy {
                ProgressView().tint(palette.secondary)
            } else {
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .medium)).foregroundStyle(palette.muted)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .opacity(state == .later ? 0.45 : 1)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var tile: some View {
        switch state {
        case .next:
            Text(verbatim: String(number)).font(AppFont.number(15)).foregroundStyle(palette.background)
                .frame(width: 38, height: 38)
                .background(palette.ink, in: RoundedRectangle(cornerRadius: 9))
        case .done:
            DayTile(palette: palette) { Image(systemName: "checkmark").font(.system(size: 14, weight: .semibold)) }
        case .later:
            DayTile(palette: palette) { Text(verbatim: String(number)) }
        }
    }
}

// MARK: - categories

/// The category picker: the default list by group, each category as the dashboard's rows draw it with a tick on the
/// right; one's own names below; unticking a category with payments asks where they go (`UntickSheet`). Pushed from
/// Settings, or in a sheet at the first run.
struct CategoryPickerScreen: View {
    @State var model: CategoryPickerModel
    var done: (() -> Void)? = nil
    @FocusState private var typing: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                FormNote(text: String(localized: "Tick the categories you use. Aresium sorts payments only into these; what fits none of them waits as Not sorted."))
                    .padding(.top, 16)
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
        .task {
            await model.load()
            #if DEBUG
            // Screenshots: `-sampleUntick <category id>` unticks it at once (the question where its payments go).
            let arguments = LaunchArguments.current
            if let index = arguments.firstIndex(of: "-sampleUntick"), arguments.indices.contains(index + 1) {
                await model.toggle(arguments[index + 1])
            }
            #endif
        }
        .sheet(item: Binding(get: { model.untick }, set: { if $0 == nil { model.cancelUntick() } })) { untick in
            UntickSheet(untick: untick) { model.resolve(moveTo: $0) }
        }
    }

    private func row(_ item: CategoryGroup.Item) -> some View {
        Button { Task { await model.toggle(item.id) } } label: {
            HStack(spacing: 12) {
                CategoryTile(icon: item.look.icon, color: item.look.color)
                Text(verbatim: item.name).font(AppFont.text(14.5, weight: .semibold)).foregroundStyle(Ink.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
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

// MARK: - layout confirmation

/// An unknown CSV: the file, each column with its first values and what it holds (a menu), the formats, and the first
/// payments read that way, as the dashboard's payment rows. Confirm saves the layout and reads the file; Cancel leaves
/// the file out.
struct LayoutConfirmSheet: View {
    @State var model: LayoutConfirmModel
    let palette: Palette
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        file.padding(.top, 16)
                        FormNote(text: String(localized: "Aresium doesn't know this bank's file yet. Check what each column holds; the first payments below are read that way. Aresium remembers it for the next file."))
                            .padding(.top, 14)
                        SettingsSection(String(localized: "Columns")) {
                            ForEach(Array(model.columns.enumerated()), id: \.element.index) { index, column in
                                if index > 0 { SettingsDivider() }
                                columnRow(column)
                            }
                        }
                        SettingsSection(String(localized: "Formats")) {
                            formatRow(Text("Dates")) {
                                Picker(selection: Binding(get: { model.draft.dateFormat }, set: { model.setDateFormat($0) })) {
                                    ForEach(LayoutDraft.dateFormats, id: \.self) {
                                        Text(verbatim: LayoutDraft.example(of: $0)).tag($0)
                                    }
                                } label: { EmptyView() }
                            } label: {
                                MenuChip(text: LayoutDraft.example(of: model.draft.dateFormat), mono: true)
                            }
                            SettingsDivider()
                            formatRow(Text("Amounts")) {
                                Picker(selection: Binding(get: { model.draft.numberFormat }, set: { model.setNumberFormat($0) })) {
                                    ForEach(LayoutDraft.numberFormats, id: \.self) {
                                        Text(verbatim: LayoutDraft.example(ofNumberFormat: $0)).tag($0)
                                    }
                                } label: { EmptyView() }
                            } label: {
                                MenuChip(text: LayoutDraft.example(ofNumberFormat: model.draft.numberFormat), mono: true)
                            }
                        }
                        SettingsSection(String(localized: "First payments")) {
                            if model.preview.isEmpty {
                                Text(model.draft.missing.isEmpty ? String(localized: "Nothing to show yet.")
                                                                  : String(localized: "Pick the date column and the amount (or money out and money in)."))
                                    .font(AppFont.text(13)).foregroundStyle(Ink.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                            }
                            ForEach(Array(model.preview.enumerated()), id: \.offset) { index, payment in
                                if index > 0 { TileRowDivider() }
                                previewRow(PreviewPayment(payment))
                            }
                        }
                        if let problem = model.previewProblem { FormProblem(text: problem).padding(.top, 12) }
                    }
                    .padding(.horizontal, 18).padding(.bottom, 24)
                }
                .scrollIndicators(.hidden)
                actions
            }
            .background { Ink.background.ignoresSafeArea() }
            .navigationTitle(Text("Check the columns"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        model.cancel()
                        dismiss()
                    }
                    .disabled(model.isSaving)
                }
            }
        }
        .tint(Ink.primary)
        .presentationBackground(Ink.background)
        .interactiveDismissDisabled()
    }

    /// The file, as the payment rows start: a document in a day tile, its name and how many columns it has.
    private var file: some View {
        HStack(spacing: 12) {
            DayTile(palette: palette) { Image(systemName: "doc.text").font(.system(size: 16, weight: .medium)) }
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: model.request.file.name).font(AppFont.text(14.5, weight: .semibold))
                    .foregroundStyle(Ink.primary).lineLimit(2).truncationMode(.middle)
                Text("\(model.columns.count) columns").font(AppFont.text(12.5)).foregroundStyle(Ink.muted)
            }
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
    }

    private var actions: some View {
        VStack(spacing: 10) {
            if let problem = model.saveProblem { FormProblem(text: problem) }
            Button { Task { if await model.confirm() { dismiss() } } } label: {
                BusyLabel(text: Text("Confirm and import"), busy: model.isSaving)
            }
            .buttonStyle(FormButtonStyle(accent: nil, busy: model.isSaving))
            .disabled(model.draft.layout == nil)
            .allowsHitTesting(!model.isSaving)
        }
        .padding(.horizontal, 18).padding(.top, 10).padding(.bottom, 10)
    }

    /// A column: its header (or its place) and what it holds as a menu, side by side when they fit and the menu under
    /// the name when not (a long bank header, the largest text sizes); its first values in mono below.
    private func columnRow(_ column: ColumnInfo) -> some View {
        let meaning = model.draft.meaning(of: column.index)
        let name = column.header.trimmingCharacters(in: .whitespaces).isEmpty
            ? String(localized: "Column \(column.index + 1)") : column.header
        let title = Text(verbatim: name).font(AppFont.text(14.5, weight: .semibold)).foregroundStyle(Ink.primary)
        let menu = Menu {
            Picker(selection: Binding(get: { meaning }, set: { model.set($0, for: column.index) })) {
                ForEach(ColumnMeaning.allCases) { Text($0.title()).tag($0) }
            } label: { EmptyView() }
        } label: {
            MenuChip(text: meaning.title(), quiet: meaning == .ignore)
        }
        .accessibilityLabel(Text(verbatim: name))
        .accessibilityValue(Text(meaning.title()))
        return VStack(alignment: .leading, spacing: 5) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    title.lineLimit(1)
                    Spacer(minLength: 8)
                    menu
                }
                VStack(alignment: .leading, spacing: 8) {
                    title.fixedSize(horizontal: false, vertical: true)
                    menu
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if !column.samples.isEmpty {
                Text(verbatim: column.samples.joined(separator: " · ")).font(AppFont.number(11.5, weight: .regular))
                    .foregroundStyle(Ink.muted).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16).padding(.vertical, 11)
    }

    private func formatRow<Choices: View>(_ title: Text, @ViewBuilder choices: () -> Choices,
                                          @ViewBuilder label: () -> MenuChip) -> some View {
        HStack(spacing: 12) {
            title.font(AppFont.text(15, weight: .medium)).foregroundStyle(Ink.primary)
            Spacer(minLength: 8)
            Menu { choices() } label: { label() }
        }
        .padding(.horizontal, 16).frame(minHeight: 54)
    }

    /// A payment read with the columns, as the dashboard's payment list draws it; the line under it carries the whole
    /// date, so a wrong date column shows at once.
    private func previewRow(_ payment: PreviewPayment) -> some View {
        HStack(spacing: 12) {
            DayTile(palette: palette) { Text(verbatim: payment.day.map(String.init) ?? "–") }
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: payment.title).font(AppFont.text(14.5, weight: .semibold)).foregroundStyle(Ink.primary)
                    .lineLimit(1)
                Text(verbatim: ([payment.date] + [payment.detail].compactMap { $0 }).joined(separator: " · "))
                    .font(AppFont.text(12.5)).foregroundStyle(Ink.muted).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(verbatim: Money.transaction(payment.amount)).font(AppFont.number(14))
                .foregroundStyle(payment.amount < 0 ? palette.expenseText : palette.income).fixedSize()
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }
}

/// A menu's current choice: a quiet outlined chip (the website's `.md-edit`), muted while nothing is chosen.
private struct MenuChip: View {
    let text: String
    var quiet = false
    var mono = false

    var body: some View {
        HStack(spacing: 6) {
            Text(verbatim: text)
                .font(mono ? AppFont.number(13, weight: .medium) : AppFont.text(13.5, weight: .semibold))
                .foregroundStyle(quiet ? Ink.muted : Ink.primary).lineLimit(1)
            Image(systemName: "chevron.up.chevron.down").font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Ink.muted)
        }
        .padding(.horizontal, 11).frame(minHeight: 32)
        .background(Ink.field, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Ink.line))
        .fixedSize()
    }
}

// MARK: - Settings → Aresium

/// Aresium's own section in Settings, in phone mode: Categories, Export, Restore from an export, a line on where the data
/// is kept, and "Delete Aresium data on this iPhone" apart in the soft red.
struct PhoneSettingsSection: View {
    let modes: ModeStore
    @State var data: PhoneDataModel
    @State private var confirmsDelete = false
    @State private var pickingExport = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SettingsSection(String(localized: "Your data on this iPhone")) {
                if let phone = modes.phone {
                    NavigationLink {
                        CategoryPickerScreen(model: CategoryPickerModel(phone: phone) {
                            await modes.dashboard.reloadAfterTransactionChange()
                        })
                    } label: {
                        SettingsRow(title: String(localized: "Categories"), value: String(phone.summary.chosen.count))
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
        .confirmationDialog(Text("Delete Aresium data on this iPhone?"), isPresented: $confirmsDelete,
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive) { Task { await data.deleteAll() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your payments, categories and learned sorting on this iPhone go for good. Export them first to keep a copy.")
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
