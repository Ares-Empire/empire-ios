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

    func upload(_ id: Int, fileURL: URL, token: String, onUnauthorized: () -> Void = {}) async throws -> Drop {
        var request = try dropRequest(["drops", String(id), "file"], method: "PUT", token: token)
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 300
        let (data, response) = try await transport.upload(request, fromFile: fileURL)
        try checkResponse(response, data: data, onUnauthorized: onUnauthorized)
        return try AresusJSON.decoder().decode(Drop.self, from: data)
    }

    func cancel(_ id: Int, token: String, onUnauthorized: () -> Void = {}) async throws {
        let request = try dropRequest(["drops", String(id)], method: "DELETE", token: token)
        let (data, response) = try await transport.send(request)
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
