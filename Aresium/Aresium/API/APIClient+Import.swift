import Foundation

struct ImportFile: Codable, Sendable, Equatable {
    let name: String
    let content: String
}

struct ImportResponse: Decodable {
    struct Result: Decodable {
        let name: String
        let added: Int
        let total: Int
        let account: String?
        let skipped: Bool
        let error: String?
    }

    let results: [Result]

    var summary: String {
        let added = results.reduce(0) { $0 + $1.added }
        let failed = results.filter { !($0.error ?? "").isEmpty }.count
        if failed > 0 { return "\(added) added · \(failed) file(s) failed" }
        let skipped = results.filter(\.skipped).count
        return "\(added) new transaction\(added == 1 ? "" : "s") imported"
            + (skipped > 0 ? " · \(skipped) skipped" : "")
    }
}

extension APIClient {
    func importFiles(_ files: [ImportFile], token: String, onUnauthorized: () -> Void) async throws -> ImportResponse {
        struct Body: Encodable { let files: [ImportFile] }
        struct Failure: Decodable { let error: String }

        var request = URLRequest(url: baseURL.appendingPathComponent("api/import"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(Body(files: files))
        request.timeoutInterval = 30
        let (data, response) = try await transport.send(request)
        if response.statusCode == 401 {
            onUnauthorized()
            throw HTTPError.unauthorized
        }
        guard (200..<300).contains(response.statusCode) else {
            let message = try? JSONDecoder().decode(Failure.self, from: data).error
            throw HTTPError.server(response.statusCode, message ?? "Import failed (\(response.statusCode))")
        }
        return try JSONDecoder().decode(ImportResponse.self, from: data)
    }
}
