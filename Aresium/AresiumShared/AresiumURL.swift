import Foundation

nonisolated enum AresiumURL: Equatable {
    case start
    case category(String)
    case importData
    case review(String)

    var url: URL {
        var components = URLComponents()
        components.scheme = "aresium"
        switch self {
        case .start: components.host = "start"
        case .importData: components.host = "import"
        case .review(let month):
            components.host = "review"
            components.path = "/" + month
        case .category(let name):
            components.host = "category"
            // A category is exactly one path component, including names containing slashes or percent signs.
            var allowed = CharacterSet.urlPathAllowed
            allowed.remove(charactersIn: "/%")
            components.percentEncodedPath = "/" + name.addingPercentEncoding(withAllowedCharacters: allowed)!
        }
        return components.url!
    }

    init?(url: URL) {
        guard url.scheme?.lowercased() == "aresium", url.query == nil, url.fragment == nil,
              url.user == nil, url.password == nil, url.port == nil else { return nil }
        switch url.host?.lowercased() {
        case "start" where url.path.isEmpty || url.path == "/": self = .start
        case "import" where url.path.isEmpty || url.path == "/": self = .importData
        case "review":
            let key = String(url.path.dropFirst())
            guard key.count == 7, key.range(of: #"^[0-9]{4}-(0[1-9]|1[0-2])$"#,
                                           options: .regularExpression) != nil else { return nil }
            self = .review(key)
        case "category":
            guard let encoded = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedPath,
                  encoded.hasPrefix("/"), !encoded.dropFirst().contains("/"),
                  let name = String(encoded.dropFirst()).removingPercentEncoding, !name.isEmpty else { return nil }
            self = .category(name)
        default: return nil
        }
    }
}
