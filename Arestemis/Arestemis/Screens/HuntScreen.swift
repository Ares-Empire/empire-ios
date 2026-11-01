import SwiftUI

/// The main tab: the hunt (status, the search in two lines, start or pause), today's figures, the portals, the
/// latest matches, and the ARESTEMIS band at the end of the scroll (`WordmarkScrollView`).
struct HuntScreen: View {
    @Bindable var store: ArestemisStore
    @Bindable var navigation: AppNavigation
    var scrollsToBottom = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack(path: $navigation.huntPath) {
            ScrollViewReader { reader in
                WordmarkScrollView(word: "ARESTEMIS") {
                    VStack(spacing: 0) {
                        AppHeader(title: "Arestemis") {
                            GlassIconButton(symbol: "gearshape", label: String(localized: "Settings")) { navigation.sheet = .settings }
                        }
                        VStack(alignment: .leading, spacing: 0) {
                            if let error = store.overviewError {
                                Text(error).font(AppFont.text(12)).foregroundStyle(Ink.muted)
                                    .frame(maxWidth: .infinity).multilineTextAlignment(.center).padding(.bottom, 10)
                            }
                            FlatHuntCard(hunt: store.hunt, busy: store.isTogglingHunt,
                                     toggle: { active in Task { await store.setHuntActive(active) } },
                                     setUp: { navigation.tab = .search })
                            if let overview = store.overview, overview.hunt != nil {
                                figures(overview).padding(.top, Look.rowGap)
                            }
                            if let sources = store.overview?.sources, !sources.isEmpty {
                                section(String(localized: "Portals")) { PortalsCard(sources: sources) }
                            }
                            if store.hunt != nil { latest }
                        }
                        .padding(.horizontal, Look.side).padding(.top, 10)
                    }
                }
                .scrollIndicators(.hidden)
                .edgeFade(top: 16)
                .refreshable { await store.reloadOverview() }
                .onAppear {
                    if scrollsToBottom { DispatchQueue.main.async { reader.scrollToWordmark() } }
                }
            }
            .provinceWall()
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Int.self) { id in
                MatchDetailScreen(id: id, store: store, navigation: navigation)
            }
            .task(id: scenePhase) { await keepFresh() }
        }
        .undoBar(visibleUndo, accent: Look.accent)
    }

    /// Only the visible tab owns the shared offer's timer; cancelling a hidden tab must not clear it.
    private var visibleUndo: Binding<UndoOffer?> {
        // Read the offer here so Observation redraws the bar when the store changes it.
        _ = store.undo
        return Binding(get: { navigation.tab == .hunt ? store.undo : nil }, set: { offer in
            if navigation.tab == .hunt { store.undo = offer }
        })
    }

    // MARK: figures

    private func figures(_ overview: Overview) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 0) {
                figure(String(localized: "New"), overview.counts.new, highlight: overview.counts.new > 0) { show(.new) }
                divider
                figure(String(localized: "Today"), overview.counts.today) { show(.all) }
                divider
                figure(String(localized: "Applied"), overview.counts.applied) { show(.applied) }
            }
            .padding(.vertical, 16)
            .glassCard()
            TimelineView(.periodic(from: .now, by: 5)) { context in
                Text(overview.lastScan.flatMap { Format.relative($0, now: context.date) }.map { String(localized: "Last scan \($0)") }
                     ?? String(localized: "No scan yet"))
                    .font(AppFont.number(11, weight: .regular)).foregroundStyle(Ink.muted)
                    .contentTransition(.numericText())
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func figure(_ label: String, _ value: Int, highlight: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Text(verbatim: "\(value)").font(AppFont.number(22, weight: .semibold)).foregroundStyle(Ink.primary)
                    .contentTransition(.numericText(value: Double(value)))
                    .animation(.snappy, value: value)
                HStack(spacing: 5) {
                    if highlight { Circle().fill(Look.accent.color).frame(width: 5, height: 5) }
                    CapsLabel(text: label)
                }
            }
            .frame(maxWidth: .infinity).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "\(label): \(value)"))
        .accessibilityHint("Shows these listings")
    }

    private var divider: some View {
        Rectangle().fill(Ink.line).frame(width: 1, height: 34)
    }

    private func show(_ filter: MatchFilter) {
        navigation.filter = filter
        navigation.tab = .listings
    }

    // MARK: latest

    @ViewBuilder private var latest: some View {
        section(String(localized: "Latest")) {
            let matches = store.latest
            if matches.isEmpty {
                Text("No listings yet. They appear here the moment they're found.")
                    .font(AppFont.text(13)).foregroundStyle(Ink.muted).lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: Look.rowGap) {
                    ForEach(matches) { match in
                        Button { navigation.huntPath.append(match.id) } label: {
                            MatchRow(match: match, showsNewDot: store.showsNewDot(match), showsState: true)
                        }
                        .buttonStyle(.plain)
                        .contextMenu { MatchRowActions(match: match, store: store) }
                    }
                }
                Button { show(.all) } label: {
                    HStack(spacing: 5) {
                        Text("All listings")
                        Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                    }
                    .font(AppFont.text(13, weight: .medium)).foregroundStyle(Ink.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing).frame(minHeight: 36)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Look.headingGap) {
            SectionHeading(text: title).padding(.leading, 4)
            content()
        }
        .padding(.top, Look.sectionGap)
    }

    /// While the tab is on screen and the app is active, the figures and "Last scan" follow the server every minute.
    private func keepFresh() async {
        guard scenePhase == .active else { return }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(60))
            guard !Task.isCancelled else { return }
            await store.reloadOverview(quiet: true)
        }
    }
}

/// The hunt's card: status, what and where, and the one button (Start hunting / Pause). Without a hunt: the way to
/// set one up.
private struct FlatHuntCard: View {
    let hunt: Hunt?
    let busy: Bool
    let toggle: (Bool) -> Void
    let setUp: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let hunt, let search = hunt.search.flat {
                HStack(spacing: 9) {
                    StatusDot(active: hunt.active)
                    StatusLabel(text: hunt.active ? String(localized: "Hunting") : String(localized: "Paused"), tone: hunt.active ? .accent : .inactive,
                                accent: Look.accent)
                }
                .accessibilityElement(children: .combine)
                let summary = SearchSummary(search)
                Text(summary.wrappingKinds).font(AppFont.text(20, weight: .semibold)).foregroundStyle(Ink.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 14)
                if !summary.parts.isEmpty {
                    Text(summary.wrappingDetails).font(AppFont.text(14)).foregroundStyle(Ink.secondary).lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 6)
                }
                Group {
                    if hunt.active {
                        Button("Pause") { toggle(false) }.buttonStyle(.glassy)
                    } else {
                        Button("Start hunting") { toggle(true) }.buttonStyle(.accent)
                    }
                }
                .disabled(busy)
                .padding(.top, 20)
            } else {
                Text("No search yet").font(AppFont.text(20, weight: .semibold)).foregroundStyle(Ink.primary)
                Text("Set what you are looking for. Arestemis then watches the portals and tells you the moment a listing fits.")
                    .font(AppFont.text(14)).foregroundStyle(Ink.secondary).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
                Button("Set up your search", action: setUp).buttonStyle(.accent).padding(.top, 20)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(accent: Look.accent, raised: true)
        .animation(.easeOut(duration: 0.2), value: hunt?.active)
    }
}

/// One row per portal: a status dot, the name, the server's note.
private struct PortalsCard: View {
    let sources: [SourceStatus]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(sources.enumerated()), id: \.element.id) { index, source in
                if index > 0 { Hairline().padding(.leading, 34) }
                HStack(spacing: 12) {
                    Circle().fill(color(source.state)).frame(width: 6, height: 6)
                    Text(source.name).font(AppFont.text(15, weight: .semibold)).foregroundStyle(Ink.primary).lineLimit(1)
                    Spacer(minLength: 10)
                    if let note = source.note {
                        Text(note).font(AppFont.text(12)).foregroundStyle(Ink.muted).lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                }
                .padding(.horizontal, 16).frame(minHeight: 48)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel([source.name, word(source.state), source.note].compactMap { $0 }.joined(separator: ", "))
            }
        }
        .glassCard()
    }

    private func color(_ state: SourceStatus.State) -> Color {
        switch state {
        case .ok: StatusTone.active.color(Look.accent)
        case .blocked, .error: StatusTone.issue.color(Look.accent)
        case .idle: StatusTone.inactive.color(Look.accent)
        }
    }

    private func word(_ state: SourceStatus.State) -> String {
        switch state {
        case .ok: String(localized: "working")
        case .blocked: String(localized: "blocked")
        case .error: String(localized: "not answering")
        case .idle: String(localized: "idle")
        }
    }
}
