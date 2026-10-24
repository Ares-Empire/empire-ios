import SwiftUI

/// A note: title, type and confidence, the summary box, the body's blocks, the notes that link here. Opened at a
/// heading when the link names one. Under the title: Brief (topic overviews) and Discuss; the menu at the top right:
/// Edit (the free editor) and Confidence.
struct NoteScreen: View {
    let link: NoteLink
    @State private var focus: NoteLink?
    @State private var expandsAll = false
    @Environment(VaultStore.self) private var store
    @Environment(AppNavigation.self) private var navigation

    var body: some View {
        Group {
            if let note = store.index.note(link.note) {
                page(note)
            } else {
                CalmMessage(text: String(localized: "This note is no longer in the vault.")).frame(maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity)
        .provinceWall()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            if let note = store.index.note(link.note) { NoteMenu(note: note, expandsAll: $expandsAll) }
        }
    }

    private func page(_ note: Note) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    header(note)
                    actions(note).padding(.top, 16)
                    if let summary = note.summary {
                        InlineText(summary, size: 15)
                            .padding(16)
                            .glassCard(accent: Look.accent, raised: true)
                            .padding(.top, 16)
                            .accessibilityLabel(Text("Summary: \(InlineMarkdown.plain(summary))"))
                    }
                    LookupPanel(note: note).padding(.top, 16)
                    NoteBody(note: note, focus: focus, expandsAll: $expandsAll).padding(.top, 18)
                    backlinks(note)
                }
                .padding(.horizontal, Look.side).padding(.top, 8).padding(.bottom, 40)
            }
            .onAppear {
                focus = link
                scroll(proxy, to: link, animated: false)
            }
            .onChange(of: navigation.scrollRequest) { _, request in
                guard let request, request.note == note.id else { return }
                focus = request
                scroll(proxy, to: request, animated: true)
                navigation.scrolled()
            }
        }
    }

    private func header(_ note: Note) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(note.title).font(AppFont.text(26, weight: .bold)).foregroundStyle(Ink.primary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: 10) {
                CapsLabel(text: Format.type(note.type))
                if let confidence = note.confidence {
                    CapsLabel(text: Format.confidence(confidence),
                              color: confidence == .shaky ? StatusTone.issue.color(Look.accent) : Ink.secondary)
                }
                if let updated = note.updated {
                    Text("Updated \(Format.day(updated))").font(AppFont.text(11)).foregroundStyle(Ink.muted)
                }
            }
        }
    }

    private func actions(_ note: Note) -> some View {
        HStack(spacing: 10) {
            if note.brief != nil {
                Button { navigation.sheet = .brief(note.id) } label: { Label("Brief", systemImage: "list.bullet.rectangle") }
                    .buttonStyle(.primaryPill)
            }
            Button { navigation.sheet = .discuss(.note(note.id)) } label: {
                Label("Discuss", systemImage: "bubble.left.and.text.bubble.right")
            }
            .buttonStyle(note.brief == nil ? .primaryPill : .pill)
        }
    }

    @ViewBuilder private func backlinks(_ note: Note) -> some View {
        let notes = store.index.backlinks(of: note.id)
        if !notes.isEmpty {
            SectionHeading(text: String(localized: "Linked from")).padding(.top, Look.sectionGap)
            VStack(spacing: Look.rowGap) {
                ForEach(notes) { NoteRow(note: $0) }
            }
            .padding(.top, Look.headingGap)
        }
    }

    private func scroll(_ proxy: ScrollViewProxy, to link: NoteLink, animated: Bool) {
        let id: String
        if let block = link.block { id = BlocksView.blockID(block) }
        else if let anchor = link.anchor { id = BlocksView.anchorID(anchor) }
        else { return }
        // After the first layout, so the heading exists.
        DispatchQueue.main.async {
            if animated {
                withAnimation { proxy.scrollTo(id, anchor: .top) }
            } else {
                proxy.scrollTo(id, anchor: .top)
            }
        }
    }
}

/// The note page's quieter actions, in one menu at the top right: the free editor and the confidence.
struct NoteMenu: ToolbarContent {
    let note: Note
    @Binding var expandsAll: Bool
    @Environment(VaultStore.self) private var store
    @Environment(AppNavigation.self) private var navigation

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                if NoteSections(note: note).compact {
                    Button { withAnimation { expandsAll.toggle() } } label: {
                        expandsAll ? Label("Close the sections", systemImage: "rectangle.compress.vertical")
                                   : Label("Open all sections", systemImage: "rectangle.expand.vertical")
                    }
                }
                Button { navigation.sheet = .quickNote(about: .note(note.id)) } label: { Label("Note", systemImage: "note.text") }
                Button { navigation.sheet = .editor(note.id) } label: { Label("Edit text", systemImage: "square.and.pencil") }
                if note.confidence != nil || [.topic, .mechanism, .event, .question].contains(note.type) {
                    Picker(selection: confidence) {
                        ForEach(Confidence.allCases, id: \.self) { value in Text(Format.confidence(value)).tag(Optional(value)) }
                    } label: {
                        Label("Confidence", systemImage: "gauge.with.dots.needle.33percent")
                    }
                    .pickerStyle(.menu)
                }
            } label: {
                Image(systemName: "ellipsis")
            }
            .accessibilityLabel(Text("More"))
            .disabled(store.isSending)
        }
    }

    /// Picking a confidence sets it on the server.
    private var confidence: Binding<Confidence?> {
        Binding(get: { note.confidence }, set: { value in
            guard let value, value != note.confidence else { return }
            Task { await store.setConfidence(value, of: note.id) }
        })
    }
}
