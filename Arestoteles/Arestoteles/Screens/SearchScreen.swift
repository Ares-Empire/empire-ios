import SwiftUI

/// Search on the device over the whole vault (`VaultSearch`): titles first, the glossary in English and German, a type
/// filter. The query and the filter live in the navigation, so they survive switching tabs.
struct SearchScreen: View {
    @Environment(VaultStore.self) private var store
    @Environment(AppNavigation.self) private var navigation

    var body: some View {
        @Bindable var navigation = navigation
        let results = store.search.results(navigation.query, type: navigation.searchType)
        ScrollView {
            VStack(alignment: .leading, spacing: Look.rowGap) {
                StatusLine()
                Picker("Type", selection: $navigation.searchType) {
                    Text("Everything").tag(NoteType?.none)
                    ForEach(NoteType.known, id: \.self) { type in Text(Format.types(type)).tag(Optional(type)) }
                }
                .pickerStyle(.menu).tint(Look.accent.color)

                if navigation.query.trimmingCharacters(in: .whitespaces).isEmpty {
                    CalmMessage(text: String(localized: "Search titles, summaries, the notes' text and the glossary, in English and German."))
                } else if results.isEmpty {
                    CalmMessage(text: String(localized: "Nothing found."))
                } else {
                    ForEach(results) { result in
                        switch result {
                        case let .note(id, _):
                            if let note = store.index.note(id) { NoteRow(note: note) }
                        case let .term(term, _):
                            TermRow(term: term)
                        }
                    }
                }
            }
            .padding(.horizontal, Look.side).padding(.top, 6).padding(.bottom, 40)
        }
        .scrollDismissesKeyboard(.interactively)
        .provinceWall()
        .navigationTitle(Text("Search"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // The quick note, as on the other tabs (whose headers carry it).
            ToolbarItem(placement: .topBarTrailing) {
                Button { navigation.sheet = .quickNote } label: { Label("Quick note", systemImage: "plus") }
            }
        }
        .searchable(text: $navigation.query, prompt: Text("Notes, positions, terms"))
    }
}

/// A glossary entry: English and German, and the note that explains it.
struct TermRow: View {
    let term: Term
    @Environment(VaultStore.self) private var store
    @Environment(AppNavigation.self) private var navigation

    var body: some View {
        Button { if let note = term.note { navigation.open(NoteLink(note: note)) } } label: {
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: "\(term.english) · \(term.german)").font(AppFont.text(15, weight: .semibold))
                    .foregroundStyle(Ink.primary)
                CapsLabel(text: Format.type(.glossary))
                if let note = term.note {
                    Text("Explained in \(store.index.title(note))").font(AppFont.text(13)).foregroundStyle(Ink.secondary)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(term.note == nil)
        .accessibilityElement(children: .combine)
    }
}
