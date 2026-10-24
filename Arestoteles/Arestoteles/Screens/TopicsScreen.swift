import SwiftUI

/// The topic overviews, each with its summary; tapping one opens its note page.
struct TopicsScreen: View {
    @Environment(VaultStore.self) private var store
    @Environment(AppNavigation.self) private var navigation

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ScreenHeader(title: String(localized: "Topics"))
                StatusLine()
                VStack(spacing: Look.rowGap) {
                    ForEach(store.index.topics) { topic in TopicCard(topic: topic) }
                    if store.index.topics.isEmpty {
                        CalmMessage(text: String(localized: "No topics in the vault yet."))
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

/// A topic overview: title, confidence, the whole summary, how many positions it holds.
struct TopicCard: View {
    let topic: Note
    @Environment(AppNavigation.self) private var navigation

    var body: some View {
        Button { navigation.open(NoteLink(note: topic.id)) } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Text(topic.title).font(AppFont.text(17, weight: .semibold)).foregroundStyle(Ink.primary)
                        .multilineTextAlignment(.leading)
                    Spacer()
                    if let confidence = topic.confidence { CapsLabel(text: Format.confidence(confidence)) }
                }
                if let summary = topic.summary {
                    Text(InlineMarkdown.plain(summary)).font(AppFont.text(14)).foregroundStyle(Ink.secondary)
                        .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                }
                if !topic.positions.isEmpty {
                    Text("^[\(topic.positions.count) position](inflect: true)").font(AppFont.text(12))
                        .foregroundStyle(Ink.muted)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCard()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}
