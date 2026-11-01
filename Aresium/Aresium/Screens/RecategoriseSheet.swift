import SwiftUI
import UIKit

/// Switch or Add for one payment or, from a category's month list, for the payments selected there (brief 82): one view
/// over `CategoryWindow`, so both windows look and behave alike. Like every iOS edit sheet, Cancel is top left and Save
/// top right (brief 36, Patrik's phone test: Save at the bottom was far from a category at the top), in ink like the
/// app's other sheets. Save in Add first asks whether to remove the current category, then asks about the shop's other
/// payments when applicable. Under "Currently in" one quiet line says why the payment is there (brief 47, from the
/// payment's page); a selection's window names "10 payments" with their total instead. Opened from the payment's page
/// (its category's chip or pen, an extra category's chip at Add), from its row's long press (brief 41), which opens it
/// before the payment has loaded, or from a selection's bar (Category).
/// In phone mode the grid ends with two quiet action tiles, for money out and money in alike: Other category… (brief 70,
/// while the other side has a category not offered here: Apple's menu of them, picked into the grid with Save storing it
/// as offered here) and New category (brief 60: Apple's alert with a name's field makes one of one's own categories as
/// Settings → Categories does). Either shows its category before the tiles, picked. A tile offered here only from the
/// other side takes Apple's context menu with "Not for money in" (or out), which takes it back.
struct RecategoriseSheet<Window: CategoryWindow>: View {
    let window: Window
    let palette: Palette
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                if let heading = window.heading {
                    VStack(alignment: .leading, spacing: 18) {
                        header(heading)
                        Picker("Mode", selection: Binding(get: { window.mode }, set: { window.mode = $0 })) {
                            ForEach(RecategorisationMode.allCases, id: \.self) { mode in Text(mode.title).tag(mode) }
                        }.pickerStyle(.segmented)
                            .disabled(window.newCategory.isMaking)   // the new category is picked in the mode it was asked in
                        Text(verbatim: CategoryWindowWording.modeLine(window.mode, current: heading.current,
                                                                      selection: heading.selection))
                            .font(AppFont.text(13)).foregroundStyle(palette.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        CategoryGrid(window: window, palette: palette)
                        // A name that made no category: why, in Settings → Categories' words (brief 60).
                        if let problem = window.newCategory.problem {
                            Text(problem).foregroundStyle(palette.expenseText)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("newCategoryProblem")
                        }
                        if window.isSample {
                            Text("Not available with sample data").foregroundStyle(palette.muted)
                        }
                        if let error = window.saveError {
                            Text(error).foregroundStyle(palette.expenseText).accessibilityIdentifier("recategorisationError")
                            Button("Retry") { Task { await window.retrySave() } }.disabled(!window.canSave)
                        }
                    }
                    .padding(20)
                    .font(AppFont.text(14)).foregroundStyle(palette.ink)
                } else if let error = window.loadError {
                    // Opened from a payment row's long press (brief 41): the payment could not be loaded.
                    VStack(alignment: .leading, spacing: 12) {
                        Text(error).font(AppFont.text(14)).foregroundStyle(palette.expenseText)
                        Button("Retry") { Task { await window.retryLoad() } }
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
            // New category (brief 60): the shared alert (`newCategoryAlert`), the name kept after a name problem.
            .newCategoryAlert(window.newCategory, tint: palette.ink) { await window.createCategory() }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    // Muted while it cannot save (nothing chosen yet, or saving), as the app's own buttons: the bar's
                    // glass button shows no difference by itself.
                    Button { Task { await window.save() } } label: {
                        (window.isSaving ? Text("Saving…") : Text("Save"))
                            .foregroundStyle(window.canSave ? palette.ink : palette.muted)
                    }
                    .disabled(!window.canSave)
                    .accessibilityIdentifier("saveCategory")
                }
            }
            .disabled(window.isSaving)
        }
        // The payment page's font reaches this sheet; the bar keeps the system's, as the app's other sheets (Save then
        // reads as the bold confirming button, greyed while it cannot save). The content above sets the app's font and
        // ink itself.
        .environment(\.font, nil)
        .tourCard()
        .tint(palette.ink)
        .interactiveDismissDisabled(window.isSaving || window.question != nil || window.newCategory.isMaking)
        .alert(Text(verbatim: window.question?.title ?? ""),
               isPresented: Binding(get: { window.question != nil }, set: { _ in }),
               presenting: window.question) { question in
            switch question {
            case let .remove(question):
                Button(question.removeTitle()) { Task { await window.answerRemoveCurrent(remove: true) } }
                Button(question.keepTitle(), role: .cancel) { Task { await window.answerRemoveCurrent(remove: false) } }
            case let .merchant(_, wording):
                Button(wording.allTitle()) { window.answer(moveOthers: true) }
                Button(wording.onlyTitle(), role: .cancel) { window.answer(moveOthers: false) }
            }
        } message: { question in
            if let message = question.message { Text(verbatim: message) }
        }
        .tint(palette.ink)      // the question's buttons in ink, as the sheet's
    }

    /// The window's top: the payment's name (or "10 payments" with their total, signed in its side's colour as a
    /// payment's page shows its amount), then "Currently in" with the category's chip and, for one payment, why it is
    /// there in one quiet line.
    private func header(_ heading: CategoryWindowHeading) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: heading.title).font(AppFont.text(22, weight: .bold))
                    .accessibilityAddTraits(.isHeader)
                if let amount = heading.amount {
                    Text(verbatim: Money.transaction(amount)).font(AppFont.number(20, weight: .bold))
                        .foregroundStyle(amount < 0 ? palette.expenseText : palette.balance)
                        .accessibilityIdentifier("selectionTotal")
                }
            }
            if heading.current != nil || heading.reason != nil {
                VStack(alignment: .leading, spacing: 8) {
                    if let current = heading.current {
                        HStack(spacing: 8) {
                            Text("Currently in").foregroundStyle(palette.muted)
                            CategoryChip(name: current, color: heading.currentColor)
                        }
                    }
                    // Why it is there (brief 47: moved here from the payment's page), one quiet line.
                    if let reason = heading.reason {
                        Text(reason).font(AppFont.text(12.5)).foregroundStyle(palette.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("categoryReason")
                    }
                }
            }
        }
    }
}

/// The change window's grid (briefs 60, 70, 82): the categories offered for the payments' side, then, in phone mode,
/// Other category… (while the other side has one not offered here) and New category. One piece for the change window and
/// the quick sort's card (brief 99), so both show the same tiles. `pick` is what a tile does (nil: the window picks it
/// for Save); `pickFromOtherSide` what a category from Other category…'s list does (nil: picked into the grid).
/// `working`: a tile's tap is at work (the quick sort sorts at once): the tapped tile keeps its look, the others grey and
/// take no taps, as while a new category is made.
struct CategoryGrid<Window: CategoryWindow>: View {
    let window: Window
    let palette: Palette
    var working = false
    var pick: ((String) -> Void)? = nil
    var pickFromOtherSide: ((String) -> Void)? = nil

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 9) {
            ForEach(window.choices) { category in choice(category, current: window.currentCategory) }
            if window.offersOtherCategory { otherCategoryTile }
            if window.offersNewCategory { newCategoryTile }
        }
    }

    /// A category being made, or a tile's tap at work: the other tiles grey and still.
    private var busy: Bool { window.newCategory.isMaking || working }

    /// The grid's last tile (brief 60): the category tiles' size, quiet ink and the line's thin outline, no category
    /// colour, so it reads as an action. While the category is made it shows the busy sign; the others are greyed.
    private var newCategoryTile: some View {
        let making = window.newCategory.isMaking
        return Button { window.beginNewCategory() } label: {
            ActionTile(symbol: "plus", title: Text("New category"), busy: making, palette: palette)
        }
        .buttonStyle(.plain)
        .opacity(working ? 0.4 : 1)
        .whileWorking(busy, tapped: making)
        .accessibilityIdentifier("newCategory")
    }

    /// Other category… (brief 70), New category's quiet look: Apple's menu of the other side's categories not offered
    /// here yet, each with its icon in its colour, under one line saying where they come from ("From spending"). Picking
    /// one closes the menu and shows it before the action tiles, picked (`pickFromOtherSide`). In a fixed order, so the
    /// line stays on top and the list reads as the window's (iOS would turn it round when it opens upwards).
    private var otherCategoryTile: some View {
        Menu {
            Section {
                ForEach(window.otherSideChoices) { category in
                    Button { (pickFromOtherSide ?? window.pickFromOtherSide)(category.name) } label: {
                        Label { Text(verbatim: category.shownName) } icon: { CategoryMenuIcon(category: category) }
                    }
                }
            } header: {
                if let line = window.otherSideListLine { Text(verbatim: line) }
            }
        } label: {
            ActionTile(symbol: "square.grid.2x2", title: Text(verbatim: CategorySideWording.otherCategory()),
                       palette: palette)
        }
        .menuOrder(.fixed)
        .buttonStyle(.plain)
        .opacity(busy ? 0.4 : 1)
        .disabled(busy)
        .accessibilityIdentifier("otherCategory")
    }

    private func choice(_ category: Category, current: String?) -> some View {
        let selected = window.isPicked(category.name)
        let color = Color(hex: category.color)
        return Button { (pick ?? window.select)(category.name) } label: {
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
            .disabled(window.mode == .add && category.name == current)
            // A category being made (brief 60), or the quick sort's tap at work: the others greyed and still, as the
            // app's other busy buttons; the tapped one keeps its look.
            .opacity(busy && !(working && selected) ? 0.4 : 1)
            .whileWorking(busy, tapped: working && selected)
            .accessibilityLabel(category.name == current ? String(localized: "\(category.shownName), current") : category.shownName)
            .accessibilityAddTraits(selected ? .isSelected : [])
            .takesBack(window.stopOfferingEntry(for: category.name)) { Task { await window.stopOffering(category.name) } }
    }
}

/// The grid's quiet action tile (New category, Other category…): the category tiles' size, the second ink and the line's
/// thin outline, no category colour, so it reads as an action. While it works it shows the busy sign in its symbol's
/// place.
private struct ActionTile: View {
    let symbol: String
    let title: Text
    var busy = false
    let palette: Palette

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10)
        HStack(spacing: 7) {
            if !busy { Image(systemName: symbol).frame(width: 20) }
            BusyLabel(text: title.font(AppFont.text(13, weight: .semibold)), busy: busy, tint: palette.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(palette.secondary).padding(10).frame(maxWidth: .infinity, minHeight: 48)
        .overlay(shape.stroke(palette.line, lineWidth: 1))
        .contentShape(shape)
    }
}

/// A category's symbol in its own colour inside Apple's menu, which draws plain symbols in its own ink (an image drawn
/// as it is keeps its colour there).
struct CategoryMenuIcon: View {
    let category: Category

    var body: some View {
        let symbol = CategorySymbol.name(for: category.icon)
        if let image = UIImage(systemName: symbol)?
            .withTintColor(UIColor(Color(hex: category.color)), renderingMode: .alwaysOriginal) {
            Image(uiImage: image)
        } else {
            Image(systemName: symbol)
        }
    }
}

private extension View {
    /// A tile offered here only from the other side (brief 70): its long press is Apple's context menu with one entry,
    /// "Not for money in" (or out). Every other tile has no long press.
    @ViewBuilder func takesBack(_ entry: String?, action: @escaping () -> Void) -> some View {
        if let entry {
            contentShape(.contextMenuPreview, RoundedRectangle(cornerRadius: 10))
                .contextMenu {
                    Button(action: action) { Label { Text(verbatim: entry) } icon: { Image(systemName: "minus.circle") } }
                }
        } else {
            self
        }
    }
}
