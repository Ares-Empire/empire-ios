import Foundation

/// The app's routes beyond the overview (the client itself is in `AresusShared/AresusAPI.swift`, which the widget
/// compiles too).
extension AresusAPI {
    func province(_ slug: String, token: String, onUnauthorized: () -> Void = {}) async throws -> ProvinceDetail {
        try await get(["provinces", slug], token: token, onUnauthorized: onUnauthorized)
    }

    func sync(token: String, onUnauthorized: () -> Void = {}) async throws -> SyncOverview {
        try await get(["sync"], token: token, onUnauthorized: onUnauthorized)
    }

    func run(_ id: Int, token: String, onUnauthorized: () -> Void = {}) async throws -> RunDetail {
        try await get(["sync", "runs", String(id)], token: token, onUnauthorized: onUnauthorized)
    }
}
