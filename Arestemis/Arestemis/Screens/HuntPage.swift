import SwiftUI

/// A hunt's page (a card on the Hunts tab, pushed): today's big hunt card with Start / Pause, Edit search (the kind's
/// form) and Listings (this search's listings on the Listings tab, over Searches), its figures (New, Today, Applied or Asked; a watch's
/// Saved) and when it was last read (a watch's card says it), then its newest matches. A watch's words name it a watch
/// (`HuntWords`). A price monitor's page has Open in shop in place of Listings, then its chart, its switches and its
/// alarms (`MonitorSections`, brief 137).
///
/// **The name is renamed where it stands** (brief 135, as Aresium renames a payment): a tap on the name or the small pen
/// after it (or Rename in the `…` menu, or a card's long press, `AppNavigation.rename`) turns it into a field in the same
/// font and place, the name all selected and the keyboard up; its grey placeholder is the automatic name
/// (`HuntText.automaticTitle`). Return, Save in the bar or a tap anywhere else saves a changed name (`NameEdit`; empty:
/// the automatic name again), Cancel in the bar or Escape leaves it as it was. The `…` menu also deletes the hunt with its
/// matches (Apple's destructive confirmation).
struct HuntPage: View {
    let id: Int
    let store: ArestemisStore
    @Bindable var navigation: AppNavigation
    @State private var confirmDelete = false
    /// An everywhere monitor's "Where it looks" (brief 157), pushed from its row.
    @State private var showsSites = false
    /// The name's field while it is open.
    @State private var edit: NameEdit?
    @State private var nameSelection: TextSelection?
    /// The field selects all of the name once it has the keyboard (a selection set before that is dropped).
    @State private var selectsName = false
    @FocusState private var nameFocused: Bool
    @Environment(\.openURL) private var openURL

    private var words: HuntWords { HuntWords(store.card(id).flatMap { SearchKind($0.hunt.kind) }) }

    var body: some View {
        Group {
            if let card = store.card(id) {
                page(card)
            } else {
                CalmMessage(text: String(localized: "This search is gone.")).frame(maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity)
        .provinceWall()
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(edit != nil)
        .toolbar { toolbar }
        .navigationDestination(isPresented: $showsSites) { MonitorSitesPage(id: id, store: store) }
        .confirmationDialog(words.deleteQuestion, isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(words.delete, role: .destructive) {
                navigation.leaveDeleted(id)
                Task { await store.deleteHunt(id: id) }
            }
        } message: {
            Text(words.deleteMessage)
        }
        .task { await store.loadLatest(hunt: id) }
        // A card's long press asked for Rename: the field opens once the page is there.
        .onChange(of: navigation.renaming, initial: true) { _, asked in
            guard asked == id else { return }
            navigation.renaming = nil
            Task {
                try? await Task.sleep(for: .milliseconds(350))      // after the push, so the keyboard comes up
                beginRename()
                debugTypeName()
            }
        }
        // Leaving the field by any way but Cancel (a tap elsewhere, a scroll, the keyboard's own key) saves.
        .onChange(of: nameFocused) { was, now in
            if was && !now { commit() }
            if now { Task { await selectName() } }
        }
    }

    private func page(_ card: HuntCard) -> some View {
        let actions = HuntPageActions(card.hunt)
        let kind = SearchKind(card.hunt.kind)
        let editing = edit != nil
        return ScrollViewReader { reader in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HuntHeroCard(card: card, sites: store.siteNames, busy: store.isChanging(hunt: id), editing: editing,
                                 offer: OfferList.selected(store.offers(hunt: id).offers?.offers ?? [], state: card.price,
                                                           off: card.hunt.search.price?.sourcesOff ?? [])) { active in
                        Task { await store.setActive(id: id, active: active) }
                    } title: { text in
                        name(card, text: text, renames: actions.rename)
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 10) {
                            if actions.editSearch, let kind {
                                Button { navigation.huntPath.append(.form(kind, hunt: id)) } label: {
                                    Label(words.editButton, systemImage: "slider.horizontal.3")
                                }
                                .buttonStyle(ProvinceButtonStyle(kind: .glass, height: 46))
                            }
                            if let monitor = card.hunt.search.price {
                                let shop = shopURL(monitor)
                                Button { if let shop { openURL(shop) } } label: {
                                    Label("Open in shop", systemImage: "safari")
                                }
                                .buttonStyle(ProvinceButtonStyle(kind: .glass, height: 46))
                                .disabled(shop == nil)
                            } else {
                                Button { showListings(nil) } label: {
                                    Label("Listings", systemImage: "list.bullet.rectangle")
                                }
                                .buttonStyle(ProvinceButtonStyle(kind: .glass, height: 46))
                            }
                        }
                        .labelStyle(ActionLabelStyle())
                        .padding(.top, Look.rowGap)
                        if let monitor = card.hunt.search.price {
                            MonitorSections(card: card, search: monitor, store: store,
                                            open: { navigation.huntPath.append(.match($0)) },
                                            showAll: { showListings(.all) }, showsSites: $showsSites)
                        } else {
                            figuresAndLatest(card, actions: actions, kind: kind)
                        }
                    }
                    // While the name is edited the rest of the page takes no taps: a tap there ends the editing (below).
                    .allowsHitTesting(!editing)
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, Look.side).padding(.top, 6).padding(.bottom, 30)
                .contentShape(Rectangle())
                .gesture(TapGesture().onEnded { nameFocused = false }, including: editing ? .all : .subviews)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .refreshable {
                await store.reloadOverview()
                await store.loadLatest(hunt: id)
            }
            .onAppear {
                // Screenshots: `-openHunt <id> -scrollTo history|switches|bottom` (a monitor's sections).
                guard store.isSample, let target = navigation.formScroll else { return }
                navigation.formScroll = nil
                Task {
                    try? await Task.sleep(for: .milliseconds(400))
                    reader.scrollTo(target, anchor: target == "bottom" ? .bottom : .top)
                }
            }
        }
    }

    /// The figures and the newest matches of a search or a watch.
    @ViewBuilder private func figuresAndLatest(_ card: HuntCard, actions: HuntPageActions, kind: SearchKind?) -> some View {
        if actions.startPause {
            HuntFigures(figures: HuntPageActions.figures(kind, counts: card.counts),
                        lastScan: card.hunt.lastScan, showsLastScan: kind != .watch, show: showListings)
                .padding(.top, Look.rowGap)
        }
        HuntSection(title: String(localized: "Latest")) {
            if let matches = store.latest(hunt: id) {
                LatestMatches(matches: matches, store: store,
                              open: { navigation.huntPath.append(.match($0)) },
                              showAll: { showListings(.all) })
            } else {
                ProgressView().controlSize(.small).tint(Ink.muted).frame(maxWidth: .infinity, minHeight: 44)
            }
        }
    }

    // MARK: the name

    /// The name on the hunt's card: a button with its pen while it can be renamed, its field while it is renamed.
    @ViewBuilder private func name(_ card: HuntCard, text: HuntText, renames: Bool) -> some View {
        if let edit, edit.hunt == id {
            nameField(card, text: text)
        } else if renames {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Button { beginRename() } label: {
                    HuntTitle(text: text, size: 20).multilineTextAlignment(.leading)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(.isHeader)
                .accessibilityHint(Text("Rename"))
                PenButton(label: Text("Rename")) { beginRename() }
            }
            .disabled(store.isChanging(hunt: id))
        } else {
            HuntTitle(text: text, size: 20).accessibilityAddTraits(.isHeader)
        }
    }

    /// The name as a field where it stands: the kind's mark and the text in the title's font and place, in a field's
    /// well that reaches into the card's margin; the clear button while something is typed.
    private func nameField(_ card: HuntCard, text: HuntText) -> some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        let binding = Binding(get: { edit?.text ?? "" }, set: { edit?.text = $0 })
        let placeholder = HuntName.placeholder(HuntText.automaticTitle(card.hunt.search, page: card.page,
                                                                       price: card.price))
        return HStack(alignment: .firstTextBaseline, spacing: 9) {
            if let kind = text.kind {
                Image(systemName: kind.symbol).font(.system(size: 20 * 0.72, weight: .medium)).foregroundStyle(Ink.muted)
                    .accessibilityHidden(true)
            }
            TextField(text: binding, selection: $nameSelection,
                      prompt: Text(verbatim: placeholder).foregroundStyle(Ink.muted)) {
                Text("Name")
            }
            .font(AppFont.text(20, weight: .semibold)).foregroundStyle(Ink.primary)
            .focused($nameFocused)
            .submitLabel(.done)
            .onSubmit { commit() }
            if !(edit?.text.isEmpty ?? true) {
                // The field's clear button, as UIKit's: back to the automatic name as the placeholder.
                Button { edit?.text = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 17)).foregroundStyle(Ink.muted)
                        .frame(width: 44, height: 44).contentShape(Rectangle()).padding(-13)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Clear"))
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(Look.well, in: shape)
        .overlay(shape.strokeBorder(Look.wellEdge))
        .contentShape(shape)
        .onTapGesture { nameFocused = true }
        .padding(.horizontal, -10).padding(.vertical, -7)  // the name stays where it stood; the well reaches out
    }

    /// The field opens with the own name selected and the keyboard up.
    private func beginRename() {
        guard edit == nil, let hunt = store.card(id)?.hunt, HuntPageActions(hunt).rename, !store.isChanging(hunt: id)
        else { return }
        edit = NameEdit(hunt)
        selectsName = true
        nameFocused = true
    }

    /// Once the field has the keyboard: all of the name selected, so typing replaces it.
    private func selectName() async {
        guard selectsName, nameFocused, let text = edit?.text else { return }
        selectsName = false
        await Task.yield()
        nameSelection = TextSelection(range: text.startIndex..<text.endIndex)
    }

    /// Return, Save, a tap elsewhere: a changed name is sent (`PUT` with the hunt's search as it is), the field closes.
    private func commit() {
        guard let edit else { return }
        endRename()
        guard edit.hasChanges else { return }
        Task { await store.renameHunt(id: edit.hunt, name: edit.name) }
    }

    /// Cancel or Escape: the name stays as it was.
    private func cancelRename() {
        endRename()
    }

    private func endRename() {
        edit = nil                  // first, so losing the focus below saves nothing
        nameFocused = false
        nameSelection = nil
        selectsName = false
    }

    /// Screenshots (sample mode, DEBUG): `-renameText <text>` types a name into the open field.
    private func debugTypeName() {
        #if DEBUG
        guard store.isSample, let typed = LaunchArguments.value("-renameText") else { return }
        edit?.text = typed
        #endif
    }

    // MARK: the bar

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        if let edit {
            // While the name is edited: Cancel and Save, as in every iOS edit (the back arrow would leave the edit).
            ToolbarItem(placement: .cancellationAction) {
                // In ink: the accent is Save's alone. Escape on a hardware keyboard is Cancel too.
                Button { cancelRename() } label: {
                    Text("Cancel").font(AppFont.text(16)).foregroundStyle(Ink.primary)
                }
                .keyboardShortcut(.cancelAction)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button { commit() } label: {
                    Text("Save").font(AppFont.text(16, weight: .semibold))
                        .foregroundStyle(edit.hasChanges ? Look.accent.color : Ink.muted)
                }
            }
        } else if let card = store.card(id) {
            ToolbarItem(placement: .topBarTrailing) { menu(card) }
        }
    }

    private func menu(_ card: HuntCard) -> some View {
        Menu {
            if HuntPageActions(card.hunt).rename {
                Button { beginRename() } label: {
                    Label("Rename", systemImage: "pencil")
                }
            }
            Button(role: .destructive) { confirmDelete = true } label: {
                Label(words.delete, systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
        }
        .tint(Ink.primary)
        .disabled(store.isChanging(hunt: id))
        .accessibilityLabel("Search actions")
    }

    /// Where "Open in shop" goes: the product's page, or for an everywhere monitor its cheapest offer now (brief 157).
    private func shopURL(_ monitor: PriceSearch) -> URL? {
        guard monitor.mode == .everywhere else { return monitor.shopURL }
        let offers = store.offers(hunt: id).offers?.offers ?? []
        return OfferList.selected(offers, state: store.card(id)?.price, off: monitor.sourcesOff)?.link
    }

    /// This search's listings on the Listings tab at the filter asked for (Listings: New while it has new ones, else
    /// All).
    private func showListings(_ filter: MatchFilter?) {
        navigation.showSearch(id, filter: filter ?? .opening(store.card(id)?.counts))
    }
}

/// A glass button's label: a small symbol before the words, in the words' ink.
private struct ActionLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 7) {
            configuration.icon.font(.system(size: 13, weight: .medium)).foregroundStyle(Ink.secondary)
            configuration.title
        }
    }
}
