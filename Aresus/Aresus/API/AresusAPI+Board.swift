import Foundation

extension AresusAPI {
    func boardWaiting(token: String, onUnauthorized: () -> Void = {}) async throws -> BoardWaiting {
        try await get(["board", "waiting"], token: token, onUnauthorized: onUnauthorized)
    }

    func boardAnswer(_ id: Int, answer: String, token: String, onUnauthorized: () -> Void = {}) async throws -> BoardItem {
        try await boardPost(id, action: "answer", answer: answer, token: token, onUnauthorized: onUnauthorized)
    }

    func boardDone(_ id: Int, token: String, onUnauthorized: () -> Void = {}) async throws -> BoardItem {
        try await boardPost(id, action: "done", token: token, onUnauthorized: onUnauthorized)
    }

    func boardDrop(_ id: Int, token: String, onUnauthorized: () -> Void = {}) async throws -> BoardItem {
        try await boardPost(id, action: "drop", token: token, onUnauthorized: onUnauthorized)
    }

    private func boardPost(_ id: Int, action: String, answer: String? = nil, token: String,
                           onUnauthorized: () -> Void) async throws -> BoardItem {
        guard let url = Self.url(["board", "items", String(id), action]) else { throw HTTPError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let answer {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(["answer": answer])
        }
        let (data, response) = try await transport.send(request)
        try checkResponse(response, data: data, onUnauthorized: onUnauthorized)
        return try AresusJSON.decoder().decode(BoardItem.self, from: data)
    }
}
