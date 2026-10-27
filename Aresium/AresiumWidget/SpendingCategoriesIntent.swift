import AppIntents

nonisolated struct SpendCategoryEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Spending category"
    static let defaultQuery = SpendCategoryQuery()
    let id: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(CategoryName.shown(id))") }
}

nonisolated struct SpendCategoryQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [SpendCategoryEntity] {
        let categories = WidgetSnapshotStore().readForCurrentLogin().snapshot?.categories ?? []
        return identifiers.compactMap { id in
            categories.contains { $0.name == id } ? SpendCategoryEntity(id: id) : nil
        }
    }

    func suggestedEntities() async throws -> [SpendCategoryEntity] {
        (WidgetSnapshotStore().readForCurrentLogin().snapshot?.categories ?? []).map { SpendCategoryEntity(id: $0.name) }
    }
}

struct SpendingCategoriesIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Spending categories"
    static let description = IntentDescription("Choose the two spending categories to show this month.")

    @Parameter(title: "First category") var firstCategory: SpendCategoryEntity?
    @Parameter(title: "Second category") var secondCategory: SpendCategoryEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Show \(\.$firstCategory) and \(\.$secondCategory)")
    }

    init() {
        let defaults = WidgetSnapshotStore().readForCurrentLogin().snapshot?.defaultCategoryNames ?? []
        firstCategory = defaults.first.map { SpendCategoryEntity(id: $0) }
        secondCategory = defaults.dropFirst().first.map { SpendCategoryEntity(id: $0) }
    }
}
