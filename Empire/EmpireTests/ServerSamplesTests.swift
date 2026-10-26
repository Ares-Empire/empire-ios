import Foundation
import Testing
@testable import Empire

/// The hub's own answers decode into the app's types, and its errors land where the contract says (council
/// 2026-10-25: the app's fixtures were hand-written and differed from the server). The files in `ServerSamples/` are
/// made by the hub's code (ares-empire `tools/empire_samples.py`); refresh them with `scripts/empire-fixtures.sh`.
@MainActor
struct ServerSamplesTests {
    private final class BundleToken {}

    private func sample(_ name: String) throws -> Data {
        let bundle = Bundle(for: BundleToken.self)
        let url = try #require(bundle.url(forResource: name, withExtension: "json")
                               ?? bundle.url(forResource: name, withExtension: "json", subdirectory: "ServerSamples"),
                               "\(name).json is missing: run scripts/empire-fixtures.sh")
        return try Data(contentsOf: url)
    }

    @Test func adminSeesEveryProvinceTheIdeasAndTheCount() throws {
        let data = try JSONDecoder().decode(EmpireData.self, from: sample("empire.admin"))
        #expect(data.me.admin && data.version == 2)
        #expect(!data.projects.isEmpty && data.addable.isEmpty)
        #expect(!data.ideas.isEmpty && data.pending != nil)
    }

    @Test func memberSeesOnlyTheirRing() throws {
        let data = try JSONDecoder().decode(EmpireData.self, from: sample("empire.member"))
        #expect(!data.me.admin && data.projects.count == 1 && data.ideas.isEmpty)
        #expect(data.chronicle.allSatisfy { entry in data.projects.contains { $0.slug == entry.project } })
    }

    @Test func newMemberHasAnEmptyRing() throws {
        let data = try JSONDecoder().decode(EmpireData.self, from: sample("empire.new-member"))
        #expect(data.projects.isEmpty && data.chronicle.isEmpty && !data.me.admin)
    }

    @Test func memberRingIsWhatTheAccountHasWithItsInstallLink() throws {
        let data = try JSONDecoder().decode(EmpireData.self, from: sample("empire.member"))
        #expect(data.projects.allSatisfy { $0.access == .granted })
        #expect(data.projects.contains { $0.install != nil })
        #expect(data.addable.allSatisfy { $0.install == nil && $0.access != .granted })
    }

    @Test(arguments: ["empire.requested", "access-request"])
    func askedAppShowsAsRequested(_ name: String) throws {
        let data = try JSONDecoder().decode(EmpireData.self, from: sample(name))
        let asked = try #require(data.addable.first { $0.access == .requested })
        #expect(!asked.isComingSoon)
        #expect(data.addable.contains { $0.isComingSoon && $0.access == .notRequested })
    }

    @Test func approvalsAndTheDecisionAnswerDecode() throws {
        let list = try JSONDecoder().decode([PendingAccount].self, from: sample("approvals"))
        #expect(!list.isEmpty && list.allSatisfy { $0.verified != nil })
        let answer = try JSONDecoder().decode(DecisionAnswer.self, from: sample("approval-decision"))
        #expect(answer.pending != nil)
    }

    /// Each error file with the status the hub sends it with, and what `checkResponse` must make of it.
    @Test(arguments: [("error.unauthorized", 401), ("error.no_access", 403), ("error.admin_only", 403),
                      ("error.bad_request", 400), ("error.not_found", 404), ("error.unavailable", 503),
                      ("error.server_error", 500)])
    func errorsMapAsTheContractSays(_ name: String, _ status: Int) throws {
        let body = try sample(name)
        let message = try JSONDecoder().decode(ServerMessage.self, from: body)
        let sentence = try #require(message.sentence)
        let code = try #require(message.code)
        #expect("error.\(code)" == name)
        let response = try #require(HTTPURLResponse(url: URL(string: "https://www.ares-empire.de/api/empire")!,
                                                    statusCode: status, httpVersion: nil, headerFields: nil))
        var loggedOut = false
        do {
            try checkResponse(response, data: body) { loggedOut = true }
            Issue.record("\(name) did not throw")
        } catch HTTPError.unauthorized {
            #expect(status == 401 && loggedOut)
        } catch HTTPError.forbidden(let forbiddenCode, let forbiddenMessage) {
            #expect(code == "admin_only" && forbiddenCode == code && forbiddenMessage == sentence)
        } catch HTTPError.server(let serverStatus, let serverMessage) {
            #expect(serverStatus == status && serverMessage == sentence && code != "admin_only")
        }
        #expect(loggedOut == (status == 401))
    }
}
