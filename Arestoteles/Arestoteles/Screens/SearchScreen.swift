import SwiftUI

/// Search over the whole vault: the server's best matches by words and meaning first (`BestMatches`, once typing
/// pauses), then the device's own results at once (`VaultSearch`): sentences, then notes and the glossary in English
/// and German, with a type filter. The query and the filter live in the navigation, so they survive switching tabs.
struct SearchScreen: View {
    @Environment(VaultStore.self) private var store
    @Environment(AppNavigation.self) private var navigation

    var body: some View {
        @Bindable var navigation = navigation
        let listing = store.bestMatches.listing(navigation.query, type: navigation.searchType, search: store.search,
                                                index: store.index)
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
                } else if listing.isEmpty && !listing.placeholder {
                    // While the server may still answer, the space stays empty rather than saying "nothing".
                    if !listing.waiting { CalmMessage(text: String(localized: "Nothing found.")) }
                } else {
                    results(listing)
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
        .onChange(of: navigation.query, initial: true) { _, query in store.bestMatches.update(query) }
    }

    /// Best matches, then the device's sentences (without the passages above), then the notes; each part under its
    /// heading once there is more than one.
    @ViewBuilder private func results(_ listing: SearchListing) -> some View {
        let query = navigation.query
        let headed = !listing.best.isEmpty || listing.placeholder
        if headed {
            SectionHeading(text: String(localized: "Best matches"))
            if listing.best.isEmpty {
                BestMatchesPlaceholder()
            } else {
                PassageCard(rows: listing.best.map { match in
                    PassageCard.Row(id: match.id, sentence: match.marksWords ? Text.marked(match.hit.sentence, query: query)
                                                                             : AttributedString(match.hit.sentence),
                                    place: match.place, route: match.route)
                }, raised: true)
            }
        }
        if !listing.sentences.isEmpty {
            SectionHeading(text: String(localized: "In the text")).padding(.top, headed ? 10 : 0)
            SentenceList(hits: listing.sentences, query: query)
        }
        if !listing.results.isEmpty {
            if headed || !listing.sentences.isEmpty {
                SectionHeading(text: String(localized: "Notes")).padding(.top, 10)
            }
            ForEach(listing.results) { result in
                switch result {
                case let .note(id, _):
                    if let note = store.index.note(id) { NoteRow(note: note) }
                case let .term(term, _):
                    TermRow(term: term)
                }
            }
        }
    }
}

/// Where the best matches will come, while the server takes its time (shown only after a moment, so it never flashes).
private struct BestMatchesPlaceholder: View {
    var body: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small).tint(Ink.muted)
            Text("Searching by meaning…").font(AppFont.text(13)).foregroundStyle(Ink.muted)
        }
        .padding(.horizontal, 14).frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .glassCard()
        .accessibilityElement(children: .combine)
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

/// Sentence hits on the device: the sentence with the query's words marked, and where it stands. Tapping opens the
/// note at that passage, marked.
struct SentenceList: View {
    let hits: [VaultSearch.SentenceHit]
    let query: String

    var body: some View {
        PassageCard(rows: hits.map { hit in
            PassageCard.Row(id: hit.id, sentence: Text.marked(hit.sentence, query: query),
                            place: [hit.title, hit.passage.heading].compactMap { $0 }.joined(separator: " · "),
                            route: .note(NoteLink(note: hit.passage.note, block: hit.passage.block)))
        })
    }
}

/// Passages in one card, divided by hairlines: the sentence, and where it stands (note · heading) in small muted
/// letters. Tapping one opens its page: the note at that passage, marked, or a position. `raised`: the screen's main
/// card (the best matches).
struct PassageCard: View {
    struct Row: Identifiable {
        let id: String
        let sentence: AttributedString
        let place: String
        let route: Route
    }

    let rows: [Row]
    var raised = false
    @Environment(AppNavigation.self) private var navigation

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { offset, row in
                if offset > 0 { Rectangle().fill(Ink.line).frame(height: 1) }
                Button { navigation.go(to: row.route) } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(row.sentence).font(AppFont.text(14)).foregroundStyle(Ink.primary)
                            .multilineTextAlignment(.leading)
                        Text(verbatim: row.place).font(AppFont.text(11)).foregroundStyle(Ink.muted).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal, 14)
        .glassCard(raised: raised)
    }
}
