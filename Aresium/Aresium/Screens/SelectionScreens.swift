import SwiftUI

// Several payments at once, the look (brief 82; the logic is `Model/PaymentSelection.swift`): as Mail selects mails. The
// header's icon turns a category's month list into selection: the rows slide a little to the right and a circle shows
// at each one's left edge, a tap ticks it (the circle filled in the app's ink with a tick, the row lightly
// highlighted), and so does a finger sliding over the rows (brief 200, `SlideSelect.swift`); the header says how many
// are ticked, with All (or None) and Done; a bar at the bottom offers Category and Name. Ink only, from the palette, in
// light, dark and red mode.
//
// The motion (brief 200, Patrik on build 14: "quite bouncy … should be less bouncy"; measured on a recording of build
// 14: every tick slid the new circle in from up to 29 pt left of its place, and the header's count rolled letter by
// letter for 0.56 s): only the rows and their circles slide, once, in a short ease-out (`SelectionMotion`); the header
// and the bar fade in place; a tick changes the circle and the row's background with a very short fade and nothing
// moves.

/// How a row shows while its list selects: its circle ticked or not; `ticked` nil for a row that cannot be selected (a
/// withdrawal's covered row: no circle, faded).
struct SelectionMark {
    let ticked: Bool?
    let palette: Palette
}

/// How selecting starts and ends (brief 200): the rows and their circles slide in one short ease-out without overshoot,
/// and the header and the bar fade in place over the same time; nothing else moves. Its own, so adding up keeps
/// `SumMotion`. Reduce Motion: no movement (the change shows at once).
enum SelectionMotion {
    static let duration = 0.25

    static func animation(reduceMotion: Bool) -> Animation? {
        guard !reduceMotion else { return nil }
        #if DEBUG
        // Frame strips of the motion itself: `-selectSlow <seconds>` stretches it.
        if let seconds = LaunchArguments.value("-selectSlow").flatMap(Double.init) {
            return .easeOut(duration: seconds)
        }
        #endif
        return .easeOut(duration: duration)
    }

    /// A tick (a tap, All, None, a slide): the circle and the row's background change with a very short fade, in place.
    static let tick = Animation.easeOut(duration: 0.1)
}

extension View {
    /// Fades in as it appears, in `animation` (nil: shown at once). For views that come in where the transaction that
    /// brings them gives them no animation (brief 200: the selection's header and bar came in one frame, also with a
    /// transition's own animation; their way out fades as it should).
    func fadesIn(_ animation: Animation?) -> some View { modifier(FadeIn(animation: animation)) }
}

private struct FadeIn: ViewModifier {
    let animation: Animation?
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown || animation == nil ? 1 : 0)
            .onAppear { withAnimation(animation) { shown = true } }
    }
}

/// The measures of selecting.
enum SelectionLook {
    /// The circle's size: a little smaller than the day's tile beside it.
    static let circle: CGFloat = 22
    /// How far the rows slide right: the circle and its gap to the day's tile.
    static let inset: CGFloat = 34
    /// The circle's place from the row's edge, where the day's tile starts while not selecting.
    static let edge: CGFloat = 12
    /// The fade of a row that cannot be selected.
    static let unavailable: Double = 0.45
    /// The circle column (brief 200): from a row's leading edge to where its day's tile starts while selecting; a drag
    /// that starts here selects by sliding. With the list's margin left of the rows it is 58 pt wide.
    static let column: CGFloat = edge + inset
}

extension View {
    /// A row's look while its list selects (nil: as always). Inside the row's button, so a tap on the circle ticks too.
    func selectionMark(_ mark: SelectionMark?) -> some View { modifier(SelectionMarkLook(mark: mark)) }

    /// VoiceOver: a ticked row reads as selected.
    func selectionTraits(_ mark: SelectionMark?) -> some View {
        accessibilityAddTraits(mark?.ticked == true ? .isSelected : [])
    }
}

private struct SelectionMarkLook: ViewModifier {
    let mark: SelectionMark?

    func body(content: Content) -> some View {
        let ticked = mark?.ticked == true
        content
            // Slid right by the circle and its gap (in `SelectionMotion`, set by whoever starts or ends selecting).
            .padding(.leading, mark == nil ? 0 : SelectionLook.inset)
            .contentShape(Rectangle())
            .background {
                // Lightly highlighted while ticked: the raised card colour, a little inside the row's height so two
                // ticked rows read as two.
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(mark?.palette.card2 ?? .clear)
                    .padding(.vertical, 1)
                    .opacity(ticked ? 1 : 0)
            }
            .overlay(alignment: .leading) {
                if let mark, let ticked = mark.ticked {
                    SelectionCircle(ticked: ticked, palette: mark.palette)
                        .padding(.leading, SelectionLook.edge)
                        // It comes in with the row from the left, as Mail's (in the motion of whoever starts selecting).
                        .transition(.offset(x: -SelectionLook.inset).combined(with: .opacity))
                }
            }
            .opacity(mark != nil && mark?.ticked == nil ? SelectionLook.unavailable : 1)
            .animation(SelectionMotion.tick, value: ticked)
    }
}

/// The circle at a row's left edge: empty in the muted ink, or filled in the app's ink with the tick in the wall's colour.
/// Both are always there, one of them seen: a tick only fades between them in place. (Brief 200: as two views swapped in
/// and out, the swap took the circle's own way in, so every tick slid the new circle in from the left.)
struct SelectionCircle: View {
    let ticked: Bool
    let palette: Palette

    var body: some View {
        ZStack {
            Image(systemName: "circle").foregroundStyle(palette.muted)
                .opacity(ticked ? 0 : 1)
            Image(systemName: "checkmark.circle.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(palette.background, palette.ink)
                .opacity(ticked ? 1 : 0)
        }
        .font(.system(size: SelectionLook.circle, weight: .regular))
        .frame(width: SelectionLook.circle, height: SelectionLook.circle)
        .accessibilityHidden(true)
    }
}

/// The header while a list selects (Mail's): All (None once every payment is ticked) on the left, the count in the
/// middle ("3 selected", "Select payments" at none), Done on the right, which ends selecting with nothing changed. The
/// back arrow, the gear and the back swipe wait until then. Words on the wall, as the header's buttons (brief 56). The
/// count changes at once as rows are ticked (brief 200: it rolled letter by letter for half a second and drifted
/// sideways as its width changed), also while a finger slides over the rows.
struct SelectionHeader: View {
    @Binding var selection: PaymentSelection?
    let store: DashboardStore
    let palette: Palette
    /// The selection last shown: while the header fades out after Done it keeps its words (brief 200: it showed "Select
    /// payments" for its last frames).
    @State private var lastShown: PaymentSelection?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let ticking = selection ?? lastShown ?? PaymentSelection(route: DashboardRoute(category: "", side: .expenses))
        let count = ticking.live(in: store).count
        HeaderLayout(spacing: 10) {
            HeaderWordButton(title: SelectionWording.allButton(allTicked: ticking.allTicked(in: store)),
                             bold: false, palette: palette) {
                selection?.toggleAll(in: store)
            }
            .accessibilityIdentifier("selectAll")
            Text(verbatim: SelectionWording.title(count)).font(AppFont.text(17, weight: .bold)).lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            HeaderWordButton(title: String(localized: "Done"), bold: true, palette: palette) {
                withAnimation(SelectionMotion.animation(reduceMotion: reduceMotion)) { selection = nil }
            }
            .accessibilityIdentifier("selectDone")
        }
        .padding(.horizontal, 14).padding(.top, 8).padding(.bottom, 10)
        // The words and the count's place follow the ticks at once, whatever transaction they come in.
        .transaction(value: count) { $0.animation = nil }
        .onChange(of: selection, initial: true) { _, now in if let now { lastShown = now } }
    }
}

/// A word in the header's row (All, Done): as tall as the header's buttons, tappable over 44 pt.
private struct HeaderWordButton: View {
    let title: String
    let bold: Bool
    let palette: Palette
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(verbatim: title).font(AppFont.text(16, weight: bold ? .bold : .medium))
                .foregroundStyle(palette.ink).lineLimit(1)
                .padding(.horizontal, 6)
                .frame(minWidth: HeaderButtonLook.side, minHeight: HeaderButtonLook.side)
                .contentShape(Rectangle())
                .minimumTapArea()
        }
        .buttonStyle(.plain)
    }
}

/// The bar at the bottom while selecting (Mail's toolbar in the app's card look): Category and Name, each its symbol
/// with its word under it, in ink, muted while off. Name shows the busy sign while it asks the store.
struct SelectionBar: View {
    let state: SelectionBarState
    /// Name is at work (it reads the shops' other payments, or saves).
    var naming = false
    let palette: Palette
    let category: () -> Void
    let name: () -> Void

    var body: some View {
        BottomBar(palette: palette) {
            BarItem(symbol: "square.grid.2x2", title: Text("Category"), enabled: state.category, palette: palette,
                    action: category)
                .accessibilityIdentifier("selectionCategory")
            if state.offersName {
                BarItem(symbol: "pencil", title: Text("Name"), enabled: state.name && !naming, busy: naming,
                        palette: palette, action: name)
                    .accessibilityIdentifier("selectionName")
            }
        }
    }
}

/// The app's bar at the bottom of a screen (Mail's toolbar in the app's card look): the selection's Category and Name
/// (brief 82), the quick sort's Undo and Skip (brief 99). Its items side by side on the card's colour laid over the
/// wall's (what scrolls under it never shows through), into the home indicator's area, with the line on top.
struct BottomBar<Content: View>: View {
    let palette: Palette
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 0) { content }
            .padding(.horizontal, 28).padding(.top, 7).padding(.bottom, 3)
            .frame(maxWidth: .infinity)
            .background {
                ZStack { palette.background; palette.card }
                    .overlay(alignment: .top) { Rectangle().fill(palette.line).frame(height: 1) }
                    .ignoresSafeArea(edges: .bottom)
            }
    }
}

/// One item of the bottom bar: its symbol with its word under it, in ink, muted while off; the busy sign in the symbol's
/// place while it works.
struct BarItem: View {
    let symbol: String
    let title: Text
    var enabled = true
    var busy = false
    let palette: Palette
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                ZStack {
                    if busy { ProgressView().controlSize(.small).tint(palette.secondary) }
                    else { Image(systemName: symbol).font(.system(size: 20, weight: .regular)) }
                }
                .frame(height: 24)
                title.font(AppFont.text(11, weight: .semibold)).lineLimit(1)
            }
            .foregroundStyle(enabled ? palette.ink : palette.muted)
            .frame(maxWidth: .infinity, minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

extension View {
    /// The selection's Name (brief 82): Apple's alert as New category's (a name's field, Cancel, and Rename as a plain
    /// button in the window's ink, not Apple's filled one, which iOS draws in the system blue), then the single rename's
    /// question about the shops' other payments.
    func selectionRenameAlerts(_ renaming: Binding<SelectionRename?>, palette: Palette) -> some View {
        modifier(SelectionRenameAlerts(renaming: renaming, palette: palette))
    }
}

private struct SelectionRenameAlerts: ViewModifier {
    @Binding var renaming: SelectionRename?
    let palette: Palette

    func body(content: Content) -> some View {
        // Read in the body, so the alert's buttons are built again as the name is typed: Rename follows the field.
        let canRename = renaming?.canRename == true
        content
            .alert(Text(verbatim: SelectionWording.nameTitle(renaming?.count ?? 0)),
                   isPresented: Binding(get: { renaming?.isAsking == true },
                                        set: { if !$0 { renaming?.isAsking = false } })) {
                TextField("Name", text: Binding(get: { renaming?.text ?? "" }, set: { renaming?.text = $0 }))
                    .textInputAutocapitalization(.sentences)
                    .submitLabel(.done)
                    .onSubmit { rename() }
                Button("Cancel", role: .cancel) { renaming = nil }
                Button("Rename") { rename() }
                    .disabled(!canRename)
            } message: {
                if let line = SelectionWording.keepShop(renaming?.skipped ?? 0) { Text(verbatim: line) }
            }
            .alert(Text(verbatim: renaming?.question?.title() ?? ""),
                   isPresented: Binding(get: { renaming?.question != nil }, set: { _ in }),
                   presenting: renaming?.question) { question in
                Button(question.allTitle()) { Task { await renaming?.answer(all: true) } }
                Button(question.onlyTitle(), role: .cancel) { Task { await renaming?.answer(all: false) } }
            } message: { question in
                Text(verbatim: question.message())
            }
            .tint(palette.ink)
    }

    /// Rename, or Return: the alert closes; a name that changes nothing closes it like Cancel.
    private func rename() {
        guard let model = renaming else { return }
        guard model.canRename else {
            renaming = nil
            return
        }
        Task { await model.rename() }
    }
}
