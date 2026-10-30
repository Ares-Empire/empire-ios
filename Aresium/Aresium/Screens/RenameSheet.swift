import SwiftUI

/// Renaming a payment (brief 44, phone mode): one field with the own name (empty, the bank's name as its placeholder,
/// while there is none), Cancel and Save at the top as in every iOS edit sheet, Save off while nothing changed, "Use
/// the bank's name" while an own name shows. After Save, while the shop has other payments, "Also the other payments
/// from <bank name>?" with "All N+1" and "Only this one", as the category change asks; removing a shop's name asks
/// first. What each saves: `RenamePlan`.
/// Opened from the payment's page (Rename) or from its row's long press, which opens it before the payment has loaded.
struct RenameSheet: View {
    @Bindable var store: TransactionDetailStore
    let palette: Palette
    @State private var model: PaymentRenameModel?
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                if let model, let info = store.renameInfo {
                    form(model, info: info)
                } else if let error = store.loadError {
                    // Opened from a payment row's long press: the payment could not be loaded.
                    VStack(alignment: .leading, spacing: 12) {
                        Text(error).font(AppFont.text(14)).foregroundStyle(palette.expenseText)
                        Button("Retry") { Task { await store.beginRenameFromRow() } }
                            .font(AppFont.text(14, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(20)
                } else {
                    // Opened from a payment row: the payment loads (a moment, the page's own load).
                    ProgressView().tint(palette.secondary).frame(maxWidth: .infinity).padding(30)
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .background { Wall(palette: palette) }
            .navigationTitle("Rename").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    DiscardingCancel(asks: model?.hasChanges == true, question: Text("Discard your changes?")) {
                        store.showsRename = false
                    }
                    .disabled(store.isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    // The spinner in the word's place while it saves; the word muted by hand while it cannot save (the
                    // bar's glass button shows no difference by itself).
                    Button { Task { await model?.save() } } label: {
                        if model?.working == .save {
                            ProgressView().tint(palette.ink)
                        } else {
                            Text("Save").foregroundStyle(model?.canSave == true ? palette.ink : palette.muted)
                        }
                    }
                    .disabled(model?.canSave != true)
                    .whileWorking(store.isSaving, tapped: model?.working == .save)
                }
            }
        }
        // The payment page's font reaches this sheet; the bar keeps the system's, as the app's other sheets. The content
        // sets the app's font and ink itself.
        .environment(\.font, nil)
        .tint(palette.ink)
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled(store.isSaving || model?.hasChanges == true || model?.asks == true)
        .alert(questionTitle, isPresented: questionShown, presenting: model?.question) { question in
            Button("All \(question.allCount)") { Task { await model?.answer(all: true) } }
            Button("Only this one", role: .cancel) { Task { await model?.answer(all: false) } }
        } message: { question in
            Text("With All, new payments from \(question.bankName) get the name too.")
        }
        .alert(bankNameTitle, isPresented: bankNameShown, presenting: model?.bankNameQuestion) { _ in
            Button("Use the bank's name") { Task { await model?.answerBankName(confirmed: true) } }
            Button("Cancel", role: .cancel) { Task { await model?.answerBankName(confirmed: false) } }
        } message: { question in
            Text("“\(question.shopName)” is your name for every payment from \(question.bankName).")
        }
        .tint(palette.ink)      // the questions' buttons in ink, as the sheet's (and the category change's question)
        .task(id: store.renameInfo) {
            // The window can open before the payment has loaded (a row's long press): the field fills once it has.
            guard model == nil, store.renameInfo != nil else { return }
            let made = PaymentRenameModel(store: store)
            model = made
            focused = true
            #if DEBUG
            await debugFill(made)
            #endif
        }
    }

    private func form(_ model: PaymentRenameModel, info: PaymentRenameInfo) -> some View {
        @Bindable var model = model
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                TextField(text: $model.text, prompt: Text(verbatim: info.bankName).foregroundStyle(palette.muted)) {
                    Text("Name")
                }
                .font(AppFont.text(17)).foregroundStyle(palette.ink)
                .focused($focused)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit { Task { await model.save() } }
                .onChange(of: model.text) { _, _ in model.limitText() }
                if !model.text.isEmpty {
                    // The field's clear button, as UIKit's: back to the bank's name as the placeholder.
                    Button { model.text = "" } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 16)).foregroundStyle(palette.muted)
                            .minimumTapArea()
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Clear"))
                }
            }
            .padding(.vertical, 4)
            .fieldBox { focused = true }
            .disabled(store.isSaving)
            VStack(alignment: .leading, spacing: 6) {
                Text("Your bank's name: \(info.bankName)").foregroundStyle(palette.secondary)
                Text("Only the name you see changes. Categories and sorting stay as they are.")
                    .foregroundStyle(palette.muted)
            }
            .font(AppFont.text(12.5))
            .fixedSize(horizontal: false, vertical: true)
            if let error = store.saveError {
                Text(error).font(AppFont.text(13)).foregroundStyle(palette.expenseText)
                    .accessibilityIdentifier("renameError")
            }
            if info.ownName != nil {
                Button { Task { await model.useBankName() } } label: {
                    BusyLabel(text: Text("Use the bank's name"), busy: model.working == .bankName, tint: palette.ink)
                }
                .buttonStyle(QuietButtonStyle())
                .whileWorking(store.isSaving, tapped: model.working == .bankName)
                .padding(.top, 6)
            }
        }
        .padding(20)
        .font(AppFont.text(14)).foregroundStyle(palette.ink)
    }

    /// As the category change asks: the count is on the button, so the sentence reads right for one payment or many.
    private var questionTitle: Text {
        guard let question = model?.question else { return Text(verbatim: "") }
        return Text("Also the other payments from \(question.bankName)?")
    }

    private var questionShown: Binding<Bool> {
        // A button answers first, so the dismissal that follows finds nothing left to answer.
        Binding(get: { model?.question != nil }, set: { shown in
            if !shown, model?.question != nil { Task { await model?.answer(all: false) } }
        })
    }

    private var bankNameTitle: Text {
        guard let question = model?.bankNameQuestion else { return Text(verbatim: "") }
        return Text("Use the bank's name for all \(question.count) payments?")
    }

    private var bankNameShown: Binding<Bool> {
        Binding(get: { model?.bankNameQuestion != nil }, set: { shown in
            if !shown, model?.bankNameQuestion != nil { Task { await model?.answerBankName(confirmed: false) } }
        })
    }

    #if DEBUG
    /// Screenshots: `-renameText <text>` types a name, `-renameSave` then taps Save (the question, when it asks),
    /// `-renameBankName` taps "Use the bank's name".
    private func debugFill(_ model: PaymentRenameModel) async {
        if let text = LaunchArguments.value("-renameText") { model.text = text }
        try? await Task.sleep(for: .milliseconds(900))
        if LaunchArguments.current.contains("-renameSave") { await model.save() }
        if LaunchArguments.current.contains("-renameBankName") { await model.useBankName() }
    }
    #endif
}
