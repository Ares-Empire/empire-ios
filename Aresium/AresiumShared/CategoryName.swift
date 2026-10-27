import Foundation

/// A category's name as the app and the widget show it. The dashboard (the engine's and the server's) puts payments
/// without a category under its own entry "Uncategorised"; the app shows it as "Not sorted" in its language, the word
/// the category picker uses. Every place that shows a category name goes through `shown`; Switch, Add, routes and links
/// keep the dashboard's real name.
nonisolated enum CategoryName {
    /// The dashboard's own name for payments without a category (engine `UNCATEGORISED`, server `src/data/dashboard.ts`).
    static let uncategorised = "Uncategorised"

    static func shown(_ name: String, language: AppLanguage = .current) -> String {
        guard name == uncategorised else { return name }
        return language.string(LocalizedStringResource("Not sorted", table: "AresiumShared"))
    }
}

extension Category {
    /// The name to show (`CategoryName.shown`); `name` stays the dashboard's key.
    var shownName: String { CategoryName.shown(name) }
}
