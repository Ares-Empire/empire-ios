import SwiftUI

/// The library: mechanisms (with how many notes use each), events as a timeline by year with a region filter and what
/// followed each, questions, actors.
struct LibraryScreen: View {
    @Environment(VaultStore.self) private var store
    @Environment(AppNavigation.self) private var navigation

    var body: some View {
        @Bindable var navigation = navigation
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ScreenHeader(title: String(localized: "Library"))
                StatusLine()
                ChipPicker(options: LibraryPart.allCases.map { ($0, $0.title) }, selection: $navigation.libraryPart)
                    .padding(.top, 6)

                VStack(alignment: .leading, spacing: Look.rowGap) {
                    switch navigation.libraryPart {
                    case .mechanisms: mechanisms
                    case .events: EventsTimeline()
                    case .questions: list(store.index.questions, empty: String(localized: "No questions yet."))
                    case .actors: list(store.index.actors, empty: String(localized: "No actors yet."))
                    }
                }
                .padding(.horizontal, Look.side).padding(.top, 16).padding(.bottom, 40)
            }
        }
        .refreshable { await store.update() }
        .provinceWall()
        .toolbar(.hidden, for: .navigationBar)
    }

    @ViewBuilder private var mechanisms: some View {
        ForEach(store.index.mechanisms) { mechanism in
            let uses = store.index.mechanismUses(mechanism.id)
            NoteRow(note: mechanism, detail: Text("Used in \(uses) notes"))
        }
        if store.index.mechanisms.isEmpty { CalmMessage(text: String(localized: "No mechanisms yet.")) }
    }

    @ViewBuilder private func list(_ notes: [Note], empty: String) -> some View {
        ForEach(notes) { note in NoteRow(note: note) }
        if notes.isEmpty { CalmMessage(text: empty) }
    }
}

/// Events by year (BCE before CE, events without a year last), filtered by region; each with its years, places,
/// summary and what followed (`led_to`).
struct EventsTimeline: View {
    static let yearWidth: CGFloat = 46
    @Environment(VaultStore.self) private var store
    @Environment(AppNavigation.self) private var navigation

    var body: some View {
        @Bindable var navigation = navigation
        let regions = store.index.regions
        if regions.count > 1 || navigation.region != nil {
            Picker("Region", selection: $navigation.region) {
                Text("All regions").tag(String?.none)
                ForEach(regions, id: \.self) { region in Text(verbatim: region).tag(Optional(region)) }
            }
            .pickerStyle(.menu).tint(Look.accent.color)
        }
        let timeline = store.index.timeline(region: navigation.region)
        VStack(alignment: .leading, spacing: 18) {
            ForEach(timeline, id: \.year) { year in
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .trailing, spacing: 6) {
                        Text(verbatim: year.year.map { Format.year($0) } ?? "–")
                            .font(AppFont.number(13, weight: .semibold)).foregroundStyle(Look.accent.color)
                            .lineLimit(1).minimumScaleFactor(0.8)
                            .accessibilityAddTraits(.isHeader)
                    }
                    .frame(width: Self.yearWidth, alignment: .trailing)
                    .padding(.top, 15)
                    Circle().fill(Look.accent.color).frame(width: 7, height: 7)
                        .overlay(Circle().strokeBorder(Ink.background, lineWidth: 2).padding(-2))
                        .padding(.top, 20)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: Look.rowGap) {
                        ForEach(year.events) { event in EventRow(event: event) }
                    }
                }
            }
        }
        // The rail runs behind the dots, from the first year to the last.
        .background(alignment: .topLeading) {
            if timeline.count > 1 {
                Rectangle().fill(.white.opacity(0.1)).frame(width: 1)
                    .padding(.leading, Self.yearWidth + 12 + 3).padding(.vertical, 22)
                    .accessibilityHidden(true)
            }
        }
        if timeline.isEmpty { CalmMessage(text: String(localized: "No events here yet.")) }
    }
}

struct EventRow: View {
    let event: Note
    @Environment(VaultStore.self) private var store
    @Environment(AppNavigation.self) private var navigation

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { navigation.open(NoteLink(note: event.id)) } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(event.title).font(AppFont.text(15, weight: .semibold)).foregroundStyle(Ink.primary)
                        .multilineTextAlignment(.leading)
                    HStack(spacing: 8) {
                        if let years = Format.years(from: event.event?.from, to: event.event?.to) {
                            Text(verbatim: years).font(AppFont.number(12)).foregroundStyle(Ink.secondary)
                        }
                        if let places = event.event?.where, !places.isEmpty {
                            Text(verbatim: places.joined(separator: ", ")).font(AppFont.text(12)).foregroundStyle(Ink.muted)
                        }
                    }
                    if let summary = event.summary ?? firstParagraph {
                        Text(InlineMarkdown.plain(summary)).font(AppFont.text(13)).foregroundStyle(Ink.secondary)
                            .lineLimit(3).multilineTextAlignment(.leading)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)

            let followed = store.index.followed(event)
            if !followed.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    CapsLabel(text: String(localized: "What followed"))
                    ForEach(followed) { next in
                        Button { navigation.open(NoteLink(note: next.id)) } label: {
                            Label(next.title, systemImage: "arrow.turn.down.right")
                                .font(AppFont.text(13, weight: .medium)).foregroundStyle(Look.accent.color)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(14)
        .glassCard()
    }

    /// Events often have no summary box: their first paragraph stands in.
    private var firstParagraph: String? {
        event.blocks.lazy.compactMap { if case let .paragraph(text) = $0 { text } else { nil } }.first
    }
}
