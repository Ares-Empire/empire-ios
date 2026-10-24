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
                DiscussionsRow().padding(.horizontal, Look.side).padding(.top, 4)
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
                        Button { navigation.sheet = .position(.add(note: target.id)) } label: {
                            Label("Add a position", systemImage: "plus")
                        }
                        .buttonStyle(.pill)
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
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(verbatim: "\(position.number)").font(AppFont.number(13, weight: .medium))
                    .foregroundStyle(position.draft ? Look.accent.color : Ink.muted)
                    .frame(minWidth: 14, alignment: .leading)
                    .accessibilityHidden(true)
                Text(verbatim: Lookup.headline(position.text))
                    .font(AppFont.text(16, weight: .medium)).foregroundStyle(Ink.primary)
                    .lineLimit(3).multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if position.draft {
                    CapsLabel(text: String(localized: "Draft"), color: Look.accent.color)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
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
                InlineText(position.text, size: 23, weight: .semibold).lineSpacing(2)
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

    /// Patrik's positions are considered, not changed on the go (2026-10-24): the page offers discussing (now or
    /// later), fixing the wording, and a note for later; a draft can be confirmed.
    private func actions(_ position: Position) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if position.draft {
                Button { Task { await store.confirmPosition(position.id) } } label: {
                    Label("Confirm as mine", systemImage: "checkmark")
                }
                .buttonStyle(.primaryPill)
            }
            // One row when it fits; else Discuss on its own and the two quieter ones under it (German runs long).
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { discuss(position); edits(position) }
                VStack(alignment: .leading, spacing: 8) {
                    discuss(position)
                    HStack(spacing: 8) { edits(position) }
                }
            }
        }
        .disabled(store.isSending)
    }

    private func discuss(_ position: Position) -> some View {
        Button { navigation.sheet = .discuss(.position(position.id)) } label: {
            Label("Discuss", systemImage: "bubble.left.and.text.bubble.right")
        }
        .buttonStyle(position.draft ? .pill : .primaryPill)
    }

    @ViewBuilder private func edits(_ position: Position) -> some View {
        Button { navigation.sheet = .position(.reword(position.id)) } label: { Label("Edit", systemImage: "pencil") }
            .buttonStyle(.pill)
        Button { navigation.sheet = .quickNote(about: .position(position.id)) } label: {
            Label("Note", systemImage: "note.text")
        }
        .buttonStyle(.pill)
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

/// "3 to discuss": the "discuss later" marks not yet discussed; opens the list. Hidden when there are none.
struct DiscussionsRow: View {
    @Environment(VaultStore.self) private var store
    @Environment(AppNavigation.self) private var navigation

    var body: some View {
        let count = store.index.openDiscussions.count
        if count > 0 {
            Button { navigation.sheet = .discussions } label: {
                HStack(spacing: 10) {
                    Image(systemName: "bookmark.fill").font(.system(size: 12)).foregroundStyle(Look.accent.color)
                    Text("\(count) to discuss").font(AppFont.text(14, weight: .medium)).foregroundStyle(Ink.primary)
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(Ink.muted)
                }
                .padding(.horizontal, 16).frame(minHeight: 46)
                .glassCard(accent: Look.accent)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}
