import SwiftUI

/// Search on the device over the whole vault (`VaultSearch`): titles first, the glossary in English and German, a type
/// filter. The query and the filter live in the navigation, so they survive switching tabs.
struct SearchScreen: View {
    @Environment(VaultStore.self) private var store
    @Environment(AppNavigation.self) private var navigation

    var body: some View {
        @Bindable var navigation = navigation
        let results = store.search.results(navigation.query, type: navigation.searchType)
        // Sentences first: a lookup usually wants the one sentence with the fact, not the note around it.
        let sentences = navigation.searchType == nil ? store.search.sentences(navigation.query) : []
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
                } else if results.isEmpty && sentences.isEmpty {
                    CalmMessage(text: String(localized: "Nothing found."))
                } else {
                    if !sentences.isEmpty {
                        SectionHeading(text: String(localized: "In the text"))
                        SentenceList(hits: sentences, query: navigation.query)
                        if !results.isEmpty { SectionHeading(text: String(localized: "Notes")).padding(.top, 10) }
                    }
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
                Button { navigation.sheet = .quickNote(about: nil) } label: { Label("Quick note", systemImage: "square.and.pencil") }
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

/// Sentence hits: the sentence with the query's words in bold, and where it stands (note · heading). Tapping opens the
/// note at that passage, marked.
struct SentenceList: View {
    let hits: [VaultSearch.SentenceHit]
    let query: String
    @Environment(AppNavigation.self) private var navigation

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(hits.enumerated()), id: \.element.id) { offset, hit in
                if offset > 0 { Rectangle().fill(Ink.line).frame(height: 1) }
                Button { navigation.open(NoteLink(note: hit.passage.note, block: hit.passage.block)) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(Self.marked(hit.sentence, query: query)).font(AppFont.text(14)).foregroundStyle(Ink.primary)
                            .multilineTextAlignment(.leading)
                        Text(verbatim: [hit.title, hit.passage.heading].compactMap { $0 }.joined(separator: " · "))
                            .font(AppFont.text(11)).foregroundStyle(Ink.muted).lineLimit(1)
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

    /// The sentence with each query word in bold and the accent (case and accents ignored).
    static func marked(_ sentence: String, query: String) -> AttributedString {
        var text = AttributedString(sentence)
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init).filter { $0.count >= 2 }
        for word in words {
            var searchFrom = text.startIndex
            while searchFrom < text.endIndex,
                  let range = text[searchFrom...].range(of: word, options: [.caseInsensitive, .diacriticInsensitive]) {
                text[range].font = AppFont.text(14, weight: .bold)
                text[range].foregroundColor = Look.accent.color
                searchFrom = range.upperBound
            }
        }
        return text
    }
}
