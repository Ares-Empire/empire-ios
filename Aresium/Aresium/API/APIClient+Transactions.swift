import Foundation

extension APIClient {
    func transactionDetail(id: String, token: String, onUnauthorized: () -> Void) async throws -> TransactionDetail {
        try await transactionRequest(id: id, token: token, onUnauthorized: onUnauthorized)
    }

    func switchCategory(id: String, category: String, token: String,
                        onUnauthorized: () -> Void) async throws -> TransactionDetail {
        let body = try JSONEncoder().encode(CategoryBody(category: category))
        return try await transactionRequest(id: id, action: "category", body: body,
                                            token: token, onUnauthorized: onUnauthorized)
    }

    func setTransactionTags(id: String, categories: [String], dropCurrent: Bool, token: String,
                            onUnauthorized: () -> Void) async throws -> TransactionDetail {
        let body = try JSONEncoder().encode(TagsBody(categories: categories, dropCurrent: dropCurrent))
        return try await transactionRequest(id: id, action: "tags", body: body,
                                            token: token, onUnauthorized: onUnauthorized)
    }

    private func transactionRequest(id: String, action: String? = nil, body: Data? = nil,
                                    token: String, onUnauthorized: () -> Void) async throws -> TransactionDetail {
        // An ID is one path segment. Encode slashes, percent signs, query/fragment
        // delimiters and Unicode just as encodeURIComponent does on the website.
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.!~*'()")
        guard let encoded = id.addingPercentEncoding(withAllowedCharacters: allowed),
              var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw HTTPError.invalidResponse
        }
        components.percentEncodedPath += "/api/transaction/" + encoded + (action.map { "/" + $0 } ?? "")
        guard let url = components.url else { throw HTTPError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = body == nil ? "GET" : "POST"
        request.httpBody = body
        request.timeoutInterval = 30
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let (data, response) = try await transport.send(request)
        try checkResponse(response, data: data, onUnauthorized: onUnauthorized)
        return try JSONDecoder().decode(TransactionDetail.self, from: data)
    }
}

private struct CategoryBody: Encodable { let category: String }
private struct TagsBody: Encodable { let categories: [String]; let dropCurrent: Bool }
