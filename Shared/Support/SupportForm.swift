import Foundation
import Observation

/// The state of the "Contact & support" form (`SupportSheet`): what is written, and how sending goes.
/// Sending builds a `SupportMessage` with the session's login and posts it (`SupportAPI`). A rejected login (401) goes
/// through `session.handleAuthFailure` (the app logs out, everywhere); a 403 here is about this message only and never
/// closes the app. In sample mode nothing is sent: a short pause, then success.
@MainActor @Observable
final class SupportForm {
    enum Phase: Equatable { case writing, sending, sent, failed(SupportFailure) }

    var kind: SupportKind = .problem
    var text = ""
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

    /// The message's length against the server's limit (`SupportMessage.maxLength`).
    var length: Int { SupportMessage.length(text) }
    var isTooLong: Bool { length > SupportMessage.maxLength }

    /// Something written, within the limit, and not already on its way or sent.
    var canSend: Bool {
        guard SupportMessage.isSendable(text) else { return false }
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
