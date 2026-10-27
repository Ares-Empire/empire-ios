import Foundation

/// A file to import, as its bytes. The server gets it as text (`content`, UTF-8 with replacement characters, as the
/// website reads files); phone mode hands the bytes to the engine, which finds the encoding itself.
nonisolated struct ImportFile: Codable, Sendable, Equatable {
    let name: String
    let data: Data

    init(name: String, data: Data) {
        self.name = name
        self.data = data
    }

    init(name: String, content: String) {
        self.init(name: name, data: Data(content.utf8))
    }

    var content: String { String(decoding: data, as: UTF8.self) }

    private enum CodingKeys: String, CodingKey { case name, content }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(name: try container.decode(String.self, forKey: .name),
                  content: try container.decode(String.self, forKey: .content))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(content, forKey: .content)
    }
}

struct ImportResponse: Decodable {
    struct Result: Decodable {
        let name: String
        let added: Int
        let total: Int
        let account: String?
        let skipped: Bool
        let error: String?

        var displayMessage: String {
            if let error, !error.isEmpty { return "\(name): \(error)" }
            return skipped ? String(localized: "\(name): \(added) added · skipped") : String(localized: "\(name): \(added) added")
        }
    }
    let results: [Result]
    var summary: String {
        let added = results.reduce(0) { $0 + $1.added }
        let failed = results.filter { !($0.error ?? "").isEmpty }.count
        if failed > 0 { return String(localized: "\(added) added") + " · " + String(localized: "\(failed) files failed") }
        let skipped = results.filter(\.skipped).count
        return String(localized: "\(added) new transactions imported")
            + (skipped > 0 ? " · " + String(localized: "\(skipped) skipped") : "")
    }
}

struct ImportRequestPlan {
    static let maximumBytes = 25 * 1024 * 1024
    struct Body: Encodable { let files: [ImportFile] }
    let batches: [[ImportFile]]
    let refused: [ImportFile]

    static func encode(_ files: [ImportFile]) throws -> Data { try JSONEncoder().encode(Body(files: files)) }

    init(files: [ImportFile], maximumBytes: Int = Self.maximumBytes) throws {
        var batches: [[ImportFile]] = []
        var current: [ImportFile] = []
        var refused: [ImportFile] = []
        for file in files {
            guard try Self.encode([file]).count <= maximumBytes else { refused.append(file); continue }
            if try Self.encode(current + [file]).count > maximumBytes {
                batches.append(current)
                current = []
            }
            current.append(file)
        }
        if !current.isEmpty { batches.append(current) }
        self.batches = batches
        self.refused = refused
    }
}

extension APIClient {
    func importFiles(_ files: [ImportFile], token: String, onUnauthorized: () -> Void) async throws -> ImportResponse {
        let body = try ImportRequestPlan.encode(files)
        guard body.count <= ImportRequestPlan.maximumBytes else {
            throw HTTPError.server(413, String(localized: "Import request exceeds 25 MB. Split the files and try again."))
        }
        var request = URLRequest(url: baseURL.appendingPathComponent("api/import"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        request.timeoutInterval = 120
        let (data, response) = try await transport.send(request)
        try checkResponse(response, data: data, onUnauthorized: onUnauthorized)
        return try JSONDecoder().decode(ImportResponse.self, from: data)
    }
}
