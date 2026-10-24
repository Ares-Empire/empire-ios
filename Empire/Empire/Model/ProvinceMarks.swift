import Foundation
import UIKit

/// Authenticated hub marks. Keep one instance alongside the store; reset with this app's session data.
@MainActor
final class ProvinceMarks {
    private let session: EmpireSession
    private let transport: any HTTPTransport
    private let isSample: Bool
    private var cache: [URL: UIImage] = [:]
    private var generation = 0

    init(session: EmpireSession, transport: any HTTPTransport = URLSessionTransport(),
         sample: Bool = EmpireSamples.isEnabled) {
        self.session = session
        self.transport = transport
        #if DEBUG
        isSample = sample
        #else
        isSample = false
        #endif
        session.onAppDataReset { [weak self] in self?.clear() }
    }

    func image(for logo: String) async -> UIImage? {
        guard !isSample, session.isSignedIn, let token = session.token, let url = Self.url(for: logo) else { return nil }
        if let image = cache[url] { return image }
        let generation = generation
        let sessionGeneration = session.generation
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30
        do {
            let (data, response) = try await transport.send(request)
            try checkResponse(response, data: data, onUnauthorized: {})
            guard generation == self.generation, sessionGeneration == session.generation, session.isSignedIn,
                  let image = UIImage(data: data) else { return nil }
            cache[url] = image
            return image
        } catch { return nil }
    }

    func clear() {
        generation += 1
        cache.removeAll()
    }

    private static func url(for logo: String) -> URL? {
        let path = logo.hasPrefix("/") ? logo : "/\(logo)"
        guard let components = URLComponents(string: path), components.scheme == nil, components.host == nil,
              components.query == nil, components.fragment == nil, components.path.hasPrefix("/brand/"),
              !components.path.contains("\\"), !components.path.contains("%"),
              !components.path.split(separator: "/").contains(where: { $0 == "." || $0 == ".." }) else { return nil }
        var destination = URLComponents(string: "https://www.ares-empire.de")!
        destination.percentEncodedPath = components.percentEncodedPath
        return destination.url
    }
}
