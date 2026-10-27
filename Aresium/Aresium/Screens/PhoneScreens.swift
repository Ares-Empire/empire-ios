import SwiftUI
import UIKit
import UniformTypeIdentifiers

// Phone mode's new screens, as structure only: plain SwiftUI from the shared pieces (Ink, SettingsSection/SettingsRow,
// FormButtonStyle) and Aresium's palette, no new styling. Claude designs their look afterwards. The logic is in
// Model/ (ModeStore, CategoryPickerModel, LayoutConfirmModel, PhoneDataModel).

/// The file types phone mode imports: bank CSVs, CAMT XML, MT940 (`.sta`, `.mt940`, `.txt`) and ZIP (which gets "unzip
/// it first").
enum PhoneImportTypes {
    static var all: [UTType] {
        [.commaSeparatedText, .xml, .plainText, .zip]
            + ["sta", "mt940"].compactMap { UTType(filenameExtension: $0) }
    }
}

// MARK: - the mode

/// While the account's mode is asked, when it cannot be asked the first time, or when the phone's store did not open.
struct ModeStatusScreen: View {
    let modes: ModeStore
    let palette: Palette

    var body: some View {
        VStack(spacing: 14) {
            switch modes.state {
            case .needsConnection:
                Text("Aresium needs a connection the first time").font(AppFont.text(17, weight: .semibold))
                    .multilineTextAlignment(.center)
                Text("After that, your data on this iPhone works without one.").font(AppFont.text(14))
                    .foregroundStyle(palette.secondary).multilineTextAlignment(.center)
                Button("Try again") { Task { await modes.retry() } }.font(AppFont.text(15, weight: .semibold))
            case .failed(let message):
                Text(message).font(AppFont.text(15)).foregroundStyle(palette.expenseText).multilineTextAlignment(.center)
                Button("Try again") { Task { await modes.retry() } }.font(AppFont.text(15, weight: .semibold))
            default:
                ProgressView()
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - first run

/// Phone mode with nothing imported yet: choose categories first, then import a bank file, or restore an export.
struct PhoneFirstRun: View {
    let phone: PhoneBackend
    let imports: ImportStore
    let palette: Palette
    let chooseCategories: () -> Void
    let restore: () -> Void
    @State private var pickingFiles = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("No payments yet").font(AppFont.text(22, weight: .bold))
                Text("Aresium reads your bank's export files on this iPhone and keeps everything here. Nothing about your money goes to a server.")
                    .font(AppFont.text(14)).foregroundStyle(palette.secondary)
                if phone.hasChosenCategories {
                    Text("\(phone.summary.chosen.count) categories chosen").font(AppFont.text(14))
                    Button("Change categories", action: chooseCategories).font(AppFont.text(15, weight: .semibold))
                } else {
                    Text("First, choose the categories you want. Nothing is ticked yet.").font(AppFont.text(14))
                    Button("Choose categories", action: chooseCategories).font(AppFont.text(15, weight: .semibold))
                }
                Button("Import a bank file") { pickingFiles = true }
                    .font(AppFont.text(15, weight: .semibold))
                    .disabled(!phone.hasChosenCategories || imports.isBusy)
                Text("Export a CSV, CAMT (XML) or MT940 file in your bank's app or website, then pick it here or share it to Aresium.")
                    .font(AppFont.text(13)).foregroundStyle(palette.muted)
                Divider().overlay(palette.line)
                Button("Restore from an export", action: restore).font(AppFont.text(15, weight: .semibold))
                Text("A file Aresium exported before, from Settings.").font(AppFont.text(13)).foregroundStyle(palette.muted)
            }
            .padding(.horizontal, 22).padding(.top, 18).padding(.bottom, 40)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .tint(palette.ink)
        .fileImporter(isPresented: $pickingFiles, allowedContentTypes: PhoneImportTypes.all, allowsMultipleSelection: true) { result in
            switch result {
            case let .success(urls): if !urls.isEmpty { Task { await imports.receive(urls) } }
            case let .failure(error): imports.show(error.localizedDescription, success: false)
            }
        }
    }
}

// MARK: - categories

/// The category picker: the default list by group with a toggle each (names in the app's language), one's own names,
/// and the question where an unticked category's payments go. Pushed from Settings, or in a sheet at the first run.
struct CategoryPickerScreen: View {
    @State var model: CategoryPickerModel
    var done: (() -> Void)? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                FormNote(text: String(localized: "Tick the categories you want. Payments are sorted only into these; the rest wait as Not sorted."))
                    .padding(.top, 18)
                ForEach(model.groups) { group in
                    SettingsSection(group.title) {
                        ForEach(Array(group.items.enumerated()), id: \.element.id) { index, item in
                            if index > 0 { SettingsDivider() }
                            row(item)
                        }
                    }
                }
                SettingsSection(String(localized: "Your own")) {
                    ForEach(Array(model.custom.enumerated()), id: \.element.id) { _, item in
                        row(item)
                        SettingsDivider()
                    }
                    HStack(spacing: 10) {
                        FormField(placeholder: String(localized: "A name of your own"), text: $model.newName, kind: .name)
                            .submitLabel(.done).onSubmit { Task { await model.addCustom() } }
                        Button("Add") { Task { await model.addCustom() } }
                            .font(AppFont.text(15, weight: .semibold))
                            .disabled(model.newName.trimmingCharacters(in: .whitespaces).isEmpty || model.isWorking)
                            .padding(.trailing, 16)
                    }
                }
                if let problem = model.problem { FormProblem(text: problem).padding(.top, 14) }
            }
            .padding(.horizontal, 18).padding(.bottom, 34)
        }
        .scrollDismissesKeyboard(.interactively)
        .background { Ink.background.ignoresSafeArea() }
        .navigationTitle(Text("Categories"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let done {
                ToolbarItem(placement: .confirmationAction) { Button("Done", action: done) }
            }
        }
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
        .confirmationDialog(untickTitle, isPresented: untickShown, titleVisibility: .visible, presenting: model.untick) { untick in
            ForEach(untick.targets) { target in
                Button(target.name) { model.resolve(moveTo: target.id) }
            }
            Button(untick.notSortedName) { model.resolve(moveTo: nil) }
            Button("Cancel", role: .cancel) { model.cancelUntick() }
        } message: { untick in
            Text("\(untick.count) payments are in \(untick.name). Where should they go?")
        }
    }

    private func row(_ item: CategoryGroup.Item) -> some View {
        Toggle(isOn: Binding(get: { item.chosen }, set: { _ in Task { await model.toggle(item.id) } })) {
            HStack(spacing: 10) {
                Image(systemName: CategorySymbol.name(for: item.look.icon)).frame(width: 22)
                    .foregroundStyle(Color(hex: item.look.color))
                Text(item.name).font(AppFont.text(15, weight: .medium)).foregroundStyle(Ink.primary)
            }
        }
        .disabled(model.isWorking)
        .padding(.horizontal, 16).frame(minHeight: 50)
    }

    private var untickTitle: Text { Text("Untick \(model.untick?.name ?? "")?") }
    private var untickShown: Binding<Bool> {
        Binding(get: { model.untick != nil }, set: { if !$0 { model.cancelUntick() } })
    }
}

// MARK: - layout confirmation

/// An unknown CSV: the guessed columns and the first rows read with them; the person can change what a column means.
/// Confirm saves the layout and reads the file; Cancel leaves the file out.
struct LayoutConfirmSheet: View {
    @State var model: LayoutConfirmModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    FormNote(text: String(localized: "Aresium does not know this bank's file yet. Check what each column holds; the first payments below are read that way. Aresium remembers it for the next file."))
                        .padding(.top, 18)
                    Text(verbatim: model.request.file.name).font(AppFont.text(13, weight: .semibold))
                        .foregroundStyle(Ink.secondary).padding(.top, 10).padding(.horizontal, 4)
                    SettingsSection(String(localized: "Columns")) {
                        ForEach(Array(model.columns.enumerated()), id: \.element.index) { index, column in
                            if index > 0 { SettingsDivider() }
                            columnRow(column)
                        }
                    }
                    SettingsSection(String(localized: "Formats")) {
                        Picker(selection: Binding(get: { model.draft.dateFormat }, set: { model.setDateFormat($0) })) {
                            ForEach(LayoutDraft.dateFormats, id: \.self) { Text(verbatim: $0).tag($0) }
                        } label: { Text("Dates") }
                        .padding(.horizontal, 16).frame(minHeight: 50)
                        SettingsDivider()
                        Picker(selection: Binding(get: { model.draft.numberFormat }, set: { model.setNumberFormat($0) })) {
                            Text(verbatim: "1.234,56").tag("de")
                            Text(verbatim: "1,234.56").tag("en")
                        } label: { Text("Amounts") }
                        .padding(.horizontal, 16).frame(minHeight: 50)
                    }
                    SettingsSection(String(localized: "First payments")) {
                        if model.preview.isEmpty {
                            Text(model.draft.missing.isEmpty ? String(localized: "Nothing to show yet.")
                                                              : String(localized: "Pick the date column and the amount (or money out and money in)."))
                                .font(AppFont.text(13)).foregroundStyle(Ink.muted)
                                .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        ForEach(Array(model.preview.enumerated()), id: \.offset) { index, payment in
                            if index > 0 { SettingsDivider() }
                            previewRow(payment)
                        }
                    }
                    if let problem = model.previewProblem { FormProblem(text: problem).padding(.top, 12) }
                    if let problem = model.saveProblem { FormProblem(text: problem).padding(.top, 12) }
                }
                .padding(.horizontal, 18).padding(.bottom, 34)
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
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Confirm") {
                        Task { if await model.confirm() { dismiss() } }
                    }
                    .disabled(!model.canConfirm)
                }
            }
        }
        .interactiveDismissDisabled()
    }

    private func columnRow(_ column: ColumnInfo) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(verbatim: column.header.isEmpty ? "—" : column.header)
                    .font(AppFont.text(15, weight: .medium)).foregroundStyle(Ink.primary)
                Spacer(minLength: 8)
                Picker(selection: Binding(get: { model.draft.meaning(of: column.index) },
                                          set: { model.set($0, for: column.index) })) {
                    ForEach(ColumnMeaning.allCases) { meaning in Text(meaning.title()).tag(meaning) }
                } label: { Text(verbatim: column.header) }
                .labelsHidden()
            }
            Text(verbatim: column.samples.joined(separator: " · ")).font(AppFont.number(12)).foregroundStyle(Ink.muted)
                .lineLimit(1)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private func previewRow(_ payment: BankTxn) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(verbatim: payment.day).font(AppFont.number(12)).foregroundStyle(Ink.secondary)
            Text(verbatim: payment.counterparty ?? payment.description).font(AppFont.text(14)).foregroundStyle(Ink.primary)
                .lineLimit(1)
            Spacer(minLength: 8)
            Text(verbatim: Money.transaction(Double(payment.amount) ?? 0)).font(AppFont.number(13)).foregroundStyle(Ink.primary)
        }
        .padding(.horizontal, 16).frame(minHeight: 44)
    }
}

// MARK: - Settings → Aresium

/// Aresium's own section in Settings, in phone mode: Categories, Export, Restore from an export, and "Delete Aresium data
/// on this iPhone".
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
                }
                .buttonStyle(SettingsRowStyle())
                .disabled(data.isWorking || modes.phone == nil)
                SettingsDivider()
                Button { pickingExport = true } label: {
                    SettingsRow(title: String(localized: "Restore from an export"),
                                subtitle: data.canRestore ? nil
                                    : String(localized: "Only while Aresium has no data on this iPhone"),
                                trailing: .none)
                }
                .buttonStyle(SettingsRowStyle())
                .disabled(data.isWorking || !data.canRestore)
            }
            VStack(spacing: 0) {
                Button { confirmsDelete = true } label: {
                    SettingsRow(title: String(localized: "Delete Aresium data on this iPhone"), trailing: .none,
                                tint: FormButtonStyle.dangerInk)
                }
                .buttonStyle(SettingsRowStyle())
                .disabled(data.isWorking || modes.phone == nil)
            }
            .glassCard()
            .padding(.top, 12)
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
