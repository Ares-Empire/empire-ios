import SwiftUI

/// The topic overviews, each with its summary; tapping one opens its note page. The search field filters them by
/// title, summary and section headings (`TabSearch`); a matching heading opens the note at that section.
struct TopicsScreen: View {
    @Environment(VaultStore.self) private var store
    @Environment(AppNavigation.self) private var navigation

    var body: some View {
        @Bindable var navigation = navigation
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ScreenHeader(title: String(localized: "Topics"))
                StatusLine()
                TabSearchField(text: $navigation.topicsQuery, prompt: Text("Search topics"))
                    .padding(.horizontal, Look.side).padding(.top, 2)
                VStack(spacing: Look.rowGap) {
                    if TabSearch.isQuery(navigation.topicsQuery) {
                        let query = navigation.topicsQuery
                        let hits = store.tabSearch.topics(query)
                        ForEach(hits) { hit in TopicCard(topic: hit.topic, query: query, headings: hit.headings) }
                        if hits.isEmpty { CalmMessage(text: Format.nothingFound(query)) }
                    } else {
                        ForEach(store.index.topics) { topic in TopicCard(topic: topic) }
                        if store.index.topics.isEmpty {
                            CalmMessage(text: String(localized: "No topics in the vault yet."))
                        }
                    }
                }
                .padding(.horizontal, Look.side).padding(.top, 20).padding(.bottom, 40)
            }
        }
        .scrollDismissesKeyboard(.immediately)
        .refreshable { await store.update() }
        .provinceWall()
        .toolbar(.hidden, for: .navigationBar)
    }
}

/// A topic overview: title, confidence, the whole summary, how many positions it holds. In the tab's search the
/// query's words are marked, and the section headings that hold one are listed under it, each opening the note there.
struct TopicCard: View {
    let topic: Note
    var query = ""
    var headings: [TabSearch.Heading] = []
    @Environment(AppNavigation.self) private var navigation

    var body: some View {
        if headings.isEmpty {
            Button { navigation.open(NoteLink(note: topic.id)) } label: { overview.padding(16).card() }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
        } else {
            VStack(alignment: .leading, spacing: 14) {
                Button { navigation.open(NoteLink(note: topic.id)) } label: { overview }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .combine)
                sections
            }
            .padding(16)
            .card()
        }
    }

    private var overview: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(topic.title, marking: query).font(AppFont.text(17, weight: .semibold)).foregroundStyle(Ink.primary)
                    .multilineTextAlignment(.leading)
                Spacer()
                if let confidence = topic.confidence { CapsLabel(text: Format.confidence(confidence)) }
            }
            if let summary = topic.summary {
                Text(InlineMarkdown.plain(summary), marking: query).font(AppFont.text(14)).foregroundStyle(Ink.secondary)
                    .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
            }
            if !topic.positions.isEmpty {
                Text("\(topic.positions.count) positions").font(AppFont.text(12))
                    .foregroundStyle(Ink.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    /// The matching section headings, like an event's "What followed".
    private var sections: some View {
        VStack(alignment: .leading, spacing: 6) {
            CapsLabel(text: String(localized: "Sections"))
            ForEach(headings, id: \.anchor) { heading in
                Button { navigation.open(NoteLink(note: topic.id, anchor: heading.anchor)) } label: {
                    Label {
                        Text(heading.text, marking: query).foregroundStyle(Ink.primary)
                    } icon: {
                        Image(systemName: "arrow.turn.down.right").foregroundStyle(Ink.muted)
                    }
                    .font(AppFont.text(13, weight: .medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private extension View {
    func card() -> some View { frame(maxWidth: .infinity, alignment: .leading).glassCard().contentShape(Rectangle()) }
}
