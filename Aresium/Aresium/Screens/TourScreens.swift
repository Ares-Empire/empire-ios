import SwiftUI
import UniformTypeIdentifiers

// The tour's look (the logic is `Model/TourModel.swift`). The real dashboard runs on the tour's made-up store; each
// step lays a light veil in the wall's colour over the screen (the app stays easy to read under it, Patrik 2026-10-27),
// leaves the control it points at clear at full strength with an ink ring (anchor preferences, so the ring follows the
// control), and shows one card in Aresium's glass at the bottom: the step, one sentence, Next, End tour. Ink only.
// Reduce Motion: nothing moves, the ring and the card change in place.

// MARK: - the tour in the environment

extension EnvironmentValues {
    /// The tour the screens run in; nil in the person's own app (the anchors, veil and card then do nothing). The shared
    /// pieces (`Shared/Design/TourPieces.swift`) see it as the `tourGuide`.
    var tour: TourModel? {
        get { tourGuide as? TourModel }
        set { tourGuide = newValue }
    }
}

/// What the shared veil, ring and scrolling read: the control the step points at, and whether taps off it stop.
extension TourModel: TourGuide {
    var spots: [AnyHashable] { target.map { [AnyHashable($0)] } ?? [] }
    var holdsTheRest: Bool { step.holdsTheRest }
}

extension View {
    /// Marks a real control the tour may point at (nothing outside the tour). nil marks nothing: a control on a page
    /// out of sight (the start screen's other page, brief 56), so the ring finds the one in view.
    func tourAnchor(_ target: TourTarget?) -> some View { tourSpot(target.map(AnyHashable.init)) }

    /// The tour's card at the bottom of a screen or sheet; the content keeps the space above it.
    func tourCard() -> some View { modifier(TourCardInset()) }
}

private struct TourCardInset: ViewModifier {
    @Environment(\.tour) private var tour

    func body(content: Content) -> some View {
        if let tour, tour.phase == .running {
            content.safeAreaInset(edge: .bottom, spacing: 0) { AresiumTourCard(tour: tour) }
        } else {
            content
        }
    }
}

// MARK: - the card

/// The step's card (`TourCard`, shared): "Tour · 3 of 18" (of the steps this tour shows), the sentence, Next (ink, the
/// main button's look) and End tour; at the import step a link to the bank guide, at the last step one button that ends
/// the tour.
private struct AresiumTourCard: View {
    let tour: TourModel

    var body: some View {
        TourCard(count: String(localized: "Tour · \(tour.number) of \(tour.count)"), text: Text(tour.text),
                 step: tour.step, leave: tour.nextStep != nil ? Text("End tour") : nil,
                 main: tour.nextStep == nil ? Text("End tour") : Text("Next"),
                 onLeave: { tour.end() }, onMain: { tour.next() }) {
            if tour.step == .importFiles {
                GuideLink { tour.showsGuide = true }
            }
        }
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
                // The graph as the person's settings were when the tour started (`TourModel.showsGraph`, `graphMoves`).
                // The back swipe and the rows' shortcuts are off while the tour holds the screen; at its swipe steps
                // the rows' swipe and long press work on the ringed row (`TourModel.rowShortcuts`).
                DashboardStack(store: world.dashboard, palette: palette, place: place, graph: tour.showsGraph,
                               graphMoves: tour.graphMoves, band: band, shortcuts: !tour.holdsTheScreen,
                               rowShortcuts: tour.rowShortcuts) { route in
                    header(route) { tour.openSettings() }
                } root: {
                    StartScreen(store: world.dashboard, palette: palette, current: place.current, side: place.side,
                                graph: tour.showsGraph, graphMoves: tour.graphMoves, band: band,
                                openDay: { place.wrappedValue.day = $0 }) {
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

/// The tour's Settings: the person's Settings sections the tour points at, in the order the real Settings has them
/// (`ContentView`'s sheet: Your data on this iPhone, Messages, Lock, Dashboard, then Help), so what the tour shows is
/// where things are. Categories opens the picker on the made-up store; every other row is a picture of the tour's own
/// state that only points and goes on (`TourModel.settingsRowTapped`): no setting changes, no lock is set, no message is
/// planned and iOS is never asked, no form opens, nothing is sent. The rest of Settings belongs to the person's own app
/// and is not part of the tour.
private struct TourSettingsSheet: View {
    let tour: TourModel
    let world: TourWorld
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    data
                    messages
                    lock
                    dashboard
                    SettingsSection(String(localized: LocalizedStringResource("Help", table: "Shared",
                                                                              locale: .appLanguage))) {
                        Button { tour.settingsRowTapped(.contactRow) } label: {
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
            // The card on the list itself (and on the picker pushed from it), above the veil: there its inset is room to
            // scroll, so the last sections rise above it (on the NavigationStack the list ran on under the card, and
            // Contact & support could not be reached).
            .tourCard()
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
                .tourCard()
            }
        }
        .tint(Ink.primary)
        // The pictures' switches as Settings draws them (`SettingsScreen` gives its own the same style).
        .toggleStyle(EmpireSwitchStyle())
        .presentationBackground(Ink.background)
    }

    /// Your data on this iPhone: Categories (the picker, on the made-up store) and Own names, a picture of the tour's
    /// own setting (`OwnNamesRow`, the person's Settings' row). One ring around both.
    private var data: some View {
        SettingsSection(String(localized: "Your data on this iPhone")) {
            VStack(spacing: 0) {
                Button { tour.setCategoriesShown(true) } label: {
                    SettingsRow(title: String(localized: "Categories"),
                                value: String(world.phone.summary.chosen.count))
                }
                .buttonStyle(SettingsRowStyle())
                SettingsDivider()
                Button { tour.settingsRowTapped(.dataRows) } label: {
                    OwnNamesRow(isOn: .constant(world.dashboard.ownNames)).allowsHitTesting(false)
                        .contentShape(Rectangle())
                }
                .buttonStyle(SettingsRowStyle())
            }
            .tourAnchor(.dataRows)
        }
    }

    /// Messages (brief 46) as the person's Settings shows it while they are off: its one row, "Off". It opens no page and
    /// never asks iOS.
    private var messages: some View {
        SettingsSection(String(localized: "Messages")) {
            Button { tour.settingsRowTapped(.messagesRow) } label: {
                SettingsRow(title: String(localized: "Reminder and review"),
                            value: MessageWording.state(MessagePreferences(), authorization: .notAsked))
            }
            .buttonStyle(SettingsRowStyle())
            .tourAnchor(.messagesRow)
        }
    }

    /// The Lock section as the person's Settings shows it with no lock set (`LockSettingsSection`): the Face ID switch
    /// off and Own code off. One button over both rows: in the tour it only answers its step; the switch is a picture
    /// (it takes no taps) and never asks for Face ID.
    private var lock: some View {
        SettingsSection(String(localized: "Lock")) {
            Button { tour.settingsRowTapped(.lockRow) } label: {
                VStack(spacing: 0) {
                    Toggle(isOn: .constant(false)) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Lock with Face ID").font(AppFont.text(15, weight: .medium)).foregroundStyle(Ink.primary)
                            Text("Or the iPhone's code").font(AppFont.text(12)).foregroundStyle(Ink.muted)
                        }
                    }
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

    /// Settings → Dashboard (`DashboardSettingsRows`, the person's Settings' rows) as a picture of the tour's own state:
    /// the graph and its moving away as they were when the tour started (`TourModel.showsGraph`, `graphMoves`), Add up
    /// same names as the tour's own choices have it. One button over all: it only answers its step.
    private var dashboard: some View {
        SettingsSection(String(localized: "Dashboard")) {
            Button { tour.settingsRowTapped(.dashboardRows) } label: {
                VStack(spacing: 0) {
                    DashboardSettingsRows(showsGraph: .constant(tour.showsGraph), graphMoves: .constant(tour.graphMoves),
                                          sumsEverywhere: .constant(world.dashboard.sums.choices.everywhere))
                        .allowsHitTesting(false)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(SettingsRowStyle())
            .tourAnchor(.dashboardRows)
        }
    }
}
