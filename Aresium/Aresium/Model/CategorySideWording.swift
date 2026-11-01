import Foundation

/// The words of category sides on screen (brief 70): the change window's Other category… with its list's line and the
/// long press that takes a category back, and Settings → Categories' side line. One place, so the window and Settings
/// say the same thing and tests can ask for both languages. A side is where a category is offered in the menus
/// (spending for money out, income for money in); since brief 71 every payment counts in the direction it went, so no
/// words explain any effect on the totals.
nonisolated enum CategorySideWording {
    /// A side's name, as the app calls the two directions: "Spending" / "Ausgaben", "Income" / "Einnahmen".
    static func name(_ side: CategorySide, language: AppLanguage = .current) -> String {
        switch side {
        case .spend: language.string("Spending")
        case .income: language.string("Income")
        }
    }

    /// The change window's tile that brings in a category of the other side.
    static func otherCategory(language: AppLanguage = .current) -> String {
        language.string("Other category…")
    }

    /// The other side's list's line, for a payment of `paymentSide`: where its categories come from ("From spending" for
    /// money in, "From income" for money out).
    static func otherSideList(for paymentSide: CategorySide, language: AppLanguage = .current) -> String {
        switch paymentSide {
        case .income: language.string("From spending")
        case .spend: language.string("From income")
        }
    }

    /// The long press's entry on a tile offered for this payment's direction only from the other side.
    static func notFor(_ paymentSide: CategorySide, language: AppLanguage = .current) -> String {
        switch paymentSide {
        case .income: language.string("Not for money in")
        case .spend: language.string("Not for money out")
        }
    }

    /// A category of `side` also offered for the other direction: Settings' second line and its switch.
    static func alsoFor(otherSideOf side: CategorySide, language: AppLanguage = .current) -> String {
        switch side {
        case .spend: language.string("Also for money in")
        case .income: language.string("Also for money out")
        }
    }
}
