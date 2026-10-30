import SwiftUI
import UniformTypeIdentifiers

// The tour's look (the logic is `Model/TourModel.swift`). The real dashboard runs on the tour's made-up store; each
// step lays a light veil in the wall's colour over the screen (the app stays easy to read under it, Patrik 2026-10-27),
// leaves the control it points at clear at full strength with an ink ring (anchor preferences, so the ring follows the
// control), and shows one card in Aresium's glass at the bottom: the step, one sentence, Next, End tour. Ink only.
// Reduce Motion: nothing moves, the ring and the card change in place.

// MARK: - the tour in the environment

private struct TourKey: EnvironmentKey {
    static let defaultValue: TourModel? = nil
}

extension EnvironmentValues {
    /// The tour the screens run in; nil in the person's own app (the anchors, veil and card then do nothing).
    var tour: TourModel? {
        get { self[TourKey.self] }
        set { self[TourKey.self] = newValue }
    }
}

/// Where the real controls are, for the veil: each one the tour may point at marks itself.
private struct TourAnchorKey: PreferenceKey {
    static let defaultValue: [TourTarget: Anchor<CGRect>] = [:]
    static func reduce(value: inout [TourTarget: Anchor<CGRect>], nextValue: () -> [TourTarget: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, new in new }
    }
}

/// Which of those controls are on screen, so a scroll view can bring one into view once it appears.
private struct TourPresentKey: PreferenceKey {
    static let defaultValue: Set<TourTarget> = []
    static func reduce(value: inout Set<TourTarget>, nextValue: () -> Set<TourTarget>) { value.formUnion(nextValue()) }
}

extension View {
    /// Marks a real control the tour may point at (nothing outside the tour).
    func tourAnchor(_ target: TourTarget) -> some View { modifier(TourAnchorMark(target: target)) }

    /// The veil and ring over a screen, around the control the tour points at when it is on this screen. Put it on each
    /// screen's root (pushed screens and sheets have their own).
    func tourSpotlight() -> some View { modifier(TourSpotlight()) }

    /// The tour's card at the bottom of a screen or sheet; the content keeps the space above it.
    func tourCard() -> some View { modifier(TourCardInset()) }

    /// On a scroll view: the control the tour points at scrolls into view above the card (the largest text sizes).
    func tourScrollsToTarget() -> some View { modifier(TourScrollToTarget()) }
}

private struct TourAnchorMark: ViewModifier {
    let target: TourTarget
    @Environment(\.tour) private var tour

    func body(content: Content) -> some View {
        if tour != nil {
            // The id lets a scroll view bring it into view (`tourScrollsToTarget`).
            content.anchorPreference(key: TourAnchorKey.self, value: .bounds) { [target: $0] }
                .preference(key: TourPresentKey.self, value: [target])
                .id(target)
        } else {
            content
        }
    }
}

private struct TourScrollToTarget: ViewModifier {
    @Environment(\.tour) private var tour
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The tour's controls inside this scroll view now (a payment's Change appears once its detail has loaded).
    @State private var present: Set<TourTarget> = []

    func body(content: Content) -> some View {
        if let tour {
            ScrollViewReader { proxy in
                content
                    .onPreferenceChange(TourPresentKey.self) { present = $0 }
                    .task(id: tour.target.map { present.contains($0) ? $0 : nil }) {
                        guard let target = tour.target, present.contains(target) else { return }
                        // After the screen is laid out: the control a third of the way down, above the card. One that
                        // shows already moves only a little.
                        try? await Task.sleep(for: .milliseconds(200))
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) {
                            proxy.scrollTo(target, anchor: UnitPoint(x: 0.5, y: 0.3))
                        }
                    }
            }
        } else {
            content
        }
    }
}

private struct TourSpotlight: ViewModifier {
    @Environment(\.tour) private var tour
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if let tour {
            content.overlayPreferenceValue(TourAnchorKey.self) { anchors in
                GeometryReader { proxy in
                    if let target = tour.target, let anchor = anchors[target] {
                        // The ring glides to the next control when the step changes (not with Reduce Motion); while
                        // the screen scrolls it stays on its control without lagging.
                        TourVeil(hole: proxy[anchor], bounds: CGRect(origin: .zero, size: proxy.size),
                                 holdsTheRest: tour.step.holdsTheRest)
                            .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: target)
                            .transition(.opacity)
                    }
                }
                .ignoresSafeArea(edges: .top)
                .animation(.easeInOut(duration: 0.2), value: tour.target)
            }
        } else {
            content
        }
    }
}

/// The wall's colour laid lightly over the screen, with the control left clear and ringed in ink. Taps on the rest stop
/// here (`holdsTheRest`), taps on the control go through.
private struct TourVeil: View {
    let hole: CGRect
    /// The screen's frame: the ring stays a little inside it (a full-width row).
    let bounds: CGRect
    let holdsTheRest: Bool
    private static let margin: CGFloat = 6
    private static let radius: CGFloat = 14
    /// How much of the wall lies over the rest of the screen: enough to set the control apart, little enough that the
    /// app under it reads easily (brief 24 had 0.74; tuned by eye in light and dark, 2026-10-27).
    static let veil: Double = 0.3

    var body: some View {
        let around = hole.insetBy(dx: -Self.margin, dy: -Self.margin)
        let inside = around.intersection(bounds.insetBy(dx: 4, dy: 0))
        let clear = inside.isNull ? around : inside
        let shape = VeilShape(hole: clear, radius: Self.radius)
        ZStack {
            shape.fill(Ink.background.opacity(Self.veil), style: FillStyle(eoFill: true))
            // With the lighter veil the ring does the setting apart: full ink, a little thicker.
            RoundedRectangle(cornerRadius: Self.radius, style: .continuous)
                .strokeBorder(Ink.primary, lineWidth: 2)
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

private struct TourCardInset: ViewModifier {
    @Environment(\.tour) private var tour

    func body(content: Content) -> some View {
        if let tour, tour.phase == .running {
            content.safeAreaInset(edge: .bottom, spacing: 0) { TourCard(tour: tour) }
        } else {
            content
        }
    }
}

// MARK: - the card

/// The step's card: "Tour · 3 of 12" (of the steps this tour shows), the sentence, Next (ink, the main button's look) and End tour; at the
/// import step a link to the bank guide, at the last step one button that ends the tour.
private struct TourCard: View {
    let tour: TourModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AccessibilityFocusState private var focused: Bool

    var body: some View {
        let step = tour.step
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                SectionHeading(text: String(localized: "Tour · \(tour.number) of \(tour.count)"))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if tour.nextStep != nil {
                    Button { tour.end() } label: {
                        Text("End tour").font(AppFont.text(13.5, weight: .semibold)).foregroundStyle(Ink.secondary)
                            .multilineTextAlignment(.trailing)
                            .frame(minHeight: 32).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            Text(step.text())
                .font(AppFont.text(16, weight: .semibold)).foregroundStyle(Ink.primary)
                .lineSpacing(2).fixedSize(horizontal: false, vertical: true)
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
        .glassCard(raised: true)
        // The largest text sizes: the card grows up to the first accessibility size, so the control it points at
        // keeps room above it.
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

    @ViewBuilder private var link: some View {
        if tour.step == .importFiles {
            GuideLink { tour.showsGuide = true }
        }
    }

    /// Next, or at the last step the one button that ends the tour. Ink filled, the words in the wall's colour (the
    /// first screen's Import data).
    private var mainButton: some View {
        Button {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) { tour.next() }
        } label: {
            (tour.nextStep == nil ? Text("End tour") : Text("Next"))
                .font(AppFont.text(15, weight: .semibold)).foregroundStyle(Ink.background)
                .padding(.horizontal, 22).frame(minHeight: 44)
                .background(Ink.primary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - the tour's screen

/// The tour in place of the dashboard: a calm state while the made-up store is filled, then the real dashboard on it,
/// with the tour's Settings and the bank guide as its sheets.
struct TourScreen<Header: View>: View {
    let tour: TourModel
    let palette: Palette
    let band: AresiumBand
    /// The app's header for a screen of the tour, with the tour's own Settings behind the gear.
    @ViewBuilder let header: (DashboardRoute?, _ openSettings: @escaping () -> Void) -> Header
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if tour.phase == .running, let world = tour.world {
                // The graph as the person's setting was when the tour started (`TourModel.showsGraph`).
                DashboardStack(store: world.dashboard, palette: palette, place: place, graph: tour.showsGraph,
                               band: band, shortcuts: !tour.holdsTheScreen) { route in
                    header(route) { tour.openSettings() }
                } root: {
                    StartScreen(store: world.dashboard, imports: world.imports, palette: palette,
                                current: place.current, side: place.side, graph: tour.showsGraph, band: band,
                                importChoices: .tour { tour.importTapped() }) {
                        place.wrappedValue.path.append($0)
                    }
                }
                .tourCard()
            } else {
                VStack(spacing: 0) {
                    header(nil) {}
                    state
                }
            }
        }
        .environment(\.tour, tour)
        .sheet(isPresented: Binding(get: { tour.showsSettings }, set: { if !$0 { tour.closeSettings() } })) {
            if let world = tour.world { TourSettingsSheet(tour: tour, world: world).environment(\.tour, tour) }
        }
        .sheet(isPresented: Binding(get: { tour.showsGuide }, set: { tour.showsGuide = $0 })) {
            // Nothing real happens in the tour: no Choose file, no bank's name sent.
            BankGuideSheet(importing: nil, outbox: nil).environment(\.tour, tour)
        }
    }

    /// The tour's place, moved through the model so the step sees what the person did.
    private var place: Binding<DashboardPlace> {
        Binding(get: { tour.place }, set: { tour.update($0) })
    }

    /// Filling the made-up store (a moment), or it could not be made.
    private var state: some View {
        VStack(spacing: 0) {
            Spacer()
            if case .failed = tour.phase {
                Text("The tour could not start.").font(AppFont.text(17, weight: .semibold)).foregroundStyle(palette.ink)
                    .multilineTextAlignment(.center)
            } else {
                ProgressView().tint(palette.secondary)
                Text("Making up sample data…").font(AppFont.text(14)).foregroundStyle(palette.secondary)
                    .multilineTextAlignment(.center).padding(.top, 14)
            }
            Spacer()
            Button { tour.end() } label: {
                Text("End tour").font(AppFont.text(15, weight: .semibold)).foregroundStyle(palette.ink)
                    .padding(.horizontal, 24).frame(minHeight: 44)
                    .background(palette.card, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(palette.line))
                    .contentShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .padding(.bottom, 30)
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The tour's Settings: "Your data on this iPhone → Categories" on the made-up store, and the Lock section and Contact &
/// support as the person's own Settings show them. Those two only point and go on (`TourModel.lockTapped`,
/// `contactTapped`): no lock is set, no form opens, nothing is sent. The rest of Settings belongs to the person's own
/// app and is not part of the tour.
private struct TourSettingsSheet: View {
    let tour: TourModel
    let world: TourWorld
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    SettingsSection(String(localized: "Your data on this iPhone")) {
                        Button { tour.setCategoriesShown(true) } label: {
                            SettingsRow(title: String(localized: "Categories"),
                                        value: String(world.phone.summary.chosen.count))
                        }
                        .buttonStyle(SettingsRowStyle())
                        .tourAnchor(.categoriesRow)
                    }
                    lock
                    SettingsSection(String(localized: LocalizedStringResource("Help", table: "Shared",
                                                                              locale: .appLanguage))) {
                        Button { tour.contactTapped() } label: {
                            SettingsRow(title: String(localized: LocalizedStringResource("Contact & support",
                                                                                         table: "Shared",
                                                                                         locale: .appLanguage)))
                        }
                        .buttonStyle(SettingsRowStyle())
                        .tourAnchor(.contactRow)
                    }
                    FormNote(text: String(localized: "In the tour, Settings shows only these rows, and they change nothing."))
                        .padding(.top, 10)
                }
                .padding(.horizontal, 18).padding(.bottom, 34)
            }
            .scrollIndicators(.hidden)
            .tourScrollsToTarget()
            .background { Ink.background.ignoresSafeArea() }
            .tourSpotlight()
            .navigationTitle(Text("Settings", tableName: "Shared"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Text("Done", tableName: "Shared") }
                }
            }
            .navigationDestination(isPresented: Binding(get: { tour.showsCategories },
                                                        set: { tour.setCategoriesShown($0) })) {
                CategoryPickerScreen(model: CategoryPickerModel(phone: world.phone) {
                    await world.dashboard.reloadAfterTransactionChange()
                })
            }
        }
        .tint(Ink.primary)
        .presentationBackground(Ink.background)
        .tourCard()
    }

    /// The Lock section as the person's Settings shows it with no lock set (`LockSettingsSection`): the Face ID switch
    /// off and Own code off. One button over both rows: in the tour it only answers its step; the switch is a picture
    /// (it takes no taps) and never asks for Face ID.
    private var lock: some View {
        SettingsSection(String(localized: "Lock")) {
            Button { tour.lockTapped() } label: {
                VStack(spacing: 0) {
                    Toggle(isOn: .constant(false)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Lock with Face ID").font(AppFont.text(15, weight: .medium)).foregroundStyle(Ink.primary)
                            Text("Or the iPhone's code").font(AppFont.text(12)).foregroundStyle(Ink.muted)
                        }
                    }
                    .toggleStyle(EmpireSwitchStyle())
                    .allowsHitTesting(false)
                    .padding(.horizontal, 16).frame(minHeight: 58)
                    SettingsDivider()
                    SettingsRow(title: String(localized: "Own code"), value: String(localized: "Off"))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(SettingsRowStyle())
            .tourAnchor(.lockRow)
        }
    }
}
