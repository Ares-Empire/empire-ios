import SwiftUI

/// A watch's form ("Watch a page", brief 131), built from the thing form's pieces in its order of habit: the page's
/// address (the URL keyboard, nothing corrected or capitalised; a whole shared text pasted in keeps only its first link),
/// the change in the user's own words, how often the page is read, and an optional name (empty: the page's title once
/// read, else the host); one line on what a watch cannot read yet; then save. Pushed on the Hunts tab for one watch, or
/// empty for a new one, which it creates paused. What is wrong shows under its field (`WatchSearchDraft.fieldLine`), and
/// so does the server's refusal of the address or the description (`ArestemisStore.searchErrorField`); unsaved edits
/// are kept per watch.
struct WatchSearchScreen: View {
    let store: ArestemisStore
    @Bindable var navigation: AppNavigation
    /// The watch this form edits; nil for a new one.
    let huntID: Int?

    @State private var draft = WatchSearchDraft()
    @State private var saved: WatchSearchDraft?
    @State private var confirmDelete = false
    @State private var launchDone = false
    @FocusState private var focus: Field?
    @Environment(\.dismiss) private var dismiss

    private enum Field: Hashable { case url, change, name }

    /// The server's fields its refusals name (Arestemis/docs/API.md → Page watches).
    private static let urlField = "search.url"
    private static let changeField = "search.change"

    private var card: HuntCard? { huntID.flatMap { store.card($0) } }
    private var creating: Bool { huntID == nil }
    private var isDirty: Bool { draft != (saved ?? WatchSearchDraft()) }
    private var canSave: Bool { draft.isValid && (creating || isDirty) }
    private var words: HuntWords { HuntWords(.watch) }

    var body: some View {
        ScrollViewReader { reader in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    FormSection(title: String(localized: "Page"), problems: lines(.url, field: Self.urlField)) { address }
                    FormSection(title: String(localized: "Tell me when"), problems: lines(.change, field: Self.changeField)) {
                        TextArea(placeholder: String(localized: "the price is under 45 €"), text: $draft.change,
                                 minHeight: 84, inWell: false)
                            .focused($focus, equals: .change)
                            .accessibilityLabel("Tell me when")
                            .glassCard()
                    }
                    FormSection(title: String(localized: "How often")) { interval }
                    FormSection(title: String(localized: "Name")) { name }
                    Caption(text: String(localized: "Pages that need a login, or build their content with JavaScript (such as appointment bookings), can't be watched yet."))
                        .padding(.leading, 4).padding(.top, 18)
                    SearchSaveArea(words: words, creating: creating, canSave: canSave, saving: store.isSavingSearch,
                                   line: saveLine, save: saveWatch, delete: creating ? nil : { confirmDelete = true })
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, Look.side).padding(.top, 4).padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .onAppear {
                guard let target = navigation.formScroll else { return }
                navigation.formScroll = nil
                DispatchQueue.main.async { reader.scrollTo(target, anchor: target == "bottom" ? .bottom : .top) }
            }
        }
        .searchFormChrome(title: creating ? words.newTitle : words.editTitle,
                          showsSave: canSave, saving: store.isSavingSearch, save: saveWatch)
        .confirmationDialog(words.deleteQuestion, isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(words.delete, role: .destructive, action: deleteWatch)
        } message: {
            Text(words.deleteMessage)
        }
        .onAppear {
            sync()
            store.clearSearchError()                // an older form's refusal is not this one's
            debugLaunch()
        }
        // The watch changed elsewhere: taken over while nothing is edited here. Edits stay, also through a save's
        // optimistic change and its rollback after a refusal.
        .onChange(of: store.savedWatchDraft(huntID: huntID)) { _, _ in
            if draft == (saved ?? WatchSearchDraft()) { sync() }
        }
        .onChange(of: draft) { _, new in store.keepWatchSearchDraft(new, huntID: huntID) }
        .onChange(of: draft.url) { _, new in
            draft.takeAddress(new)
            if store.searchErrorField == Self.urlField { store.clearSearchError() }
        }
        .onChange(of: draft.change) { _, _ in
            if store.searchErrorField == Self.changeField { store.clearSearchError() }
        }
        .onChange(of: draft.name) { _, new in
            let limited = HuntName.limited(new)
            if limited != new { draft.name = limited }
        }
    }

    /// Screenshots (sample mode, DEBUG): `-watchURL <text>` types (or pastes) an address, `-watchChange <text>` the
    /// change, `-saveWatch` then taps Save, to see the server's refusal at its field.
    private func debugLaunch() {
        #if DEBUG
        guard store.isSample, !launchDone else { return }
        launchDone = true
        if let url = LaunchArguments.value("-watchURL") { draft.url = url }
        if let change = LaunchArguments.value("-watchChange") { draft.change = change }
        if LaunchArguments.current.contains("-saveWatch") {
            Task {
                try? await Task.sleep(for: .milliseconds(600))
                saveWatch()
            }
        }
        #endif
    }

    /// The watch as saved, with the edits kept for it while it is still current.
    private func sync() {
        saved = store.savedWatchDraft(huntID: huntID)
        draft = store.watchSearchDraft(huntID: huntID)
    }

    /// The lines under a section: what is wrong with its field, and the server's refusal of it.
    private func lines(_ problem: WatchSearchDraft.Problem, field: String) -> [String] {
        let refusal = store.searchErrorField == field ? store.searchError : nil
        return [draft.fieldLine(problem), refusal].compactMap { $0 }
    }

    // MARK: fields

    private var address: some View {
        TextField("", text: $draft.url, prompt: Text(verbatim: "https://…").foregroundStyle(Ink.muted))
            .font(AppFont.text(16, weight: .medium)).foregroundStyle(Ink.primary)
            .keyboardType(.URL)
            .textContentType(.URL)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .submitLabel(.next)
            .onSubmit { focus = .change }
            .focused($focus, equals: .url)
            .accessibilityLabel("The page's address")
            .frame(minHeight: 52)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()
    }

    /// How often the page is read: Apple's menu in a quiet well, as the thing form's condition.
    private var interval: some View {
        FormCard {
            FormRow(label: String(localized: "Read the page")) {
                Menu {
                    Picker("How often", selection: $draft.every) {
                        ForEach(WatchInterval.choices(keeping: draft.every), id: \.self) { minutes in
                            Text(verbatim: WatchInterval.title(minutes)).tag(minutes)
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(verbatim: WatchInterval.title(draft.every))
                            .font(AppFont.text(15)).foregroundStyle(Ink.primary)
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Ink.muted)
                    }
                    .padding(.horizontal, 12).frame(height: 38)
                    .background(Look.well, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Look.wellEdge))
                }
                .accessibilityLabel("How often")
                .accessibilityValue(WatchInterval.title(draft.every))
            }
        }
    }

    /// The watch's own name; while it is empty the field shows what the watch will be called.
    private var name: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("", text: $draft.name,
                      prompt: Text(verbatim: draft.namePlaceholder(savedURL: saved?.url, pageTitle: card?.page?.pageTitle))
                        .foregroundStyle(Ink.muted))
                .font(AppFont.text(16, weight: .medium)).foregroundStyle(Ink.primary)
                .submitLabel(.done)
                .focused($focus, equals: .name)
                .accessibilityLabel("Name")
                .frame(minHeight: 52)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard()
            Caption(text: words.renameMessage).padding(.leading, 4)
        }
    }

    // MARK: save and delete

    /// Under Save: the server's refusal (unless its field shows it), what is still missing, or what saving does.
    private var saveLine: String? {
        if let error = store.searchError, ![Self.urlField, Self.changeField].contains(store.searchErrorField) { return error }
        if let hint = draft.hint() { return hint }
        if creating { return words.startsPaused }
        if card?.hunt.active == true && isDirty { return String(localized: "Changes apply from the next scan.") }
        return nil
    }

    private func saveWatch() {
        endTyping()
        guard let search = draft.search() else { return }
        Task {
            guard let saved = await store.saveHunt(id: huntID, kind: .watch, name: draft.sentName, search: .watch(search),
                                                   fieldsShown: [Self.urlField, Self.changeField]) else { return }
            if creating { navigation.showCreated(saved.id) } else { dismiss() }
        }
    }

    private func deleteWatch() {
        guard let huntID else { return }
        navigation.leaveDeleted()
        Task { await store.deleteHunt(id: huntID) }
    }
}
