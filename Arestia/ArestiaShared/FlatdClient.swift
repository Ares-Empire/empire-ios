import Foundation
import os

/// Why a request to flatd failed, in the terms the app shows (never a raw error).
nonisolated enum FlatdError: Error, Equatable, Sendable {
    /// No connection at all: the Mac is asleep, flatd is not running, or the phone is not on the home network.
    case unreachable
    /// Connected, but no answer in time: flatd may still have done it, so a command is never sent again elsewhere.
    case noAnswer
    /// 401: the key is wrong or flatd has a new one.
    case refused
    /// 404: flatd does not know this device, mode or scene (any more).
    case unknown
    /// 504: the device itself did not answer; nothing changed.
    case deviceDidNotAnswer
    /// 409: not possible now (a blind without a favourite spot asked to go there).
    case notPossible
    /// Any other refusal, with flatd's own sentence when it sent one.
    case failed(status: Int, message: String?)
    /// An answer this app cannot read.
    case invalidAnswer

    /// One short line for the person, in the app's language.
    func message(language: AppLanguage = .current) -> String {
        switch self {
        case .unreachable:
            language.string(LocalizedStringResource("Can't reach the flat. The Mac may be asleep, or you're not at home.",
                                                    table: "ArestiaShared"))
        case .noAnswer:
            language.string(LocalizedStringResource("The flat service didn't answer in time. It may still have done it.",
                                                    table: "ArestiaShared"))
        case .refused:
            language.string(LocalizedStringResource("The flat service refused the key. Enter it again in Settings.",
                                                    table: "ArestiaShared"))
        case .unknown:
            language.string(LocalizedStringResource("The flat service doesn't know this any more.", table: "ArestiaShared"))
        case .deviceDidNotAnswer:
            language.string(LocalizedStringResource("The device didn't answer. Nothing changed.", table: "ArestiaShared"))
        case .notPossible:
            language.string(LocalizedStringResource("That isn't possible right now.", table: "ArestiaShared"))
        case let .failed(status, message):
            message ?? language.string(LocalizedStringResource("The flat service couldn't do it (\(status)).",
                                                               table: "ArestiaShared"))
        case .invalidAnswer:
            language.string(LocalizedStringResource("The flat service sent an answer this app can't read.",
                                                    table: "ArestiaShared"))
        }
    }
}

/// Talks to flatd over HTTP (contract v1.1: every endpoint but `/api/health` needs `Authorization: Bearer <token>`).
/// The app, its intents and its Control Center controls all go through this one client, so nothing else builds a
/// request.
nonisolated struct FlatdClient: Sendable {
    let baseURL: URL
    let token: String
    var transport: any HTTPTransport & Sendable = URLSessionTransport()
    /// Reads answer quickly or not at all (the service is on the home network).
    var readTimeout: TimeInterval = 6
    /// A command waits for the device to confirm (a Rollo's board, a plug), so it may take longer.
    var commandTimeout: TimeInterval = 12

    // MARK: reads

    /// `GET /api/health`, without the key: whether this address answers like flatd (`{"ok": true, "version": …}`).
    func health() async throws -> Bool {
        let data: Data
        do {
            data = try await send(request("api/health", timeout: readTimeout, authorized: false))
        } catch let error as FlatdError where error != .unreachable && error != .noAnswer {
            return false                         // something answered, but not flatd's health
        }
        struct Health: Decodable { let ok: Bool?; let version: String? }
        guard let health = try? JSONDecoder().decode(Health.self, from: data) else { return false }
        return health.ok == true && health.version != nil
    }

    /// Before the key goes to an address: it must answer like flatd. Plain HTTP on the home network cannot prove who
    /// answers (that needs flatd to prove it knows the key, a contract change), but this keeps the key from a printer or
    /// a stranger's device that happens to have the saved address on another Wi-Fi. Throws `.unreachable` otherwise.
    func verify() async throws {
        guard try await health() else { throw FlatdError.unreachable }
    }

    func devices() async throws -> [Device] {
        struct Answer: Decodable { let devices: [Device] }
        return try decode(Answer.self, try await send(request("api/devices", timeout: readTimeout))).devices
    }

    func modes() async throws -> [FlatMode] {
        struct Answer: Decodable { let modes: [FlatMode] }
        return try decode(Answer.self, try await send(request("api/modes", timeout: readTimeout))).modes
    }

    func scenes() async throws -> [FlatScene] {
        struct Answer: Decodable { let scenes: [FlatScene] }
        return try decode(Answer.self, try await send(request("api/scenes", timeout: readTimeout))).scenes
    }

    // MARK: commands

    /// Sends a command and returns the device as flatd confirmed it.
    func send(_ command: DeviceCommand, to id: String) async throws -> Device {
        let body = try JSONEncoder().encode(command.body)
        let data = try await send(request("api/devices/" + Self.pathID(id), method: "POST", body: body,
                                          timeout: commandTimeout))
        return try decode(Device.self, data)
    }

    /// Turns a mode on or off. flatd changes the mode even when a device fails; those come back in `failed`.
    func setMode(_ id: String, active: Bool) async throws -> (mode: FlatMode, failed: [String]) {
        try await setMode(id, body: try JSONEncoder().encode(["active": active]))
    }

    /// The same with a body as the 3D page sent it (BRIDGE.md: forwarded unchanged).
    func setMode(_ id: String, body: Data) async throws -> (mode: FlatMode, failed: [String]) {
        let data = try await send(request("api/modes/" + Self.pathID(id), method: "POST", body: body,
                                          timeout: commandTimeout))
        return (try decode(FlatMode.self, data), (try? JSONDecoder().decode(CommandFailures.self, from: data))?.ids ?? [])
    }

    /// Runs a scene; returns the devices that did not follow.
    @discardableResult
    func runScene(_ id: String) async throws -> [String] {
        let data = try await send(request("api/scenes/" + Self.pathID(id), method: "POST", body: Data("{}".utf8),
                                          timeout: commandTimeout))
        return (try? JSONDecoder().decode(CommandFailures.self, from: data))?.ids ?? []
    }

    /// A device command with a body as the 3D page sent it (BRIDGE.md: `request.body` is exactly flatd's body).
    func send(body: Data, to id: String) async throws -> Device {
        let data = try await send(request("api/devices/" + Self.pathID(id), method: "POST", body: body,
                                          timeout: commandTimeout))
        return try decode(Device.self, data)
    }

    // MARK: the event stream and the 3D page

    /// `ws://<host>/api/events?token=…` (a WebSocket cannot carry the header from every client, so flatd takes the
    /// query too).
    var eventsURL: URL {
        var components = URLComponents(url: baseURL.appending(path: "api/events"), resolvingAgainstBaseURL: false)!
        components.scheme = baseURL.scheme == "https" ? "wss" : "ws"
        components.queryItems = [URLQueryItem(name: "token", value: token)]
        return components.url!
    }

    /// The phone viewer page (`GET /viewer`, private: flatd serves it only with the key). The page is never bundled.
    var viewerRequest: URLRequest {
        var request = URLRequest(url: baseURL.appending(path: "viewer"), cachePolicy: .reloadIgnoringLocalCacheData,
                                 timeoutInterval: 20)
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        return request
    }

    // MARK: plumbing

    /// A device id in a path: each part encoded, the colon kept (`fan:kitchen` stays readable).
    static func pathID(_ id: String) -> String {
        id.split(separator: ":", omittingEmptySubsequences: false)
            .map { String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(["/", "?", "#"])) ?? "" }
            .joined(separator: ":")
    }

    func request(_ path: String, method: String = "GET", body: Data? = nil, timeout: TimeInterval,
                 authorized: Bool = true) -> URLRequest {
        // The path is appended as written, so an encoded id is not encoded twice.
        let base = baseURL.absoluteString.hasSuffix("/") ? baseURL.absoluteString : baseURL.absoluteString + "/"
        var request = URLRequest(url: URL(string: base + path)!, cachePolicy: .reloadIgnoringLocalCacheData,
                                 timeoutInterval: timeout)
        request.httpMethod = method
        request.httpBody = body
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if authorized { request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
        return request
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let data: Data, response: HTTPURLResponse
        do {
            (data, response) = try await transport.send(request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as URLError where error.code == .timedOut {
            throw FlatdError.noAnswer
        } catch {
            throw FlatdError.unreachable
        }
        switch response.statusCode {
        case 200..<300: return data
        case 401: throw FlatdError.refused
        case 404: throw FlatdError.unknown
        case 409: throw FlatdError.notPossible
        case 504: throw FlatdError.deviceDidNotAnswer
        default:
            let sentence = (try? JSONDecoder().decode(ServerMessage.self, from: data))?.sentence
            throw FlatdError.failed(status: response.statusCode, message: sentence)
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            Self.log.error("flatd's answer did not decode (\(String(describing: T.self), privacy: .public))")
            throw FlatdError.invalidAnswer
        }
    }

    private static let log = Logger(subsystem: "de.ares-empire.arestia", category: "flatd")
}
