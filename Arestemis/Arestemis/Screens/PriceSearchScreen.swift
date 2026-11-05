import SwiftUI

/// A price monitor's form ("Preismonitor", brief 137, the sketch's mockup; brief 157, the plan's section 3): at the top
/// a segmented "One shop | Everywhere" ("Ein Shop | Überall"), then the name (first, as in every form; grey: the
/// product's name once found). **One shop** is brief 137's form: the product's link (the URL keyboard; a whole shared
/// text pasted in keeps its first link) with the server's preview under it once the link looks complete and typing
/// pauses ("Found: NINTENDO Switch 2 · €483.99 · in stock", or the server's refusal in its words, `PricePreviewModel`).
/// **Everywhere**: the product in words and its details in one optional line (colour, size or variant; no menu, Patrik:
/// "the search could just as well be a microphone, bike, helmet"), the server's look under the product once typing
/// pauses ("Found: Apple AirPods Max (2nd gen.)" over "in 11 shops, from €529.00", `ProductPreviewModel`), then the
/// quiet line "Looks on 11 sites · Change", which opens "Where it looks" (`PriceSitesScreen`). Then, in both, what it
/// should do (`MonitorSwitchesCard`: the history, the alarm with its two conditions; Save is off while both are off,
/// with one quiet line) and how often (Everywhere hourly or slower); then save. The alarm's price starts a little under
/// the price found (Everywhere: the cheapest). Each mode keeps its fields while the other shows. Pushed on the Hunts tab
/// for one monitor, or a new one (empty, or from one of New search's examples), which it creates paused. Unsaved edits
/// are kept per monitor.
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
    @State private var productPreview: ProductPreviewModel?
    /// The alarm's price waits for the product's price to be found (an example, or the alarm switched on before).
    @State private var limitWaits = false
    @State private var exampleApplied = false
    @State private var confirmDelete = false
    @State private var launchDone = false
    /// "Where it looks", pushed from the sites' line.
    @State private var showsSites = false
    /// Screenshots: "Where it looks" opens once its sites are known (`-priceSites`).
    @State private var opensSitesWhenKnown = false
    @State private var sampleActionDone = false
    @FocusState private var focus: Field?
    @Environment(\.dismiss) private var dismiss

    private enum Field: Hashable { case url, name, product, details }

    /// The server's fields its refusals name (Arestemis/docs/API.md → Price monitors, → Price monitors everywhere).
    private static let urlField = "search.url"
    private static let productFields: Set<String> = ["search.product", "search.identity", "search.identity.eans"]
    private static let detailsField = "search.details"
    private static let switchFields: Set<String> = ["search.history", "search.alarm"]

    private var card: HuntCard? { huntID.flatMap { store.card($0) } }
    private var creating: Bool { huntID == nil }
    private var isDirty: Bool { draft != (saved ?? PriceSearchDraft()) }
    private var canSave: Bool { draft.isValid && hasCompatibleSite && (creating || isDirty) }
    private var hasCompatibleSite: Bool {
        draft.mode == .page || sites.map { PriceSites.onCount($0, off: draft.sourcesOff, delivery: draft.delivery) > 0 } ?? true
    }
    private var words: HuntWords { HuntWords(.price) }

    /// The saved monitor's words, while the form still shows them: its card, offers and sites are then this product's.
    private var showsSavedProduct: Bool {
        guard let saved, saved.mode == .everywhere, draft.mode == .everywhere else { return false }
        return saved.words == draft.words
    }

    /// The product's preview, when it is for the words in the fields.
    private var productFound: ProductPreview? {
        guard productPreview?.query == draft.previewQuery else { return nil }
        return productPreview?.answer
    }

    private var suggestions: ProductSuggestions? { productPreview?.suggestions(for: draft.words) }

    /// The product as known now: One shop: the preview's, else the saved monitor's last read while its link is
    /// unchanged; Everywhere: the preview's (its cheapest offer), else the saved monitor's while its words are unchanged.
    private var known: (product: String?, price: Double?, currency: String?, shippingUnknown: Bool) {
        switch draft.mode {
        case .page:
            if let found = preview?.preview { return (found.product, found.price, found.currency, false) }
            guard let state = card?.price, let saved, saved.mode == .page, saved.url == draft.url else { return (nil, nil, nil, false) }
            return (state.product, state.price, state.currency, false)
        case .everywhere:
            if let found = productFound {
                let cheapest = EverywhereWords.cheapest(found, off: draft.sourcesOff)
                return (found.identity.name, cheapest?.price, cheapest?.currency, cheapest?.shippingUnknown ?? false)
            }
            guard showsSavedProduct, saved?.previewQuery == draft.previewQuery else { return (draft.isConfirmed ? draft.identity?.name : nil, nil, nil, false) }
            let name = card?.price?.product ?? draft.identity?.name
            if let huntID, let offers = store.offers(hunt: huntID).offers {
                let eligible = EverywhereWords.cheapest(offers.offers, off: draft.sourcesOff)
                return (name, eligible?.price, eligible?.currency, eligible?.shippingUnknown ?? false)
            }
            guard draft.sourcesOff == saved?.sourcesOff else { return (name, nil, nil, false) }
            return (name, card?.price?.price, card?.price?.currency, card?.price?.shippingUnknown ?? false)
        }
    }

    /// Everywhere: the sites it would look in: the preview's, else the saved monitor's while its words are unchanged; nil
    /// while none are known.
    private var sites: [PriceSite]? {
        if let found = productFound { return found.sites.isEmpty ? nil : found.sites }
        if let last = productPreview?.lastFound, last.query.words == draft.words, !last.answer.sites.isEmpty {
            return last.answer.sites
        }
        guard showsSavedProduct, let huntID, let loaded = store.offers(hunt: huntID).offers?.sites,
              !loaded.isEmpty else { return nil }
        return loaded
    }

    var body: some View {
        ScrollViewReader { reader in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    modePicker
                    FormSection(title: String(localized: "Name")) {
                        NameField(text: $draft.name, placeholder: draft.namePlaceholder(product: known.product))
                            .focused($focus, equals: .name)
                    }
                    switch draft.mode {
                    case .page:
                        FormSection(title: String(localized: "Product"), problems: linkProblems) { link }
                    case .everywhere:
                        FormSection(title: String(localized: "Product"), problems: productProblems) { productField }
                        FormSection(title: String(localized: "Details (optional)"), problems: detailsProblems) {
                            detailsField
                        }
                        FormSection(title: String(localized: "Handover"), problems: handoverProblems) {
                            PriceHandoverCard(delivery: $draft.delivery, places: $draft.places, radiusKm: $draft.radiusKm) {
                                endTyping()
                                navigation.showsPlaceSearch = true
                            }
                        }
                        .id("handover")
                        FormCard {
                            Toggle("Also used", isOn: $draft.includeUsed)
                                .font(AppFont.text(15, weight: .medium)).foregroundStyle(Ink.primary)
                                .toggleStyle(EmpireSwitchStyle(accent: Look.accent))
                                .frame(minHeight: 50)
                        }
                        .padding(.top, Look.rowGap).id("used")
                        if let sites { sitesLine(sites).transition(.opacity) }
                    }
                    FormSection(title: String(localized: "What it should do"), problems: switchRefusal) {
                        MonitorSwitchesCard(history: $draft.history, alarm: alarmBinding, below: $draft.below,
                                            backInStock: $draft.backInStock, line: switchesLine)
                    }
                    FormSection(title: String(localized: "How often")) {
                        ReadIntervalCard(every: everyBinding, choices: PriceSearch.everyChoices(for: draft.mode),
                                         label: draft.mode == .everywhere ? String(localized: "Check the shops")
                                             : String(localized: "Read the page"))
                    }
                    SearchSaveArea(words: words, creating: creating, canSave: canSave, saving: store.isSavingSearch,
                                   line: saveLine, save: saveMonitor, delete: creating ? nil : { confirmDelete = true })
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, Look.side).padding(.top, 4).padding(.bottom, 30)
                .animation(.easeOut(duration: 0.2), value: sites != nil)
                .animation(.easeOut(duration: 0.2), value: draft.delivery)
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
        .navigationDestination(isPresented: $showsSites) {
            PriceSitesScreen(product: known.product ?? HuntText.text(draft.words.product), sites: sites,
                             off: $draft.sourcesOff, store: store, delivery: draft.delivery)
        }
        .sheet(isPresented: $navigation.showsPlaceSearch) {
            PlaceSearchSheet(store: store, chosen: draft.places, initialQuery: navigation.placeQuery) { draft.add($0) }
                .presentationDetents([.large])
                .presentationBackground(Ink.background)
        }
        .confirmationDialog(words.deleteQuestion, isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(words.delete, role: .destructive, action: deleteMonitor)
        } message: {
            Text(words.deleteMessage)
        }
        .onAppear {
            if preview == nil { preview = store.pricePreviewModel() }
            if productPreview == nil { productPreview = store.productPreviewModel() }
            sync()
            store.clearSearchError()                // an older form's refusal is not this one's
            debugLaunch()
            askForProduct()
        }
        // A saved monitor's sites (Everywhere): its offers' answer, as on its page.
        .task(id: huntID) { if let huntID { await store.loadOffers(hunt: huntID) } }
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
        .onChange(of: draft.previewQuery) { _, _ in
            askForProduct()
            if let field = store.searchErrorField, Self.productFields.contains(field) || field == Self.detailsField
                || field.hasPrefix("search.places") || field == "search.radius_km" || field == "search.delivery" {
                store.clearSearchError()
            }
        }
        .onChange(of: draft.mode) { _, mode in
            clearFieldRefusals()
            if mode == .everywhere { askForProduct() }
            if mode == .page, draft.url != saved?.url { preview?.update(draft.url) }
        }
        .onChange(of: draft.below) { _, _ in limitWaits = false }
        .onChange(of: preview?.preview) { _, found in
            guard limitWaits, draft.mode == .page, let found else { return }
            if draft.prefillLimit(price: found.price, currency: found.currency) { limitWaits = false }
        }
        // The product found for the words in the fields becomes the one saving confirms, and fills a waiting limit.
        .onChange(of: productFound) { _, found in
            guard let found, let words = productPreview?.query else { return }
            draft.confirm(found.identity, for: words)
            if limitWaits, draft.mode == .everywhere, let cheapest = EverywhereWords.cheapest(found, off: draft.sourcesOff),
               draft.prefillLimit(price: cheapest.price, currency: cheapest.currency) {
                limitWaits = false
            }
        }
        .onChange(of: sites != nil) { _, knownNow in
            if knownNow && opensSitesWhenKnown {
                opensSitesWhenKnown = false
                showsSites = true
            }
        }
        .onChange(of: suggestions) { _, choices in debugSuggestionAction(choices) }
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
            limitWaits = filled.alarm && filled.below == nil
        }
    }

    // MARK: the mode

    /// "One shop | Everywhere" at the top, as Listings' New | Searches stands under its header.
    private var modePicker: some View {
        Picker("Price monitor", selection: $draft.mode.animation(.easeOut(duration: 0.2))) {
            ForEach([PriceSearch.Mode.page, .everywhere], id: \.self) { mode in
                Text(EverywhereWords.mode(mode)).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .padding(.top, 8)
    }

    // MARK: One shop: the link and its preview

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
                PreviewLine(reading: preview?.phase == .reading, title: line)
            }
        }
        .animation(.easeOut(duration: 0.2), value: preview?.phase)
    }

    /// Under the link: a link too long, the preview's refusal, the server's refusal of the save.
    private var linkProblems: [String] {
        let refusal = store.searchErrorField == Self.urlField ? store.searchError : nil
        return [draft.urlLine(), preview?.refusal, refusal].compactMap { $0 }
    }

    // MARK: Everywhere: the product, its details, its preview and its sites

    private var productField: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("", text: $draft.product, prompt: Text("e.g. AirPods Max 2").foregroundStyle(Ink.muted))
                .font(AppFont.text(16, weight: .medium)).foregroundStyle(Ink.primary)
                .submitLabel(.next)
                .onSubmit { focus = .details }
                .focused($focus, equals: .product)
                .accessibilityLabel("Product")
                .frame(minHeight: 52)
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassCard()
            productPreviewLine
            if let suggestions {
                productChoices(suggestions)
            }
        }
        .animation(.easeOut(duration: 0.2), value: productPreview?.phase)
    }

    private func productChoices(_ choices: ProductSuggestions) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !choices.names.isEmpty {
                DidYouMeanChips(names: choices.names) { selectProduct(choices.names[$0]) }
            }
            if let search = choices.itemSearch {
                Button { openThings(search) } label: {
                    // In the accent, as "Change" beside the sites: it reads as the way on, not as a note.
                    Text(verbatim: search.title()).font(AppFont.text(13, weight: .medium)).foregroundStyle(Look.accent.color)
                        .fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.leading)
                        .frame(minHeight: 44, alignment: .leading).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 4)
            }
        }
    }

    private func selectProduct(_ name: String) {
        endTyping()
        productPreview?.select(name, in: &draft)
    }

    private func openThings(_ search: ProductItemSearch) {
        endTyping()
        store.keepSearchDraft(draft, huntID: huntID)
        navigation.openItemSearch(search)
    }

    /// The server's look: "Looking for the product…", the product found over its shops and cheapest price, or the
    /// preview's failure. A saved monitor whose words are unchanged shows nothing here: its page says the rest.
    @ViewBuilder private var productPreviewLine: some View {
        switch productPreview?.query == draft.previewQuery ? productPreview?.phase : nil {
        case .reading?:
            PreviewLine(reading: true, title: String(localized: "Looking for the product…"))
        case .found(let found)?:
            let lines = EverywhereWords.found(found, off: draft.sourcesOff)
            PreviewLine(reading: false, title: lines.title, detail: lines.detail, shippingNote: lines.shippingNote)
        case .failed(let message)?:
            PreviewLine(reading: false, title: message)
        case .refused(let message)? where suggestions?.names.isEmpty == true:
            PreviewLine(reading: false, title: message)
        default:
            EmptyView()
        }
    }

    private var detailsField: some View {
        TextField("", text: $draft.details, prompt: Text("e.g. colour Midnight or Blue").foregroundStyle(Ink.muted))
            .font(AppFont.text(15)).foregroundStyle(Ink.primary)
            .submitLabel(.done)
            .focused($focus, equals: .details)
            .accessibilityLabel("Details")
            .frame(minHeight: 52)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()
    }

    /// "Looks on 11 sites · Change": one quiet line, the whole of it opening "Where it looks".
    private func sitesLine(_ sites: [PriceSite]) -> some View {
        Button {
            endTyping()
            showsSites = true
        } label: {
            HStack(spacing: 8) {
                Text(verbatim: EverywhereWords.looksIn(PriceSites.onCount(sites, off: draft.sourcesOff, delivery: draft.delivery), includeUsed: draft.includeUsed))
                    .foregroundStyle(Ink.secondary)
                Spacer(minLength: 8)
                Text("Change").fontWeight(.semibold).foregroundStyle(Look.accent.color)
            }
            .font(AppFont.text(13))
            .padding(.horizontal, 4)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, 6)
    }

    /// Under the product: one too short or too long, the preview's refusal, the server's refusal of the save.
    private var productProblems: [String] {
        let refusal = store.searchErrorField.map(Self.productFields.contains) == true ? store.searchError : nil
        let previewRefusal = productPreview?.query == draft.previewQuery && suggestions == nil ? productPreview?.refusal : nil
        return [draft.productLine(), previewRefusal, refusal].compactMap { $0 }
    }

    private var handoverProblems: [String] {
        var lines = draft.problems.filter { $0 == .radius || ($0 == .places && !draft.places.isEmpty) }
            .map { draft.message($0) }
        if let field = store.searchErrorField,
           field.hasPrefix("search.places") || field == "search.radius_km" || field == "search.delivery",
           let error = store.searchError { lines.append(error) }
        if !hasCompatibleSite { lines.append(PriceSites.lastSiteLine()) }
        return lines
    }

    private var detailsProblems: [String] {
        let refusal = store.searchErrorField == Self.detailsField ? store.searchError : nil
        return [draft.detailsLine(), refusal].compactMap { $0 }
    }

    /// The words changed (or the form opened on Everywhere): a saved monitor's own words take its saved product again
    /// (nothing to ask the server: its page's offers give the sites); other words are looked for once typing pauses,
    /// also a kept draft's found before (its sites and prices are asked anew; words asked already are not asked again).
    private func askForProduct() {
        guard draft.mode == .everywhere else { return }
        if showsSavedProduct, saved?.previewQuery == draft.previewQuery, let identity = saved?.identity {
            draft.confirm(identity, for: draft.words)
            productPreview?.ask(nil)
            return
        }
        productPreview?.update(draft.previewQuery)
    }

    // MARK: the switches and how often

    /// The switches' line; an alarm whose price still waits for the product's price (no link or product yet, or it is
    /// being read) is not told to say when it rings.
    private var switchesLine: String? {
        let reading = draft.mode == .page ? preview?.phase == .reading : productPreview?.phase == .reading
        let empty = draft.mode == .page ? draft.url.trimmingCharacters(in: .whitespaces).isEmpty
            : draft.words.product.isEmpty
        let waiting = limitWaits && (empty || reading)
        if waiting && draft.problems.contains(.alarmCondition) && !draft.problems.contains(.neither) { return nil }
        return draft.switchesLine()
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

    private func clearFieldRefusals() {
        guard let field = store.searchErrorField else { return }
        if field == Self.urlField || field == Self.detailsField || Self.productFields.contains(field) {
            store.clearSearchError()
        }
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

    /// How often: Everywhere shows at least hourly; the chosen value stays for One shop.
    private var everyBinding: Binding<Int> {
        Binding(get: { draft.effectiveEvery }, set: { draft.every = $0 })
    }

    // MARK: save and delete

    /// Under Save: the server's refusal (unless a field shows it), a missing link or product, or what saving does.
    private var saveLine: String? {
        if let error = store.searchError {
            let field = store.searchErrorField ?? ""
            if !fieldsShown.contains(field) { return error }
        }
        if let hint = draft.hint() { return hint }
        if creating { return words.startsPaused }
        if card?.hunt.active == true && isDirty { return String(localized: "Changes apply from the next scan.") }
        return nil
    }

    /// The fields whose refusals show where they are.
    private var fieldsShown: Set<String> {
        draft.mode == .page ? Self.switchFields.union([Self.urlField])
            : Self.switchFields.union(Self.productFields).union([Self.detailsField, "search.places", "search.radius_km", "search.delivery"])
    }

    private func saveMonitor() {
        endTyping()
        guard let search = draft.search() else { return }
        Task {
            guard let saved = await store.saveHunt(id: huntID, kind: .price, name: draft.sentName, search: .price(search),
                                                   fieldsShown: fieldsShown) else { return }
            if creating { navigation.showCreated(saved.id) } else { dismiss() }
        }
    }

    private func deleteMonitor() {
        guard let huntID else { return }
        navigation.leaveDeleted(huntID)
        Task { await store.deleteHunt(id: huntID) }
    }

    /// Screenshots (sample mode, DEBUG): `-priceMode page|everywhere` picks the mode, `-priceURL <text>` types (or
    /// pastes) a link, `-priceProduct <text>` and `-priceDetails <text>` type the product and its details,
    /// `-sitesOff <id,id>` switches sites off, `-priceSites` opens "Where it looks" once its sites are known,
    /// `-priceSwitches both|history|alarm|none` sets the switches. With `-fulfillmentSample shipping|pickup|either`,
    /// `-priceDelivery shipping|pickup|either` selects the handover; `-priceNoPlace` clears places and `-pricePlace` opens
    /// the existing place picker. All selections use the regular preview and draft paths.
    private func debugLaunch() {
        #if DEBUG
        guard store.isSample, !launchDone else { return }
        launchDone = true
        if let mode = LaunchArguments.value("-priceMode").flatMap(PriceSearch.Mode.init(rawValue:)) { draft.mode = mode }
        if let url = LaunchArguments.value("-priceURL") { draft.url = url }
        if let product = LaunchArguments.value("-priceProduct") { draft.product = product }
        if let details = LaunchArguments.value("-priceDetails") { draft.details = details }
        if let sample = LaunchArguments.value("-productSample"), ["family", "generic", "chip", "things"].contains(sample) {
            draft.mode = .everywhere
            draft.product = sample == "generic" ? ProductSuggestionSample.generic : ProductSuggestionSample.family
            draft.details = ProductSuggestionSample.details
        }
        if let selection = LaunchArguments.value("-priceDelivery").flatMap(Delivery.init(rawValue:)) {
            draft.delivery = selection
            draft.places = selection == .shipping ? [] : [FulfillmentSample.place]
            draft.radiusKm = 20
        }
        if LaunchArguments.current.contains("-priceNoPlace") { draft.places = [] }
        if LaunchArguments.current.contains("-pricePlace") {
            navigation.placeQuery = FulfillmentSample.place.name
            navigation.showsPlaceSearch = true
        }
        if let used = LaunchArguments.value("-priceUsed") { draft.includeUsed = used == "on" }
        if let off = LaunchArguments.value("-sitesOff") { draft.sourcesOff = off.components(separatedBy: ",") }
        if LaunchArguments.current.contains("-priceSites") { opensSitesWhenKnown = true }
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

    /// Exercises the same actions as a chip or the Things row after the sample refusal has arrived.
    private func debugSuggestionAction(_ choices: ProductSuggestions?) {
        #if DEBUG
        guard store.isSample, !sampleActionDone, let choices else { return }
        switch LaunchArguments.value("-productSample") {
        case "chip":
            guard let name = choices.names.first else { return }
            sampleActionDone = true
            selectProduct(name)
        case "things":
            guard let search = choices.itemSearch else { return }
            sampleActionDone = true
            openThings(search)
        default: break
        }
        #endif
    }
}

/// The quiet lines under a field while the server looks at it: a small spinner while it reads, then what it found
/// (`title`, in the secondary ink as the sketch's bold line, and `detail` under it) or why not.
private struct PreviewLine: View {
    let reading: Bool
    let title: String
    var detail: String? = nil
    var shippingNote: String? = nil

    var body: some View {
        HStack(alignment: .center, spacing: 7) {
            if reading {
                ProgressView().controlSize(.mini).tint(Ink.muted)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title).font(AppFont.text(12, weight: detail == nil ? .regular : .medium))
                    .foregroundStyle(detail == nil ? Ink.muted : Ink.secondary)
                if let detail {
                    Text(verbatim: detail).font(AppFont.text(12)).foregroundStyle(Ink.muted)
                }
                if let shippingNote {
                    Text(verbatim: shippingNote).font(AppFont.text(12)).foregroundStyle(Ink.muted)
                }
            }
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.leading, 4)
        .transition(.opacity)
        .accessibilityElement(children: .combine)
    }
}
