import Foundation

/// The calls every app makes for the account itself (ares-empire docs/ACCOUNTS.md → Accounts in every app; contract:
/// empire-ios docs/build-2026-10-25/briefs/F-accounts-contract.md): sign up, confirm the email, reset a forgotten
/// password, ask for an app, change the password, leave an app, delete the account. Logging in stays in
/// `EmpireAuthClient`. Every failure arrives as an `AccountFailure`, the one line a form shows.
struct EmpireAccountClient {
    var transport: any HTTPTransport = URLSessionTransport()
    static let server = URL(string: "https://auth.ares-empire.de")!
    private static let users = server.appendingPathComponent("api/collections/users")

    // MARK: without a login (the login screen)

    /// `POST …/users/records`: a new account asking for this app; Patrik approves it after the email is confirmed.
    func signUp(_ account: NewAccount) async throws(AccountFailure) {
        _ = try await send("POST", Self.users.appendingPathComponent("records"), body: account)
    }

    /// `POST …/users/request-verification`: the email with the link that confirms the address.
    func requestVerification(email: String) async throws(AccountFailure) {
        _ = try await send("POST", Self.users.appendingPathComponent("request-verification"), body: ["email": email])
    }

    /// `POST …/users/request-password-reset`: answers 204 whether or not an account has this address.
    func requestPasswordReset(email: String) async throws(AccountFailure) {
        _ = try await send("POST", Self.users.appendingPathComponent("request-password-reset"), body: ["email": email])
    }

    // MARK: with the login

    /// `GET …/users/records/<id>`: the account as it is now (its services and requests may have changed in another app).
    func account(id: String, token: String) async throws(AccountFailure) -> EmpireRecord {
        try decode(await send("GET", try record(id), token: token))
    }

    /// `PATCH …/users/records/<id>` `{requested}`: the apps the account asks for (all of them, not only the new one).
    func setRequested(_ services: [String], account id: String, token: String) async throws(AccountFailure) -> EmpireRecord {
        try decode(await send("PATCH", try record(id), body: ["requested": services], token: token))
    }

    /// `PATCH …/users/records/<id>` `{oldPassword, password, passwordConfirm}`. Afterwards the account server refuses
    /// every token it gave out before, this app's too: log in again with the new password at once.
    func changePassword(from old: String, to new: String, account id: String,
                        token: String) async throws(AccountFailure) -> EmpireRecord {
        let body = ["oldPassword": old, "password": new, "passwordConfirm": new]
        return try decode(await send("PATCH", try record(id), body: body, token: token))
    }

    /// `POST /api/empire/leave` `{service}` on the account server: removes the service from the account's access and
    /// its requests, and answers what is left.
    func leave(service: String, token: String) async throws(AccountFailure) -> AccountAccess {
        let url = Self.server.appendingPathComponent("api/empire/leave")
        return try decode(await send("POST", url, body: ["service": service], token: token))
    }

    /// `DELETE <the app's API>/me`: the app's server deletes what it keeps for this account (today only Arestemis).
    func deleteServiceData(at url: URL, token: String) async throws(AccountFailure) {
        _ = try await send("DELETE", url, token: token)
    }

    /// `DELETE …/users/records/<id>`: the account goes; the account server then deletes its data in every service.
    func deleteAccount(id: String, token: String) async throws(AccountFailure) {
        _ = try await send("DELETE", try record(id), token: token)
    }

    // MARK: requests

    /// One account's record URL. PocketBase ids are 15 letters and digits; anything else is never sent.
    private func record(_ id: String) throws(AccountFailure) -> URL {
        guard !id.isEmpty, id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }) else { throw .other }
        return Self.users.appendingPathComponent("records").appendingPathComponent(id)
    }

    private func send(_ method: String, _ url: URL, token: String? = nil) async throws(AccountFailure) -> Data {
        try await send(method, url, body: Optional<[String: String]>.none, token: token)
    }

    private func send<Body: Encodable>(_ method: String, _ url: URL, body: Body?,
                                       token: String? = nil) async throws(AccountFailure) -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            do { request.httpBody = try JSONEncoder().encode(body) } catch { throw .other }
        }
        request.timeoutInterval = 30
        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await transport.send(request)
        } catch {
            throw AccountFailure(error)
        }
        if let failure = AccountFailure(status: response.statusCode, body: data) { throw failure }
        return data
    }

    private func decode<T: Decodable>(_ data: Data) throws(AccountFailure) -> T {
        do { return try JSONDecoder().decode(T.self, from: data) } catch { throw .other }
    }
}

/// A new account as `POST …/users/records` takes it.
struct NewAccount: Encodable, Equatable {
    let email: String
    let password: String
    let passwordConfirm: String
    let name: String?               // left out when not given
    let requested: [String]         // the app it was made in
    let language: String            // "en" or "de": the emails it gets

    init(email: String, password: String, name: String?, app: EmpireAppIdentity, language: AppLanguage) {
        self.email = email
        self.password = password
        passwordConfirm = password
        self.name = name
        requested = [app.service]
        self.language = language.code
    }
}

/// What `POST /api/empire/leave` answers: the account's access after leaving.
struct AccountAccess: Decodable, Equatable {
    let services: [String]
    let requested: [String]
}

/// Why an account action did not go through, as the form says it in one line. Built from the account server's answer
/// (PocketBase: `{"message", "data": {"<field>": {"code"}}}`) or from the transport's error.
enum AccountFailure: Error, Equatable {
    case offline, tooMany, loggedOut, unavailable, other
    case wrongPassword              // the password typed to confirm (deleting the account)
    case wrongCurrentPassword       // changing the password: the current one
    case emailTaken, invalidEmail
    case passwordTooShort, passwordTooLong, passwordsDiffer

    /// The failure an answer stands for; nil for a 2xx.
    init?(status: Int, body: Data) {
        switch status {
        case 200..<300: return nil
        case 401: self = .loggedOut
        case 429: self = .tooMany
        case 502, 503, 504: self = .unavailable
        case 400: self = Self.field(in: body) ?? .other
        default: self = .other
        }
    }

    init(_ error: Error) {
        switch error {
        case let failure as AccountFailure: self = failure
        case HTTPError.unauthorized: self = .loggedOut
        case HTTPError.server(429, _): self = .tooMany
        case HTTPError.server(503, _): self = .unavailable
        case let error as URLError where Self.offlineCodes.contains(error.code): self = .offline
        default: self = .other
        }
    }

    /// PocketBase names the field it refused: the first one this app can explain.
    private static func field(in body: Data) -> AccountFailure? {
        struct Answer: Decodable { let data: [String: Field]? }
        struct Field: Decodable { let code: String? }
        guard let fields = (try? JSONDecoder().decode(Answer.self, from: body))?.data else { return nil }
        if fields["oldPassword"] != nil { return .wrongCurrentPassword }
        if let email = fields["email"] { return email.code == "validation_not_unique" ? .emailTaken : .invalidEmail }
        if fields["passwordConfirm"] != nil { return .passwordsDiffer }
        if fields["password"] != nil { return .passwordTooShort }
        return nil
    }

    private static let offlineCodes: Set<URLError.Code> = [
        .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed,
        .timedOut, .dataNotAllowed, .internationalRoamingOff, .callIsActive,
    ]

    /// Whether trying the same again in a moment may work (no connection, the server busy).
    var isTransient: Bool { [.offline, .unavailable, .other].contains(self) }

    var message: String {
        switch self {
        case .offline: String(localized: "No connection. Try again when you're online.", table: "Shared")
        case .tooMany: String(localized: "Too many tries for now. Please wait a few minutes.", table: "Shared")
        case .loggedOut: HTTPError.unauthorized.localizedDescription      // the login was refused: the app logs out
        case .unavailable: String(localized: "The account server can't be reached right now. Try again in a moment.",
                                  table: "Shared")
        case .other: String(localized: "It didn't go through. Please try again.", table: "Shared")
        case .wrongPassword: String(localized: "Wrong password.", table: "Shared")
        case .wrongCurrentPassword: String(localized: "The current password is wrong.", table: "Shared")
        case .emailTaken: String(localized: "There is already an account with this email. Log in, or reset its password.",
                                 table: "Shared")
        case .invalidEmail: String(localized: "This doesn't look like an email address.", table: "Shared")
        case .passwordTooShort: String(localized: "The password needs at least 8 characters.", table: "Shared")
        case .passwordTooLong: String(localized: "The password is too long: at most 71 characters.", table: "Shared")
        case .passwordsDiffer: String(localized: "The two passwords are not the same.", table: "Shared")
        }
    }
}

/// What the forms check before anything is sent: the account server's own limits (PocketBase's email format,
/// passwords of 8 to 71 characters).
enum AccountInput {
    static let passwordLength = 8...71

    static func trimmedEmail(_ email: String) -> String { email.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// One "@", something before it, and a dot in the part after it ("a@b.de").
    static func looksLikeEmail(_ email: String) -> Bool {
        let parts = trimmedEmail(email).split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, !parts[0].contains(where: \.isWhitespace) else { return false }
        let domain = parts[1]
        guard let dot = domain.lastIndex(of: "."), dot != domain.startIndex, domain.index(after: dot) != domain.endIndex,
              !domain.contains(where: \.isWhitespace) else { return false }
        return true
    }

    /// The problem with a new password and its repetition, if there is one.
    static func newPasswordProblem(_ password: String, again: String) -> AccountFailure? {
        if password.count < passwordLength.lowerBound { return .passwordTooShort }
        if password.count > passwordLength.upperBound { return .passwordTooLong }
        if password != again { return .passwordsDiffer }
        return nil
    }
}
