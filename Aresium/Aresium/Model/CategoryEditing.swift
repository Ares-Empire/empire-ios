import Foundation

/// The result of typing a category name, shared by Settings and all three choosing windows.
nonisolated struct CategoryUse: Equatable, Sendable {
    enum Outcome: Equatable, Sendable { case made, existing, offered, ticked }
    let id: String
    let outcome: Outcome
    let alsoOffered: CategorySide?

    func message(name: String, language: AppLanguage = .current) -> String? {
        switch outcome {
        case .made: return nil
        case .existing: return language.string("\(name) is already in your list.")
        case .offered:
            return alsoOffered == .income ? language.string("\(name) is now offered for money in too.")
                                         : language.string("\(name) is now offered for money out too.")
        case .ticked:
            let line = language.string("\(name) is ticked.")
            guard let alsoOffered else { return line }
            return line + " " + (alsoOffered == .income ? language.string("Also for money in.")
                                                       : language.string("Also for money out."))
        }
    }
}

/// A row's delete/remove confirmation. The payment count includes manual choices, as unchoose resets those too.
nonisolated struct CategoryRemoval: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let count: Int
    var isCustom: Bool { ChosenCategory.isCustom(id) }

    func action(language: AppLanguage = .current) -> String {
        isCustom ? language.string("Delete") : language.string("Remove")
    }
    func title(language: AppLanguage = .current) -> String {
        isCustom ? language.string("Delete \(name)?") : language.string("Remove \(name)?")
    }
    func message(language: AppLanguage = .current) -> String {
        var line = count > 0 ? language.string("Its \(count) payments are sorted again. Those Aresium can't sort go to Not sorted.") : ""
        if !isCustom {
            if !line.isEmpty { line += " " }
            line += language.string("You can tick it again any time.")
        }
        return line
    }
}
