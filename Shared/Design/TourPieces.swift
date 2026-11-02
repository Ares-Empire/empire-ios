import SwiftUI

// The pieces every app's tour shares (Aresium's since brief 24, Arestemis's since brief 139; moved here from Aresium's
// `TourScreens.swift` unchanged in look): a tour runs over the app's real screens, each control it may point at marks
// itself (`tourSpot`), each screen and sheet lays a light veil in the wall's colour over itself with the control left
// clear and ringed (`tourSpotlight`), a scroll view brings the control into view above the card
// (`tourScrollsToTarget`), and one card at the bottom says the step (`TourCard`). What the steps are, where they point
// and what moves them on is each app's own (`TourGuide`). Reduce Motion: the ring jumps, nothing slides.

/// A tour running over an app's real screens, as the shared pieces see it.
@MainActor protocol TourGuide: AnyObject {
    /// What the tour points at now, as the controls marked themselves (`tourSpot`): one control, or a few that stand
    /// together, which one ring goes around. Empty: nothing; the screen is free and has no veil.
    var spots: [AnyHashable] { get }
    /// While it points at something, taps on the rest of the screen stop at the veil; the control itself takes them.
    var holdsTheRest: Bool { get }
    /// The ring's colour: ink in an ink-only app, else the app's accent.
    var ring: Color { get }
    /// The app's pages keep the card's room in their safe area (Arestemis), so a scroll view shows a control when it
    /// lies in the scroll view's safe area; false: in its upper part (`TourScrollPlace.shownPart`, Aresium).
    var cardRoomInSafeArea: Bool { get }
}

extension TourGuide {
    var ring: Color { Ink.primary }
    var cardRoomInSafeArea: Bool { false }
}

extension EnvironmentValues {
    /// The tour the screens run in; nil outside a tour (the marks, veil and scrolling then do nothing).
    @Entry var tourGuide: (any TourGuide)? = nil
}

/// Where the real controls are, for the veil: each one the tour may point at marks itself.
private struct TourAnchorKey: PreferenceKey {
    static let defaultValue: [AnyHashable: Anchor<CGRect>] = [:]
    static func reduce(value: inout [AnyHashable: Anchor<CGRect>], nextValue: () -> [AnyHashable: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// Which of those controls are on screen, so a scroll view can bring one into view once it appears.
private struct TourPresentKey: PreferenceKey {
    static let defaultValue: Set<AnyHashable> = []
    static func reduce(value: inout Set<AnyHashable>, nextValue: () -> Set<AnyHashable>) { value.formUnion(nextValue()) }
}

extension View {
    /// Marks a real control the tour may point at (nothing outside a tour). nil marks nothing (a control out of sight
    /// that has a twin in view). Each app wraps it with its own type of spots (`tourAnchor`).
    func tourSpot(_ spot: AnyHashable?) -> some View { modifier(TourSpotMark(spot: spot)) }

    /// The veil and ring over a screen, around the control the tour points at when it is on this screen. Put it on each
    /// screen's root (pushed screens and sheets have their own).
    func tourSpotlight() -> some View { modifier(TourSpotlightOverlay()) }

    /// On a scroll view: the control the tour points at scrolls into view above the card (the largest text sizes).
    func tourScrollsToTarget() -> some View { modifier(TourScrollToTarget()) }
}

private struct TourSpotMark: ViewModifier {
    let spot: AnyHashable?
    @Environment(\.tourGuide) private var guide

    func body(content: Content) -> some View {
        if guide != nil, let spot {
            // The id lets a scroll view bring it into view (`tourScrollsToTarget`).
            content.anchorPreference(key: TourAnchorKey.self, value: .bounds) { [spot: $0] }
                .preference(key: TourPresentKey.self, value: [spot])
                .id(spot)
        } else {
            content
        }
    }
}

private struct TourScrollToTarget: ViewModifier {
    @Environment(\.tourGuide) private var guide
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The tour's controls inside this scroll view now (a payment's Change appears once its detail has loaded).
    @State private var present: Set<AnyHashable> = []
    /// Where the controls pointed at are in the scroll view now, and the scroll view's height.
    @State private var place: TourScrollPlace?

    func body(content: Content) -> some View {
        if let guide {
            ScrollViewReader { proxy in
                content
                    .onPreferenceChange(TourPresentKey.self) { present = $0 }
                    .overlayPreferenceValue(TourAnchorKey.self) { anchors in
                        GeometryReader { geometry in
                            let frames = guide.spots.compactMap { anchors[$0] }.map { geometry[$0] }
                            // The reader's space is the scroll view's safe area, as `scrollTo`'s anchors are.
                            let visible = guide.cardRoomInSafeArea ? 0...geometry.size.height : nil
                            Color.clear
                                .onChange(of: TourScrollPlace(frames: frames, height: geometry.size.height,
                                                              visible: visible),
                                          initial: true) { _, value in place = value }
                                .allowsHitTesting(false)
                        }
                        .accessibilityHidden(true)
                    }
                    // Where the card's room is in the safe area (Arestemis), again once the scroll view's height has
                    // settled (the card's room arrives a moment after the tour's first screen).
                    .task(id: ScrollTask(spot: guide.spots.first { present.contains($0) },
                                         height: guide.cardRoomInSafeArea ? place?.height : nil)) {
                        // The first of the controls (the top one when the ring goes around several).
                        guard let spot = guide.spots.first(where: { present.contains($0) }) else { return }
                        // After the screen is laid out: as far as it takes to show the control above the card, and not
                        // at all when it shows there already.
                        try? await Task.sleep(for: .milliseconds(200))
                        // Within the safe area, a newer layout (its own task) scrolls instead.
                        if guide.cardRoomInSafeArea && Task.isCancelled { return }
                        let anchor: UnitPoint
                        if let place {
                            guard let needed = place.scrollAnchor else { return }
                            anchor = needed
                        } else {
                            anchor = TourScrollPlace.unknown
                        }
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) {
                            proxy.scrollTo(spot, anchor: anchor)
                        }
                    }
            }
        } else {
            content
        }
    }
}

/// What starts a scroll to the control pointed at: it shows up, or (`TourGuide.cardRoomInSafeArea`) the scroll view's
/// height changes.
private struct ScrollTask: Equatable {
    let spot: AnyHashable?
    let height: CGFloat?
}

/// Where a control the tour points at is in its scroll view, and how far to scroll to show it (Aresium's brief 59: only
/// as far as it takes, so a start page's moving graph does not go half away for a category row that nearly showed).
nonisolated struct TourScrollPlace: Equatable {
    /// The control, or the controls one ring goes around together.
    let frame: CGRect
    let height: CGFloat
    /// When the ring goes around several controls: the first of them, which the scroll view moves by its id.
    var first: CGRect? = nil
    /// The scroll view's safe area (in the space `frame` is measured in, as `scrollTo`'s anchors are), when the card's
    /// room is in it (`TourGuide.cardRoomInSafeArea`): a control shows when it lies inside, a little in from its edges.
    /// nil: the upper `shownPart` of the scroll view.
    var visible: ClosedRange<CGFloat>? = nil

    /// The upper part of the scroll view, above where the tour's card lies: a control wholly inside it shows.
    static let shownPart: CGFloat = 0.6
    /// A control not laid out yet (far down a lazy list): a third of the way down, as before.
    static let unknown = UnitPoint(x: 0.5, y: 0.3)

    /// How far in from the safe area's edges a control counts as shown, and is brought to.
    static let margin: CGFloat = 12

    init(frame: CGRect, height: CGFloat, first: CGRect? = nil, visible: ClosedRange<CGFloat>? = nil) {
        self.frame = frame
        self.height = height
        self.first = first
        self.visible = visible
    }

    /// The controls' frames as they lie in the scroll view; nil when none is laid out.
    init?(frames: [CGRect], height: CGFloat, visible: ClosedRange<CGFloat>? = nil) {
        guard let first = frames.first else { return nil }
        let all = frames.dropFirst().reduce(first) { $0.union($1) }
        self.init(frame: all, height: height, first: frames.count > 1 ? first : nil, visible: visible)
    }

    /// nil when the control shows already; else the anchor that brings its lower edge to the shown part's end (its top
    /// edge to the top when it is taller than that).
    var scrollAnchor: UnitPoint? {
        if let visible { return anchor(within: visible) }
        let limit = height * Self.shownPart
        if frame.minY >= 0 && frame.maxY <= limit { return nil }
        guard let first else {
            guard height > frame.height else { return UnitPoint(x: 0.5, y: 0) }
            let y = (limit - frame.height) / (height - frame.height)
            return UnitPoint(x: 0.5, y: min(1, max(0, y)))
        }
        // Several: the first moves by as much as the whole group must, so the group's lower edge comes to the shown
        // part's end (its top edge to the top when it is taller than that). An anchor's y puts the first control's top
        // at y × (height − its height).
        let shift = frame.height > limit ? frame.minY : frame.maxY - limit
        guard height > first.height else { return UnitPoint(x: 0.5, y: 0) }
        let y = (first.minY - shift) / (height - first.height)
        return UnitPoint(x: 0.5, y: min(1, max(0, y)))
    }

    /// Within the safe area: as far as it takes, a control below the shown part up until its lower edge is a margin above
    /// the safe area's end, one above it (or taller than the room) down until its top edge is a margin under the start.
    /// The anchor's y puts the moved control's top at the safe area's start + y × (its height − the control's), as a
    /// scroll view places it.
    private func anchor(within visible: ClosedRange<CGFloat>) -> UnitPoint? {
        let top = visible.lowerBound + Self.margin
        let bottom = visible.upperBound - Self.margin
        let tall = frame.height > bottom - top
        if frame.minY >= top && frame.maxY <= bottom { return nil }
        // Taller than the room and its top where it should be: as shown as it gets.
        if tall && abs(frame.minY - top) < 1 { return nil }
        let shift = tall || frame.minY < top ? frame.minY - top : frame.maxY - bottom
        let moved = first ?? frame
        let room = visible.upperBound - visible.lowerBound - moved.height
        guard room > 0 else { return UnitPoint(x: 0.5, y: 0) }
        let y = (moved.minY - shift - visible.lowerBound) / room
        return UnitPoint(x: 0.5, y: min(1, max(0, y)))
    }
}

private struct TourSpotlightOverlay: ViewModifier {
    @Environment(\.tourGuide) private var guide
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if let guide {
            content.overlayPreferenceValue(TourAnchorKey.self) { anchors in
                GeometryReader { proxy in
                    let rects = guide.spots.compactMap { anchors[$0] }.map { proxy[$0] }
                    if let first = rects.first {
                        // The ring glides to the next control when the step changes (not with Reduce Motion); while
                        // the screen scrolls it stays on its control without lagging.
                        TourVeil(hole: rects.dropFirst().reduce(first) { $0.union($1) },
                                 bounds: CGRect(origin: .zero, size: proxy.size),
                                 holdsTheRest: guide.holdsTheRest, ring: guide.ring)
                            .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: guide.spots)
                            .transition(.opacity)
                    }
                }
                .ignoresSafeArea(edges: .top)
                .animation(.easeInOut(duration: 0.2), value: guide.spots)
            }
        } else {
            content
        }
    }
}

/// The wall's colour laid lightly over the screen, with the control left clear and ringed. Taps on the rest stop here
/// (`holdsTheRest`), taps on the control go through.
private struct TourVeil: View {
    let hole: CGRect
    /// The screen's frame: the ring stays a little inside it (a full-width row).
    let bounds: CGRect
    let holdsTheRest: Bool
    let ring: Color
    private static let margin: CGFloat = 6
    private static let radius: CGFloat = 14
    /// How much of the wall lies over the rest of the screen: enough to set the control apart, little enough that the
    /// app under it reads easily (Aresium's brief 24 had 0.74; tuned by eye in light and dark, 2026-10-27).
    static let veil: Double = 0.3

    var body: some View {
        let around = hole.insetBy(dx: -Self.margin, dy: -Self.margin)
        let inside = around.intersection(bounds.insetBy(dx: 4, dy: 0))
        let clear = inside.isNull ? around : inside
        let shape = VeilShape(hole: clear, radius: Self.radius)
        ZStack {
            shape.fill(Ink.background.opacity(Self.veil), style: FillStyle(eoFill: true))
            // With the lighter veil the ring does the setting apart: full strength, a little thicker.
            RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
                .strokeBorder(ring, lineWidth: 2)
                .frame(width: clear.width, height: clear.height)
                .position(x: clear.midX, y: clear.midY)
                .allowsHitTesting(false)
        }
        .contentShape(shape, eoFill: true)
        .allowsHitTesting(holdsTheRest)
        .accessibilityHidden(true)
    }
}

/// The whole frame with a rounded hole.
private nonisolated struct VeilShape: Shape {
    var hole: CGRect
    let radius: CGFloat

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get { AnimatablePair(AnimatablePair(hole.origin.x, hole.origin.y), AnimatablePair(hole.width, hole.height)) }
        set { hole = CGRect(x: newValue.first.first, y: newValue.first.second, width: newValue.second.first,
                            height: newValue.second.second) }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path(rect.insetBy(dx: -400, dy: -400))
        path.addRoundedRect(in: hole, cornerSize: CGSize(width: radius, height: radius), style: .continuous)
        return path
    }
}

// MARK: - the card

/// A tour's card at the bottom of a screen or sheet, in the glass of the app: which step of how many (a quiet heading),
/// the way out at the top right (End tour, Skip; none at the last step, where the main button ends the tour), the step's
/// title if the app gives one, its words, and the main button (Next, or the one that ends the tour) filled in ink or the
/// app's accent; `link` is an optional quiet action left of it (Aresium's bank guide at its import step). The words are
/// the app's. VoiceOver: the card takes the focus at each step. The largest text sizes: the card grows up to the first
/// accessibility size, so the control it points at keeps room above it.
struct TourCard<Link: View>: View {
    /// "Tour · 3 of 22", "3 / 8".
    let count: String
    /// The step's title (Arestemis); nil: the words alone, larger (Aresium).
    var title: String? = nil
    let text: Text
    /// The step shown: its words fade and the focus moves when it changes.
    let step: AnyHashable
    /// The way out (End tour, Skip); nil at the last step.
    let leave: Text?
    /// Next, or at the last step the button that ends the tour.
    let main: Text
    /// The main button's fill and words: ink and the wall's colour (Aresium's first screen's Import data), or the
    /// app's accent and the words for it.
    var mainFill: Color = Ink.primary
    var mainInk: Color = Ink.background
    /// false: the card's glass without its blur (`GlassCard.blur`), where something moves under the card (Arestemis's
    /// pulsing searches): a blur would be taken again in every frame.
    var blur = true
    let onLeave: () -> Void
    let onMain: () -> Void
    @ViewBuilder let link: Link
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AccessibilityFocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                SectionHeading(text: count)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if let leave {
                    Button { onLeave() } label: {
                        leave.font(AppFont.text(13.5, weight: .semibold)).foregroundStyle(Ink.secondary)
                            .multilineTextAlignment(.trailing)
                            .frame(minHeight: 32).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            words
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityFocused($focused)
                .id(step)
                .transition(.opacity)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) {
                    link
                    Spacer(minLength: 0)
                    mainButton
                }
                VStack(alignment: .leading, spacing: 10) {
                    link
                    mainButton
                }
            }
        }
        .padding(16)
        .glassCard(raised: true, blur: blur)
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 6)
        .background {
            // The screen fades into the wall under the card, as under a bar, so no row shows half beneath it.
            LinearGradient(stops: [.init(color: Ink.background.opacity(0), location: 0),
                                   .init(color: Ink.background.opacity(0.9), location: 0.45)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .bottom)
                .allowsHitTesting(false)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: step)
        .accessibilityElement(children: .contain)
        .onChange(of: step, initial: true) { _, _ in focused = true }
    }

    /// The words alone (Aresium: one sentence, large), or a title over quieter words (Arestemis).
    @ViewBuilder private var words: some View {
        if let title {
            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(AppFont.text(17, weight: .semibold)).foregroundStyle(Ink.primary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                text
                    .font(AppFont.text(14.5)).foregroundStyle(Ink.secondary)
                    .lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
        } else {
            text
                .font(AppFont.text(16, weight: .semibold)).foregroundStyle(Ink.primary)
                .lineSpacing(2).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var mainButton: some View {
        Button {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) { onMain() }
        } label: {
            main
                .font(AppFont.text(15, weight: .semibold)).foregroundStyle(mainInk)
                .padding(.horizontal, 22).frame(minHeight: 44)
                .background(mainFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
