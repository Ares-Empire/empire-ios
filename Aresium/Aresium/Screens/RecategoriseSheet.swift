import SwiftUI

/// Switch or Add for one payment. Like every iOS edit sheet, Cancel is top left and Save top right (brief 36, Patrik's
/// phone test: Save at the bottom was far from a category at the top), in ink like the app's other sheets; in Add mode
/// "Save & remove from current" follows the choices as the quiet second answer. After a Switch in phone mode the
/// merchant's other payments are asked about before the sheet closes. Opened from the payment's page (Change) or from its
/// row's long press (brief 41), which opens it before the payment has loaded.
struct RecategoriseSheet: View {
    @Bindable var store: TransactionDetailStore
    let palette: Palette
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                if let detail = store.detail {
                    VStack(alignment: .leading, spacing: 18) {
                        Text(detail.place).font(AppFont.text(22, weight: .bold))
                        HStack(spacing: 8) {
                            Text("Currently in").foregroundStyle(palette.muted)
                            CategoryChip(name: detail.category, color: detail.categoryColor)
                        }
                        Picker("Mode", selection: $store.mode) {
                            ForEach(RecategorisationMode.allCases, id: \.self) { mode in Text(mode.title).tag(mode) }
                        }.pickerStyle(.segmented)
                        Text(store.mode == .switchCategory
                             ? "Wrong category? Pick the one it belongs in — it moves there."
                             : "Also show this under other categories. It stays counted once (in \(CategoryName.shown(detail.category))), so nothing is double-counted.")
                            .font(AppFont.text(13)).foregroundStyle(palette.secondary)
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 9) {
                            ForEach(store.choices) { category in choice(category, current: detail.category) }
                        }
                        if store.isSample {
                            Text("Not available with sample data").foregroundStyle(palette.muted)
                        }
                        if let error = store.saveError {
                            Text(error).foregroundStyle(palette.expenseText).accessibilityIdentifier("recategorisationError")
                            Button("Retry") { Task { await store.retrySave() } }.disabled(!store.canSave)
                        }
                        if store.mode == .add {
                            Button("Save & remove from current") { Task { await store.save(dropCurrent: true) } }
                                .buttonStyle(QuietButtonStyle())
                                .disabled(!store.canRemoveCurrent)
                        }
                    }
                    .padding(20)
                    .font(AppFont.text(14)).foregroundStyle(palette.ink)
                } else if let error = store.loadError {
                    // Opened from a payment row's long press (brief 41): the payment could not be loaded.
                    VStack(alignment: .leading, spacing: 12) {
                        Text(error).font(AppFont.text(14)).foregroundStyle(palette.expenseText)
                        Button("Retry") { Task { await store.beginRecategorisationFromRow() } }
                            .font(AppFont.text(14, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(20)
                } else {
                    // Opened from a payment row: the payment loads (a moment, the page's own load).
                    ProgressView().tint(palette.secondary).frame(maxWidth: .infinity).padding(30)
                }
            }
            .background { Wall(palette: palette) }
            .navigationTitle("Recategorise").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    // Muted while it cannot save (nothing chosen yet, or saving), as the app's own buttons: the bar's
                    // glass button shows no difference by itself.
                    Button { Task { await store.save() } } label: {
                        (store.isSaving ? Text("Saving…") : Text("Save"))
                            .foregroundStyle(store.canSave ? palette.ink : palette.muted)
                    }
                    .disabled(!store.canSave)
                }
            }
            .disabled(store.isSaving)
        }
        // The payment page's font reaches this sheet; the bar keeps the system's, as the app's other sheets (Save then
        // reads as the bold confirming button, greyed while it cannot save). The content above sets the app's font and
        // ink itself.
        .environment(\.font, nil)
        .tourCard()
        .tint(palette.ink)
        .interactiveDismissDisabled(store.isSaving || store.followUp != nil)
        // Phone mode, after a Switch: the merchant's other payments, as a short centred question. The count is on the
        // button, so every sentence reads right for one payment or many.
        .alert(followUpTitle, isPresented: followUpShown, presenting: store.followUp) { followUp in
            Button("Move \(followUp.count) more") { store.answer(moveOthers: true) }
            Button("Only this one", role: .cancel) { store.answer(moveOthers: false) }
        } message: { followUp in
            Text("From now on, payments from \(followUp.shop) go to \(followUp.category).")
        }
        .tint(palette.ink)      // the question's buttons in ink, as the sheet's
    }

    private var followUpTitle: Text {
        guard let followUp = store.followUp else { return Text(verbatim: "") }
        return Text("Also the other payments from \(followUp.shop)?")
    }

    private var followUpShown: Binding<Bool> {
        // After a button the answer is already taken, so a dismissal that follows answers nothing twice.
        Binding(get: { store.followUp != nil }, set: { shown in if !shown { store.answer(moveOthers: false) } })
    }

    private func choice(_ category: Category, current: String) -> some View {
        let selected = store.mode == .switchCategory ? store.target == category.name : store.extras.contains(category.name)
        let color = Color(hex: category.color)
        return Button { store.select(category.name) } label: {
            HStack(spacing: 7) {
                Image(systemName: CategorySymbol.name(for: category.icon)).frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(category.shownName).font(AppFont.text(13, weight: .semibold))
                    if category.name == current { Text("current").font(AppFont.text(9, weight: .semibold)) }
                }.frame(maxWidth: .infinity, alignment: .leading)
                if selected { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)) }
            }.foregroundStyle(color).padding(10).frame(maxWidth: .infinity, minHeight: 48)
                .background(color.opacity(selected ? 0.17 : 0.08), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(color.opacity(selected ? 1 : 0.33), lineWidth: selected ? 2 : 1))
        }.buttonStyle(.plain)
            .disabled(store.mode == .add && category.name == current)
            .accessibilityLabel(category.name == current ? String(localized: "\(category.shownName), current") : category.shownName)
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
