import SwiftUI

/// A thing hunt's search ("Things"), built from the flat form's pieces in the same order of habit: its name and "Describe
/// it" at the top, then the search words (up to five as chips, brief 149, `SearchWordsField`) with the words to leave
/// out, the wishes every listing is checked against (brief 187: Must have, which filters out a listing that clearly
/// does not match, and Nice to have, which never does, `WishField`), price (with
/// how far a negotiable price may lie over the maximum), condition, where (pickup, shipping or either; places and radius
/// unless only shipped), seller, portals (the server's sites for things, with "Include auctions" while a chosen one has
/// auctions; a site that cannot serve the delivery greyed and switched off, brief 129); then save. Pushed on the Hunts
/// tab for one hunt, or for a new one (empty, or from one of New search's examples), which it creates paused.
/// What is wrong shows under its field (`ItemSearchDraft.fieldLine`), and so does the server's refusal of a search word,
/// led by that word (`SearchWords.refusalLine`); unsaved edits are kept per hunt. Saving first asks the server about the
/// words' spelling (brief 178, `SpellingCheck`): a likely misspelled brand or model word holds the save and shows
/// "Did you mean…" with the corrected entries as chips under the words; Save again saves the words as they are then.
struct ItemSearchScreen: View {
    let store: ArestemisStore
    @Bindable var navigation: AppNavigation
    /// The hunt whose search this is; nil for a new one.
    let huntID: Int?
    /// New search's example the new form opens with, filled in.
    var example: SearchExample? = nil
    var prefill: ProductItemSearch? = nil

    @State private var draft = ItemSearchDraft()
    /// The saved hunt as this form shows it (search and name); nil for a new one.
    @State private var saved: ItemSearchDraft?
    @State private var exampleApplied = false
    @State private var description = ""
    @State private var confirmDelete = false
    @State private var launchDone = false
    @FocusState private var wordFocused: Bool
    /// Return or + found a word that cannot be added: its line shows although the field is still in use.
    @State private var triedAdding = false
    /// The words' spelling, asked about when saving (brief 178), for as long as the form is open.
    @State private var spelling = SpellingCheck()
    @Environment(\.dismiss) private var dismiss

    private var hunt: Hunt? { huntID.flatMap { store.card($0)?.hunt } }
    private var creating: Bool { huntID == nil }
    private var isDirty: Bool { draft.isChanged(from: creating ? nil : hunt) }
    private var canSave: Bool { draft.isValid && (creating || isDirty) }

    var body: some View {
        ScrollViewReader { reader in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    FormSection(title: String(localized: "Name")) {
                        NameField(text: $draft.name, placeholder: draft.namePlaceholder())
                    }
                    DescribeLine { navigation.showsDescribe = true }
                    FormSection(title: String(localized: "Search words"), problems: lines(.exclude)) { what }
                        .id("words")
                    FormSection(title: Wish.heading()) { wishes }
                        .id("wishes")                   // `-scrollTo wishes`
                    FormSection(title: String(localized: "Price"), problems: lines(.priceMin, .priceMax, .priceOrder, .vbOverMax)) {
                        price
                    }
                    FormSection(title: String(localized: "Condition"), problems: lines(.condition)) { condition }
                    FormSection(title: String(localized: "Where"), problems: lines(.places, .radius)) { place }
                        .id("where")                    // `-scrollTo where`: the delivery with the sites under it
                    FormSection(title: String(localized: "Seller")) { seller }
                    FormSection(title: String(localized: "Portals"), problems: lines(.sources)) { portals }
                    SearchSaveArea(creating: creating, canSave: canSave, saving: saving, line: saveLine,
                                   save: saveSearch, delete: creating ? nil : { confirmDelete = true })
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, Look.side).padding(.top, 4).padding(.bottom, 30)
                .animation(.easeOut(duration: 0.2), value: draft.delivery)
                .animation(.easeOut(duration: 0.2), value: showsAuctions)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .onAppear {
                guard let target = navigation.formScroll else { return }
                navigation.formScroll = nil
                DispatchQueue.main.async { reader.scrollTo(target, anchor: target == "bottom" ? .bottom : .top) }
            }
            // A suggestion held the save (Save sits at the form's end): the words come into view with their chips, as
            // little scrolled as that takes.
            .onChange(of: spelling.suggestions.isEmpty) { _, empty in
                guard !empty else { return }
                withAnimation(.easeOut(duration: 0.3)) { reader.scrollTo("words") }
            }
        }
        .searchFormChrome(title: creating ? String(localized: "New search") : String(localized: "Edit search"),
                          showsSave: canSave, saving: saving, save: saveSearch)
        .sheet(isPresented: $navigation.showsPlaceSearch) {
            PlaceSearchSheet(store: store, chosen: draft.places, initialQuery: navigation.placeQuery) { place in
                draft.add(place)
            }
            .presentationDetents([.large])
            .presentationBackground(Ink.background)
        }
        .sheet(isPresented: $navigation.showsDescribe) {
            DescribeSheet(store: store, kind: .item, text: $description) { parsed in
                guard case .item(let item) = parsed else { return }
                withAnimation(.easeOut(duration: 0.25)) { draft.apply(item.search) }
            }
            .presentationDetents([.large])
            .presentationBackground(Ink.background)
        }
        .confirmationDialog("Delete the search?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete search", role: .destructive, action: deleteSearch)
        } message: {
            Text("The hunt stops and its listings are deleted.")
        }
        .onAppear {
            sync()
            store.clearSearchError()                    // an older form's refusal is not this one's
            debugLaunch()
        }
        .task { await store.loadKinds() }               // the sites as the server offers them now
        // The hunt changed elsewhere (another device, renamed): taken over while nothing is edited here.
        .onChange(of: store.savedDraft(ItemSearchDraft.self, huntID: huntID)) { _, _ in
            if draft == (saved ?? ItemSearchDraft()) { sync() }
        }
        // A site that cannot serve the delivery goes off at once, also when the sites' answer arrives later.
        .onChange(of: draft.delivery) { _, _ in withAnimation(.easeOut(duration: 0.2)) { switchOffUnservedSites() } }
        .onChange(of: store.kinds) { _, _ in switchOffUnservedSites() }
        .onChange(of: draft) { _, new in store.keepSearchDraft(new, huntID: huntID) }
        // The server's refusal of a word goes once the words change (its place among them may be another's then), and so
        // do the spelling's chips, unless a chip's own tap changed them.
        .onChange(of: draft.sentWords) { _, words in
            if SearchWords.isWordsField(store.searchErrorField) { store.clearSearchError() }
            spelling.wordsChanged(words)
        }
    }

    /// Screenshots (sample mode, DEBUG): `-itemWords <a,b,c>` adds words as chips, `-itemTyped <text>` types into the
    /// words' field, `-itemFits <text>` fills Must have and `-itemNice <text>` Nice to have (brief 187), `-saveItem` then
    /// taps Save (with `-sampleWordRefusal <i>` the
    /// sample refuses `search.more_queries[i]` as the server would; the sample's spelling check suggests Zegna for
    /// "Zenga" and the like, `-sampleSpelling unchecked|failed|slow` makes it not check, fail or take too long).
    private func debugLaunch() {
        #if DEBUG
        guard store.isSample, !launchDone else { return }
        launchDone = true
        if let words = LaunchArguments.value("-itemWords") {
            for word in words.components(separatedBy: ",") { draft.add(word: word) }
        }
        if let typed = LaunchArguments.value("-itemTyped") { draft.type(typed) }
        if let fits = LaunchArguments.value("-itemFits") { draft.extra = fits }
        if let nice = LaunchArguments.value("-itemNice") { draft.nice = nice }
        if LaunchArguments.current.contains("-saveItem") {
            Task {
                try? await Task.sleep(for: .milliseconds(600))
                saveSearch()
            }
        }
        #endif
    }

    /// The hunt as saved, with the edits kept for it while it is still current; a new form opened from an example
    /// starts filled in from it, once.
    private func sync() {
        saved = store.savedDraft(ItemSearchDraft.self, huntID: huntID)
        // Returning from a child page keeps edits to this prefilled form, just as it keeps the Everywhere draft.
        if creating, prefill != nil, exampleApplied { return }
        draft = store.itemSearchDraft(huntID: huntID)
        if creating, !exampleApplied, let filled = prefill?.draft ?? example?.itemDraft() {
            exampleApplied = true
            draft = filled
        }
        switchOffUnservedSites()                        // a search saved before the server refused such a site
    }

    /// Switches off the chosen sites the delivery rules out (the server would refuse the search); the line under the
    /// sites says why.
    private func switchOffUnservedSites() {
        draft.switchOffSitesThatCannotServe(sites.sites)
    }

    /// The lines under a section: what is wrong with its fields.
    private func lines(_ problems: ItemSearchDraft.Problem...) -> [String] {
        problems.compactMap { draft.fieldLine($0) }
    }

    /// Under the chips: what is wrong with the search words (a word still too short only once it was to be added or the
    /// field is left, not while its first letter is typed), and the server's refusal of one, led by that word.
    private var wordLines: [String] {
        var lines: [String] = []
        if let line = draft.fieldLine(.words), !(draft.typed == .tooShort && wordFocused && !triedAdding) {
            lines.append(line)
        }
        if let field = store.searchErrorField, SearchWords.isWordsField(field), let error = store.searchError {
            lines.append(SearchWords.refusalLine(error, field: field, words: draft.sentWords))
        }
        return lines
    }

    // MARK: portals

    /// The server's sites for things (Kleinanzeigen alone until it answered), and any other the saved search names,
    /// for the delivery chosen.
    private var sites: SiteChoices { store.siteChoices(.item, chosen: draft.sources, delivery: draft.delivery) }
    private var showsAuctions: Bool { sites.showsAuctions(chosen: draft.sources) }

    private var portals: some View {
        PortalToggles(choices: sites, chosen: $draft.sources, statuses: store.overview?.sources ?? []) {
            if showsAuctions {
                FormCard {
                    Toggle(isOn: $draft.auctions) {
                        Text("Include auctions").font(AppFont.text(15, weight: .medium)).foregroundStyle(Ink.primary)
                    }
                    .tint(Look.accent.color)
                    .frame(minHeight: 50)
                }
                .padding(.top, Look.rowGap - 8)
                .transition(.opacity)
            }
        }
    }

    // MARK: what

    /// The search words with their lines right under the chips (the quiet note, what is wrong, the server's refusal),
    /// and the words to leave out under them.
    private var what: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                SearchWordsField(draft: $draft, focus: $wordFocused, triedAdding: $triedAdding)
                if let note = draft.wordsNote() {
                    Caption(text: note).padding(.bottom, 2).transition(.opacity)
                }
                ForEach(wordLines, id: \.self) { ProblemLine(text: $0).padding(.bottom, 2) }
                if !spelling.suggestions.isEmpty {
                    DidYouMeanChips(names: spelling.suggestions.map(\.suggestion), headingInset: 0, choose: takeSuggestion)
                        .padding(.top, 4).padding(.bottom, 2)
                        .transition(.opacity)
                }
            }
            .padding(.vertical, 12)
            .animation(.easeOut(duration: 0.2), value: draft.words)
            .animation(.easeOut(duration: 0.2), value: spelling.suggestions)
            Hairline()
            VStack(alignment: .leading, spacing: 10) {
                CapsLabel(text: String(localized: "Leave out"))
                WordChips(words: draft.exclude, placeholder: String(localized: "Add word"),
                          remove: { word in draft.exclude.removeAll { $0 == word } },
                          add: { draft.addExclude($0) })
                Caption(text: String(localized: "Listings with one of these words in the title don't show."))
            }
            .padding(.vertical, 14)
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    // MARK: wishes

    /// The two places for wishes (brief 187; Patrik: the app asks whether a wish must be or would be nice), in one card
    /// as the search words and the words to leave out: Must have (`extra`), then Nice to have (`nice`), each with the
    /// line that says what it does and what is wrong with it under that.
    private var wishes: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Wish.allCases, id: \.self) { wish in
                if wish != Wish.allCases.first { Hairline() }
                WishField(wish: wish, problem: draft.fieldLine(wish.problem), text: $draft[dynamicMember: wish.text])
            }
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    // MARK: price

    private var price: some View {
        VStack(alignment: .leading, spacing: 8) {
            FormCard {
                RangeRow(label: String(localized: "Between"), range: priceRange, prefix: Euro.prefix, suffix: Euro.suffix,
                         unitName: String(localized: "euros"))
                Hairline()
                HStack(spacing: 8) {
                    Text("VB up to").font(AppFont.text(15, weight: .medium)).foregroundStyle(Ink.primary)
                        .lineLimit(1).minimumScaleFactor(0.85)
                    Spacer(minLength: 6)
                    NumberField(value: amount(\.vbOverMax), prefix: Euro.prefix, suffix: Euro.suffix, placeholder: "0", width: 92,
                                label: String(localized: "Negotiable, at most this much over your maximum, in euros"))
                    // The field under the price's "min", "over" where "– max" is.
                    Text("over").font(AppFont.text(14)).foregroundStyle(Ink.muted)
                        .lineLimit(1).minimumScaleFactor(0.8)
                        .frame(width: 108, alignment: .leading)
                        .accessibilityHidden(true)
                }
                .frame(minHeight: 54)
            }
            Caption(text: String(localized: "Negotiable listings a little over your maximum still show.")).padding(.leading, 4)
        }
    }

    /// The draft's price texts as the range row's numbers (whole euros; empty = no limit).
    private var priceRange: Binding<SearchDraft.Range> {
        Binding(get: { SearchDraft.Range(min: Self.number(draft.priceMin), max: Self.number(draft.priceMax)) },
                set: { range in
                    let min = Self.text(range.min), max = Self.text(range.max)
                    if draft.priceMin != min { draft.priceMin = min }
                    if draft.priceMax != max { draft.priceMax = max }
                })
    }

    private func amount(_ field: WritableKeyPath<ItemSearchDraft, String>) -> Binding<Double?> {
        Binding(get: { Self.number(draft[keyPath: field]) }, set: { value in
            let text = Self.text(value)
            if draft[keyPath: field] != text { draft[keyPath: field] = text }
        })
    }

    private static func number(_ text: String) -> Double? {
        Double(text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
    }

    private static func text(_ value: Double?) -> String { value.map { String(Int($0.rounded())) } ?? "" }

    // MARK: condition

    private var condition: some View {
        FormCard {
            FormRow(label: String(localized: "At least")) {
                Menu {
                    Picker("At least", selection: $draft.conditionMin) {
                        ForEach([Condition.new, .likeNew, .good, .ok], id: \.self) { condition in
                            Text(verbatim: condition.title()).tag(Condition?.some(condition))
                        }
                        Text("Any").tag(Condition?.none)
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(verbatim: draft.conditionMin?.title() ?? String(localized: "Any"))
                            .font(AppFont.text(15)).foregroundStyle(Ink.primary)
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Ink.muted)
                    }
                    .padding(.horizontal, 12).frame(height: 38)
                    .background(Look.well, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Look.wellEdge))
                }
                .accessibilityLabel("Condition, at least")
                .accessibilityValue(draft.conditionMin?.title() ?? String(localized: "Any"))
            }
            Hairline()
            Toggle(isOn: $draft.forParts) {
                Text("Defective is fine too").font(AppFont.text(15, weight: .medium)).foregroundStyle(Ink.primary)
            }
            .tint(Look.accent.color)
            .frame(minHeight: 50)
        }
    }

    // MARK: where

    private var place: some View {
        VStack(alignment: .leading, spacing: 0) {
            Picker("Delivery", selection: $draft.delivery) {
                Text("Pickup").tag(Delivery.pickup)
                Text("Shipping").tag(Delivery.shipping)
                Text("Either").tag(Delivery.either)
            }
            .pickerStyle(.segmented)
            .padding(.vertical, 12)
            if draft.asksPlaces {
                Hairline()
                PlaceChips(places: draft.places, canAdd: draft.places.count < ItemSearchDraft.maxPlaces,
                           remove: { place in draft.places.removeAll { $0.id == place.id } },
                           add: { navigation.showsPlaceSearch = true })
                    .padding(.vertical, 14)
                Hairline()
                radius
            }
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }

    /// The radius around each place, in steps of 5, 10, 20, 50, 100 and 200 km.
    private var radius: some View {
        let value = Self.number(draft.radiusKm)
        return Stepper {
            HStack {
                Text("Radius").font(AppFont.text(15, weight: .medium)).foregroundStyle(Ink.primary).lineLimit(1)
                Spacer(minLength: 8)
                Text(verbatim: value.map { Format.number($0) + " km" } ?? "–")
                    .font(AppFont.number(15, weight: .medium)).foregroundStyle(Ink.primary)
                    .contentTransition(.numericText())
                    .padding(.trailing, 6)
            }
        } onIncrement: {
            withAnimation(.snappy) { draft.radiusKm = Self.text(RadiusSteps.up(from: value ?? 0)) }
        } onDecrement: {
            withAnimation(.snappy) { draft.radiusKm = Self.text(RadiusSteps.down(from: value ?? 0)) }
        }
        .frame(minHeight: 50)
        .accessibilityValue(value.map { Format.number($0) + " km" } ?? "")
    }

    // MARK: seller

    private var seller: some View {
        Picker("Seller", selection: $draft.seller) {
            Text("Private only").tag(SearchSeller.private)
            Text("Any").tag(SearchSeller.any)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 14).padding(.vertical, 12)
        .glassCard()
    }

    // MARK: save and delete

    /// Saving, or asking about the words' spelling first: the save buttons' busy state.
    private var saving: Bool { store.isSavingSearch || spelling.isChecking }

    /// A chip's tap: its entry takes the suggestion (the main words, or that one more word), and its chip goes.
    private func takeSuggestion(_ index: Int) {
        guard spelling.suggestions.indices.contains(index) else { return }
        let suggestion = spelling.suggestions[index]
        withAnimation(.easeOut(duration: 0.2)) { spelling.take(suggestion, in: &draft) }
    }

    /// Under Save: the server's refusal (unless its field shows it), what is still missing, or what saving does.
    private var saveLine: String? {
        if let error = store.searchError, !SearchWords.isWordsField(store.searchErrorField) { return error }
        if let hint = draft.hint() { return hint }
        if creating { return String(localized: "The search starts paused.") }
        if hunt?.active == true && isDirty { return String(localized: "Changes apply from the next scan.") }
        return nil
    }

    /// Save: the words' spelling first, once per word (a suggestion holds the save), then the search as it is now.
    private func saveSearch() {
        endTyping()
        guard draft.search() != nil, !saving else { return }
        Task {
            guard await spelling.beforeSaving(draft.sentWords, ask: { [store] in try await store.spelling($0) }),
                  let search = draft.search() else { return }
            guard let saved = await store.saveHunt(id: huntID, kind: .item, name: draft.sentName, search: .item(search),
                                                   fieldsShown: SearchWords.refusalFields) else { return }
            if creating { navigation.showCreated(saved.id) } else { dismiss() }
        }
    }

    private func deleteSearch() {
        guard let huntID else { return }
        navigation.leaveDeleted(huntID)
        Task { await store.deleteHunt(id: huntID) }
    }
}

/// One of the thing form's two wishes (brief 187): its name in small capitals, the text (one line, growing with what is
/// typed, as the search words' field above it), the line that says what it does, and what is wrong with it. A tap on
/// the name or the line starts typing too; the field keeps its own taps (the cursor goes where the finger is).
private struct WishField: View {
    let wish: Wish
    let problem: String?
    @Binding var text: String
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CapsLabel(text: wish.title())
                .startsTyping($focused)
            TextField("", text: $text, prompt: Text(verbatim: wish.placeholder()).foregroundStyle(Ink.muted), axis: .vertical)
                .font(AppFont.text(15)).foregroundStyle(Ink.primary).lineSpacing(3)
                .lineLimit(1...)
                .focused($focused)
                .accessibilityLabel(Text(verbatim: wish.title()))
                .accessibilityHint(Text(verbatim: wish.caption()))
            Caption(text: wish.caption())
                .startsTyping($focused)
            if let problem { ProblemLine(text: problem).padding(.top, 2) }
        }
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private extension View {
    /// A wish's name or line: a tap there puts the cursor in its field. Hidden from VoiceOver, which reads both with
    /// the field.
    func startsTyping(_ focused: FocusState<Bool>.Binding) -> some View {
        frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { focused.wrappedValue = true }
            .accessibilityHidden(true)
    }
}
