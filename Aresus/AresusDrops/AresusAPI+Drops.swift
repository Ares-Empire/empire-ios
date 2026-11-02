import Foundation

extension AresusAPI {
    func folders(token: String, onUnauthorized: () -> Void = {}) async throws -> FolderList {
        try await get(["drops", "folders"], token: token, onUnauthorized: onUnauthorized)
    }

    func drops(token: String, onUnauthorized: () -> Void = {}) async throws -> [Drop] {
        let answer: DropsAnswer = try await get(["drops"], token: token, onUnauthorized: onUnauthorized)
        return answer.drops
    }

    func create(_ drop: NewDrop, token: String, onUnauthorized: () -> Void = {}) async throws -> Drop {
        var request = try dropRequest(["drops"], method: "POST", token: token)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try AresusJSON.encoder().encode(drop)
        let (data, response) = try await transport.send(request)
        try checkResponse(response, data: data, onUnauthorized: onUnauthorized)
        return try AresusJSON.decoder().decode(Drop.self, from: data)
    }

    func uploadRequest(_ id: Int, token: String) throws -> URLRequest {
        var request = try dropRequest(["drops", String(id), "file"], method: "PUT", token: token)
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 300
        return request.withLanguage()
    }

    /// Deletes a drop from the list, in any state (`DELETE /drops/{id}`, 2026-11-02): one not landed yet is cancelled
    /// (the Mac never gets it); a landed file stays on the Mac. A `404` (unknown, or already removed) counts as deleted.
    func delete(_ id: Int, token: String, onUnauthorized: () -> Void = {}) async throws {
        let request = try dropRequest(["drops", String(id)], method: "DELETE", token: token)
        let (data, response) = try await transport.send(request)
        if response.statusCode == 404 { return }
        try checkResponse(response, data: data, onUnauthorized: onUnauthorized)
    }

    private func dropRequest(_ path: [String], method: String, token: String) throws -> URLRequest {
        guard let url = Self.url(path) else { throw HTTPError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30
        return request
    }
}
