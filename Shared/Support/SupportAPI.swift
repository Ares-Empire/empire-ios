import Foundation

/// The account server's `feedback` collection (ares-empire/docs/ACCOUNTS.md → Contact & support): a signed-in account
/// creates a message, the server mails it to Patrik. At most 10 an hour (429 after that).
struct SupportAPI {
    var transport: any HTTPTransport = URLSessionTransport()
    static let url = URL(string: "https://auth.ares-empire.de/api/collections/feedback/records")!

    /// Throws `HTTPError` (`.unauthorized` for a rejected login, `.server(429, _)` when too many were sent) or the
    /// transport's error (`URLError` when offline).
    func send(_ message: SupportMessage, token: String) async throws {
        var request = URLRequest(url: Self.url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(message)
        request.timeoutInterval = 30
        let (data, response) = try await transport.send(request)
        try checkResponse(response, data: data, onUnauthorized: {})
    }
}

extension SupportAPI {
    /// The account server's open `contact` collection, for a message without a login (`ContactMessage`): at most 5 an
    /// hour from one address (429 after that).
    static let contactURL = URL(string: "https://auth.ares-empire.de/api/collections/contact/records")!

    /// Sends a message without a login. Throws `SupportFailure.invalidEmail` when the server refuses the address,
    /// `HTTPError` (`.server(429, _)` for too many) or the transport's error (`URLError` when offline).
    func sendContact(_ message: ContactMessage) async throws {
        var request = URLRequest(url: Self.contactURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(message)
        request.timeoutInterval = 30
        let (data, response) = try await transport.send(request)
        // PocketBase names the refused fields in `data`; a refused address is the person's to correct.
        if response.statusCode == 400, Self.refusedFields(data).contains("email") { throw SupportFailure.invalidEmail }
        try checkResponse(response, data: data, onUnauthorized: {})
    }

    /// The fields a PocketBase 400 names (`{"data": {"email": {"code": …}}}`).
    static func refusedFields(_ data: Data) -> Set<String> {
        guard let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let fields = body["data"] as? [String: Any] else { return [] }
        return Set(fields.keys)
    }
}

/// Why a message did not go out, as the form says it in one line. The text stays in the form in every case.
enum SupportFailure: Error, Equatable {
    case offline, tooMany, loggedOut, other
    /// Without a login: the email to answer to is not an address.
    case invalidEmail

    init(_ error: Error) {
        switch error {
        case let failure as SupportFailure: self = failure
        case HTTPError.unauthorized: self = .loggedOut
        case HTTPError.server(429, _): self = .tooMany
        case let error as URLError where Self.offlineCodes.contains(error.code): self = .offline
        default: self = .other
        }
    }

    private static let offlineCodes: Set<URLError.Code> = [
        .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed,
        .timedOut, .dataNotAllowed, .internationalRoamingOff, .callIsActive,
    ]

    var message: String {
        switch self {
        case .offline: String(localized: LocalizedStringResource("No connection. Send it again when you're online.",
                                                                 table: "Shared",
                                                                 locale: .appLanguage))
        case .tooMany: String(localized: LocalizedStringResource("Too many messages for now. Please try again later.",
                                                                 table: "Shared",
                                                                 locale: .appLanguage))
        case .loggedOut: HTTPError.unauthorized.localizedDescription      // the login was rejected: the app logs out
        case .other: String(localized: LocalizedStringResource("It didn't go through. Please try again.",
                                                               table: "Shared",
                                                               locale: .appLanguage))
        case .invalidEmail: AccountFailure.invalidEmail.message
        }
    }
}
