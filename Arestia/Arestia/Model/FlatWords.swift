import Foundation

/// The app's words for the flat's state, in English and German (pure, so the tests pin both languages). Device names
/// come from flatd and stay as they are; mode and scene names are the app's own for the ones it knows.
enum FlatWords {
    // MARK: fans

    /// "On · 24 min left", "On", "Off", "Offline".
    static func fanStatus(_ state: DeviceState, now: Date, language: AppLanguage = .current) -> String {
        guard state.online else { return language.string("Offline") }
        guard state.on == true else { return language.string("Off") }
        guard let offAt = state.offAt, offAt > now else { return language.string("On") }
        return language.string("On · \(remaining(until: offAt, now: now, language: language)) left")
    }

    /// "24 min", "1 h 5 min", "under 1 min" (rounded up, so a timer never reads 0 while it runs).
    static func remaining(until end: Date, now: Date, language: AppLanguage = .current) -> String {
        let minutes = Int((end.timeIntervalSince(now) / 60).rounded(.up))
        if minutes <= 0 { return language.string("under 1 min") }
        if minutes < 60 { return language.string("\(minutes) min") }
        let hours = minutes / 60, rest = minutes % 60
        return rest == 0 ? language.string("\(hours) h") : language.string("\(hours) h \(rest) min")
    }

    /// The quick timer a running fan shows as chosen: the shortest one that still covers what is left (12 min left:
    /// 15), "until off" without a timer, none for a longer timer set elsewhere (a Shortcut's 2 hours).
    static func runningChoice(_ state: DeviceState, now: Date) -> FanTimer? {
        guard state.on == true else { return nil }
        guard let offAt = state.offAt, offAt > now else { return .untilOff }
        let left = offAt.timeIntervalSince(now) / 60
        return FanTimer.timed.first { Double($0.minutes ?? 0) >= left - 0.5 }
    }

    // MARK: blinds

    /// "Open", "Closed", "40 % closed", "Going up", "Going down to 60 %", "At its favourite spot", "Offline".
    static func rolloStatus(_ state: DeviceState, position shown: Int? = nil, language: AppLanguage = .current) -> String {
        guard state.online else { return language.string("Offline") }
        if let moving = state.moving {
            if let target = state.target, target != 0, target != 100 {
                return moving == .up ? language.string("Going up to \(percent(target))")
                    : language.string("Going down to \(percent(target))")
            }
            return moving == .up ? language.string("Going up") : language.string("Going down")
        }
        guard let position = shown ?? state.position else { return language.string("Position unknown") }
        if shown == nil, let favourite = state.favourite, favourite == position, position != 0, position != 100 {
            return language.string("At its favourite spot · \(percent(position))")
        }
        switch position {
        case 0: return language.string("Open")
        case 100: return language.string("Closed")
        default: return language.string("\(percent(position)) closed")
        }
    }

    /// A blind's position sent when the finger let go, before flatd answered: "Sending: 40 % closed", never as done.
    static func rolloPending(_ target: Int, language: AppLanguage = .current) -> String {
        switch target {
        case 0: language.string("Sending: open")
        case 100: language.string("Sending: closed")
        default: language.string("Sending: \(percent(target)) closed")
        }
    }

    /// "40 %" (both languages put a space before the sign; a narrow one, so it never breaks off).
    static func percent(_ value: Int) -> String {
        "\(value)\u{202F}%"
    }

    // MARK: cooking, modes and scenes

    /// "since 18:42" (24-hour in both languages).
    static func since(_ date: Date, language: AppLanguage = .current) -> String {
        let time = date.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: language.locale))
        return language.string("since \(time)")
    }

    /// What the devices of a mode do now: "Fan 1 on · Fan 2 on · Blind 1 open".
    static func devicesNow(_ devices: [Device], language: AppLanguage = .current) -> String {
        devices.map { device in
            switch device.kind {
            case .rollo:
                let state = device.state
                if let moving = state.moving {
                    return moving == .up ? language.string("\(device.label) going up")
                        : language.string("\(device.label) going down")
                }
                return RolloOpenness.isOpen(state) ? language.string("\(device.label) open")
                    : language.string("\(device.label) closed")
            default:
                return device.state.on == true ? language.string("\(device.label) on")
                    : language.string("\(device.label) off")
            }
        }
        .joined(separator: " · ")
    }

    static func cookingEnded(language: AppLanguage = .current) -> String {
        language.string("Cooking ended.")
    }

    static func sceneDone(_ title: String, language: AppLanguage = .current) -> String {
        language.string("\(title): done.")
    }

    /// Cooking changed from a control or a Shortcut while devices did not follow (`ModeTrouble`), said once in the app.
    static func troubleFromOutside(_ trouble: ModeTrouble, language: AppLanguage = .current) -> String {
        let names = trouble.names.joined(separator: ", ")
        return trouble.active
            ? language.string("Cooking was started outside the app. Didn't answer: \(names).")
            : language.string("Cooking was ended outside the app. Didn't answer: \(names).")
    }

    /// A mode's name: the app's own for the ones it knows, flatd's label for any other.
    static func modeTitle(_ mode: FlatMode, language: AppLanguage = .current) -> String {
        mode.id == FlatMode.cookingID ? language.string("Cooking") : mode.label
    }

    static func sceneTitle(_ scene: FlatScene, language: AppLanguage = .current) -> String {
        switch scene.id {
        case FlatScene.airOutID: language.string("Air out")
        case FlatScene.allDownID: language.string("All down")
        default: scene.label
        }
    }

    /// The SF Symbol of a mode or scene.
    static func symbol(mode id: String) -> String {
        switch id {
        case FlatMode.cookingID: "flame"
        case FlatScene.airOutID: "wind"
        case FlatScene.allDownID: "blinds.horizontal.closed"
        default: "sparkles"
        }
    }

    // MARK: the summary at the top

    /// "Cooking", "Fan 1 is on", "2 fans on", "Blind 1 is moving", "All quiet".
    static func summary(cooking: Bool, fans: [Device], rollos: [Device], language: AppLanguage = .current) -> String {
        if cooking { return language.string("Cooking") }
        let running = fans.filter { $0.state.on == true }
        if running.count == 1 { return language.string("\(running[0].label) is on") }
        if running.count > 1 { return language.string("\(running.count) fans on") }
        let moving = rollos.filter { $0.state.moving != nil }
        if moving.count == 1 { return language.string("\(moving[0].label) is moving") }
        if moving.count > 1 { return language.string("Blinds moving") }
        return language.string("All quiet")
    }

    /// "Last seen 18:40" for state that is no longer live.
    static func lastSeen(_ date: Date, now: Date, language: AppLanguage = .current) -> String {
        let sameDay = Calendar.current.isDate(date, inSameDayAs: now)
        let style = sameDay ? Date.FormatStyle(date: .omitted, time: .shortened, locale: language.locale)
            : Date.FormatStyle(date: .abbreviated, time: .shortened, locale: language.locale)
        return language.string("Last seen \(date.formatted(style))")
    }
}

/// A fan's quick timers: 15, 30, 60 minutes, or until switched off (Patrik, 2026-11-19: "fans with timers is good").
enum FanTimer: Hashable, CaseIterable, Identifiable {
    case fifteen, thirty, sixty, untilOff

    static let timed: [FanTimer] = [.fifteen, .thirty, .sixty]

    var id: Self { self }

    var minutes: Int? {
        switch self {
        case .fifteen: 15
        case .thirty: 30
        case .sixty: 60
        case .untilOff: nil
        }
    }

    /// "15", "30", "60", "∞": the chip's face (the unit is said once beside them).
    var face: String {
        switch self {
        case .fifteen: "15"
        case .thirty: "30"
        case .sixty: "60"
        case .untilOff: "∞"
        }
    }

    func accessibilityName(language: AppLanguage = .current) -> String {
        switch self {
        case .untilOff: language.string("On until switched off")
        default: language.string("On for \(minutes ?? 0) minutes")
        }
    }
}
