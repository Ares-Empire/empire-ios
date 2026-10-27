import Foundation

// The first screen (brief 25, Patrik 2026-10-27): while phone mode has no data, Aresium shows a clear empty state ("No
// data yet", Import data, Start tour) instead of the dashboard, and it comes back after the tour as long as there is no
// data, so the tour's made-up data is never seen outside the tour. `MainScreen` decides what shows. Import data opens
// the file picker at once (brief 27, Patrik 2026-10-27: the file first); the category picker follows an import that
// added payments while none is chosen (`ImportStore.asksForCategories`). The look is `PhoneFirstScreen`
// (Screens/PhoneScreens.swift).

/// What the app shows in place of its dashboard (ContentView).
nonisolated enum MainScreen: Equatable, Sendable {
    /// The phone's store is opening, or did not open (`ModeStatusScreen`).
    case opening
    /// The tour on its made-up store (`TourScreen`).
    case tour
    /// Server mode at launch, while the saved login is renewed: nothing to show yet.
    case waitingForLogin
    /// Phone mode without data: "No data yet" (`PhoneFirstScreen`).
    case firstScreen
    /// The dashboard: phone mode with data, server mode, the server sample.
    case dashboard

    /// - Parameters:
    ///   - tour: the running tour's phase; nil without a tour. An ended tour shows nothing any more.
    ///   - hasMode: the mode is known and has its backend (or the server sample shows).
    ///   - waitsForServerLogin: server mode before its login is renewed.
    ///   - phonePayments: phone mode's payments on this iPhone; nil in server mode.
    @MainActor static func choose(tour: TourModel.Phase?, hasMode: Bool, waitsForServerLogin: Bool,
                                  phonePayments: Int?) -> MainScreen {
        if let tour, tour != .ended { return .tour }
        guard hasMode else { return .opening }
        if waitsForServerLogin { return .waitingForLogin }
        if phonePayments == 0 { return .firstScreen }
        return .dashboard
    }
}
