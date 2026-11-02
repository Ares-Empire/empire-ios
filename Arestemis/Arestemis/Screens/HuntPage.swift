import SwiftUI

/// A hunt's page (a card on the Hunts tab, pushed): today's big hunt card with Start / Pause, Edit search (the kind's
/// form) and Listings (this search's listings on the Listings tab, over Searches), its figures (New, Today, Applied or Asked; a watch's
/// Saved) and when it was last read (a watch's card says it), then its newest matches. The `…` in the bar renames it
/// (Apple's name alert, up to 60 characters; empty names it after its search, or a watch after its page, again) or
/// deletes it with its matches (Apple's destructive confirmation). A watch's words name it a watch (`HuntWords`).
struct HuntPage: View {
    let id: Int
    let store: ArestemisStore
    @Bindable var navigation: AppNavigation
    @State private var renaming = false
    @State private var name = ""
    @State private var confirmDelete = false

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
        .toolbar {
            if let card = store.card(id) {
                ToolbarItem(placement: .topBarTrailing) { menu(card) }
            }
        }
        .alert(words.rename, isPresented: $renaming) {
            TextField("Name", text: $name)
                .onChange(of: name) { _, new in
                    let limited = HuntName.limited(new)
                    if limited != new { name = limited }
                }
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                let cleaned = HuntName.cleaned(name)
                Task { await store.renameHunt(id: id, name: cleaned) }
            }
        } message: {
            Text(words.renameMessage)
        }
        .confirmationDialog(words.deleteQuestion, isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(words.delete, role: .destructive) {
                navigation.leaveDeleted(id)
                Task { await store.deleteHunt(id: id) }
            }
        } message: {
            Text(words.deleteMessage)
        }
        .task { await store.loadLatest(hunt: id) }
    }

    private func page(_ card: HuntCard) -> some View {
        let actions = HuntPageActions(card.hunt)
        let kind = SearchKind(card.hunt.kind)
        return ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HuntHeroCard(card: card, sites: store.siteNames, busy: store.isChanging(hunt: id)) { active in
                    Task { await store.setActive(id: id, active: active) }
                }
                HStack(spacing: 10) {
                    if actions.editSearch, let kind {
                        Button { navigation.huntPath.append(.form(kind, hunt: id)) } label: {
                            Label(words.editButton, systemImage: "slider.horizontal.3")
                        }
                        .buttonStyle(ProvinceButtonStyle(kind: .glass, height: 46))
                    }
                    Button { showListings(nil) } label: {
                        Label("Listings", systemImage: "list.bullet.rectangle")
                    }
                    .buttonStyle(ProvinceButtonStyle(kind: .glass, height: 46))
                }
                .labelStyle(ActionLabelStyle())
                .padding(.top, Look.rowGap)
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
            .padding(.horizontal, Look.side).padding(.top, 6).padding(.bottom, 30)
        }
        .scrollIndicators(.hidden)
        .refreshable {
            await store.reloadOverview()
            await store.loadLatest(hunt: id)
        }
    }

    private func menu(_ card: HuntCard) -> some View {
        Menu {
            Button {
                name = card.hunt.name ?? ""
                renaming = true
            } label: {
                Label("Rename", systemImage: "pencil")
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
