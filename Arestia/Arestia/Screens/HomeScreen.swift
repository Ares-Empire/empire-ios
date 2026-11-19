import SwiftUI

/// The first tab: what the flat is doing and the few things to do about it (Patrik, 2026-11-19: "not many buttons and
/// big menu but just easy navigation"). From the top: the state in one line; cooking while it runs, with Done cooking as
/// the one big button, else the modes and scenes as three tiles; the fans with their timers; the blinds; then what
/// runs by itself. Ends with the ARESTIA band (`WordmarkScrollView`).
struct HomeScreen: View {
    let store: FlatStore
    let openSettings: () -> Void
    let reconnect: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollViewReader { proxy in
            WordmarkScrollView(word: "ARESTIA") {
                VStack(alignment: .leading, spacing: 0) {
                    ArestiaHeader(title: "Arestia") {
                        GlassIconButton(symbol: "gearshape", label: String(localized: "Settings"), action: openSettings)
                    }
                    content.padding(.horizontal, 18)
                        .animation(reduceMotion ? nil : .smooth(duration: 0.35), value: store.isCooking)
                        .animation(reduceMotion ? nil : .smooth(duration: 0.35), value: store.link)
                }
            }
            .scrollIndicators(.hidden)
            .refreshable { store.retry() }
            #if DEBUG
            .task(id: store.hasSnapshot) {
                // Screenshots: `-scrollToEnd` shows the automations and the band; `-scrollTo blinds|automations`.
                guard store.hasSnapshot else { return }
                try? await Task.sleep(for: .milliseconds(400))
                if LaunchArguments.current.contains("-scrollToEnd") { proxy.scrollToWordmark() }
                if let place = LaunchArguments.value("-scrollTo") { proxy.scrollTo(place, anchor: .top) }
            }
            #endif
        }
        .background { ProvinceWall(accent: .arestia) }
        .undoBar(Binding(get: { store.offer }, set: { store.offer = $0 }), accent: .arestia)
    }

    @ViewBuilder private var content: some View {
        StatusSummary(store: store).padding(.top, 14)
        switch (store.link, store.hasSnapshot) {
        case (.refused, _):
            CalmCard(symbol: "key", title: String(localized: "The flat service refused the key"),
                     text: String(localized: "flatd has a new key, or this one was mistyped. Enter it again."),
                     action: (String(localized: "Enter the key"), reconnect))
                .padding(.top, 22)
        case (_, false) where store.link == .offline:
            CalmCard(symbol: "moon.zzz", title: String(localized: "Can't reach the flat"),
                     text: String(localized: "The Mac may be asleep, or you're not at home. Arestia keeps trying by itself."),
                     action: (String(localized: "Try again"), { store.retry() }))
                .padding(.top, 22)
        case (_, false):
            ProgressView().tint(Ink.secondary).frame(maxWidth: .infinity).padding(.top, 120)
        default:
            flat.opacity(store.link == .offline ? 0.72 : 1)
        }
    }

    @ViewBuilder private var flat: some View {
        if let cooking = store.cooking, cooking.active {
            CookingCard(store: store, mode: cooking).padding(.top, 16)
                .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
        }
        let tiles = ModeTiles.tiles(store: store)
        if !tiles.isEmpty {
            ModeTiles(store: store, tiles: tiles).padding(.top, store.isCooking ? 14 : 22)
        }
        if !store.fans.isEmpty {
            SectionTitle(text: String(localized: "Fans"), value: FanCard.countLine(store.fans))
                .padding(.top, 30).padding(.bottom, 10)
            FanCard(store: store)
        }
        if !store.rollos.isEmpty {
            SectionTitle(text: String(localized: "Blinds")).padding(.top, 30).padding(.bottom, 10).id("blinds")
            BlindCard(store: store)
        }
        if !store.others.isEmpty {
            SectionTitle(text: String(localized: "More")).padding(.top, 30).padding(.bottom, 10)
            SwitchCard(store: store, devices: store.others)
        }
        SectionTitle(text: String(localized: "Automations")).padding(.top, 34).padding(.bottom, 10).id("automations")
        AutomationsCard(store: store)
    }
}

/// The state in one line, big, and how fresh it is: "All quiet" · LIVE, or "Cooking", or last seen while not live.
private struct StatusSummary: View {
    let store: FlatStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                LiveDot(live: store.link == .live)
                SectionHeading(text: linkWord)
            }
            // While cooking, the cooking card below says it; the line would only repeat it.
            if store.hasSnapshot, !store.isCooking {
                Text(verbatim: FlatWords.summary(cooking: store.isCooking, fans: store.fans, rollos: store.rollos))
                    .font(AppFont.text(26, weight: .bold))
                    // Not live: the last known state, quieter, and why it may be old.
                    .foregroundStyle(store.link == .live ? Ink.primary : Ink.secondary)
                    .contentTransition(.opacity)
                    .padding(.top, 6)
                if store.link != .live, let seen = store.lastSeen {
                    Text(verbatim: store.link == .offline
                         ? FlatWords.lastSeen(seen, now: .now) + " · " + String(localized: "The Mac may be asleep, or you're not at home.")
                         : FlatWords.lastSeen(seen, now: .now))
                        .font(AppFont.text(13)).foregroundStyle(Ink.muted).lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true).padding(.top, 4)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var linkWord: String {
        switch store.link {
        case .live: String(localized: "Live")
        case .connecting: String(localized: "Connecting")
        case .offline: String(localized: "Not reachable")
        case .refused: String(localized: "Key refused")
        case .notSetUp: String(localized: "Not connected")
        }
    }
}

// MARK: - cooking

/// Cooking while it runs (Patrik: "in the app it shows that cooking is active and one click deactivates fans and rolls
/// blind to fav spot"): since when, what its devices do right now, and Done cooking.
private struct CookingCard: View {
    let store: FlatStore
    let mode: FlatMode

    var body: some View {
        let devices = mode.devices.compactMap(store.device)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(AppAccent.arestia.color.opacity(0.16))
                    Image(systemName: "flame.fill").font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(AppAccent.arestia.color)
                }
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Cooking").font(AppFont.text(19, weight: .bold)).foregroundStyle(Ink.primary)
                    if let since = mode.since {
                        Text(verbatim: FlatWords.since(since)).font(AppFont.number(12.5)).foregroundStyle(Ink.secondary)
                    }
                }
            }
            if !devices.isEmpty {
                Text(verbatim: FlatWords.devicesNow(devices))
                    .font(AppFont.text(13.5)).foregroundStyle(Ink.secondary).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 14)
            }
            Button {
                store.setMode(mode.id, active: false)
            } label: {
                BusyLabel(text: Text("Done cooking"), busy: store.isWorking("mode:" + mode.id))
            }
            .buttonStyle(FormButtonStyle(accent: .arestia, busy: store.isWorking("mode:" + mode.id)))
            .disabled(store.isWorking("mode:" + mode.id))
            .padding(.top, 18)
            Text("Fans off, the blind goes to its favourite spot.")
                .font(AppFont.text(12.5)).foregroundStyle(Ink.muted)
                .frame(maxWidth: .infinity).multilineTextAlignment(.center)
                .padding(.top, 9)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard(accent: .arestia, raised: true)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - modes and scenes

/// The modes and scenes as tiles in one row: Cooking (while not cooking), Air out, All down.
private struct ModeTiles: View {
    struct Tile: Identifiable, Equatable {
        enum Kind: Equatable { case mode, scene }
        let id: String
        let kind: Kind
        let title: String
    }

    let store: FlatStore
    let tiles: [Tile]

    static func tiles(store: FlatStore) -> [Tile] {
        store.modes.filter { !$0.active }.map { Tile(id: $0.id, kind: .mode, title: FlatWords.modeTitle($0)) }
            + store.scenes.map { Tile(id: $0.id, kind: .scene, title: FlatWords.sceneTitle($0)) }
    }

    var body: some View {
        HStack(spacing: 10) {
            ForEach(tiles) { tile in
                let key = (tile.kind == .mode ? "mode:" : "scene:") + tile.id
                Button {
                    switch tile.kind {
                    case .mode: store.setMode(tile.id, active: true)
                    case .scene: store.runScene(tile.id, title: tile.title)
                    }
                } label: {
                    VStack(spacing: 9) {
                        ZStack {
                            if store.isWorking(key) {
                                ProgressView().tint(Ink.secondary)
                            } else {
                                Image(systemName: FlatWords.symbol(mode: tile.id))
                                    .font(.system(size: 19, weight: .medium))
                                    .foregroundStyle(tile.id == FlatMode.cookingID ? AppAccent.arestia.color : Ink.primary)
                            }
                        }
                        .frame(height: 24)
                        Text(verbatim: tile.title).font(AppFont.text(13, weight: .semibold)).foregroundStyle(Ink.primary)
                            .lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity, minHeight: 82)
                    .glassCard()
                    .contentShape(RoundedRectangle(cornerRadius: Ink.cardRadius, style: .continuous))
                }
                .buttonStyle(PressedScale())
                .disabled(store.isWorking(key))
                .accessibilityHint(tile.kind == .mode ? Text("Turns it on") : Text("Runs it once"))
            }
        }
    }
}

// MARK: - fans

/// Every fan: on or off with one tap, and how long it runs (15, 30, 60 min, or until off) with the time left.
struct FanCard: View {
    let store: FlatStore

    /// "1 on", "2 on", nil while none runs.
    static func countLine(_ fans: [Device]) -> String? {
        let running = fans.filter { $0.state.on == true }.count
        return running == 0 ? nil : String(localized: "\(running) on")
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(store.fans.enumerated()), id: \.element.id) { index, fan in
                if index > 0 { SettingsDivider() }
                FanRow(store: store, fan: fan)
            }
        }
        .glassCard()
    }
}

private struct FanRow: View {
    let store: FlatStore
    let fan: Device

    var body: some View {
        let on = fan.state.on == true
        TimelineView(.periodic(from: .now, by: 15)) { context in
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(verbatim: fan.label).font(AppFont.text(16, weight: .semibold)).foregroundStyle(Ink.primary)
                            .lineLimit(1)
                        Text(verbatim: FlatWords.fanStatus(fan.state, now: context.date))
                            .font(AppFont.text(13)).foregroundStyle(on ? AppAccent.arestia.color : Ink.muted)
                            .contentTransition(.opacity)
                    }
                    Spacer(minLength: 8)
                    PowerButton(isOn: on, busy: store.isWorking("power:" + fan.id),
                                label: fan.label) {
                        store.setFan(fan.id, on: !on)
                    }
                }
                TimerSegments(chosen: FlatWords.runningChoice(fan.state, now: context.date)) { timer in
                    store.setFan(fan.id, on: true, minutes: timer.minutes)
                }
                .disabled(store.isWorking("power:" + fan.id) || !fan.state.online)
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .opacity(fan.state.online ? 1 : 0.6)
        }
        .accessibilityElement(children: .contain)
    }
}

/// Lights and plugs flatd has besides the fans: on or off.
private struct SwitchCard: View {
    let store: FlatStore
    let devices: [Device]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(devices.enumerated()), id: \.element.id) { index, device in
                if index > 0 { SettingsDivider() }
                let on = device.state.on == true
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(verbatim: device.label).font(AppFont.text(15, weight: .semibold)).foregroundStyle(Ink.primary)
                        Text(verbatim: FlatWords.fanStatus(device.state, now: .now))
                            .font(AppFont.text(13)).foregroundStyle(Ink.muted)
                    }
                    Spacer(minLength: 8)
                    if device.controls.contains("on") {
                        PowerButton(isOn: on, busy: store.isWorking("power:" + device.id), label: device.label) {
                            store.setFan(device.id, on: !on)
                        }
                    }
                }
                .padding(.horizontal, 16).padding(.vertical, 12)
            }
        }
        .glassCard()
    }
}

// MARK: - blinds

/// Every blind: its window with the fabric where it is (drag it to send it there), up / favourite / down, and stop
/// while it moves.
private struct BlindCard: View {
    let store: FlatStore

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(store.rollos.enumerated()), id: \.element.id) { index, rollo in
                if index > 0 { SettingsDivider() }
                BlindRow(store: store, rollo: rollo)
            }
        }
        .glassCard()
    }
}

private struct BlindRow: View {
    let store: FlatStore
    let rollo: Device

    var body: some View {
        let state = rollo.state
        let shown = store.shownPosition(of: rollo)
        HStack(alignment: .top, spacing: 16) {
            BlindWindow(position: shown, moving: state.moving, target: state.target,
                        onDrag: { store.drag(rollo.id, to: $0) },
                        onRelease: { store.setRollo(rollo.id, position: $0) })
                .accessibilityElement()
                .accessibilityLabel(rollo.label)
                .accessibilityValue(Text(verbatim: FlatWords.rolloStatus(state)))
                .accessibilityAdjustableAction { direction in
                    let now = shown ?? 0
                    store.setRollo(rollo.id, position: direction == .increment ? now - 25 : now + 25)
                }
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text(verbatim: rollo.label).font(AppFont.text(16, weight: .semibold)).foregroundStyle(Ink.primary)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                }
                Text(verbatim: FlatWords.rolloStatus(state, position: store.dragging[rollo.id]))
                    .font(AppFont.text(13))
                    .foregroundStyle(state.moving != nil || store.dragging[rollo.id] != nil
                                     ? AppAccent.arestia.color : Ink.muted)
                    .contentTransition(.opacity)
                    .padding(.top, 3)
                HStack(spacing: 8) {
                    if state.moving != nil {
                        MoveButton(symbol: "stop.fill", title: String(localized: "Stop"), prominent: true) {
                            store.moveRollo(rollo.id, .stop)
                        }
                    } else {
                        MoveButton(symbol: "chevron.up", title: String(localized: "Up")) { store.moveRollo(rollo.id, .up) }
                        if let favourite = state.favourite {
                            MoveButton(symbol: "star", title: FlatWords.percent(favourite)) {
                                store.moveRollo(rollo.id, .favourite)
                            }
                            .accessibilityLabel(Text("Favourite spot, \(FlatWords.percent(favourite))"))
                        }
                        MoveButton(symbol: "chevron.down", title: String(localized: "Down")) {
                            store.moveRollo(rollo.id, .down)
                        }
                    }
                }
                .padding(.top, 12)
                .disabled(!state.online)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .opacity(state.online ? 1 : 0.6)
        .accessibilityElement(children: .contain)
    }
}

// MARK: - automations

/// What runs by itself or from outside the app, honestly and small: the modes and scenes with what they do (from
/// flatd's own lists), the fans' timers, the NFC tag and Control Center.
private struct AutomationsCard: View {
    let store: FlatStore

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                if index > 0 { SettingsDivider() }
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: row.symbol).font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Ink.secondary).frame(width: 22).padding(.top, 2)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(verbatim: row.title).font(AppFont.text(14.5, weight: .semibold)).foregroundStyle(Ink.primary)
                        Text(verbatim: row.text).font(AppFont.text(12.5)).foregroundStyle(Ink.muted).lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16).padding(.vertical, 13)
                .accessibilityElement(children: .combine)
            }
        }
        .glassCard()
    }

    private var rows: [AutomationRow] {
        AutomationRow.rows(modes: store.modes, scenes: store.scenes, devices: store.devices)
    }
}
