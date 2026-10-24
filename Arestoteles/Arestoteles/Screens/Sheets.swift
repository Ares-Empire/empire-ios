import SwiftUI
import UIKit

/// A sheet's frame: its own navigation bar with a title and Close, on the wall.
struct SheetFrame<Content: View, Actions: ToolbarContent>: View {
    let title: String
    let content: Content
    let actions: Actions
    @Environment(\.dismiss) private var dismiss

    init(title: String, @ViewBuilder content: () -> Content, @ToolbarContentBuilder actions: () -> Actions) {
        self.title = title
        self.content = content()
        self.actions = actions()
    }

    var body: some View {
        NavigationStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .provinceWall()
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                    actions
                }
        }
    }
}

/// A sheet without actions of its own.
struct NoSheetActions: ToolbarContent {
    var body: some ToolbarContent { ToolbarItemGroup { EmptyView() } }
}

extension SheetFrame where Actions == NoSheetActions {
    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
        actions = NoSheetActions()
    }
}

// MARK: - brief

/// A topic before a discussion (the server's `brief`): my positions, the sections in short, Claude's counterpoints,
/// the shaky claims, the terms, the open questions.
struct BriefSheet: View {
    let note: String
    @Environment(VaultStore.self) private var store
    @Environment(AppNavigation.self) private var navigation

    var body: some View {
        SheetFrame(title: String(localized: "Brief")) {
            if let topic = store.index.note(note), let brief = topic.brief {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(topic.title).font(AppFont.text(22, weight: .bold)).foregroundStyle(Ink.primary)
                        if let summary = topic.summary { InlineText(summary, color: Ink.secondary).padding(.top, 8) }
                        section(String(localized: "My positions"), show: !brief.positions.isEmpty) {
                            ForEach(store.index.positions(brief.positions)) { PositionCard(position: $0) }
                        }
                        section(String(localized: "Sections"), show: !brief.sections.isEmpty) {
                            ForEach(Array(brief.sections.enumerated()), id: \.offset) { offset, section in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(verbatim: "\(offset + 1). \(section.title)").font(AppFont.text(15, weight: .semibold))
                                        .foregroundStyle(Ink.primary)
                                    InlineText(section.summary, size: 14, color: Ink.secondary)
                                    if let page = section.note { SectionLinkView(note: page) }
                                }
                                .padding(14).frame(maxWidth: .infinity, alignment: .leading).glassCard()
                            }
                        }
                        section(String(localized: "Counterpoints"), show: !brief.counterpoints.isEmpty) {
                            ForEach(Array(brief.counterpoints.enumerated()), id: \.offset) { _, point in
                                quoted(note: point.note, title: point.title, text: point.text)
                            }
                        }
                        section(String(localized: "Shaky"), show: !brief.shaky.isEmpty) {
                            ForEach(Array(brief.shaky.enumerated()), id: \.offset) { _, point in
                                quoted(note: point.note, title: nil, text: point.text)
                            }
                        }
                        section(String(localized: "Terms"), show: !brief.terms.isEmpty) {
                            ForEach(brief.terms, id: \.self) { TermRow(term: $0) }
                        }
                        section(String(localized: "Open questions"), show: !brief.questions.isEmpty) {
                            ForEach(brief.questions, id: \.self) { id in
                                if let question = store.index.note(id) { NoteRow(note: question) }
                            }
                        }
                    }
                    .padding(.horizontal, Look.side).padding(.top, 8).padding(.bottom, 40)
                }
            } else {
                CalmMessage(text: String(localized: "This topic has no brief."))
            }
        }
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, show: Bool, @ViewBuilder content: () -> Content) -> some View {
        if show {
            SectionHeading(text: title).padding(.top, Look.sectionGap)
            VStack(spacing: Look.rowGap) { content() }.padding(.top, Look.headingGap)
        }
    }

    private func quoted(note: String, title: String?, text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let title { InlineText(title, size: 14, weight: .semibold) }
            InlineText(text, size: 14, color: Ink.secondary)
            Button { navigation.open(NoteLink(note: note)) } label: {
                Text("In \(store.index.title(note))").font(AppFont.text(12)).foregroundStyle(Look.accent.color)
            }
            .buttonStyle(.plain)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading).glassCard()
    }
}

// MARK: - free editor

/// The free editor: the note's Markdown (without frontmatter), saved as a whole against the version it was loaded at.
struct EditorSheet: View {
    @State private var editor: NoteEditor
    @State private var confirmsDiscard = false
    @Environment(\.dismiss) private var dismiss

    init(note: String, store: VaultStore) {
        _editor = State(initialValue: NoteEditor(note: note, store: store))
    }

    var body: some View {
        @Bindable var editor = editor
        NavigationStack {
            Group {
                switch editor.state {
                case .loading:
                    CalmMessage(text: String(localized: "Loading the note…"), loading: true)
                case let .failed(message):
                    CalmMessage(text: message, action: (String(localized: "Try again"), { Task { await editor.load() } }))
                case .editing:
                    VStack(spacing: 10) {
                        if let problem = editor.problem { problemBox(problem) }
                        TextEditor(text: $editor.text)
                            .font(.system(size: 15, design: .monospaced))
                            .scrollContentBackground(.hidden)
                            .padding(10)
                            .glassCard()
                            .disabled(editor.isSaving)
                    }
                    .padding(.horizontal, Look.side).padding(.vertical, 10)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .provinceWall()
            .navigationTitle(Text("Edit"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { if editor.hasChanges { confirmsDiscard = true } else { dismiss() } }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if editor.isSaving {
                        ProgressView()
                    } else {
                        Button("Save") { Task { if await editor.save() { dismiss() } } }.disabled(!editor.canSave)
                    }
                }
            }
            .confirmationDialog("Discard your changes?", isPresented: $confirmsDiscard, titleVisibility: .visible) {
                Button("Discard", role: .destructive) { dismiss() }
            }
        }
        .interactiveDismissDisabled(editor.hasChanges)
        .task { if editor.state == .loading { await editor.load() } }
    }

    private func problemBox(_ problem: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(problem).font(AppFont.text(13)).foregroundStyle(Ink.primary).fixedSize(horizontal: false, vertical: true)
            if editor.conflict {
                HStack(spacing: 10) {
                    Button("Copy my text") { UIPasteboard.general.string = editor.text }.buttonStyle(.pill)
                    Button("Load the current version") { Task { await editor.loadCurrentVersion() } }.buttonStyle(.pill)
                }
            }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading).glassCard(raised: true)
    }
}

// MARK: - discuss

/// Discuss with Claude: the prompt for a Claude Code session on the vault (plus an optional question), copied, then
/// Claude opens.
struct DiscussSheet: View {
    let subject: DiscussSubject
    @State private var question = ""
    @Environment(VaultStore.self) private var store
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let prompt = DiscussPrompt.make(subject, question: question, index: store.index)
        SheetFrame(title: String(localized: "Discuss")) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Claude Code works on the vault with its rules. The prompt below is copied; paste it in a new session.")
                        .font(AppFont.text(13)).foregroundStyle(Ink.secondary).fixedSize(horizontal: false, vertical: true)
                    TextField("Your question (optional)", text: $question, axis: .vertical)
                        .lineLimit(2...6)
                        .font(AppFont.text(15))
                        .padding(12).glassCard()
                    if let prompt {
                        Text(verbatim: prompt).font(AppFont.number(12.5, weight: .regular)).foregroundStyle(Ink.secondary)
                            .textSelection(.enabled)
                            .padding(12).frame(maxWidth: .infinity, alignment: .leading).glassCard()
                        Button("Copy and open Claude") {
                            UIPasteboard.general.string = prompt
                            openURL(DiscussPrompt.target)
                            dismiss()
                        }
                        .buttonStyle(.primaryPill)
                        .frame(maxWidth: .infinity)
                    } else {
                        CalmMessage(text: String(localized: "This is no longer in the vault."))
                    }
                }
                .padding(.horizontal, Look.side).padding(.vertical, 12)
            }
        }
    }
}

// MARK: - quick note

/// A quick note for the Inbox, verbatim. Kept on the phone until the server has it; the waiting ones are listed.
struct QuickNoteSheet: View {
    @State private var text = ""
    @State private var waitingNow = false
    @FocusState private var focused: Bool
    @Environment(VaultStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SheetFrame(title: String(localized: "Quick note")) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    TextField("A thought for the Inbox", text: $text, axis: .vertical)
                        .lineLimit(4...12)
                        .font(AppFont.text(16))
                        .focused($focused)
                        .padding(12).glassCard()
                    if waitingNow {
                        Text("Saved on the phone. It goes to the Inbox once the server can be reached.")
                            .font(AppFont.text(13)).foregroundStyle(Ink.secondary)
                    }
                    if !store.pendingQuickNotes.isEmpty {
                        SectionHeading(text: String(localized: "Not sent yet")).padding(.top, 10)
                        ForEach(store.pendingQuickNotes) { note in PendingRow(note: note) }
                    }
                }
                .padding(.horizontal, Look.side).padding(.vertical, 12)
            }
        } actions: {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    let typed = text
                    Task {
                        switch await store.addQuickNote(typed) {
                        case .sent: dismiss()
                        case .waiting:
                            text = ""
                            waitingNow = true
                        case .empty: break
                        }
                    }
                }
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .onAppear { focused = true }
    }
}

/// A quick note still on the phone: waiting, or refused by the server (with its reason, and Delete).
struct PendingRow: View {
    let note: PendingQuickNote
    @Environment(VaultStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(note.text).font(AppFont.text(14)).foregroundStyle(Ink.primary).textSelection(.enabled)
            if let problem = note.problem {
                Text(problem).font(AppFont.text(12)).foregroundStyle(StatusTone.issue.color(Look.accent))
            } else {
                Text("Waiting to be sent").font(AppFont.text(12)).foregroundStyle(Ink.muted)
            }
            Button("Delete", role: .destructive) { store.deleteQuickNote(note.id) }
                .font(AppFont.text(12)).buttonStyle(.borderless)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading).glassCard()
    }
}

// MARK: - positions

/// Reword, change my view (asks why), drop (asks why), add a position (where, the sentence, evidence picked from the
/// notes).
struct PositionSheet: View {
    @State private var draft: PositionDraft
    @Environment(VaultStore.self) private var store
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.dismiss) private var dismiss

    init(kind: PositionDraft.Kind, index: VaultIndex) {
        _draft = State(initialValue: PositionDraft(kind, index: index))
    }

    var body: some View {
        @Bindable var draft = draft
        @Bindable var navigation = navigation
        NavigationStack {
            Form {
                if let id = draft.kind.position, let position = store.index.position(id) {
                    Section { InlineText(position.text, color: Ink.secondary) } header: { Text("Now") }
                }
                if case .add = draft.kind {
                    Picker("Where", selection: $draft.note) {
                        ForEach(store.index.positionTargets) { target in
                            Text(target.type == .positions ? String(localized: "Across topics") : target.title).tag(target.id)
                        }
                    }
                }
                if draft.needsText {
                    Section {
                        TextField("One sentence, in your words", text: $draft.text, axis: .vertical).lineLimit(2...6)
                    } header: { Text(textHeader) } footer: { Text(textFooter) }
                }
                if draft.needsWhy {
                    Section {
                        TextField("What changed it", text: $draft.why, axis: .vertical).lineLimit(2...6)
                    } header: { Text("Why") } footer: { Text("Your old view goes to “How my view changed”, with today's date.") }
                }
                if case .add = draft.kind {
                    Section {
                        ForEach(draft.evidence, id: \.self) { id in Text(store.index.title(id)) }
                        Button("Pick notes") { navigation.showsEvidencePicker = true }
                    } header: { Text("Evidence") }
                }
                if let problem = draft.problem {
                    Section { Text(problem).foregroundStyle(StatusTone.issue.color(Look.accent)) }
                }
            }
            .scrollContentBackground(.hidden)
            .provinceWall()
            .navigationDestination(isPresented: $navigation.showsEvidencePicker) { EvidencePicker(draft: draft) }
            .navigationTitle(Text(title))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    if draft.isSaving {
                        ProgressView()
                    } else {
                        Button(saveTitle, role: saveRole) {
                            Task { await save() }
                        }
                        .disabled(!draft.canSave)
                    }
                }
            }
        }
        .interactiveDismissDisabled(draft.isSaving)
        .onDisappear { navigation.showsEvidencePicker = false }
    }

    private func save() async {
        guard await draft.save(with: store) else { return }
        if case let .drop(id) = draft.kind { navigation.closePosition(id) }
        dismiss()
    }

    private var title: String {
        switch draft.kind {
        case .reword: String(localized: "Reword")
        case .change: String(localized: "Change my view")
        case .drop: String(localized: "Drop this position")
        case .add: String(localized: "Add a position")
        }
    }

    private var saveRole: ButtonRole? {
        if case .drop = draft.kind { .destructive } else { nil }
    }

    private var saveTitle: String {
        switch draft.kind {
        case .reword, .change: String(localized: "Save")
        case .drop: String(localized: "Drop")
        case .add: String(localized: "Add")
        }
    }

    private var textHeader: String {
        switch draft.kind {
        case .change: String(localized: "My view now")
        default: String(localized: "Position")
        }
    }

    private var textFooter: String {
        switch draft.kind {
        case .reword: String(localized: "Same view, better words: nothing goes to the history.")
        case .change: String(localized: "A changed view replaces the sentence.")
        default: String(localized: "Saved as you write it.")
        }
    }
}

/// Picks the evidence notes for a new position, in the order tapped.
struct EvidencePicker: View {
    let draft: PositionDraft
    @State private var query = ""
    @Environment(VaultStore.self) private var store

    var body: some View {
        let notes = query.isEmpty ? (store.vault?.notes ?? [])
            : store.search.results(query).compactMap { if case let .note(id, _) = $0 { store.index.note(id) } else { nil } }
        List(notes) { note in
            Button { draft.toggleEvidence(note.id) } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(note.title).foregroundStyle(Ink.primary)
                        Text(Format.type(note.type)).font(.caption).foregroundStyle(Ink.muted)
                    }
                    Spacer()
                    if let position = draft.evidence.firstIndex(of: note.id) {
                        Text(verbatim: "\(position + 1)").font(AppFont.number(13)).foregroundStyle(Look.accent.color)
                    }
                }
            }
            .accessibilityAddTraits(draft.evidence.contains(note.id) ? .isSelected : [])
        }
        .scrollContentBackground(.hidden)
        .provinceWall()
        .searchable(text: $query)
        .navigationTitle(Text("Evidence"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
