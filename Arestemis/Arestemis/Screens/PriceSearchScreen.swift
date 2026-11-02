import SwiftUI

/// A price monitor's form ("Preismonitor", brief 137, the sketch's mockup), in the watch form's pieces: its name (first,
/// as in every form; grey: the product's name once found, else the host), the product's link (the URL keyboard; a whole
/// shared text pasted in keeps its first link) with the server's preview under it once the link looks complete and
/// typing pauses ("Found: NINTENDO Switch 2 · €483.99 · in stock", or the server's refusal in its words, `PricePreview
/// Model`), what it should do (`MonitorSwitchesCard`: the history, the alarm with its two conditions; Save is off while
/// both are off, with one quiet line), how often; then save. The alarm's price starts a little under the price found.
/// Pushed on the Hunts tab for one monitor, or a new one (empty, or from one of New search's examples), which it creates
/// paused. Unsaved edits are kept per monitor.
struct PriceSearchScreen: View {
    let store: ArestemisStore
    @Bindable var navigation: AppNavigation
    /// The monitor this form edits; nil for a new one.
    let huntID: Int?
    /// New search's example the new form opens with, filled in.
    var example: SearchExample? = nil

    @State private var draft = PriceSearchDraft()
    @State private var saved: PriceSearchDraft?
    @State private var preview: PricePreviewModel?
    /// The alarm's price waits for the product's price to be found (an example, or the alarm switched on before).
    @State private var limitWaits = false
    @State private var exampleApplied = false
    @State private var confirmDelete = false
    @State private var launchDone = false
    @FocusState private var focus: Field?
    @Environment(\.dismiss) private var dismiss

    private enum Field: Hashable { case url, name }

    /// The server's fields its refusals name (Arestemis/docs/API.md → Price monitors).
    private static let urlField = "search.url"
    private static let switchFields: Set<String> = ["search.history", "search.alarm"]

    private var card: HuntCard? { huntID.flatMap { store.card($0) } }
    private var creating: Bool { huntID == nil }
    private var isDirty: Bool { draft != (saved ?? PriceSearchDraft()) }
    private var canSave: Bool { draft.isValid && (creating || isDirty) }
    private var words: HuntWords { HuntWords(.price) }

    /// The product as known now: the preview's, else the saved monitor's last read while its link is unchanged.
    private var known: (product: String?, price: Double?, currency: String?) {
        if let found = preview?.preview { return (found.product, found.price, found.currency) }
        guard let state = card?.price, let saved, saved.url == draft.url else { return (nil, nil, nil) }
        return (state.product, state.price, state.currency)
    }

    var body: some View {
        ScrollViewReader { reader in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    FormSection(title: String(localized: "Name")) {
                        NameField(text: $draft.name, placeholder: draft.namePlaceholder(product: known.product))
                            .focused($focus, equals: .name)
                    }
                    FormSection(title: String(localized: "Product"), problems: linkProblems) { link }
                    FormSection(title: String(localized: "What it should do"), problems: switchRefusal) {
                        MonitorSwitchesCard(history: $draft.history, alarm: alarmBinding, below: $draft.below,
                                            backInStock: $draft.backInStock, line: switchesLine)
                    }
                    FormSection(title: String(localized: "How often")) { ReadIntervalCard(every: $draft.every) }
                    SearchSaveArea(words: words, creating: creating, canSave: canSave, saving: store.isSavingSearch,
                                   line: saveLine, save: saveMonitor, delete: creating ? nil : { confirmDelete = true })
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
                          showsSave: canSave, saving: store.isSavingSearch, save: saveMonitor)
        .confirmationDialog(words.deleteQuestion, isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(words.delete, role: .destructive, action: deleteMonitor)
        } message: {
            Text(words.deleteMessage)
        }
        .onAppear {
            if preview == nil { preview = store.pricePreviewModel() }
            sync()
            store.clearSearchError()                // an older form's refusal is not this one's
            debugLaunch()
        }
        // The monitor changed elsewhere (its page's switches): taken over while nothing is edited here.
        .onChange(of: store.savedDraft(PriceSearchDraft.self, huntID: huntID)) { _, _ in
            if draft == (saved ?? PriceSearchDraft()) { sync() }
        }
        .onChange(of: draft) { _, new in store.keepSearchDraft(new, huntID: huntID) }
        .onChange(of: draft.url) { _, new in
            draft.takeAddress(new)
            // A changed link is read again; the saved one is known from the monitor's card.
            if new != saved?.url || preview?.phase != .idle { preview?.update(draft.url) }
            if store.searchErrorField == Self.urlField { store.clearSearchError() }
        }
        .onChange(of: draft.below) { _, _ in limitWaits = false }
        .onChange(of: preview?.preview) { _, found in
            guard limitWaits, let found else { return }
            if draft.prefillLimit(price: found.price, currency: found.currency) { limitWaits = false }
        }
        .onChange(of: draft.history) { _, _ in clearSwitchRefusal() }
        .onChange(of: draft.alarm) { _, _ in clearSwitchRefusal() }
    }

    /// The monitor as saved, with the edits kept for it while it is still current; a new form opened from an example
    /// starts filled in from it, once.
    private func sync() {
        saved = store.savedDraft(PriceSearchDraft.self, huntID: huntID)
        draft = store.searchDraft(PriceSearchDraft.self, huntID: huntID)
        if creating, !exampleApplied, let filled = example?.priceDraft {
            exampleApplied = true
            draft = filled
            limitWaits = example == .priceBelow
        }
    }

    // MARK: the link and the preview

    private var link: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("", text: $draft.url, prompt: Text(verbatim: "https://…").foregroundStyle(Ink.muted))
                .font(AppFont.text(16, weight: .medium)).foregroundStyle(Ink.primary)
                .keyboardType(.URL)
                .textContentType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .focused($focus, equals: .url)
                .accessibilityLabel("The product's link")
                .frame(minHeight: 52)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard()
            if let line = preview?.line() {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    if preview?.phase == .reading {
                        ProgressView().controlSize(.mini).tint(Ink.muted)
                    }
                    Text(verbatim: line).font(AppFont.text(12)).foregroundStyle(Ink.muted).lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.leading, 4)
                .transition(.opacity)
                .accessibilityElement(children: .combine)
            }
        }
        .animation(.easeOut(duration: 0.2), value: preview?.phase)
    }

    /// The switches' line; an alarm whose price still waits for the product's price (no link yet, or it is being read)
    /// is not told to say when it rings.
    private var switchesLine: String? {
        let waiting = limitWaits && (draft.url.trimmingCharacters(in: .whitespaces).isEmpty || preview?.phase == .reading)
        if waiting && draft.problems.contains(.alarmCondition) && !draft.problems.contains(.neither) { return nil }
        return draft.switchesLine()
    }

    /// Under the link: a link too long, the preview's refusal, the server's refusal of the save.
    private var linkProblems: [String] {
        let refusal = store.searchErrorField == Self.urlField ? store.searchError : nil
        return [draft.urlLine(), preview?.refusal, refusal].compactMap { $0 }
    }

    /// The server's refusal of the switches (the form keeps its own line meanwhile).
    private var switchRefusal: [String] {
        guard let field = store.searchErrorField, Self.switchFields.contains(field), let error = store.searchError,
              error != draft.switchesLine() else { return [] }
        return [error]
    }

    private func clearSwitchRefusal() {
        if let field = store.searchErrorField, Self.switchFields.contains(field) { store.clearSearchError() }
    }

    /// The alarm switched on: its conditions come on, the price a little under the price found (or once it is found).
    private var alarmBinding: Binding<Bool> {
        Binding(get: { draft.alarm }, set: { on in
            if on {
                let known = known
                limitWaits = draft.turnAlarmOn(price: known.price, currency: known.currency)
            } else {
                draft.alarm = false
                limitWaits = false
            }
        })
    }

    // MARK: save and delete

    /// Under Save: the server's refusal (unless a field shows it), a missing link, or what saving does.
    private var saveLine: String? {
        if let error = store.searchError {
            let field = store.searchErrorField ?? ""
            if field != Self.urlField && !Self.switchFields.contains(field) { return error }
        }
        if let hint = draft.hint() { return hint }
        if creating { return words.startsPaused }
        if card?.hunt.active == true && isDirty { return String(localized: "Changes apply from the next scan.") }
        return nil
    }

    private func saveMonitor() {
        endTyping()
        guard let search = draft.search() else { return }
        Task {
            guard let saved = await store.saveHunt(id: huntID, kind: .price, name: draft.sentName, search: .price(search),
                                                   fieldsShown: Self.switchFields.union([Self.urlField])) else { return }
            if creating { navigation.showCreated(saved.id) } else { dismiss() }
        }
    }

    private func deleteMonitor() {
        guard let huntID else { return }
        navigation.leaveDeleted(huntID)
        Task { await store.deleteHunt(id: huntID) }
    }

    /// Screenshots (sample mode, DEBUG): `-priceURL <text>` types (or pastes) a link, `-priceSwitches
    /// both|history|alarm|none` sets the switches.
    private func debugLaunch() {
        #if DEBUG
        guard store.isSample, !launchDone else { return }
        launchDone = true
        if let url = LaunchArguments.value("-priceURL") { draft.url = url }
        switch LaunchArguments.value("-priceSwitches") {
        case "both":
            draft.history = true
            limitWaits = draft.turnAlarmOn(price: nil)
        case "history":
            draft.history = true
            draft.alarm = false
        case "alarm":
            draft.history = false
            limitWaits = draft.turnAlarmOn(price: nil)
        case "none":
            draft.history = false
            draft.alarm = false
        default: break
        }
        #endif
    }
}
