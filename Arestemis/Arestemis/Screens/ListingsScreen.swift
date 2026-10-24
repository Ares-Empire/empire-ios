import SwiftUI

/// Every match by state (New · Saved · Applied · All), as glass cards: swipe right to save, left to dismiss, tap for the
/// match. At the end, the listings the AI filtered out.
struct ListingsScreen: View {
    let store: ArestemisStore
    @Bindable var navigation: AppNavigation

    private var filter: MatchFilter { navigation.filter }

    var body: some View {
        NavigationStack(path: $navigation.listingsPath) {
            VStack(spacing: 0) {
                header
                List {
                    content
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .scrollIndicators(.hidden)
                .contentMargins(.top, 10, for: .scrollContent)
                .contentMargins(.bottom, 24, for: .scrollContent)
                .edgeFade(top: 14)
                .refreshable {
                    async let matches: Void = store.loadMatches(filter)
                    async let rejected: Void = store.loadRejected()
                    _ = await (matches, rejected)
                }
            }
            .provinceWall()
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Int.self) { id in
                MatchDetailScreen(id: id, store: store, navigation: navigation)
            }
            .task(id: filter) {
                if !store.list(filter).loaded { await store.loadMatches(filter) }
            }
            .task { if !store.rejectedLoaded { await store.loadRejected() } }
        }
    }

    private var header: some View {
        VStack(spacing: 10) {
            AppHeader(title: String(localized: "Listings"))
            Picker("Show", selection: $navigation.filter) {
                ForEach(MatchFilter.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, Look.side)
        }
        .padding(.bottom, 2)
    }

    @ViewBuilder private var content: some View {
        let list = store.list(filter)
        let matches = store.matches(filter)
        if matches.isEmpty {
            Group {
                if !list.loaded && list.error == nil {
                    CalmMessage(text: String(localized: "Loading listings…"), loading: true)
                } else if let error = list.error {
                    CalmMessage(text: error, action: (String(localized: "Try again"), { Task { await store.loadMatches(filter) } }))
                } else if store.hunt == nil {
                    CalmMessage(text: String(localized: "No search yet. Set one up and listings appear here the moment they're found."),
                                action: (String(localized: "Set up your search"), { navigation.tab = .search }))
                } else {
                    CalmMessage(text: emptyText)
                }
            }
            .padding(.top, 40)
            .plainRow()
        } else {
            ForEach(matches) { match in
                Button { navigation.listingsPath.append(match.id) } label: {
                    MatchRow(match: match, showsNewDot: store.showsNewDot(match), showsState: filter == .all)
                }
                .buttonStyle(.plain)
                .plainRow(vertical: Look.rowGap / 2)
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    if match.state == .new {
                        Button { Task { await store.setState(.saved, for: match.id) } } label: {
                            Label("Save", systemImage: "bookmark")
                        }
                        .tint(Look.accent.deep)
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button { Task { await store.setState(.dismissed, for: match.id) } } label: {
                        Label("Dismiss", systemImage: "xmark")
                    }
                    .tint(Color(hex: 0x4B4E58))
                }
                .accessibilityAction(named: "Save") { Task { await store.setState(.saved, for: match.id) } }
                .accessibilityAction(named: "Dismiss") { Task { await store.setState(.dismissed, for: match.id) } }
            }
            if list.more {
                Button("Show older") { Task { await store.loadMatches(filter, more: true) } }
                    .buttonStyle(.quiet).disabled(list.isLoading)
                    .frame(maxWidth: .infinity)
                    .plainRow()
            }
        }
        if !store.rejected.isEmpty {
            Button { navigation.sheet = .rejected } label: {
                HStack(spacing: 6) {
                    Text("Filtered out ·")
                    Text(verbatim: "\(store.rejected.count)").font(AppFont.number(13, weight: .regular))
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
                }
                .font(AppFont.text(13, weight: .medium)).foregroundStyle(Ink.muted)
                .padding(.horizontal, 16).frame(minHeight: 46)
                .overlay(RoundedRectangle(cornerRadius: Ink.cardRadius, style: .continuous).strokeBorder(Ink.line))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Filtered out, \(store.rejected.count) listings")
            .plainRow(vertical: 10)
        }
    }

    private var emptyText: String {
        switch filter {
        case .new: String(localized: "Nothing new. New listings appear here the moment they're found.")
        case .saved: String(localized: "Nothing saved. Swipe right on a listing to keep it here.")
        case .applied: String(localized: "No applications yet.")
        case .all: String(localized: "No listings yet. They appear here the moment they're found.")
        }
    }
}

private extension View {
    /// A list row without the list's look: no background, no separator, the app's side margins.
    func plainRow(vertical: CGFloat = 0) -> some View {
        listRowInsets(EdgeInsets(top: vertical, leading: Look.side, bottom: vertical, trailing: Look.side))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}

/// The listings the AI turned down in the last 7 days, each with its reason; tapping one opens it on the portal.
struct RejectedSheet: View {
    let store: ArestemisStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Look.rowGap) {
                    Text("Listings that passed the fields but not the AI's check, from the last 7 days. If good ones end up here, the search may be too strict.")
                        .font(AppFont.text(13)).foregroundStyle(Ink.muted).lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 4).padding(.bottom, 6)
                    if store.rejected.isEmpty {
                        CalmMessage(text: store.rejectedError ?? String(localized: "Nothing was filtered out."), loading: store.isLoadingRejected)
                    }
                    ForEach(store.rejected) { item in
                        Button { item.listing.portalURL.map { openURL($0) } } label: { row(item) }
                            .buttonStyle(.plain)
                            .disabled(item.listing.portalURL == nil)
                    }
                }
                .padding(.horizontal, Look.side).padding(.top, 8).padding(.bottom, 30)
            }
            .provinceWall()
            .navigationTitle("Filtered out")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .task { await store.loadRejected() }
    }

    private func row(_ item: Rejected) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(item.listing.title).font(AppFont.text(15, weight: .semibold)).foregroundStyle(Ink.primary)
                    .lineLimit(2).multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(Ink.muted)
            }
            if !item.listing.factsWithRent.isEmpty {
                Text(item.listing.factsWithRent).font(AppFont.text(13)).foregroundStyle(Ink.secondary).lineLimit(1)
            }
            Text(item.reason).font(AppFont.text(13)).foregroundStyle(Ink.muted).lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            TimelineView(.periodic(from: .now, by: 30)) { context in
                Text([item.listing.sourceName, Format.relative(item.found, now: context.date)].compactMap { $0 }
                        .joined(separator: " · "))
                    .font(AppFont.text(11)).foregroundStyle(Ink.muted.opacity(0.85))
            }
            .padding(.top, 2)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the listing on \(item.listing.sourceName)")
    }
}
