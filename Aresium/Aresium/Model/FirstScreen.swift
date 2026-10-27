import Foundation
import Observation

// The first screen (brief 25, Patrik 2026-10-27): while phone mode has no data, Aresium shows a clear empty state ("No
// data yet", Import data, Start tour) instead of the dashboard, and it comes back after the tour as long as there is no
// data, so the tour's made-up data is never seen outside the tour. `MainScreen` decides what shows, `ImportFlow` is
// Import data. The look is `PhoneFirstScreen` (Screens/PhoneScreens.swift).

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

/// Import data in phone mode (the first screen, the dashboard's import button, the guide's Choose file): while no
/// category is chosen, the category picker comes first and the file picker follows once it closes with categories
/// chosen (closed without any, it ends there); with categories, the file picker at once. Each screen that offers it
/// owns one and shows the two pickers it asks for.
@MainActor @Observable
final class ImportFlow {
    /// The category picker shows.
    var choosesCategories = false
    /// The file picker shows.
    var picksFiles = false
    /// The file picker follows when the category picker closes.
    @ObservationIgnored private var filesNext = false

    /// Import data.
    func start(hasCategories: Bool) {
        if hasCategories {
            picksFiles = true
        } else {
            filesNext = true
            choosesCategories = true
        }
    }

    /// The category picker closed (Done, or swiped away).
    func categoriesClosed(hasCategories: Bool) {
        choosesCategories = false
        if filesNext && hasCategories { picksFiles = true }
        filesNext = false
    }

    /// The category picker on its own (DEBUG `-openSheet categories`): no file picker after it.
    func showCategories() {
        filesNext = false
        choosesCategories = true
    }
}
