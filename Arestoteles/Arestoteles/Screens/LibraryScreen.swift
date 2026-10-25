import SwiftUI

/// The library: mechanisms (with how many notes use each), events as a timeline by year with a region filter and what
/// followed each, questions, actors. While something is typed in the search field, the matches of every kind show
/// instead (`TabSearch`), each row with its kind; clearing the field returns to the chosen kind.
struct LibraryScreen: View {
    @Environment(VaultStore.self) private var store
    @Environment(AppNavigation.self) private var navigation

    var body: some View {
        @Bindable var navigation = navigation
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ScreenHeader(title: String(localized: "Library"))
                StatusLine()
                TabSearchField(text: $navigation.libraryQuery, prompt: Text("Search the library"))
                    .padding(.horizontal, Look.side).padding(.top, 2)
                if TabSearch.isQuery(navigation.libraryQuery) {
                    found(navigation.libraryQuery)
                        .padding(.horizontal, Look.side).padding(.top, 20).padding(.bottom, 40)
                } else {
                    ChipPicker(options: LibraryPart.allCases.map { ($0, $0.title) }, selection: $navigation.libraryPart)
                        .padding(.top, 14)
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
        }
        .scrollDismissesKeyboard(.immediately)
        .refreshable { await store.update() }
        .provinceWall()
        .toolbar(.hidden, for: .navigationBar)
    }

    @ViewBuilder private var mechanisms: some View {
        ForEach(store.index.mechanisms) { mechanism in
            NoteRow(note: mechanism, detail: uses(mechanism))
        }
        if store.index.mechanisms.isEmpty { CalmMessage(text: String(localized: "No mechanisms yet.")) }
    }

    @ViewBuilder private func list(_ notes: [Note], empty: String) -> some View {
        ForEach(notes) { note in NoteRow(note: note) }
        if notes.isEmpty { CalmMessage(text: empty) }
    }

    /// Matches of every kind, as rows with their kind, the words marked (events and actors without a summary show their
    /// first paragraph).
    private func found(_ query: String) -> some View {
        let hits = store.tabSearch.library(query)
        return VStack(alignment: .leading, spacing: Look.rowGap) {
            ForEach(hits) { hit in
                NoteRow(note: hit.note, detail: detail(hit.note), lead: hit.lead, query: query)
            }
            if hits.isEmpty { CalmMessage(text: Format.nothingFound(query)) }
        }
    }

    /// Beside the title: how often a mechanism is used, an event's years.
    private func detail(_ note: Note) -> Text? {
        switch note.type {
        case .mechanism: uses(note)
        case .event: Format.years(from: note.event?.from, to: note.event?.to).map { Text(verbatim: $0) }
        default: nil
        }
    }

    private func uses(_ mechanism: Note) -> Text { Text("Used in \(store.index.mechanismUses(mechanism.id)) notes") }
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
                Rectangle().fill(Ink.line).frame(width: 1)
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
                    if let summary = event.summary ?? Lookup.firstParagraph(of: event) {
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
}
