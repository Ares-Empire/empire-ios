import SwiftUI

/// A note's body (the contract's `Block`s): headings (scroll targets for anchors), paragraphs, lists, the positions as
/// cards, callouts (Claude's with Adopt and Dismiss), quotes, embeds shown inline, tables, section links, rules.
/// `owner` is the note the blocks belong to (an embed's blocks belong to the embedded note).
struct BlocksView: View {
    let blocks: [Block]
    let owner: Note
    /// 1 inside an embed: an embed in there shows as a link only, so notes embedding each other never loop.
    var embedDepth = 0

    static func anchorID(_ anchor: String) -> String { "anchor:" + anchor }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                BlockView(block: block, owner: owner, embedDepth: embedDepth)
            }
        }
    }
}

struct BlockView: View {
    let block: Block
    let owner: Note
    let embedDepth: Int
    @Environment(VaultStore.self) private var store
    @Environment(AppNavigation.self) private var navigation

    var body: some View {
        switch block {
        case let .heading(level, text, anchor):
            InlineText(text, size: level == 2 ? 20 : level == 3 ? 17 : 15, weight: .bold)
                .padding(.top, level == 2 ? 10 : 4)
                .id(BlocksView.anchorID(anchor))
                .accessibilityAddTraits(.isHeader)
        case let .paragraph(text):
            InlineText(text)
        case let .list(ordered, items):
            ListBlock(ordered: ordered, items: items)
        case let .positions(ids):
            VStack(spacing: Look.rowGap) {
                ForEach(store.index.positions(ids)) { PositionCard(position: $0) }
            }
            if owner.isTopicOverview || owner.type == .positions, embedDepth == 0 {
                Button("Add a position") { navigation.sheet = .position(.add(note: owner.id)) }
                    .buttonStyle(.bordered).tint(Ink.secondary)
                    .disabled(store.isSending)
            }
        case let .callout(style, title, text, index):
            CalloutView(style: style, title: title, text: text, index: index, owner: owner)
        case let .quote(text):
            HStack(spacing: 12) {
                Rectangle().fill(Ink.line).frame(width: 3)
                InlineText(text, color: Ink.secondary)
            }
        case let .embed(note, anchor):
            EmbedView(note: note, anchor: anchor, depth: embedDepth)
        case let .table(header, rows):
            TableBlock(header: header, rows: rows)
        case let .sectionLink(note):
            SectionLinkView(note: note)
        case .rule:
            Rectangle().fill(Ink.line).frame(height: 1).padding(.vertical, 6)
        case .unknown:
            EmptyView()
        }
    }
}

struct ListBlock: View {
    let ordered: Bool
    let items: [ListItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { offset, item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(verbatim: ordered ? "\(number(at: offset))." : "•").font(AppFont.number(14))
                        .foregroundStyle(Ink.muted)
                    InlineText(item.text)
                }
                .padding(.leading, CGFloat(item.depth) * 18)
            }
        }
    }

    /// The number of an ordered item among the items of its own depth since the last shallower one.
    private func number(at offset: Int) -> Int {
        let depth = items[offset].depth
        var count = 0
        for index in stride(from: offset, through: 0, by: -1) {
            if items[index].depth < depth { break }
            if items[index].depth == depth { count += 1 }
        }
        return count
    }
}

/// A callout: Claude's note (with Adopt and Dismiss), a shaky claim, or another callout.
struct CalloutView: View {
    let style: CalloutStyle
    let title: String?
    let text: String
    let index: Int
    let owner: Note
    @Environment(VaultStore.self) private var store
    @State private var confirmsDismiss = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CapsLabel(text: label, color: style == .shaky ? StatusTone.issue.color(Look.accent) : Ink.secondary)
            if let title { InlineText(title, weight: .semibold) }
            InlineText(text, size: 14, color: Ink.secondary)
            if style == .claude {
                HStack(spacing: 10) {
                    Button("Adopt") { Task { await store.adoptCallout(index, of: owner.id) } }
                    Button("Dismiss", role: .destructive) { confirmsDismiss = true }
                }
                .buttonStyle(.bordered).tint(Ink.secondary)
                .disabled(store.isSending)
                .padding(.top, 4)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
        .confirmationDialog("Dismiss Claude's note?", isPresented: $confirmsDismiss, titleVisibility: .visible) {
            Button("Dismiss", role: .destructive) { Task { await store.dismissCallout(index, of: owner.id) } }
        } message: {
            Text("It is removed from the note.")
        }
    }

    private var label: String {
        switch style {
        case .claude: String(localized: "Claude")
        case .shaky: String(localized: "Shaky")
        default: String(localized: "Note")
        }
    }
}

/// `![[Note#Heading]]`: that part of the other note, shown here; tapping its title opens it there.
struct EmbedView: View {
    let note: String
    let anchor: String?
    let depth: Int
    @Environment(VaultStore.self) private var store
    @Environment(AppNavigation.self) private var navigation

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { navigation.open(NoteLink(note: note, anchor: anchor)) } label: {
                Label(anchor.map { "\(store.index.title(note)) › \($0)" } ?? store.index.title(note),
                      systemImage: "arrow.up.right.square")
                    .font(AppFont.text(13, weight: .medium)).foregroundStyle(Look.accent.color)
            }
            .buttonStyle(.plain)
            if depth == 0, let embedded = store.index.note(note) {
                let blocks = store.index.section(of: note, anchor: anchor)
                    // The embedded heading is shown as the link above.
                    .filter { if case let .heading(_, _, found) = $0 { found != anchor } else { true } }
                BlocksView(blocks: blocks, owner: embedded, embedDepth: depth + 1)
            }
        }
        .padding(.leading, 12)
        .overlay(alignment: .leading) { Rectangle().fill(Look.accent.color.opacity(0.4)).frame(width: 2) }
    }
}

struct TableBlock: View {
    let header: [String]
    let rows: [[String]]

    var body: some View {
        ScrollView(.horizontal) {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                GridRow {
                    ForEach(Array(header.enumerated()), id: \.offset) { _, cell in
                        InlineText(cell, size: 13, weight: .semibold, color: Ink.secondary).fixedSize()
                    }
                }
                Divider()
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                            InlineText(cell, size: 14).fixedSize()
                        }
                    }
                }
            }
            .padding(14)
        }
        .scrollIndicators(.hidden)
        .glassCard()
    }
}

/// "→ Section page": the page and its summary.
struct SectionLinkView: View {
    let note: String
    @Environment(VaultStore.self) private var store
    @Environment(AppNavigation.self) private var navigation

    var body: some View {
        Button { navigation.open(NoteLink(note: note)) } label: {
            VStack(alignment: .leading, spacing: 4) {
                Label(store.index.title(note), systemImage: "arrow.right")
                    .font(AppFont.text(14, weight: .semibold)).foregroundStyle(Look.accent.color)
                if let summary = store.index.note(note)?.summary {
                    Text(InlineMarkdown.plain(summary)).font(AppFont.text(13)).foregroundStyle(Ink.secondary)
                        .multilineTextAlignment(.leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
