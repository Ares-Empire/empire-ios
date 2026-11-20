import Foundation
import Testing
@testable import Arestia

/// The app's words for the flat, in both languages.
struct WordsTests {
    let now = FlatdDate.parse("2026-11-19T18:00:00Z")!

    func state(_ fields: [String: Any]) throws -> DeviceState { try Flat.decode(DeviceState.self, fields) }

    @Test func aFansLine() throws {
        #expect(FlatWords.fanStatus(try state(["on": false]), now: now, language: .english) == "Off")
        #expect(FlatWords.fanStatus(try state(["on": true]), now: now, language: .english) == "On")
        let timed = try state(["on": true, "off_at": "2026-11-19T18:24:00Z"])
        #expect(FlatWords.fanStatus(timed, now: now, language: .english) == "On · 24 min left")
        #expect(FlatWords.fanStatus(timed, now: now, language: .german) == "An · noch 24 Min.")
        #expect(FlatWords.fanStatus(try state(["on": true, "online": false]), now: now, language: .german) == "Offline")
        // A timer that ran out but no event yet: just on.
        #expect(FlatWords.fanStatus(try state(["on": true, "off_at": "2026-11-19T17:59:00Z"]), now: now,
                                    language: .english) == "On")
    }

    @Test func timeLeft() {
        let at = { (seconds: Double) in self.now.addingTimeInterval(seconds) }
        #expect(FlatWords.remaining(until: at(20), now: now, language: .english) == "1 min")
        #expect(FlatWords.remaining(until: at(0), now: now, language: .english) == "under 1 min")
        #expect(FlatWords.remaining(until: at(3600), now: now, language: .english) == "1 h")
        #expect(FlatWords.remaining(until: at(3900), now: now, language: .english) == "1 h 5 min")
        #expect(FlatWords.remaining(until: at(3900), now: now, language: .german) == "1 Std. 5 Min.")
    }

    @Test func whichTimerShowsAsChosen() throws {
        #expect(FlatWords.runningChoice(try state(["on": false]), now: now) == nil)
        #expect(FlatWords.runningChoice(try state(["on": true]), now: now) == .untilOff)
        #expect(FlatWords.runningChoice(try state(["on": true, "off_at": "2026-11-19T18:12:00Z"]), now: now) == .fifteen)
        #expect(FlatWords.runningChoice(try state(["on": true, "off_at": "2026-11-19T18:30:00Z"]), now: now) == .thirty)
        #expect(FlatWords.runningChoice(try state(["on": true, "off_at": "2026-11-19T18:45:00Z"]), now: now) == .sixty)
        #expect(FlatWords.runningChoice(try state(["on": true, "off_at": "2026-11-19T20:00:00Z"]), now: now) == nil)
    }

    @Test func aBlindsLine() throws {
        let line = { (fields: [String: Any], language: AppLanguage) in
            FlatWords.rolloStatus(try self.state(fields), language: language)
        }
        #expect(try line(["position": 0], .english) == "Open")
        #expect(try line(["position": 100], .german) == "Zu")
        #expect(try line(["position": 40], .english) == "40\u{202F}% closed")
        #expect(try line(["position": 40], .german) == "40\u{202F}% zu")
        #expect(try line(["position": 60, "favourite": 60], .english) == "At its favourite spot · 60\u{202F}%")
        #expect(try line(["position": 20, "moving": "down", "target": 100], .english) == "Going down")
        #expect(try line(["position": 20, "moving": "down", "target": 60], .german) == "Fährt runter auf 60\u{202F}%")
        #expect(try line(["position": 80, "moving": "up", "target": 0], .german) == "Fährt hoch")
        #expect(try line(["position": NSNull()], .english) == "Position unknown")
        #expect(try line(["position": 0, "online": false], .english) == "Offline")
        // While a finger drags it: the finger's position, not "at its favourite spot".
        #expect(FlatWords.rolloStatus(try state(["position": 60, "favourite": 60]), position: 60,
                                      language: .english) == "60\u{202F}% closed")
    }

    @Test func whatTheModesDevicesDoNow() throws {
        let devices = try Flat.devices([Flat.fan(1, on: true), Flat.fan(2), Flat.rollo(1, position: 0),
                                        Flat.rollo(2, position: 30, moving: "down", target: 100)])
        #expect(FlatWords.devicesNow(devices, language: .english) == "Fan 1 on · Fan 2 off · Blind 1 open · Blind 2 going down")
        #expect(FlatWords.devicesNow(devices, language: .german) == "Fan 1 an · Fan 2 aus · Blind 1 offen · Blind 2 fährt runter")
    }

    @Test func theSummary() throws {
        let fans = try Flat.devices([Flat.fan(1, on: true), Flat.fan(2)])
        let rollos = try Flat.devices([Flat.rollo(1, moving: "up", target: 0)])
        #expect(FlatWords.summary(cooking: true, fans: fans, rollos: rollos, language: .english) == "Cooking")
        #expect(FlatWords.summary(cooking: false, fans: fans, rollos: [], language: .english) == "Fan 1 is on")
        #expect(FlatWords.summary(cooking: false, fans: try Flat.devices([Flat.fan(1, on: true), Flat.fan(2, on: true)]),
                                  rollos: [], language: .german) == "2 Ventilatoren an")
        #expect(FlatWords.summary(cooking: false, fans: [], rollos: rollos, language: .english) == "Blind 1 is moving")
        #expect(FlatWords.summary(cooking: false, fans: [], rollos: [], language: .german) == "Alles ruhig")
    }

    @Test func modeAndSceneNames() {
        let cooking = FlatMode(id: "cooking", label: "Cooking", active: false)
        #expect(FlatWords.modeTitle(cooking, language: .german) == "Kochen")
        #expect(FlatWords.modeTitle(FlatMode(id: "party", label: "Party", active: false), language: .german) == "Party")
        #expect(FlatWords.sceneTitle(FlatScene(id: "air_out", label: "Air out"), language: .german) == "Lüften")
        #expect(FlatWords.sceneTitle(FlatScene(id: "all_down", label: "All blinds down"), language: .german) == "Alle runter")
        #expect(FlatWords.sceneTitle(FlatScene(id: "movie", label: "Movie"), language: .german) == "Movie")
    }

    @Test func lastSeen() {
        let today = now.addingTimeInterval(-600)
        #expect(FlatWords.lastSeen(today, now: now, language: .english).hasPrefix("Last seen "))
        #expect(FlatWords.lastSeen(today, now: now, language: .german).hasPrefix("Zuletzt gesehen "))
    }
}

/// The bridge to the 3D page (the viewer's BRIDGE.md v1).
struct BridgeTests {
    @Test func whatThePageSays() throws {
        #expect(PageMessage.parse(["v": 1, "type": "ready", "devices": ["fan:fan_1"], "modes": ["cooking"]]) == .ready)
        let request = PageMessage.parse(["v": 1, "type": "request", "reqId": "r3", "id": "fan:fan_1",
                                         "body": ["on": true]])
        guard case let .request(reqId, id, body)? = request else {
            Issue.record("no request")
            return
        }
        #expect(reqId == "r3" && id == "fan:fan_1")
        // Forwarded unchanged, the boolean a boolean.
        let forwarded = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(forwarded["on"] as? Bool == true)
        #expect(String(decoding: body, as: UTF8.self) == #"{"on":true}"#)

        guard case .mode("r4", "cooking", _)? = PageMessage.parse(["type": "mode", "reqId": "r4", "id": "cooking",
                                                                   "body": ["active": false]]) else {
            Issue.record("no mode")
            return
        }
        #expect(PageMessage.parse(["type": "haptic", "style": "success"]) == .haptic("success"))
        #expect(PageMessage.parse(["type": "view", "room": "kitchen"]) == .other)
        #expect(PageMessage.parse(["type": "request", "id": "fan:fan_1"]) == nil)       // no reqId, no body
        #expect(PageMessage.parse("ready") == nil)
    }

    @Test func thePagesLogLevelsAndDefaults() {
        for (level, expected) in [("error", PageLogLevel.error), ("warn", .warn), ("info", .info), ("debug", .error)] {
            #expect(PageMessage.parse(["v": 1, "type": "log", "level": level, "message": "test"])
                    == .log(level: expected, text: "test", timing: [:]))
        }
        #expect(PageMessage.parse(["type": "log", "message": "old page"])
                == .log(level: .error, text: "old page", timing: [:]))
        #expect(PageMessage.parse(["type": "log", "timing": [12, 34]])
                == .log(level: .error, text: "", timing: [:]))
    }

    @Test func pageTimingKeepsOnlyValidNamesAndNumbersInTheOrderTheyHappened() {
        let long = String(repeating: "x", count: 25)
        let values: [String: Any] = [
            "script": 905.5, "html": 412, "stage_3": 1, "bad name": 2, "ümlaut": 3, long: 4, "": 5,
            "infinite": Double.infinity, "nan": Double.nan, "too_big": Double.greatestFiniteMagnitude,
            "boolean": true, "text": "123", "null": NSNull(), "object": ["value": 6],
        ]
        let message: [String: Any] = ["type": "log", "timing": values]
        let expected = ["html": 412, "script": 905, "stage_3": 1]
        #expect(PageMessage.parse(message) == .log(level: .error, text: "", timing: expected))
        #expect(PageMessage.timingLine(expected) == "stage_3 1, html 412, script 905")
        #expect(PageMessage.timingLine(["shown": 900, "light": 900, "main": 80]) == "main 80, light 900, shown 900")
    }

    @Test func pageTimingKeepsAtMostTwentyFourEntries() {
        let names = (0..<30).map { "stage_\($0)" }
        let values = Dictionary(uniqueKeysWithValues: zip(names, 0..<30))
        let message: [String: Any] = ["type": "log", "timing": values]
        guard case let .log(_, _, timing) = PageMessage.parse(message) else { Issue.record("not a log"); return }
        #expect(timing.count == 24)
    }

    @Test func oneResultPerRequest() throws {
        let ok = try #require(try JSONSerialization.jsonObject(with: PageScript.result(reqId: "r1", error: nil)) as? [String: Any])
        #expect(ok["type"] as? String == "result" && ok["reqId"] as? String == "r1" && ok["ok"] as? Bool == true)
        #expect(ok["error"] == nil)
        let failed = try #require(try JSONSerialization.jsonObject(
            with: PageScript.result(reqId: "r2", error: .unreachable, language: .english)) as? [String: Any])
        #expect(failed["ok"] as? Bool == false)
        #expect(failed["error"] as? String == "offline")
        #expect((failed["message"] as? String)?.isEmpty == false)
    }

    @Test func theBridgesErrorWords() {
        #expect(PageScript.errorWord(.unreachable) == "offline")
        #expect(PageScript.errorWord(.deviceDidNotAnswer) == "timeout")
        #expect(PageScript.errorWord(.refused) == "unauthorized")
        #expect(PageScript.errorWord(.unknown) == "unknown")
        #expect(PageScript.errorWord(.failed(status: 400, message: nil)) == "refused")
        #expect(PageScript.errorWord(.notPossible) == "refused")
        #expect(PageScript.errorWord(.failed(status: 500, message: nil)) == "failed")
    }

    @Test func theCallIntoThePage() {
        let script = PageScript.receive(Data(#"{"type":"connection","status":"offline","x":"a\#u{2028}b"}"#.utf8))
        #expect(script.hasPrefix("window.flat3d && flat3d.receive && flat3d.receive({"))
        #expect(!script.contains("\u{2028}"))
        #expect(script.contains("\\u2028"))
    }

    @Test func connectionAndConfig() throws {
        let offline = try #require(try JSONSerialization.jsonObject(with: PageScript.connection(.offline)) as? [String: Any])
        #expect(offline["status"] as? String == "offline")
        let live = try #require(try JSONSerialization.jsonObject(with: PageScript.connection(.live)) as? [String: Any])
        #expect(live["status"] as? String == "connected")
        let config = try #require(try JSONSerialization.jsonObject(
            with: PageScript.config(dark: false, language: .german, accent: "#FF9A62", alwaysDaylight: false,
                                    bottomBar: 49.4)) as? [String: Any])
        #expect(config["theme"] as? String == "light")
        #expect(config["lighting"] as? String == "real")
        let day = try #require(try JSONSerialization.jsonObject(
            with: PageScript.config(dark: true, language: .english, accent: "#FF9A62", alwaysDaylight: true,
                                    bottomBar: 0)) as? [String: Any])
        #expect(day["lighting"] as? String == "day")
        #expect(config["language"] as? String == "de")
        #expect((config["insets"] as? [String: Any])?["bottom"] as? Double == 49)
    }
}
