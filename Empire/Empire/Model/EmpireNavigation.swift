import Foundation
import Observation

/// Where a notification takes the Empire app. The app declares no URL scheme: its links come only in a notification's
/// payload (`url`, read by `PushCenter`). Today one: `empire://ring`, "<App> is ready" (thread `access`), sent to a
/// member when Patrik approved a request (ares-empire docs/EMPIRE-APP.md → Notifications); the app is in the ring now.
/// Patrik's sign-ups and requests come by email, not as a push (Patrik, 2026-10-26).
enum EmpireLink: Equatable {
    case ring

    init?(url: URL) {
        guard url.scheme?.lowercased() == "empire" else { return nil }
        var parts = url.pathComponents.filter { $0 != "/" }
        if let host = url.host(percentEncoded: false), !host.isEmpty { parts.insert(host, at: 0) }
        guard parts == ["ring"] else { return nil }
        self = .ring
    }
}

/// What the home screen shows over itself: a sheet, or the expansions instead of the provinces. Owned by `ContentView`
/// (not the home screen), so a tapped notification can bring the ring back, also before the hub has loaded.
@MainActor @Observable
final class EmpireNavigation {
    var sheet: EmpireHome.Sheet?
    var expanded = false

    /// A tapped notification's `url`: follows it and asks the hub again, so the app just granted is in the ring. False
    /// for a URL that is not one of the app's links (the app just opens).
    @discardableResult
    func open(_ url: URL, store: EmpireStore) async -> Bool {
        guard let link = EmpireLink(url: url) else { return false }
        follow(link)
        await store.reload()
        return true
    }

    /// The ring, with nothing over it.
    func follow(_ link: EmpireLink) {
        switch link {
        case .ring:
            sheet = nil
            expanded = false
        }
    }

    /// Logged out: nothing stays open for the next login.
    func reset() {
        sheet = nil
        expanded = false
    }
}
