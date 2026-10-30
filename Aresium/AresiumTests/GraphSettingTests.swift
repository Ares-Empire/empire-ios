import Foundation
import SwiftUI
import Testing
@testable import Aresium

/// Settings → Dashboard → Graph (brief 42): on by default, and what the switch saves is what the next launch reads.
struct GraphSettingTests {
    /// Defaults of the test's own, never the app's.
    private static func defaults() -> UserDefaults {
        let name = "aresium.tests.graph.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func theGraphIsOnByDefault() {
        #expect(GraphSetting.shownByDefault)
        #expect(GraphSetting.isShown(in: Self.defaults()))
        #expect(GraphSetting.key.hasPrefix("aresium."))
    }

    @Test(arguments: [false, true])
    func theChoiceIsKept(shown: Bool) {
        let defaults = Self.defaults()
        defaults.set(shown, forKey: GraphSetting.key)
        #expect(GraphSetting.isShown(in: defaults) == shown)
    }

    /// The switch and the dashboard use `@AppStorage` with the key and the default: it reads and writes the same value.
    @MainActor @Test func theSwitchAndTheDashboardAgree() {
        let defaults = Self.defaults()
        let stored = AppStorage(wrappedValue: GraphSetting.shownByDefault, GraphSetting.key, store: defaults)
        #expect(stored.wrappedValue, "nothing saved yet: on")
        stored.wrappedValue = false                              // the switch turned off
        #expect(!GraphSetting.isShown(in: defaults))
        // A new launch: a new reader of the same defaults.
        #expect(!AppStorage(wrappedValue: GraphSetting.shownByDefault, GraphSetting.key, store: defaults).wrappedValue)
        stored.wrappedValue = true
        #expect(GraphSetting.isShown(in: defaults))
    }
}
