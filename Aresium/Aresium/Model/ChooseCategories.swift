import Foundation

// Choosing categories on the first run (brief 215, the first-run review's finding 1): Done on the category list with
// nothing ticked left every payment Not sorted, and the quick sort could then offer only Own transfers and New category.
// Now Done with nothing ticked asks once whether to use the categories the payments fit into (the rows' numbers,
// `CategoryPickerModel.fitting`); while none is chosen the dashboard says so in one card that opens the list
// (`DashboardStore.waitsForCategories`), and the quick sort waits.

/// The question and the dashboard's card in the app's language (English here, German in the catalog).
nonisolated enum ChooseCategoriesWording {
    /// Done with nothing ticked: "Use the 12 categories that fit?"
    static func question(_ count: Int, language: AppLanguage = .current) -> String {
        language.string("Use the \(count) categories that fit?")
    }

    /// Under the question: what Use does, and where the categories change later.
    static func questionLine(language: AppLanguage = .current) -> String {
        language.string("Aresium sorts your payments right away. You can change your categories any time in Settings → Categories.")
    }

    static func use(language: AppLanguage = .current) -> String { language.string("Use") }
    static func notNow(language: AppLanguage = .current) -> String { language.string("Not now") }

    /// The dashboard's card while no category is chosen.
    static func cardTitle(language: AppLanguage = .current) -> String { language.string("Choose your categories") }
    static func cardLine(language: AppLanguage = .current) -> String {
        language.string("Then Aresium sorts your payments.")
    }
}
