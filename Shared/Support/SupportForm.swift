import Foundation
import Observation

/// The state of the "Contact & support" form (`SupportSheet`): what is written, and how sending goes.
/// Sending builds a `SupportMessage` with the session's login and posts it (`SupportAPI`). A rejected login (401) goes
/// through `session.handleAuthFailure` (the app logs out, everywhere); a 403 here is about this message only and never
/// closes the app. In an app that works without an account (Aresium) and while no Ares app is logged in, the message
/// goes without a login instead (`sendsWithoutLogin`, a `ContactMessage` with an email to answer to); the other apps
/// never take that path. In sample mode nothing is sent: a short pause, then success.
@MainActor @Observable
final class SupportForm {
    enum Phase: Equatable { case writing, sending, sent, failed(SupportFailure) }

    var kind: SupportKind = .problem
    var text = ""
    /// Without a login: where the answer goes, and an optional name.
    var email = ""
    var name = ""
    private(set) var phase: Phase = .writing

    @ObservationIgnored private let session: EmpireSession
    @ObservationIgnored private let sample: Bool
    @ObservationIgnored private let api: SupportAPI
    @ObservationIgnored private let device: () -> SupportDevice
    @ObservationIgnored private let language: AppLanguage
    @ObservationIgnored private let sampleDelay: Duration

    init(session: EmpireSession, sample: Bool = false, api: SupportAPI = SupportAPI(),
         device: @escaping () -> SupportDevice = { .current }, language: AppLanguage = .current,
         sampleDelay: Duration = .seconds(1.2)) {
        self.session = session
        self.sample = sample
        self.api = api
        self.device = device
        self.language = language
        self.sampleDelay = sampleDelay
    }

    /// The message goes without a login (`ContactMessage`): the app works without an account and no Ares app on the
    /// iPhone is logged in. The form then asks for an email to answer to.
    var sendsWithoutLogin: Bool { session.app.accountOptional && session.token == nil }

    /// The message's length against the server's limit (without a login, less the footer the message carries).
    var length: Int { SupportMessage.length(text) }
    var maxLength: Int {
        sendsWithoutLogin ? ContactMessage.maxTextLength(footer: ContactMessage.footer(kind: kind, app: session.app,
                                                                                       device: device()))
                          : SupportMessage.maxLength
    }
    var isTooLong: Bool { length > maxLength }

    /// Something written, within the limit (and an email to answer to, without a login), and not already on its way
    /// or sent.
    var canSend: Bool {
        guard (1...maxLength).contains(length) else { return false }
        if sendsWithoutLogin, AccountInput.trimmedEmail(email).isEmpty { return false }
        return phase != .sending && phase != .sent
    }

    /// Closing would lose what was written (the form asks first).
    var hasUnsentText: Bool { phase != .sent && !SupportMessage.trimmed(text).isEmpty }

    var failure: SupportFailure? { if case .failed(let failure) = phase { failure } else { nil } }

    func send() async {
        guard canSend else { return }
        phase = .sending
        do {
            if sample {
                try await Task.sleep(for: sampleDelay)
            } else {
                try await sendToServer()
            }
            phase = .sent
        } catch {
            phase = .failed(SupportFailure(error))
        }
    }

    #if DEBUG
    /// Screenshots only (`SupportSheet`'s launch arguments): show a state without sending.
    func debugPhase(_ phase: Phase) { self.phase = phase }
    #endif

    private func sendToServer() async throws {
        if sendsWithoutLogin {
            let message: ContactMessage
            do {
                message = try ContactMessage(kind: kind, text: text, email: email, name: name, app: session.app,
                                             device: device(), language: language)
            } catch .email {
                throw SupportFailure.invalidEmail
            } catch {
                throw SupportFailure.other
            }
            try await api.sendContact(message)
            return
        }
        guard let token = session.token else { throw SupportFailure.loggedOut }
        let generation = session.generation
        let message: SupportMessage
        do {
            message = try SupportMessage(kind: kind, text: text, token: token, app: session.app, device: device(),
                                         language: language)
        } catch {
            throw SupportFailure.other
        }
        do {
            try await api.send(message, token: token)
        } catch HTTPError.unauthorized {
            session.handleAuthFailure(HTTPError.unauthorized, generation: generation, token: token)
            throw HTTPError.unauthorized
        }
    }
}
