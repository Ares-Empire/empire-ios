import SwiftUI

/// The start tab: what Patrik thinks, as `vault.positions` groups them ("Across topics" first, then each topic). Each
/// card opens the position's page; "Add a position" opens the add sheet (across topics, or a topic picked there).
struct PositionsScreen: View {
    @Environment(VaultStore.self) private var store
    @Environment(AppNavigation.self) private var navigation

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ScreenHeader(title: String(localized: "Positions"))
                StatusLine()
                let groups = store.vault?.positions ?? []
                VStack(alignment: .leading, spacing: Look.sectionGap) {
                    ForEach(groups, id: \.note) { group in
                        VStack(alignment: .leading, spacing: Look.headingGap) {
                            Button { navigation.open(NoteLink(note: group.note)) } label: {
                                SectionHeading(text: group.title)
                            }
                            .buttonStyle(.plain)
                            if group.positions.isEmpty {
                                Text("No positions yet.").font(AppFont.text(13)).foregroundStyle(Ink.muted)
                            }
                            ForEach(group.positions) { position in PositionCard(position: position) }
                        }
                    }
                    if groups.isEmpty {
                        CalmMessage(text: String(localized: "No positions in the vault yet."))
                    }
                    if let target = store.index.positionTargets.first {
                        Button("Add a position") { navigation.sheet = .position(.add(note: target.id)) }
                            .buttonStyle(.bordered).tint(Look.accent.color)
                            .frame(maxWidth: .infinity)
                            .disabled(store.isSending)
                    }
                }
                .padding(.horizontal, Look.side).padding(.top, 10).padding(.bottom, 40)
            }
        }
        .refreshable { await store.update() }
        .provinceWall()
        .toolbar(.hidden, for: .navigationBar)
    }
}

/// A position as a card: its sentence, the draft mark, how many notes back it. Tapping opens its page.
struct PositionCard: View {
    let position: Position
    @Environment(AppNavigation.self) private var navigation

    var body: some View {
        Button { navigation.showPosition(position.id) } label: {
            VStack(alignment: .leading, spacing: 8) {
                InlineText(position.text, size: 15, weight: .medium)
                HStack(spacing: 10) {
                    if position.draft { CapsLabel(text: String(localized: "Draft"), color: Look.accent.color) }
                    Text("^[\(position.evidence.count) note](inflect: true) as evidence")
                        .font(AppFont.text(12)).foregroundStyle(Ink.muted)
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(Ink.muted)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}

/// A position's page: the sentence, where it is written, the actions (Confirm for a draft, Reword, Change my view,
/// Drop, Discuss), how the view changed, and the evidence notes with their summaries.
struct PositionScreen: View {
    let id: String
    @Environment(VaultStore.self) private var store
    @Environment(AppNavigation.self) private var navigation

    var body: some View {
        Group {
            if let position = store.index.position(id) {
                page(position)
            } else {
                CalmMessage(text: String(localized: "This position is no longer in the vault."))
                    .frame(maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity)
        .provinceWall()
        .navigationBarTitleDisplayMode(.inline)
    }

    private func page(_ position: Position) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if position.draft {
                    CapsLabel(text: String(localized: "Draft, worded by Claude"), color: Look.accent.color).padding(.bottom, 8)
                }
                InlineText(position.text, size: 22, weight: .semibold)
                Button { navigation.open(NoteLink(note: position.note)) } label: {
                    Text("Position \(position.number) on \(store.index.title(position.note))")
                        .font(AppFont.text(13)).foregroundStyle(Ink.secondary)
                }
                .buttonStyle(.plain).padding(.top, 8)

                actions(position).padding(.top, 20)

                if !position.history.isEmpty {
                    SectionHeading(text: String(localized: "How my view changed")).padding(.top, Look.sectionGap)
                    VStack(alignment: .leading, spacing: Look.rowGap) {
                        ForEach(Array(position.history.enumerated()), id: \.offset) { _, change in
                            HistoryRow(change: change)
                        }
                    }
                    .padding(.top, Look.headingGap)
                }

                SectionHeading(text: String(localized: "Evidence")).padding(.top, Look.sectionGap)
                let evidence = store.index.evidence(of: position)
                VStack(spacing: Look.rowGap) {
                    ForEach(evidence) { note in NoteRow(note: note) }
                    if evidence.isEmpty {
                        Text("No notes named as evidence.").font(AppFont.text(13)).foregroundStyle(Ink.muted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.top, Look.headingGap)
            }
            .padding(.horizontal, Look.side).padding(.top, 10).padding(.bottom, 40)
        }
    }

    private func actions(_ position: Position) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if position.draft {
                Button("Confirm") { Task { await store.confirmPosition(position.id) } }
                    .buttonStyle(.borderedProminent).tint(Look.accent.color)
            }
            HStack(spacing: 10) {
                Button("Reword") { navigation.sheet = .position(.reword(position.id)) }
                Button("Change my view") { navigation.sheet = .position(.change(position.id)) }
                Button("Drop", role: .destructive) { navigation.sheet = .position(.drop(position.id)) }
            }
            .buttonStyle(.bordered).tint(Ink.secondary)
            Button("Discuss with Claude") { navigation.sheet = .discuss(.position(position.id)) }
                .buttonStyle(.bordered).tint(Ink.secondary)
        }
        .disabled(store.isSending)
    }
}

/// One entry of "How my view changed": the day, what I thought, what changed it.
struct HistoryRow: View {
    let change: PositionChange

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: Format.day(change.date)).font(AppFont.number(12)).foregroundStyle(Ink.muted)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("I thought:").font(AppFont.text(14, weight: .semibold)).foregroundStyle(Ink.secondary)
                InlineText(change.text, size: 14, color: Ink.secondary)
            }
            if let why = change.why {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("What changed it:").font(AppFont.text(14, weight: .semibold)).foregroundStyle(Ink.secondary)
                    InlineText(why, size: 14, color: Ink.secondary)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .accessibilityElement(children: .combine)
    }
}
