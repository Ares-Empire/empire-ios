import SwiftUI
import UIKit

/// Authenticated hub marks (the province busts on www.ares-empire.de/brand/), for every app that shows provinces.
/// Keep one instance alongside the store; reset with this app's session data.
@MainActor
final class ProvinceMarks {
    private let session: EmpireSession
    private let transport: any HTTPTransport
    private let isSample: Bool
    private var cache: [URL: UIImage] = [:]
    private var generation = 0

    init(session: EmpireSession, transport: any HTTPTransport = URLSessionTransport(),
         sample: Bool = false) {
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

/// A province's mark: its image when loaded, else its initial in a quiet tile (.tab-mono; on the light wall an ivory
/// tile with a dark initial).
struct ProvinceMarkView: View {
    let name: String
    let image: UIImage?
    var size: CGFloat = 50

    var body: some View {
        if let image {
            Image(uiImage: image).resizable().scaledToFit().frame(width: size, height: size)
                .shadow(color: Color(light: Color(hex: 0x2A2418, opacity: 0.18), dark: .black.opacity(0.55)), radius: 9, y: 8)
        } else {
            Text(String(name.prefix(1)).uppercased())
                .font(AppFont.text(size * 0.44, weight: .bold))
                .foregroundStyle(Color(light: Color(hex: 0x2A2620), dark: Color(hex: 0xF3F1EA)))
                .frame(width: size * 0.92, height: size * 0.92)
                .background(RadialGradient(colors: [Color(light: .white.opacity(0.95), dark: .white.opacity(0.08)),
                                                    Color(light: Color(hex: 0xE6E2D8), dark: .black.opacity(0.2))],
                                           center: .init(x: 0.3, y: 0.2), startRadius: 0, endRadius: size),
                            in: .rect(cornerRadius: 13))
                .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(Color(light: Color(hex: 0x1A1813, opacity: 0.12),
                                                                                dark: .white.opacity(0.12))))
        }
    }
}
