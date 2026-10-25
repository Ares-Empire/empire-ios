import SwiftUI

/// A note's body for looking things up (Patrik, 2026-10-24: "usually I just want to quickly look up a fact"): a long
/// note shows its sections closed, each with its heading and first sentence; tapping one opens it. "My position" stays
/// open (the positions are one line each). A link to a passage opens its section and marks the passage. Pressing and
/// holding a paragraph or list item offers editing just that passage, a note about the note, and copying.
struct NoteBody: View {
    let note: Note
    /// The passage to show and mark (search hit, figure, source), and the heading to open, from the link.
    let focus: NoteLink?
    @Binding var expandsAll: Bool
    @State private var open: Set<Int> = []
    @State private var marked: Int?

    /// Above this many words the sections start closed.
    static let compactFrom = 250

    var body: some View {
        let sections = NoteSections(note: note)
        VStack(alignment: .leading, spacing: 14) {
            BlocksView(blocks: sections.preamble.map { note.blocks[$0] }, lines: sections.preamble.map { note.blockLines[$0] },
                       indices: sections.preamble, owner: note, marked: marked)
            ForEach(sections.sections) { section in
                let isOpen = expandsAll || !sections.compact || section.alwaysOpen || open.contains(section.heading)
                SectionHeader(note: note, section: section, isOpen: isOpen, collapsible: sections.compact && !section.alwaysOpen) {
                    withAnimation(.easeOut(duration: 0.2)) {
                        if open.contains(section.heading) { open.remove(section.heading) } else { open.insert(section.heading) }
                    }
                }
                if isOpen {
                    BlocksView(blocks: section.body.map { note.blocks[$0] }, lines: section.body.map { note.blockLines[$0] },
                               indices: section.body, owner: note, marked: marked)
                }
            }
        }
        .onAppear { reveal(focus, in: sections) }
        .onChange(of: focus) { _, link in reveal(link, in: NoteSections(note: note)) }
    }

    /// Opens the section of the linked passage or heading and marks the passage for a moment.
    private func reveal(_ link: NoteLink?, in sections: NoteSections) {
        guard let link else { return }
        if let block = link.block, let section = sections.section(containing: block) {
            open.insert(section.heading)
        }
        if let anchor = link.anchor, let section = sections.sections.first(where: { $0.anchor == anchor }) {
            open.insert(section.heading)
        }
        if let block = link.block {
            marked = block
            Task {
                try? await Task.sleep(for: .seconds(2.5))
                withAnimation(.easeOut(duration: 0.6)) { if marked == block { marked = nil } }
            }
        }
    }
}

/// A note's blocks cut at its `##` headings: what comes before the first one, then each section.
struct NoteSections {
    struct Section: Identifiable {
        let heading: Int                // index of the `##` heading block
        let anchor: String
        let body: [Int]                 // indices of the blocks under it
        let alwaysOpen: Bool            // "My position" (short cards) and "How my view changed"
        var id: Int { heading }
    }

    let preamble: [Int]
    let sections: [Section]
    /// Long enough to start with the sections closed.
    let compact: Bool

    init(note: Note) {
        var preamble: [Int] = []
        var sections: [Section] = []
        var current: (heading: Int, anchor: String, body: [Int], open: Bool)?
        for (index, block) in note.blocks.enumerated() {
            if case let .heading(level, _, anchor) = block, level == 2 {
                if let current { sections.append(Section(heading: current.heading, anchor: current.anchor, body: current.body,
                                                         alwaysOpen: current.open)) }
                let holdsPositions = note.blocks.dropFirst(index + 1).prefix { block in
                    if case let .heading(next, _, _) = block { return next > 2 } else { return true }
                }.contains { if case .positions = $0 { true } else { false } }
                current = (index, anchor, [], holdsPositions)
            } else if current != nil {
                current?.body.append(index)
            } else {
                preamble.append(index)
            }
        }
        if let current { sections.append(Section(heading: current.heading, anchor: current.anchor, body: current.body,
                                                 alwaysOpen: current.open)) }
        self.preamble = preamble
        self.sections = sections
        let words = VaultSearch.text(of: note.blocks).split(whereSeparator: \.isWhitespace).count
        compact = sections.count > 1 && words > NoteBody.compactFrom
    }

    func section(containing block: Int) -> Section? {
        sections.first { $0.heading == block || $0.body.contains(block) }
    }
}

/// A `##` heading; closed, with the section's first sentence under it and a chevron. Tapping opens or closes it.
private struct SectionHeader: View {
    let note: Note
    let section: NoteSections.Section
    let isOpen: Bool
    let collapsible: Bool
    let toggle: () -> Void

    var body: some View {
        if case let .heading(_, text, anchor) = note.blocks[section.heading] {
            Button(action: toggle) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(verbatim: InlineMarkdown.plain(text)).font(AppFont.text(19, weight: .bold))
                            .foregroundStyle(Ink.primary).multilineTextAlignment(.leading)
                        Spacer(minLength: 6)
                        if collapsible {
                            Image(systemName: "chevron.down").font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(Ink.muted).rotationEffect(.degrees(isOpen ? 0 : -90))
                        }
                    }
                    if collapsible && !isOpen, let first = firstSentence {
                        Text(verbatim: first).font(AppFont.text(14)).foregroundStyle(Ink.secondary)
                            .lineLimit(2).multilineTextAlignment(.leading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .allowsHitTesting(collapsible)
            .padding(.top, 8)
            .id(BlocksView.anchorID(anchor))
            .accessibilityAddTraits(.isHeader)
            .accessibilityHint(collapsible ? Text(isOpen ? "Closes the section" : "Opens the section") : Text(verbatim: ""))
        }
    }

    private var firstSentence: String? {
        for index in section.body {
            switch note.blocks[index] {
            case let .paragraph(text), let .quote(text):
                return Lookup.headline(text)
            case let .list(_, items):
                if let item = items.first { return Lookup.headline(item.text) }
            case let .sectionLink(id):
                return "→ " + id
            default:
                continue
            }
        }
        return nil
    }
}

// MARK: - figures, sources, terms

/// What a lookup button lists.
enum LookupKind: String, CaseIterable, Identifiable {
    case figures, sources, terms
    var id: String { rawValue }

    var title: String {
        switch self {
        case .figures: String(localized: "Figures & dates")
        case .sources: String(localized: "Sources")
        case .terms: String(localized: "Terms")
        }
    }
}

/// The lookup buttons of a note (only the ones with something to show) and, under them, the list of the chosen one.
/// A topic overview looks through its whole topic (the overview and its section pages).
struct LookupPanel: View {
    let note: Note
    @State private var shown: LookupKind?
    @Environment(VaultStore.self) private var store
    @Environment(AppNavigation.self) private var navigation

    var body: some View {
        let notes = scope
        let figures = notes.flatMap(Lookup.figures)
        let sources = notes.flatMap(Lookup.sources)
        let terms = store.vault?.glossary.filter { term in term.note.map { id in notes.contains { $0.id == id } } ?? false } ?? []
        let available = LookupKind.allCases.filter { kind in
            switch kind {
            case .figures: !figures.isEmpty
            case .sources: !sources.isEmpty
            case .terms: !terms.isEmpty
            }
        }
        if !available.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    ForEach(available) { kind in
                        let selected = shown == kind
                        Button { withAnimation(.easeOut(duration: 0.18)) { shown = selected ? nil : kind } } label: {
                            Text(kind.title)
                                .font(AppFont.text(13, weight: selected ? .semibold : .medium))
                                .foregroundStyle(selected ? AppAccent.onColor : Ink.secondary)
                                .padding(.horizontal, 12).frame(minHeight: 32)
                                .background {
                                    if selected { Capsule().fill(Look.accent.color) }
                                    else { Capsule().fill(Ink.field).overlay(Capsule().strokeBorder(Ink.edge)) }
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
                switch shown {
                case .figures: passages(figures)
                case .sources: passages(sources)
                case .terms: termList(terms)
                case nil: EmptyView()
                }
            }
        }
    }

    /// The overview and its section pages for a topic overview; the note alone otherwise.
    private var scope: [Note] {
        guard note.isTopicOverview else { return [note] }
        let pages = (store.vault?.notes ?? []).filter { $0.topic == note.id && $0.id != note.id }
        return [note] + pages
    }

    private func passages(_ found: [Lookup.Passage]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(found.enumerated()), id: \.offset) { offset, passage in
                if offset > 0 { Rectangle().fill(Ink.line).frame(height: 1) }
                Button { navigation.open(NoteLink(note: passage.note, block: passage.block)) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(InlineMarkdown.attributed(passage.markdown)).font(AppFont.text(14)).foregroundStyle(Ink.primary)
                            .multilineTextAlignment(.leading).tint(Look.accent.color)
                        Text(verbatim: place(passage)).font(AppFont.text(11)).foregroundStyle(Ink.muted).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .glassCard()
    }

    private func termList(_ terms: [Term]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(terms.enumerated()), id: \.offset) { offset, term in
                if offset > 0 { Rectangle().fill(Ink.line).frame(height: 1) }
                HStack(alignment: .firstTextBaseline) {
                    Text(verbatim: term.english).font(AppFont.text(14)).foregroundStyle(Ink.secondary)
                    Spacer(minLength: 12)
                    Text(verbatim: term.german).font(AppFont.text(14, weight: .semibold)).foregroundStyle(Ink.primary)
                        .multilineTextAlignment(.trailing)
                }
                .padding(.vertical, 10)
            }
        }
        .padding(.horizontal, 14)
        .glassCard()
    }

    /// "Section page · Heading": where a passage stands (the note only when it is another page of the topic).
    private func place(_ passage: Lookup.Passage) -> String {
        var parts: [String] = []
        if passage.note != note.id { parts.append(store.index.title(passage.note)) }
        if let heading = passage.heading { parts.append(heading) }
        return parts.joined(separator: " · ")
    }
}

/// A note's summary box: four lines, the rest on a tap (a lookup rarely needs all of it).
struct SummaryBox: View {
    let summary: String
    @State private var expanded = false

    var body: some View {
        Button { withAnimation(.easeOut(duration: 0.2)) { expanded.toggle() } } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(InlineMarkdown.attributed(summary)).font(AppFont.text(15)).foregroundStyle(Ink.primary)
                    .tint(Look.accent.color).lineSpacing(3)
                    .lineLimit(expanded ? nil : 4)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if !expanded && InlineMarkdown.plain(summary).count > 220 {
                    Text("More").font(AppFont.text(12, weight: .semibold)).foregroundStyle(Look.accent.color)
                }
            }
            .padding(16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
