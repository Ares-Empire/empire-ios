import SwiftUI

/// A watch's form ("Watch a website", brief 131), built from the thing form's pieces in its order of habit: its name
/// (brief 135: first, as in every form; empty: the page's title once read, else the host), the page's address (the URL
/// keyboard, nothing corrected or capitalised; a whole shared text pasted in keeps only its first link), the change in
/// the user's own words, with examples as chips over it that fill the sentence for the user to sharpen (brief 137,
/// `WatchChange`), and how often the page is read; one line on what a watch cannot read; then save. Pushed on
/// the Hunts tab for one watch, or for a new one (empty, or from one of New search's examples), which it creates paused. What is wrong shows under its field (`WatchSearchDraft.fieldLine`), and
/// so does the server's refusal of the address or the description (`ArestemisStore.searchErrorField`); unsaved edits
/// are kept per watch. Opened from a watch's suggested page (brief 178, "Watch this page") it shows the watch with that
/// address in place of its own; saving it reads the new page from the start, as any change of the address does.
struct WatchSearchScreen: View {
    let store: ArestemisStore
    @Bindable var navigation: AppNavigation
    /// The watch this form edits; nil for a new one.
    let huntID: Int?
    /// New search's example the new form opens with, filled in.
    var example: SearchExample? = nil
    /// The watch's suggested page (brief 178): the form opens with this address in place of the watch's own.
    var suggestedAddress: String? = nil

    @State private var draft = WatchSearchDraft()
    @State private var saved: WatchSearchDraft?
    @State private var exampleApplied = false
    @State private var addressApplied = false
    @State private var confirmDelete = false
    @State private var launchDone = false
    /// The example chip tapped last, shown chosen while its sentence is sharpened; at first the one whose sentence the
    /// field holds.
    @State private var chosenChange: WatchChange?
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
                    FormSection(title: String(localized: "Name")) {
                        NameField(text: $draft.name,
                                  placeholder: draft.namePlaceholder(savedURL: saved?.url, pageTitle: card?.page?.pageTitle))
                            .focused($focus, equals: .name)
                    }
                    FormSection(title: String(localized: "Page"), problems: lines(.url, field: Self.urlField)) { address }
                    FormSection(title: String(localized: "Tell me when"), problems: lines(.change, field: Self.changeField)) {
                        VStack(alignment: .leading, spacing: 10) {
                            changeChips
                            TextArea(placeholder: String(localized: "3.4.0 is out, not a release candidate"),
                                     text: $draft.change, minHeight: 84, inWell: false)
                                .focused($focus, equals: .change)
                                .accessibilityLabel("Tell me when")
                                .glassCard()
                        }
                    }
                    FormSection(title: String(localized: "How often")) { ReadIntervalCard(every: $draft.every) }
                    Caption(text: String(localized: "Pages behind a login, or that need clicks (such as appointment bookings), can't be watched."))
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
        .onChange(of: store.savedDraft(WatchSearchDraft.self, huntID: huntID)) { _, _ in
            if draft == (saved ?? WatchSearchDraft()) { sync() }
        }
        .onChange(of: draft) { _, new in store.keepSearchDraft(new, huntID: huntID) }
        .onChange(of: draft.url) { _, new in
            draft.takeAddress(new)
            if store.searchErrorField == Self.urlField { store.clearSearchError() }
        }
        .onChange(of: draft.change) { _, _ in
            if store.searchErrorField == Self.changeField { store.clearSearchError() }
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

    /// The watch as saved, with the edits kept for it while it is still current; a new form opened from an example
    /// starts filled in from it, once, and one opened from the suggested page takes its address, once (edits made
    /// after it stay when the form appears again).
    private func sync() {
        saved = store.savedDraft(WatchSearchDraft.self, huntID: huntID)
        if suggestedAddress != nil, addressApplied { return }
        draft = store.searchDraft(WatchSearchDraft.self, huntID: huntID)
        if creating, !exampleApplied, let filled = example?.watchDraft() {
            exampleApplied = true
            draft = filled
        }
        if let suggestedAddress, !addressApplied {
            addressApplied = true
            draft = draft.adopting(address: suggestedAddress)
        }
        if chosenChange == nil { chosenChange = WatchChange.example(in: draft.change) }
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

    /// The examples over the sentence (the sketch's third mockup): a tap fills it in and puts the cursor in it, to
    /// sharpen; "own description" empties a sentence that is still an example's. The chip tapped last shows chosen.
    private var changeChips: some View {
        FlowLayout(spacing: 8, lineSpacing: 8) {
            ForEach(WatchChange.allCases) { change in
                Button {
                    draft.change = change.apply(to: draft.change)
                    chosenChange = change
                    focus = .change
                } label: {
                    Chip(text: change.title(), selected: chosenChange == change)
                        .padding(.vertical, 5).contentShape(Rectangle()).padding(.vertical, -5)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(chosenChange == change ? .isSelected : [])
                .accessibilityHint(change == .own ? Text("Write your own sentence") : Text("Fills in the sentence"))
            }
        }
        .padding(.leading, 2)
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
        navigation.leaveDeleted(huntID)
        Task { await store.deleteHunt(id: huntID) }
    }
}
