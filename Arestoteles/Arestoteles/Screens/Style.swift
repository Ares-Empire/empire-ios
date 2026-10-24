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

/// The top of a tab: the bust on the left (its menu logs out), the title centred, the quick-note button on the right
/// (reachable from every tab).
struct ScreenHeader: View {
    let title: String
    @Environment(AppNavigation.self) private var navigation
    @Environment(\.logOut) private var logOut

    var body: some View {
        ZStack {
            Text(title).font(AppFont.text(17, weight: .bold)).foregroundStyle(Ink.primary).lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            HStack {
                Menu {
                    Button("Log out", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) { logOut() }
                } label: {
                    Image("Bust").resizable().scaledToFit().frame(width: 38, height: 38)
                }
                .accessibilityLabel(Text("Account"))
                Spacer()
                GlassIconButton(symbol: "square.and.pencil", label: String(localized: "Quick note")) {
                    navigation.sheet = .quickNote(about: nil)
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

/// A note as a row: title, type, summary (two lines). Tapping opens it.
struct NoteRow: View {
    let note: Note
    var detail: Text? = nil
    @Environment(AppNavigation.self) private var navigation

    var body: some View {
        Button { navigation.open(NoteLink(note: note.id)) } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(note.title).font(AppFont.text(15, weight: .semibold)).foregroundStyle(Ink.primary)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 8)
                    if let detail { detail.font(AppFont.text(12)).foregroundStyle(Ink.secondary) }
                }
                CapsLabel(text: Format.type(note.type))
                if let summary = note.summary {
                    Text(InlineMarkdown.plain(summary)).font(AppFont.text(13)).foregroundStyle(Ink.secondary)
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

/// A pill button. Prominent: the screen's one main action, in the accent (dark text on teal). Otherwise glass.
struct PillButtonStyle: ButtonStyle {
    var prominent = false
    var destructive = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppFont.text(14, weight: .semibold))
            .foregroundStyle(prominent ? Color(hex: 0x06201D) : destructive ? StatusTone.issue.color(Look.accent) : Ink.primary)
            .lineLimit(1)
            .padding(.horizontal, 16).frame(minHeight: 40)
            .background {
                if prominent {
                    Capsule().fill(Look.accent.color)
                } else {
                    Capsule().fill(.white.opacity(0.06))
                        .overlay(Capsule().strokeBorder(.white.opacity(0.12)))
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
                            .foregroundStyle(selected ? Color(hex: 0x06201D) : Ink.secondary)
                            .padding(.horizontal, 14).frame(minHeight: 34)
                            .background {
                                if selected { Capsule().fill(Look.accent.color) }
                                else { Capsule().fill(.white.opacity(0.05)).overlay(Capsule().strokeBorder(.white.opacity(0.1))) }
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
