import SwiftUI

/// Arestoteles on top of Shared/Design: the province wall and glass in Aegean teal. Structure only; the lead styles the
/// screens (DESIGN.md of the 2026-10-24 build: the accent only on the selected tab, the one primary button of a screen
/// and small highlights).
enum Look {
    static let accent = AppAccent.arestoteles
    static let side: CGFloat = 18                       // side margins
    static let rowGap: CGFloat = 12                     // between rows and cards
    static let sectionGap: CGFloat = 28                 // between sections
    static let headingGap: CGFloat = 10                 // a section heading to its card
}

/// The top of a tab: the bust on the left, the title centred, the quick-note button (reachable from every tab) and
/// Settings on the right.
struct ScreenHeader: View {
    let title: String
    @Environment(AppNavigation.self) private var navigation

    var body: some View {
        ZStack {
            Text(title).font(AppFont.text(17, weight: .bold)).foregroundStyle(Ink.primary).lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            HStack(spacing: 8) {
                Image("Bust").resizable().scaledToFit().frame(width: 38, height: 38).accessibilityHidden(true)
                Spacer()
                GlassIconButton(symbol: "square.and.pencil", label: String(localized: "Quick note")) {
                    navigation.sheet = .quickNote(about: nil)
                }
                GlassIconButton(symbol: "gearshape", label: String(localized: "Settings")) {
                    navigation.sheet = .settings
                }
            }
        }
        .frame(minHeight: 44)
        .padding(.horizontal, Look.side).padding(.top, 4).padding(.bottom, 6)
    }
}

/// The contract's inline Markdown as text; note links open in the app, web links in Safari (the root's `openURL`).
struct InlineText: View {
    let markdown: String
    var size: CGFloat = 15
    var weight: Font.Weight = .regular
    var color: Color = Ink.primary

    init(_ markdown: String, size: CGFloat = 15, weight: Font.Weight = .regular, color: Color = Ink.primary) {
        self.markdown = markdown
        self.size = size
        self.weight = weight
        self.color = color
    }

    var body: some View {
        Text(InlineMarkdown.attributed(markdown))
            .font(AppFont.text(size, weight: weight)).foregroundStyle(color).tint(Look.accent.color)
            .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Tracked capitals: a note's type, a confidence, a label.
struct CapsLabel: View {
    let text: String
    var color: Color = Ink.muted

    var body: some View {
        Text(text.uppercased()).font(AppFont.text(10, weight: .semibold)).tracking(1.4).foregroundStyle(color).lineLimit(1)
    }
}

/// Empty, loading and error states: one calm sentence, centred, at most one action.
struct CalmMessage: View {
    let text: String
    var action: (title: String, run: () -> Void)? = nil
    var loading = false

    var body: some View {
        VStack(spacing: 14) {
            if loading { ProgressView().tint(Ink.muted) }
            Text(text).font(AppFont.text(14)).foregroundStyle(Ink.muted).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let action { Button(action.title, action: action.run).buttonStyle(.pill) }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 30).padding(.vertical, 36)
    }
}

/// A note as a row: title, type, summary (two lines). Tapping opens it. In a tab's search, `lead` stands in for a
/// missing summary and the query's words are marked.
struct NoteRow: View {
    let note: Note
    var detail: Text? = nil
    /// The line under the title, plain text; nil: the summary.
    var lead: String? = nil
    var query = ""
    @Environment(AppNavigation.self) private var navigation

    var body: some View {
        Button { navigation.open(NoteLink(note: note.id)) } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(note.title, marking: query).font(AppFont.text(15, weight: .semibold)).foregroundStyle(Ink.primary)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 8)
                    if let detail { detail.font(AppFont.text(12)).foregroundStyle(Ink.secondary) }
                }
                CapsLabel(text: Format.type(note.type))
                if let line = lead ?? note.summary.map(InlineMarkdown.plain) {
                    Text(line, marking: query).font(AppFont.text(13)).foregroundStyle(Ink.secondary)
                        .lineLimit(2).multilineTextAlignment(.leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .glassCard()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }
}

/// The search field at the top of Positions, Topics and Library: the look of the Search tab's own field (a capsule of
/// light glass, the magnifier, × to clear, the system font as there, growing with Dynamic Type), but in the content, so
/// it scrolls with it.
struct TabSearchField: View {
    @Binding var text: String
    let prompt: Text
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass").font(.body.weight(.medium))
                .foregroundStyle(Self.glyph)
                .accessibilityHidden(true)
            TextField(text: $text, prompt: prompt.foregroundStyle(Self.prompt)) { prompt }
                .font(.body).foregroundStyle(Ink.primary).tint(Look.accent.color)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .submitLabel(.search)
                .focused($isFocused)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.body)
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Self.clearMark, Self.glyph)
                        .frame(width: 28, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Clear the search"))
            }
        }
        .padding(.leading, 14).padding(.trailing, text.isEmpty ? 14 : 6)
        .frame(minHeight: 42)
        .background(Capsule().fill(Self.fill))
        .contentShape(Capsule())
        .onTapGesture { isFocused = true }
    }

    // The Search tab's own field (iOS's), measured on the wall in each look: a light fill with near-white marks on the
    // dark wall, a grey fill with near-black marks on the light one.
    private static let fill = Color(light: Color(hex: 0x767680, opacity: 0.12), dark: .white.opacity(0.11))
    /// The magnifier and the clear button's disc.
    private static let glyph = Color(light: Color(hex: 0x333334), dark: .white.opacity(0.8))
    private static let prompt = Color(light: Color(hex: 0x929399), dark: .white.opacity(0.45))
    /// The × on the clear button: the field's own colour, so it reads as cut out of the disc.
    private static let clearMark = Color(light: Color(hex: 0xDEDFE4), dark: Color(hex: 0x202024))
}

extension Text {
    /// A text with the query's words marked as the search marks them: bold, in the accent. Case and accents do not
    /// matter; words of one letter are left alone. An empty query marks nothing.
    init(_ text: String, marking query: String) {
        self.init(Self.marked(text, query: query))
    }

    static func marked(_ text: String, query: String) -> AttributedString {
        var marked = AttributedString(text)
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init).filter { $0.count >= 2 }
        for word in words {
            var searchFrom = marked.startIndex
            while searchFrom < marked.endIndex,
                  let range = marked[searchFrom...].range(of: word, options: [.caseInsensitive, .diacriticInsensitive]) {
                marked[range].inlinePresentationIntent = .stronglyEmphasized
                marked[range].foregroundColor = Look.accent.color
                searchFrom = range.upperBound
            }
        }
        return marked
    }
}

/// What an edit said, shown briefly over the tabs.
struct NoticeBanner: View {
    let notice: VaultStore.Notice
    let close: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: notice.tone == .problem ? "exclamationmark.circle" : "checkmark.circle")
                .foregroundStyle(notice.tone == .problem ? StatusTone.issue.color(Look.accent) : Look.accent.color)
            Text(notice.text).font(AppFont.text(13)).foregroundStyle(Ink.primary)
                .frame(maxWidth: .infinity, alignment: .leading).fixedSize(horizontal: false, vertical: true)
            Button(action: close) { Image(systemName: "xmark").foregroundStyle(Ink.muted) }
                .buttonStyle(.plain).accessibilityLabel("Close")
        }
        .padding(12)
        .glassCard(raised: true)
        .padding(.horizontal, Look.side)
        .accessibilityElement(children: .combine)
    }
}

/// "Offline · updated 4 min ago" and the quick notes waiting, at the top of a tab when it applies.
struct StatusLine: View {
    @Environment(VaultStore.self) private var store

    var body: some View {
        let waiting = store.pendingQuickNotes.count { $0.problem == nil }
        if store.isOffline || waiting > 0 || store.loadError != nil {
            VStack(spacing: 4) {
                if store.isOffline {
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        Text(offline(now: context.date)).font(AppFont.text(12)).foregroundStyle(Ink.muted)
                    }
                } else if let error = store.loadError {
                    Text(error).font(AppFont.text(12)).foregroundStyle(Ink.muted)
                }
                if waiting > 0 {
                    Text("\(waiting) quick notes waiting to be sent").font(AppFont.text(12)).foregroundStyle(Ink.muted)
                }
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Look.side).padding(.bottom, 8)
        }
    }

    private func offline(now: Date) -> String {
        let built = store.lastRefresh ?? store.vault.flatMap { Format.timestamp($0.built) }
        guard let built else { return String(localized: "Offline") }
        return String(localized: "Offline · updated \(Format.age(built, now: now))")
    }
}

extension View {
    /// The wall every Arestoteles screen stands on.
    func provinceWall() -> some View { background { ProvinceWall(accent: Look.accent) } }
}

// MARK: - buttons

/// A pill button. Prominent: the screen's one main action, in the accent (`AppAccent.onColor` on teal). Otherwise a
/// quiet outlined pill (`Ink.field`, `Ink.edge`).
struct PillButtonStyle: ButtonStyle {
    var prominent = false
    var destructive = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppFont.text(14, weight: .semibold))
            .foregroundStyle(prominent ? AppAccent.onColor : destructive ? StatusTone.issue.color(Look.accent) : Ink.primary)
            .lineLimit(1)
            .padding(.horizontal, 16).frame(minHeight: 40)
            .background {
                if prominent {
                    Capsule().fill(Look.accent.color)
                } else {
                    Capsule().fill(Ink.field)
                        .overlay(Capsule().strokeBorder(Ink.edge))
                }
            }
            .opacity(isEnabled ? (configuration.isPressed ? 0.75 : 1) : 0.45)
            .contentShape(Capsule())
    }
}

extension ButtonStyle where Self == PillButtonStyle {
    static var pill: PillButtonStyle { PillButtonStyle() }
    static var primaryPill: PillButtonStyle { PillButtonStyle(prominent: true) }
    static var destructivePill: PillButtonStyle { PillButtonStyle(destructive: true) }
}

/// A row of choices as small capsules that scrolls sideways when it does not fit (German labels run long).
struct ChipPicker<Value: Hashable>: View {
    let options: [(value: Value, title: String)]
    @Binding var selection: Value

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(options, id: \.value) { option in
                    let selected = option.value == selection
                    Button { withAnimation(.easeOut(duration: 0.15)) { selection = option.value } } label: {
                        Text(option.title)
                            .font(AppFont.text(13, weight: selected ? .semibold : .medium))
                            .foregroundStyle(selected ? AppAccent.onColor : Ink.secondary)
                            .padding(.horizontal, 14).frame(minHeight: 34)
                            .background {
                                if selected { Capsule().fill(Look.accent.color) }
                                else { Capsule().fill(Ink.field).overlay(Capsule().strokeBorder(Ink.edge)) }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(.horizontal, Look.side)
        }
        .scrollClipDisabled()
    }
}
