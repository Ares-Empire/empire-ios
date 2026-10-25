import Foundation
import Observation

// The account's own actions, one small model each, so the screens only show them (Shared/Design/AccountSheets.swift,
// AccountScreens.swift, the login screens). Contract: ares-empire docs/ACCOUNTS.md → Accounts in every app.
// Each one talks to the account server through the session's transport (`EmpireSession.accountClient`), so tests and the
// screenshot account (`SampleAccount`) reach every call. A 401 goes through `session.handleAuthFailure` (the login ends
// everywhere); any other failure leaves the account and the login as they were and says so in one line. Sample mode
// (`-sampleData`) never calls a server: a short pause, then success.

// MARK: - creating an account (the login screen)

/// "Create account": email, password twice, an optional name. The account asks for this app and gets its emails in the
/// app's language. Two steps: the account, then the email that confirms the address; if only the second fails, sending
/// again repeats only the second.
@MainActor @Observable
final class SignUpForm {
    enum Phase: Equatable { case writing, sending, done, failed(AccountFailure) }

    var email = ""
    var password = ""
    var passwordAgain = ""
    var name = ""
    private(set) var phase: Phase = .writing
    /// The account exists; only the confirmation email is left to send (the fields are locked).
    private(set) var accountCreated = false

    @ObservationIgnored private let session: EmpireSession
    @ObservationIgnored private let language: AppLanguage
    @ObservationIgnored private let sample: Bool
    @ObservationIgnored private let sampleDelay: Duration

    init(session: EmpireSession, language: AppLanguage = .current, sample: Bool = false,
         sampleDelay: Duration = .seconds(1.2)) {
        self.session = session
        self.language = language
        self.sample = sample
        self.sampleDelay = sampleDelay
    }

    var failure: AccountFailure? { if case .failed(let failure) = phase { failure } else { nil } }

    var canSend: Bool {
        guard phase != .sending, phase != .done else { return false }
        return accountCreated
            || (!AccountInput.trimmedEmail(email).isEmpty && !password.isEmpty && !passwordAgain.isEmpty)
    }

    func send() async {
        guard canSend else { return }
        if !accountCreated {
            email = AccountInput.trimmedEmail(email)
            guard AccountInput.looksLikeEmail(email) else { phase = .failed(.invalidEmail); return }
            if let problem = AccountInput.newPasswordProblem(password, again: passwordAgain) {
                phase = .failed(problem)
                return
            }
        }
        phase = .sending
        if sample {
            try? await Task.sleep(for: sampleDelay)
            forgetPasswords()
            phase = .done
            return
        }
        let client = session.accountClient
        do {
            if !accountCreated {
                let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
                try await client.signUp(NewAccount(email: email, password: password, name: name.isEmpty ? nil : name,
                                                   app: session.app, language: language))
                accountCreated = true
                forgetPasswords()
            }
            try await client.requestVerification(email: email)
            phase = .done
        } catch {
            phase = .failed(error)
        }
    }

    private func forgetPasswords() {
        password = ""
        passwordAgain = ""
    }
}

// MARK: - a forgotten password (the login screen)

/// "Forgot password?": the account server sends a link if it knows the address, and says the same either way.
@MainActor @Observable
final class PasswordResetForm {
    enum Phase: Equatable { case writing, sending, sent, failed(AccountFailure) }

    var email: String
    private(set) var phase: Phase = .writing

    @ObservationIgnored private let session: EmpireSession
    @ObservationIgnored private let sample: Bool
    @ObservationIgnored private let sampleDelay: Duration

    /// - Parameter email: what the login's email field holds, so it need not be typed twice.
    init(session: EmpireSession, email: String = "", sample: Bool = false, sampleDelay: Duration = .seconds(1.2)) {
        self.session = session
        self.email = AccountInput.trimmedEmail(email)
        self.sample = sample
        self.sampleDelay = sampleDelay
    }

    var failure: AccountFailure? { if case .failed(let failure) = phase { failure } else { nil } }
    var canSend: Bool { phase != .sending && phase != .sent && !AccountInput.trimmedEmail(email).isEmpty }

    func send() async {
        guard canSend else { return }
        email = AccountInput.trimmedEmail(email)
        guard AccountInput.looksLikeEmail(email) else { phase = .failed(.invalidEmail); return }
        phase = .sending
        if sample {
            try? await Task.sleep(for: sampleDelay)
            phase = .sent
            return
        }
        do {
            try await session.accountClient.requestPasswordReset(email: email)
            phase = .sent
        } catch {
            phase = .failed(error)
        }
    }
}

// MARK: - asking for this app (the no-access screen)

/// "Ask for access": adds this app to the apps the account asked for; Patrik approves it, and an email follows. The
/// account is read first, so a request made meanwhile in another app is kept.
@MainActor @Observable
final class AccessRequest {
    enum Phase: Equatable { case ready, asking, failed(AccountFailure) }

    private(set) var phase: Phase = .ready
    private var askedInSample = false

    @ObservationIgnored private let session: EmpireSession
    @ObservationIgnored private let sample: Bool
    @ObservationIgnored private let sampleDelay: Duration

    init(session: EmpireSession, sample: Bool = false, sampleDelay: Duration = .seconds(1.2)) {
        self.session = session
        self.sample = sample
        self.sampleDelay = sampleDelay
    }

    var isAsked: Bool { askedInSample || session.hasAskedForAccess }
    var failure: AccountFailure? { if case .failed(let failure) = phase { failure } else { nil } }

    func ask() async {
        guard phase != .asking, !isAsked else { return }
        phase = .asking
        if sample {
            try? await Task.sleep(for: sampleDelay)
            askedInSample = true
            phase = .ready
            return
        }
        guard let token = session.token, let id = session.accountID else { phase = .failed(.loggedOut); return }
        let service = session.app.service
        let generation = session.generation
        let client = session.accountClient
        do {
            let current = try await client.account(id: id, token: token)
            guard generation == session.generation else { phase = .ready; return }
            if current.services.contains(service) {
                // Approved meanwhile: the login's next check opens the app.
                phase = .ready
                await session.restore()
                return
            }
            var requested = current.requested
            if !requested.contains(service) { requested.append(service) }
            let updated = try await client.setRequested(requested, account: id, token: token)
            guard generation == session.generation else { phase = .ready; return }
            session.updateAccess(services: updated.services, requested: updated.requested)
            phase = .ready
        } catch {
            if error == .loggedOut { session.handleAuthFailure(HTTPError.unauthorized, generation: generation) }
            phase = .failed(error)
        }
    }

    #if DEBUG
    /// Screenshots only: show a state without asking.
    func debugShow(asked: Bool, phase: Phase) {
        askedInSample = asked
        self.phase = phase
    }
    #endif
}

// MARK: - changing the password (Settings → Account)

/// "Change password": the current one and the new one twice. The account server then refuses every login made before,
/// in every app on this iPhone, so the app logs in again with the new password at once and saves that login for all of
/// them (`session.takeOverLogin`). While it does, a 401 from an older request is no logout
/// (`session.beginPasswordChange`). If logging in again fails, the page offers to try again; closing it then logs out,
/// with a line saying to log in with the new password.
@MainActor @Observable
final class ChangePasswordForm {
    enum Phase: Equatable { case writing, changing, done, failed(AccountFailure), loginFailed(AccountFailure) }

    var current = ""
    var newPassword = ""
    var newAgain = ""
    private(set) var phase: Phase = .writing

    @ObservationIgnored private let session: EmpireSession
    @ObservationIgnored private let sample: Bool
    @ObservationIgnored private let sampleDelay: Duration
    @ObservationIgnored private let retryDelay: Duration
    /// The new login, kept only between the change and the login with it.
    @ObservationIgnored private var pendingLogin: (email: String, password: String)?
    @ObservationIgnored private var closed = false

    init(session: EmpireSession, sample: Bool = false, sampleDelay: Duration = .seconds(1.2),
         retryDelay: Duration = .seconds(1)) {
        self.session = session
        self.sample = sample
        self.sampleDelay = sampleDelay
        self.retryDelay = retryDelay
    }

    var failure: AccountFailure? {
        switch phase {
        case .failed(let failure), .loginFailed(let failure): failure
        default: nil
        }
    }

    var canChange: Bool {
        switch phase {
        case .writing, .failed: !current.isEmpty && !newPassword.isEmpty && !newAgain.isEmpty
        default: false
        }
    }

    /// The page must stay open: the change is under way, or the new password is set and the app is not logged in
    /// with it yet.
    var holdsThePage: Bool {
        switch phase {
        case .changing, .loginFailed: true
        default: false
        }
    }

    func change() async {
        guard canChange else { return }
        if let problem = AccountInput.newPasswordProblem(newPassword, again: newAgain) { phase = .failed(problem); return }
        phase = .changing
        if sample {
            try? await Task.sleep(for: sampleDelay)
            forgetFields()
            phase = .done
            return
        }
        guard let token = session.token, let id = session.accountID, let email = session.email else {
            phase = .failed(.loggedOut)
            return
        }
        let generation = session.generation
        session.beginPasswordChange()
        do {
            _ = try await session.accountClient.changePassword(from: current, to: newPassword, account: id, token: token)
        } catch {
            session.endPasswordChange()
            if error == .loggedOut { session.handleAuthFailure(HTTPError.unauthorized, generation: generation) }
            phase = .failed(error)
            return
        }
        // From here the account server refuses the old login everywhere: log in with the new password now.
        pendingLogin = (email, newPassword)
        forgetFields()
        await logInAgain()
    }

    /// After a failed login with the new password: try that login again (the password stays changed).
    func retryLogin() async {
        guard case .loginFailed = phase else { return }
        phase = .changing
        await logInAgain()
    }

    /// The page closes. With the password changed but no login with it, the old login is useless: log out everywhere.
    func close() {
        guard !closed else { return }
        closed = true
        if case .loginFailed = phase { logOutWithNewPassword() }
    }

    private func logInAgain() async {
        guard let login = pendingLogin else { return }
        var failure = AccountFailure.other
        for attempt in 1...2 {
            do {
                let response = try await session.authClient.login(email: login.email, password: login.password)
                try session.takeOverLogin(response)
                session.endPasswordChange()
                pendingLogin = nil
                phase = .done
                return
            } catch {
                failure = AccountFailure(error)
                guard attempt == 1, failure.isTransient else { break }
                try? await Task.sleep(for: retryDelay)
            }
        }
        phase = .loginFailed(failure)
        if closed { logOutWithNewPassword() }
    }

    private func logOutWithNewPassword() {
        pendingLogin = nil
        session.logOut(notice: String(localized: LocalizedStringResource("Your password is changed. Log in with the new one.",
                                                                         table: "Shared", locale: .appLanguage)))
    }

    private func forgetFields() {
        current = ""
        newPassword = ""
        newAgain = ""
    }

    #if DEBUG
    func debugPhase(_ phase: Phase) { self.phase = phase }
    #endif
}

// MARK: - leaving this app (Settings → Account)

/// "Leave <app>": this app's access goes, with its data on its server (where it keeps any) and on this iPhone; the
/// account and the other apps stay. The order matters: the server's data first (once the access is gone, the server
/// refuses this account), then the access. Afterwards the session closes this app (`updateAccess`), which forgets its
/// data on the phone and removes its push device; the shared login stays.
@MainActor @Observable
final class LeaveAppFlow {
    enum Phase: Equatable { case ready, leaving, left, failed(AccountFailure) }

    private(set) var phase: Phase = .ready
    /// The app's server deleted the account's data, but the access is still there (the second step failed).
    private(set) var serverDataDeleted = false

    @ObservationIgnored private let session: EmpireSession
    @ObservationIgnored private let serverData: URL?
    @ObservationIgnored private let sample: Bool
    @ObservationIgnored private let sampleDelay: Duration

    /// - Parameter serverData: the app's `DELETE …/me`, when its server keeps data per account (today Arestemis).
    init(session: EmpireSession, serverData: URL?, sample: Bool = false, sampleDelay: Duration = .seconds(1.2)) {
        self.session = session
        self.serverData = serverData
        self.sample = sample
        self.sampleDelay = sampleDelay
    }

    var failure: AccountFailure? { if case .failed(let failure) = phase { failure } else { nil } }

    func leave() async {
        guard phase != .leaving, phase != .left else { return }
        phase = .leaving
        if sample {
            try? await Task.sleep(for: sampleDelay)
            phase = .left
            return
        }
        guard let token = session.token else { phase = .failed(.loggedOut); return }
        let service = session.app.service
        let generation = session.generation
        let client = session.accountClient
        do {
            if let serverData {
                try await client.deleteServiceData(at: serverData, token: token)
                serverDataDeleted = true
            }
            let access = try await client.leave(service: service, token: token)
            guard generation == session.generation else { phase = .failed(.loggedOut); return }
            phase = .left
            // The server took the access away: this app closes, also if its answer still named the service.
            session.updateAccess(services: access.services.filter { $0 != service },
                                 requested: access.requested.filter { $0 != service })
        } catch {
            if error == .loggedOut { session.handleAuthFailure(HTTPError.unauthorized, generation: generation) }
            phase = .failed(error)
        }
    }

    #if DEBUG
    func debugShow(_ phase: Phase, serverDataDeleted: Bool = false) {
        self.phase = phase
        self.serverDataDeleted = serverDataDeleted
    }
    #endif
}

// MARK: - deleting the account (Settings → Account)

/// "Delete Ares account": the password is checked first (a login with it), then the person confirms, then the account
/// is deleted with that fresh login; the account server deletes its data in every service. Afterwards the login ends in
/// every app. Until the deletion answers 204 nothing changes on the phone.
@MainActor @Observable
final class DeleteAccountFlow {
    enum Phase: Equatable { case writing, checking, confirming, deleting, deleted, failed(AccountFailure) }

    var password = ""
    private(set) var phase: Phase = .writing

    @ObservationIgnored private let session: EmpireSession
    @ObservationIgnored private let sample: Bool
    @ObservationIgnored private let sampleDelay: Duration
    /// The login the password check made: it proves the password and deletes the account. Never saved.
    @ObservationIgnored private var checkedLogin: String?

    init(session: EmpireSession, sample: Bool = false, sampleDelay: Duration = .seconds(1.2)) {
        self.session = session
        self.sample = sample
        self.sampleDelay = sampleDelay
    }

    var failure: AccountFailure? { if case .failed(let failure) = phase { failure } else { nil } }

    var canCheck: Bool {
        switch phase {
        case .writing, .failed: !password.isEmpty
        default: false
        }
    }

    var isWorking: Bool { phase == .checking || phase == .deleting }

    /// Checks the password; on success the screen asks for the confirmation (`phase == .confirming`).
    func check() async {
        guard canCheck else { return }
        phase = .checking
        if sample {
            try? await Task.sleep(for: sampleDelay)
            password = ""
            phase = .confirming
            return
        }
        guard session.token != nil, let email = session.email, let id = session.accountID else {
            phase = .failed(.loggedOut)
            return
        }
        let generation = session.generation
        do {
            let response = try await session.authClient.login(email: email, password: password)
            // Only ever this account, and only while it is still the one logged in.
            guard generation == session.generation, response.record.id == id else { phase = .failed(.other); return }
            checkedLogin = response.token
            password = ""
            phase = .confirming
        } catch HTTPError.server(400, _) {
            phase = .failed(.wrongPassword)
        } catch {
            phase = .failed(AccountFailure(error))
        }
    }

    /// The person did not confirm: nothing happens, the password is asked again next time.
    func cancel() {
        guard phase == .confirming else { return }
        checkedLogin = nil
        phase = .writing
    }

    func delete() async {
        guard phase == .confirming else { return }
        phase = .deleting
        if sample {
            try? await Task.sleep(for: sampleDelay)
            phase = .deleted
            return
        }
        guard let token = checkedLogin, let id = session.accountID else { phase = .failed(.other); return }
        checkedLogin = nil
        let generation = session.generation
        do {
            try await session.accountClient.deleteAccount(id: id, token: token)
            phase = .deleted
            session.accountDeleted()
        } catch {
            if error == .loggedOut { session.handleAuthFailure(HTTPError.unauthorized, generation: generation) }
            phase = .failed(error)
        }
    }

    #if DEBUG
    func debugPhase(_ phase: Phase) { self.phase = phase }
    #endif
}

#if DEBUG
// MARK: - screenshots

/// Screenshots of the account screens (DEBUG): `-accountPhase <state>` shows a form's state without sending; which
/// states a form knows is listed at each `applyDebugArguments`. `-accountEmail <text>` fills the email fields.
enum AccountDebug {
    static func value(_ name: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    static func phase(_ arguments: [String]) -> String? { value("-accountPhase", in: arguments) }

    /// The failures by name, for `-accountPhase offline` and the like.
    static func failure(_ name: String?) -> AccountFailure? {
        switch name {
        case "offline": .offline
        case "tooMany": .tooMany
        case "unavailable": .unavailable
        case "other": .other
        case "wrongPassword": .wrongPassword
        case "wrongCurrent": .wrongCurrentPassword
        case "emailTaken": .emailTaken
        case "invalidEmail": .invalidEmail
        case "tooShort": .passwordTooShort
        case "passwordsDiffer": .passwordsDiffer
        default: nil
        }
    }
}

extension SignUpForm {
    /// `-accountPhase sending|done|notSent|<failure>`; `notSent`: the account exists, its email did not go out.
    func applyDebugArguments(_ arguments: [String]) {
        if let email = AccountDebug.value("-accountEmail", in: arguments) { self.email = email }
        switch AccountDebug.phase(arguments) {
        case "sending": phase = .sending
        case "done": phase = .done
        case "notSent":
            accountCreated = true
            phase = .failed(.offline)
        case let name: if let failure = AccountDebug.failure(name) { phase = .failed(failure) }
        }
    }
}

extension PasswordResetForm {
    /// `-accountPhase sending|sent|<failure>`.
    func applyDebugArguments(_ arguments: [String]) {
        if let email = AccountDebug.value("-accountEmail", in: arguments) { self.email = email }
        switch AccountDebug.phase(arguments) {
        case "sending": phase = .sending
        case "sent": phase = .sent
        case let name: if let failure = AccountDebug.failure(name) { phase = .failed(failure) }
        }
    }
}

extension ChangePasswordForm {
    /// `-accountPhase changing|done|loginFailed|<failure>`.
    func applyDebugArguments(_ arguments: [String]) {
        switch AccountDebug.phase(arguments) {
        case "changing": debugPhase(.changing)
        case "done": debugPhase(.done)
        case "loginFailed": debugPhase(.loginFailed(.offline))
        case let name: if let failure = AccountDebug.failure(name) { debugPhase(.failed(failure)) }
        }
    }
}

extension LeaveAppFlow {
    /// `-accountPhase leaving|dataDeleted|<failure>`; `dataDeleted`: the server's data went, the access did not.
    func applyDebugArguments(_ arguments: [String]) {
        switch AccountDebug.phase(arguments) {
        case "leaving": debugShow(.leaving)
        case "dataDeleted": debugShow(.failed(.offline), serverDataDeleted: true)
        case let name: if let failure = AccountDebug.failure(name) { debugShow(.failed(failure)) }
        }
    }
}

extension DeleteAccountFlow {
    /// `-accountPhase checking|confirming|deleting|<failure>`.
    func applyDebugArguments(_ arguments: [String]) {
        switch AccountDebug.phase(arguments) {
        case "checking": debugPhase(.checking)
        case "confirming": debugPhase(.confirming)
        case "deleting": debugPhase(.deleting)
        case let name: if let failure = AccountDebug.failure(name) { debugPhase(.failed(failure)) }
        }
    }
}

extension AccessRequest {
    /// `-accountPhase asking|asked|<failure>`.
    func applyDebugArguments(_ arguments: [String]) {
        switch AccountDebug.phase(arguments) {
        case "asking": debugShow(asked: false, phase: .asking)
        case "asked": debugShow(asked: true, phase: .ready)
        case let name: if let failure = AccountDebug.failure(name) { debugShow(asked: false, phase: .failed(failure)) }
        }
    }
}
#endif
