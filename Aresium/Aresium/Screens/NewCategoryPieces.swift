import SwiftUI

// New category where a category is chosen (brief 60; the logic is `Model/NewCategory.swift`): the alert every place
// uses, and the Category row of the receipt window and Add cash, whose menu ends with New category…. The change window
// draws its own tile (`RecategoriseSheet`) and uses the same alert.

extension View {
    /// The picker uses the same plain ink action and keyboard Return as New category.
    func renameCategoryAlert(_ model: CategoryPickerModel) -> some View {
        modifier(RenameCategoryAlert(model: model))
    }

    /// The New category alert: Apple's alert with a name's field ("Name"), Cancel and Create, in the window's ink (`tint`;
    /// not Apple's filled default button, which iOS draws in the system blue whatever the tint). Create is off while the
    /// name is empty or spaces; the keyboard's Return creates too, and on such a name iOS's Return closes the alert like
    /// Cancel (seen 2026-10-31). `create` is the window's own: it makes the category through the model and picks it there.
    func newCategoryAlert(_ model: NewCategoryModel, tint: Color = Ink.primary,
                          create: @escaping () async -> Void) -> some View {
        modifier(NewCategoryAlert(model: model, tint: tint, create: create))
    }
}

private struct RenameCategoryAlert: ViewModifier {
    @Bindable var model: CategoryPickerModel

    func body(content: Content) -> some View {
        content.alert("Rename category", isPresented: $model.showsRename) {
            TextField("Name", text: $model.renameName)
                .textInputAutocapitalization(.sentences)
                .submitLabel(.done)
                .onSubmit {
                    model.showsRename = false
                    Task { await model.rename() }
                }
            Button("Cancel", role: .cancel) { model.cancelRename() }
            Button("Rename") {
                model.showsRename = false
                Task { await model.rename() }
            }
            .disabled(!model.canRename)
        }
        .tint(Ink.primary)
    }
}

private struct NewCategoryAlert: ViewModifier {
    @Bindable var model: NewCategoryModel
    let tint: Color
    let create: () async -> Void

    func body(content: Content) -> some View {
        content
            .alert("New category", isPresented: $model.isAsking) {
                TextField("Name", text: $model.name)
                    .textInputAutocapitalization(.sentences)
                    .submitLabel(.done)
                    .onSubmit {
                        model.isAsking = false
                        Task { await create() }
                    }
                Button("Cancel", role: .cancel) { model.cancel() }
                Button("Create") { Task { await create() } }
                    .disabled(!model.canCreate)
            }
            .tint(tint)
    }
}

/// The receipt window's and Add cash's Category: Apple's menu of the window's choices on the column check's chip, ending
/// with New category… after a divider (the same alert, the category made and picked in the window). While it is made
/// the chip shows the busy sign; a name problem is one line under the row in the windows' problem style.
struct CategoryMenuRow: View {
    @Binding var selection: String?
    let choices: [ReceiptCheckModel.Choice]
    let newCategory: NewCategoryModel
    let create: () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            FieldRow(label: String(localized: "Category")) {
                Menu {
                    Picker(selection: $selection) {
                        ForEach(choices) { choice in Text(verbatim: choice.name).tag(choice.id) }
                    } label: { EmptyView() }
                    Divider()
                    Button { newCategory.begin() } label: { Label("New category…", systemImage: "plus") }
                } label: {
                    HStack(spacing: 8) {
                        if newCategory.isMaking { ProgressView().tint(Ink.secondary) }
                        MenuChip(text: choices.first { $0.id == selection }?.name ?? "")
                    }
                }
                .disabled(newCategory.isMaking)
                .accessibilityLabel(Text("Category"))
                .accessibilityIdentifier("categoryMenu")
            }
            if let problem = newCategory.problem {
                FormProblem(text: problem).padding(.horizontal, 12).padding(.bottom, 12)
                    .accessibilityIdentifier("newCategoryProblem")
            }
        }
        .newCategoryAlert(newCategory, create: create)
        #if DEBUG
        .task { _ = await newCategory.debugLaunch(begin: newCategory.begin, create: create) }
        #endif
    }
}
