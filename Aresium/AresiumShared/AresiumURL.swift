import Foundation

nonisolated enum AresiumURL: Equatable {
    case start
    case category(String)

    var url: URL {
        var components = URLComponents()
        components.scheme = "aresium"
        switch self {
        case .start: components.host = "start"
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
        case "category":
            guard let encoded = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedPath,
                  encoded.hasPrefix("/"), !encoded.dropFirst().contains("/"),
                  let name = String(encoded.dropFirst()).removingPercentEncoding, !name.isEmpty else { return nil }
            self = .category(name)
        default: return nil
        }
    }
}
