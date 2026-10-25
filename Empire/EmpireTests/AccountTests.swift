import Foundation
import Testing
@testable import Empire

/// Shared/Auth: the account's own actions (AccountForms, EmpireAccountClient) against a fake account server: what is
/// sent, in which order, and that a failed step never leaves the login half done.
@MainActor
struct AccountTests {
    static let account = "accounta0000001"
    static let email = "member@example.invalid"
    static let oldToken = SharedLoginTests.token(account: account)
    static let newToken = SharedLoginTests.token(account: account, renewal: 1)

    static func record(account: String = account, services: [String] = ["empire"], requested: [String] = []) -> [String: Any] {
        ["id": account, "email": email, "approved": true, "services": services, "requested": requested]
    }

    static func json(_ object: Any) -> Data { try! JSONSerialization.data(withJSONObject: object) }

    static func login(_ token: String, account: String = account, services: [String] = ["empire"],
                      requested: [String] = []) -> Data {
        json(["token": token, "record": record(account: account, services: services, requested: requested)])
    }

    /// A PocketBase 400 naming one field.
    static func refused(_ field: String, code: String = "validation_invalid_value") -> Data {
        json(["status": 400, "message": "Failed.", "data": [field: ["code": code, "message": "Fictional."]]])
    }

    /// A session of `app`, logged in as the account with `services`; the server's requests so far are cleared.
    func signedIn(_ app: EmpireAppIdentity = .empire, services: [String] = ["empire"], requested: [String] = [],
                  server: EmpireFakeTransport) async -> (EmpireSession, EmpireMemoryTokens) {
        let storage = EmpireMemoryTokens()
        server.responses = [(200, Self.login(Self.oldToken, services: services, requested: requested))]
        let session = EmpireSession(app: app, storage: storage, client: EmpireAuthClient(transport: server),
                                    restoreOnLaunch: false)
        await session.login(email: Self.email, password: "fictional-password")
        server.requests.removeAll()
        return (session, storage)
    }

    func loggedOut(_ app: EmpireAppIdentity = .empire, server: EmpireFakeTransport) -> EmpireSession {
        EmpireSession(app: app, storage: EmpireMemoryTokens(), client: EmpireAuthClient(transport: server),
                      restoreOnLaunch: false)
    }

    static func body(_ request: URLRequest?) -> [String: Any]? {
        request?.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    }

    static func path(_ request: URLRequest?) -> String? {
        request.flatMap { "\($0.httpMethod ?? "") \($0.url?.absoluteString ?? "")" }
    }

    static let users = "https://auth.ares-empire.de/api/collections/users"

    // MARK: creating an account

    @Test func signUpSendsTheAccountThenTheConfirmationEmail() async {
        let server = EmpireFakeTransport()
        server.responses = [(200, Self.json(["id": "newaccount00001"])), (204, Data())]
        let form = SignUpForm(session: loggedOut(.arestemis, server: server), language: .german)
        form.email = "  new@example.invalid "
        form.password = "fictional-pass"
        form.passwordAgain = "fictional-pass"
        form.name = " Kim Sample "
        await form.send()

        #expect(form.phase == .done && form.accountCreated)
        #expect(server.requests.map { Self.path($0) } == [
            "POST \(Self.users)/records", "POST \(Self.users)/request-verification",
        ])
        let account = Self.body(server.requests.first)
        #expect(account?["email"] as? String == "new@example.invalid")
        #expect(account?["password"] as? String == "fictional-pass")
        #expect(account?["passwordConfirm"] as? String == "fictional-pass")
        #expect(account?["name"] as? String == "Kim Sample")
        #expect(account?["requested"] as? [String] == ["arestemis"])     // the app it was made in
        #expect(account?["language"] as? String == "de")
        #expect(account?.count == 6)
        #expect(Self.body(server.requests.last) as? [String: String] == ["email": "new@example.invalid"])
        #expect(server.requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == nil })
        #expect(form.password.isEmpty && form.passwordAgain.isEmpty)
    }

    @Test func signUpLeavesOutAnEmptyName() async {
        let server = EmpireFakeTransport()
        server.responses = [(200, Self.json(["id": "newaccount00001"])), (204, Data())]
        let form = SignUpForm(session: loggedOut(server: server), language: .english)
        form.email = "new@example.invalid"
        form.password = "fictional-pass"
        form.passwordAgain = "fictional-pass"
        form.name = "   "
        await form.send()
        let account = Self.body(server.requests.first)
        #expect(account?["name"] == nil && account?["requested"] as? [String] == ["empire"])
        #expect(account?["language"] as? String == "en")
    }

    @Test func signUpChecksTheFieldsBeforeSendingAnything() async {
        let server = EmpireFakeTransport()
        let form = SignUpForm(session: loggedOut(server: server))
        func attempt(_ email: String, _ password: String, _ again: String) async -> AccountFailure? {
            form.email = email
            form.password = password
            form.passwordAgain = again
            await form.send()
            return form.failure
        }
        #expect(await attempt("not-an-email", "fictional-pass", "fictional-pass") == .invalidEmail)
        #expect(await attempt("a@b", "fictional-pass", "fictional-pass") == .invalidEmail)
        #expect(await attempt("new@example.invalid", "short", "short") == .passwordTooShort)
        #expect(await attempt("new@example.invalid", String(repeating: "x", count: 72),
                              String(repeating: "x", count: 72)) == .passwordTooLong)
        #expect(await attempt("new@example.invalid", "fictional-pass", "fictional-pas") == .passwordsDiffer)
        #expect(server.requests.isEmpty)
    }

    @Test func aFailedConfirmationEmailIsSentAgainOnItsOwn() async {
        let server = EmpireFakeTransport()
        server.responses = [(200, Self.json(["id": "newaccount00001"])), (429, Self.json(["message": "Too Many Requests."]))]
        let form = SignUpForm(session: loggedOut(server: server))
        form.email = "new@example.invalid"
        form.password = "fictional-pass"
        form.passwordAgain = "fictional-pass"
        await form.send()
        #expect(form.phase == .failed(.tooMany) && form.accountCreated && form.canSend)

        server.responses = [(204, Data())]
        await form.send()
        #expect(form.phase == .done)
        #expect(server.requests.map { $0.url?.lastPathComponent } == ["records", "request-verification",
                                                                      "request-verification"])
    }

    @Test func anEmailInUseSaysSoAndCreatesNothing() async {
        let server = EmpireFakeTransport()
        server.responses = [(400, Self.refused("email", code: "validation_not_unique"))]
        let form = SignUpForm(session: loggedOut(server: server))
        form.email = "taken@example.invalid"
        form.password = "fictional-pass"
        form.passwordAgain = "fictional-pass"
        await form.send()
        #expect(form.phase == .failed(.emailTaken) && !form.accountCreated && server.requests.count == 1)
        #expect(form.failure?.message == "There is already an account with this email. Log in, or reset its password.")
    }

    // MARK: a forgotten password

    @Test func aPasswordResetSaysTheSameEitherWay() async {
        let server = EmpireFakeTransport()
        server.responses = [(204, Data())]
        let form = PasswordResetForm(session: loggedOut(server: server), email: " someone@example.invalid ")
        await form.send()
        #expect(form.phase == .sent)
        #expect(Self.path(server.requests.first) == "POST \(Self.users)/request-password-reset")
        #expect(Self.body(server.requests.first) as? [String: String] == ["email": "someone@example.invalid"])
    }

    @Test func aPasswordResetNamesWhyItDidNotGo() async {
        let server = EmpireFakeTransport()
        server.responses = [(429, Data())]
        let form = PasswordResetForm(session: loggedOut(server: server), email: "someone@example.invalid")
        await form.send()
        #expect(form.phase == .failed(.tooMany))
        server.failure = URLError(.notConnectedToInternet)
        await form.send()
        #expect(form.phase == .failed(.offline))
        form.email = "nonsense"
        await form.send()
        #expect(form.phase == .failed(.invalidEmail) && server.requests.count == 2)
    }

    // MARK: asking for this app

    @Test func askingForAccessKeepsTheOtherRequests() async {
        let server = EmpireFakeTransport()
        let (session, storage) = await signedIn(.arestemis, services: ["empire"], server: server)
        #expect(session.isDenied && session.canAskForAccess && !session.hasAskedForAccess)
        server.responses = [
            (200, Self.json(Self.record(requested: ["aresus"]))),               // asked for Aresus meanwhile
            (200, Self.json(Self.record(requested: ["aresus", "arestemis"]))),
        ]
        let request = AccessRequest(session: session)
        await request.ask()

        #expect(server.requests.map { Self.path($0) } == [
            "GET \(Self.users)/records/\(Self.account)", "PATCH \(Self.users)/records/\(Self.account)",
        ])
        #expect(server.requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer \(Self.oldToken)" })
        #expect(Self.body(server.requests.last)?["requested"] as? [String] == ["aresus", "arestemis"])
        #expect(request.isAsked && session.hasAskedForAccess && request.phase == .ready)
        #expect(session.isDenied && storage.token == Self.oldToken)          // asked, not granted; login kept

        await request.ask()
        #expect(server.requests.count == 2)                                   // once is enough
    }

    @Test func anAccountThatAskedAlreadyShowsItAtOnce() async {
        let server = EmpireFakeTransport()
        let (session, _) = await signedIn(.arestemis, services: ["empire"], requested: ["arestemis"], server: server)
        let request = AccessRequest(session: session)
        #expect(request.isAsked)
        await request.ask()
        #expect(server.requests.isEmpty)
    }

    @Test func aRefusedLoginWhileAskingLogsOutButARefusalDoesNot() async {
        let server = EmpireFakeTransport()
        let (session, storage) = await signedIn(.arestemis, services: ["empire"], server: server)
        server.responses = [(403, Self.json(["message": "Only superusers can perform this action."]))]
        let request = AccessRequest(session: session)
        await request.ask()
        #expect(request.phase == .failed(.other) && storage.token == Self.oldToken && session.isDenied)

        server.responses = [(401, Data())]
        await request.ask()
        #expect(request.phase == .failed(.loggedOut) && storage.token == nil && session.token == nil)
    }

    @Test func anAccountApprovedMeanwhileOpensTheApp() async {
        let server = EmpireFakeTransport()
        let (session, _) = await signedIn(.arestemis, services: ["empire"], server: server)
        server.responses = [
            (200, Self.json(Self.record(services: ["empire", "arestemis"]))),
            (200, Self.login(Self.oldToken, services: ["empire", "arestemis"])),     // the login's check
        ]
        await AccessRequest(session: session).ask()
        #expect(session.isSignedIn && server.requests.last?.url?.lastPathComponent == "auth-refresh")
    }

    // MARK: changing the password

    @Test func changingThePasswordLogsInAgainWithTheNewOne() async {
        let server = EmpireFakeTransport()
        let (session, storage) = await signedIn(server: server)
        var resets = 0
        session.onAppDataReset { resets += 1 }
        let generation = session.generation
        server.responses = [(200, Self.json(Self.record())), (200, Self.login(Self.newToken))]
        let form = ChangePasswordForm(session: session)
        form.current = "fictional-password"
        form.newPassword = "fictional-new-pass"
        form.newAgain = "fictional-new-pass"
        await form.change()

        #expect(form.phase == .done)
        #expect(server.requests.map { Self.path($0) } == [
            "PATCH \(Self.users)/records/\(Self.account)", "POST \(Self.users)/auth-with-password",
        ])
        #expect(server.requests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer \(Self.oldToken)")
        #expect(Self.body(server.requests.first) as? [String: String] == [
            "oldPassword": "fictional-password", "password": "fictional-new-pass", "passwordConfirm": "fictional-new-pass",
        ])
        #expect(Self.body(server.requests.last) as? [String: String] == [
            "identity": Self.email, "password": "fictional-new-pass",
        ])
        // The new login, for this app and (through the shared item) the others; the same session, its data kept.
        #expect(session.token == Self.newToken && storage.token == Self.newToken && session.isSignedIn)
        #expect(session.generation == generation && resets == 0 && !session.isChangingPassword)
        #expect(form.current.isEmpty && form.newPassword.isEmpty && form.newAgain.isEmpty)
    }

    @Test func aWrongCurrentPasswordChangesNothing() async {
        let server = EmpireFakeTransport()
        let (session, storage) = await signedIn(server: server)
        server.responses = [(400, Self.refused("oldPassword", code: "validation_invalid_old_password"))]
        let form = ChangePasswordForm(session: session)
        form.current = "not-the-password"
        form.newPassword = "fictional-new-pass"
        form.newAgain = "fictional-new-pass"
        await form.change()
        #expect(form.phase == .failed(.wrongCurrentPassword) && server.requests.count == 1)
        #expect(session.isSignedIn && storage.token == Self.oldToken && !session.isChangingPassword)
        #expect(form.failure?.message == "The current password is wrong.")
    }

    @Test func theNewPasswordIsCheckedBeforeSending() async {
        let server = EmpireFakeTransport()
        let (session, _) = await signedIn(server: server)
        let form = ChangePasswordForm(session: session)
        form.current = "fictional-password"
        form.newPassword = "fictional-new-pass"
        form.newAgain = "fictional-new-pas"
        await form.change()
        #expect(form.phase == .failed(.passwordsDiffer) && server.requests.isEmpty)
    }

    @Test func anOldRequestRefusedDuringTheChangeIsNoLogout() async {
        let server = EmpireFakeTransport()
        let (session, storage) = await signedIn(server: server)
        server.responses = [(200, Self.json(Self.record())), (200, Self.login(Self.newToken))]
        let gate = EmpireRequestGate()
        server.nextGate = gate
        let form = ChangePasswordForm(session: session)
        form.current = "fictional-password"
        form.newPassword = "fictional-new-pass"
        form.newAgain = "fictional-new-pass"
        let change = Task { await form.change() }
        await gate.waitUntilPaused()
        #expect(session.isChangingPassword)
        // Another request of this app, made with the old token, comes back 401 meanwhile.
        session.handleAuthFailure(HTTPError.unauthorized, generation: session.generation)
        #expect(session.isSignedIn && storage.token == Self.oldToken)
        gate.resume()
        await change.value
        #expect(form.phase == .done && session.token == Self.newToken && !session.isChangingPassword)

        session.handleAuthFailure(HTTPError.unauthorized, generation: session.generation)
        #expect(!session.isSignedIn)                                          // afterwards a 401 logs out again
    }

    @Test func aFailedLoginWithTheNewPasswordOffersToTryAgain() async {
        let server = EmpireFakeTransport()
        let (session, storage) = await signedIn(server: server)
        server.responses = [(200, Self.json(Self.record())), (503, Data()), (503, Data())]
        let form = ChangePasswordForm(session: session, retryDelay: .zero)
        form.current = "fictional-password"
        form.newPassword = "fictional-new-pass"
        form.newAgain = "fictional-new-pass"
        await form.change()
        #expect(form.phase == .loginFailed(.unavailable) && form.holdsThePage)
        #expect(server.requests.map { $0.url?.lastPathComponent } == [Self.account, "auth-with-password", "auth-with-password"])
        #expect(session.isChangingPassword && storage.token == Self.oldToken)

        server.responses = [(200, Self.login(Self.newToken))]
        await form.retryLogin()
        #expect(form.phase == .done && session.token == Self.newToken && storage.token == Self.newToken)
        #expect(Self.body(server.requests.last)?["password"] as? String == "fictional-new-pass")
    }

    @Test func closingAfterAFailedLoginLogsOutWithALine() async {
        let server = EmpireFakeTransport()
        let (session, storage) = await signedIn(server: server)
        server.responses = [(200, Self.json(Self.record())), (400, Data()), (400, Data())]
        let form = ChangePasswordForm(session: session, retryDelay: .zero)
        form.current = "fictional-password"
        form.newPassword = "fictional-new-pass"
        form.newAgain = "fictional-new-pass"
        await form.change()
        #expect(form.phase == .loginFailed(.other))
        form.close()
        #expect(!session.isSignedIn && storage.token == nil && !session.isChangingPassword)
        #expect(session.notice == "Your password is changed. Log in with the new one." && session.error == nil)
    }

    // MARK: leaving this app

    @Test func leavingDeletesTheAppsDataFirstThenTheAccess() async {
        let server = EmpireFakeTransport()
        let (session, storage) = await signedIn(.arestemis, services: ["empire", "arestemis"], server: server)
        var resets = 0
        session.onAppDataReset { resets += 1 }
        server.responses = [(204, Data()), (200, Self.json(["services": ["empire"], "requested": [String]()]))]
        let flow = LeaveAppFlow(session: session, serverData: URL(string: "https://www.ares-empire.de/api/arestemis/me")!)
        await flow.leave()

        #expect(flow.phase == .left)
        #expect(server.requests.map { Self.path($0) } == [
            "DELETE https://www.ares-empire.de/api/arestemis/me", "POST https://auth.ares-empire.de/api/empire/leave",
        ])
        #expect(server.requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == "Bearer \(Self.oldToken)" })
        #expect(Self.body(server.requests.last) as? [String: String] == ["service": "arestemis"])
        // This app closes and forgets its data; the shared login stays for the other apps.
        #expect(session.isDenied && !session.isSignedIn && resets == 1)
        #expect(storage.token == Self.oldToken && session.token == Self.oldToken && session.services == ["empire"])
    }

    @Test func leavingAnAppWithoutDataOnItsServerOnlyRemovesTheAccess() async {
        let server = EmpireFakeTransport()
        let (session, _) = await signedIn(.aresus, services: ["empire", "aresus"], server: server)
        server.responses = [(200, Self.json(["services": ["empire"], "requested": [String]()]))]
        let flow = LeaveAppFlow(session: session, serverData: nil)
        await flow.leave()
        #expect(flow.phase == .left && server.requests.map { $0.url?.path } == ["/api/empire/leave"] && session.isDenied)
    }

    @Test func whenTheAppsDataCannotGoTheAccessStays() async {
        let server = EmpireFakeTransport()
        let (session, _) = await signedIn(.arestemis, services: ["empire", "arestemis"], server: server)
        server.responses = [(500, Data())]
        let flow = LeaveAppFlow(session: session, serverData: URL(string: "https://www.ares-empire.de/api/arestemis/me")!)
        await flow.leave()
        #expect(flow.phase == .failed(.other) && !flow.serverDataDeleted)
        #expect(server.requests.count == 1 && session.isSignedIn)               // no leave call without the data gone
    }

    @Test func whenLeavingStopsAfterTheDataWentItSaysSoAndTriesBothAgain() async {
        let server = EmpireFakeTransport()
        let (session, _) = await signedIn(.arestemis, services: ["empire", "arestemis"], server: server)
        server.responses = [(204, Data()), (503, Data())]
        let flow = LeaveAppFlow(session: session, serverData: URL(string: "https://www.ares-empire.de/api/arestemis/me")!)
        await flow.leave()
        #expect(flow.phase == .failed(.unavailable) && flow.serverDataDeleted && session.isSignedIn)

        server.responses = [(204, Data()), (200, Self.json(["services": ["empire"], "requested": [String]()]))]
        await flow.leave()
        #expect(flow.phase == .left && session.isDenied)
        #expect(server.requests.map { $0.httpMethod } == ["DELETE", "POST", "DELETE", "POST"])
    }

    @Test func aRefusedLoginWhileLeavingLogsOut() async {
        let server = EmpireFakeTransport()
        let (session, storage) = await signedIn(.arestemis, services: ["empire", "arestemis"], server: server)
        server.responses = [(401, Data())]
        let flow = LeaveAppFlow(session: session, serverData: URL(string: "https://www.ares-empire.de/api/arestemis/me")!)
        await flow.leave()
        #expect(flow.phase == .failed(.loggedOut) && storage.token == nil && server.requests.count == 1)
    }

    // MARK: deleting the account

    @Test func deletingChecksThePasswordFirstThenDeletesWithThatLogin() async {
        let server = EmpireFakeTransport()
        let (session, storage) = await signedIn(server: server)
        server.responses = [(200, Self.login(Self.newToken))]
        let flow = DeleteAccountFlow(session: session)
        flow.password = "fictional-password"
        await flow.check()

        #expect(flow.phase == .confirming && flow.password.isEmpty)
        #expect(server.requests.map { Self.path($0) } == ["POST \(Self.users)/auth-with-password"])
        #expect(Self.body(server.requests.first) as? [String: String] == [
            "identity": Self.email, "password": "fictional-password",
        ])
        #expect(session.isSignedIn && storage.token == Self.oldToken)            // nothing deleted yet

        server.responses = [(204, Data())]
        await flow.delete()
        #expect(flow.phase == .deleted)
        #expect(Self.path(server.requests.last) == "DELETE \(Self.users)/records/\(Self.account)")
        #expect(server.requests.last?.value(forHTTPHeaderField: "Authorization") == "Bearer \(Self.newToken)")
        // Logged out everywhere, with a calm line instead of an error.
        #expect(!session.isSignedIn && session.token == nil && storage.token == nil)
        #expect(session.notice == "Your Ares account is deleted." && session.error == nil)
    }

    @Test func aWrongPasswordDeletesNothing() async {
        let server = EmpireFakeTransport()
        let (session, storage) = await signedIn(server: server)
        server.responses = [(400, Self.json(["message": "Failed to authenticate."]))]
        let flow = DeleteAccountFlow(session: session)
        flow.password = "not-the-password"
        await flow.check()
        #expect(flow.phase == .failed(.wrongPassword) && flow.failure?.message == "Wrong password.")
        await flow.delete()
        #expect(server.requests.count == 1 && session.isSignedIn && storage.token == Self.oldToken)
    }

    @Test func notConfirmingDeletesNothing() async {
        let server = EmpireFakeTransport()
        let (session, _) = await signedIn(server: server)
        server.responses = [(200, Self.login(Self.newToken))]
        let flow = DeleteAccountFlow(session: session)
        flow.password = "fictional-password"
        await flow.check()
        flow.cancel()
        await flow.delete()
        #expect(flow.phase == .writing && server.requests.count == 1 && session.isSignedIn)
    }

    @Test func aFailedDeletionKeepsTheLogin() async {
        let server = EmpireFakeTransport()
        let (session, storage) = await signedIn(server: server)
        server.responses = [(200, Self.login(Self.newToken)), (404, Self.json(["message": "Not found."]))]
        let flow = DeleteAccountFlow(session: session)
        flow.password = "fictional-password"
        await flow.check()
        await flow.delete()
        #expect(flow.phase == .failed(.other) && session.isSignedIn && storage.token == Self.oldToken)
        #expect(session.notice == nil)
    }

    @Test func anotherAccountsLoginNeverDeletes() async {
        let server = EmpireFakeTransport()
        let (session, _) = await signedIn(server: server)
        server.responses = [(200, Self.login(SharedLoginTests.token(account: "otheraccount001"), account: "otheraccount001"))]
        let flow = DeleteAccountFlow(session: session)
        flow.password = "fictional-password"
        await flow.check()
        await flow.delete()
        #expect(flow.phase == .failed(.other) && server.requests.count == 1 && session.isSignedIn)
    }

    // MARK: sample mode

    @Test func sampleModeNeverCallsTheServer() async {
        let server = EmpireFakeTransport()
        let session = loggedOut(server: server)
        let signUp = SignUpForm(session: session, sample: true, sampleDelay: .zero)
        signUp.email = "new@example.invalid"
        signUp.password = "fictional-pass"
        signUp.passwordAgain = "fictional-pass"
        await signUp.send()
        let leave = LeaveAppFlow(session: session, serverData: nil, sample: true, sampleDelay: .zero)
        await leave.leave()
        let delete = DeleteAccountFlow(session: session, sample: true, sampleDelay: .zero)
        delete.password = "fictional-password"
        await delete.check()
        await delete.delete()
        let access = AccessRequest(session: session, sample: true, sampleDelay: .zero)
        await access.ask()
        #expect(signUp.phase == .done && leave.phase == .left && delete.phase == .deleted && access.isAsked)
        #expect(server.requests.isEmpty)
    }

    // MARK: the lines

    @Test func answersBecomePlainLines() {
        #expect(AccountFailure(status: 204, body: Data()) == nil)
        #expect(AccountFailure(status: 401, body: Data()) == .loggedOut)
        #expect(AccountFailure(status: 429, body: Data()) == .tooMany)
        #expect(AccountFailure(status: 503, body: Data()) == .unavailable)
        #expect(AccountFailure(status: 500, body: Data()) == .other)
        #expect(AccountFailure(status: 400, body: Data()) == .other)
        #expect(AccountFailure(status: 400, body: Self.refused("oldPassword")) == .wrongCurrentPassword)
        #expect(AccountFailure(status: 400, body: Self.refused("email", code: "validation_not_unique")) == .emailTaken)
        #expect(AccountFailure(status: 400, body: Self.refused("email", code: "validation_is_email")) == .invalidEmail)
        #expect(AccountFailure(status: 400, body: Self.refused("password", code: "validation_min_text_constraint"))
                == .passwordTooShort)
        #expect(AccountFailure(status: 400, body: Self.refused("passwordConfirm")) == .passwordsDiffer)
        #expect(AccountFailure(URLError(.notConnectedToInternet)) == .offline)
        #expect(AccountFailure(URLError(.timedOut)) == .offline)
        #expect(AccountFailure(HTTPError.unauthorized) == .loggedOut)

        #expect(AccountFailure.offline.message == "No connection. Try again when you're online.")
        #expect(AccountFailure.tooMany.message == "Too many tries for now. Please wait a few minutes.")
        #expect(AccountFailure.loggedOut.message == "Your session expired. Please log in again.")
        #expect(AccountFailure.other.message == "It didn't go through. Please try again.")
        #expect(AccountFailure.passwordTooShort.message == "The password needs at least 8 characters.")
    }

    @Test func theLoginErrorAlsoNamesAnAccountNotConfirmedOrApproved() async {
        let server = EmpireFakeTransport(data: Self.json(["message": "Failed to authenticate."]))
        server.status = 400
        let session = loggedOut(server: server)
        await session.login(email: Self.email, password: "fictional-password")
        #expect(session.error == "Wrong email or password, or the account is not confirmed or approved yet.")
    }

    @Test func recognisesAnEmailAddress() {
        #expect(AccountInput.looksLikeEmail("someone@example.invalid"))
        #expect(AccountInput.looksLikeEmail(" someone@mail.example.de "))
        #expect(!AccountInput.looksLikeEmail("someone@example"))
        #expect(!AccountInput.looksLikeEmail("@example.invalid"))
        #expect(!AccountInput.looksLikeEmail("some one@example.invalid"))
        #expect(!AccountInput.looksLikeEmail("someone@example."))
        #expect(!AccountInput.looksLikeEmail("a@b@example.invalid"))
    }

    // MARK: the session

    @Test func theAccountsRequestsComeWithItsRecord() throws {
        let decoded = try JSONDecoder().decode(EmpireRecord.self, from: Self.json(Self.record(requested: ["aresus"])))
        #expect(decoded.requested == ["aresus"] && decoded.email == Self.email)
        var old = Self.record()
        old["requested"] = nil
        #expect(try JSONDecoder().decode(EmpireRecord.self, from: Self.json(old)).requested.isEmpty)
        old["requested"] = ""                                            // PocketBase's empty select
        #expect(try JSONDecoder().decode(EmpireRecord.self, from: Self.json(old)).requested.isEmpty)
    }

    @Test func anotherAccountsLoginIsNeverTakenOver() async {
        let server = EmpireFakeTransport()
        let (session, storage) = await signedIn(server: server)
        let other = try? JSONDecoder().decode(AuthResponse.self, from: Self.login("other-token", account: "otheraccount001"))
        #expect(throws: (any Error).self) { try session.takeOverLogin(other!) }
        #expect(session.token == Self.oldToken && storage.token == Self.oldToken)
    }

    @Test func approvalsNameTheAppsAsked() throws {
        let decoded = try JSONDecoder().decode([PendingAccount].self, from: Self.json([
            ["id": "a", "email": "a@example.invalid", "name": "", "created": "2026-10-25",
             "requested": ["arestemis", "aresus"], "approved": true],
            ["id": "b", "email": "b@example.invalid", "name": "B", "created": "2026-10-25"],   // an older hub
        ]))
        #expect(decoded[0].approved && decoded[0].requestedApps == "Arestemis, Aresus")
        #expect(!decoded[1].approved && decoded[1].requested.isEmpty)
    }
}
