import SwiftUI

// Arestia's own pieces, built on the shared design (`Shared/Design`): the glass cards, the wall, the type and Ink, with
// the hearth ember (`AppAccent.arestia`) only where something is on or is the one thing to press.

/// The header every Empire province app has: its mark on the left, the name in the middle, the gear on the right.
struct ArestiaHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 10) {
            ArestiaMark(size: 38)
                .frame(width: 42, height: 42).accessibilityHidden(true)
            Spacer(minLength: 0)
            HStack(spacing: 8) { trailing }.frame(minWidth: 42, minHeight: 42)
        }
        .overlay {
            Text(verbatim: title).font(AppFont.text(17, weight: .bold)).foregroundStyle(Ink.primary).lineLimit(1)
                .padding(.horizontal, 104).accessibilityAddTraits(.isHeader)
        }
        .padding(.horizontal, 14).padding(.top, 6).padding(.bottom, 8)
    }
}

/// The app's mark (the bust's place in the other apps).
struct ArestiaMark: View {
    var size: CGFloat

    var body: some View {
        Image("Mark").resizable().scaledToFit().frame(width: size, height: size)
    }
}

/// A section's heading over its card, with an optional quiet figure on the right ("FANS ··· 1 ON").
struct SectionTitle: View {
    let text: String
    var value: String? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            SectionHeading(text: text)
            Spacer(minLength: 8)
            if let value {
                Text(verbatim: value.uppercased()).font(AppFont.text(11, weight: .semibold)).tracking(1.1)
                    .foregroundStyle(Ink.muted)
                    .contentTransition(.numericText())
            }
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
    }
}

/// The round on/off button of a switch (a fan, a plug): filled with the ember while on, a thin ring while off, a
/// spinner while flatd confirms.
struct PowerButton: View {
    let isOn: Bool
    let busy: Bool
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                // On: the ember as a soft tint and a ring, not a fill (the one filled button is the screen's main one).
                Circle().fill(isOn ? AppAccent.arestia.color.opacity(0.16) : Ink.field)
                Circle().strokeBorder(isOn ? AppAccent.arestia.color.opacity(0.6) : Ink.edge, lineWidth: 1)
                if busy {
                    ProgressView().tint(isOn ? AppAccent.arestia.color : Ink.secondary)
                } else {
                    Image(systemName: "power").font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(isOn ? AppAccent.arestia.color : Ink.secondary)
                }
            }
            .frame(width: 48, height: 48)
            .contentShape(Circle())
        }
        .buttonStyle(PressedScale())
        .disabled(busy)
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? Text("On") : Text("Off"))
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// A button that gives a little as it is pressed.
struct PressedScale: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

/// A small capsule choice ("15 min"), chosen in the ember's soft tone.
struct Chip: View {
    let title: String
    let chosen: Bool
    var accessibility: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(verbatim: title)
                .font(AppFont.text(13, weight: chosen ? .semibold : .medium))
                .foregroundStyle(chosen ? AppAccent.arestia.color : Ink.secondary)
                .frame(maxWidth: .infinity, minHeight: 34)
                .background {
                    Capsule().fill(chosen ? AppAccent.arestia.color.opacity(0.14) : Ink.field)
                }
                .overlay {
                    Capsule().strokeBorder(chosen ? AppAccent.arestia.color.opacity(0.55) : Ink.edge, lineWidth: 1)
                }
                .contentShape(Capsule())
                .frame(minHeight: 44)
        }
        .buttonStyle(PressedScale())
        .accessibilityLabel(accessibility ?? title)
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }
}

/// A fan's timers as one segmented capsule: 15 min · 30 min · 1 h · ∞. The one running is lit in the ember's soft
/// tone; a tap switches the fan on for that long (∞: until switched off).
struct TimerSegments: View {
    let chosen: FanTimer?
    let choose: (FanTimer) -> Void
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(FanTimer.allCases.enumerated()), id: \.element) { index, timer in
                if index > 0 {
                    Rectangle().fill(Ink.line).frame(width: 1, height: 16)
                        .opacity(chosen == timer || chosen == FanTimer.allCases[index - 1] ? 0 : 1)
                }
                Button { choose(timer) } label: {
                    face(timer)
                        .foregroundStyle(chosen == timer ? AppAccent.arestia.color : Ink.secondary)
                        .frame(maxWidth: .infinity, minHeight: 34)
                        .background {
                            if chosen == timer {
                                Capsule().fill(AppAccent.arestia.color.opacity(0.15))
                                    .overlay(Capsule().strokeBorder(AppAccent.arestia.color.opacity(0.45), lineWidth: 1))
                            }
                        }
                        .contentShape(Rectangle())
                        .frame(minHeight: 44)
                }
                .buttonStyle(PressedScale())
                .accessibilityLabel(timer.accessibilityName())
                .accessibilityAddTraits(chosen == timer ? .isSelected : [])
            }
        }
        .padding(.horizontal, 3)
        .background(Capsule().fill(Ink.field).frame(height: 40))
        .overlay(Capsule().strokeBorder(Ink.edge, lineWidth: 1).frame(height: 40))
        .opacity(isEnabled ? 1 : 0.5)
        .animation(.easeOut(duration: 0.2), value: chosen)
    }

    @ViewBuilder private func face(_ timer: FanTimer) -> some View {
        switch timer {
        case .untilOff:
            Image(systemName: "infinity").font(.system(size: 15, weight: .semibold))
        case .sixty:
            Text("1 h").font(AppFont.text(13, weight: chosen == timer ? .semibold : .medium))
        default:
            Text("\(timer.minutes ?? 0) min").font(AppFont.text(13, weight: chosen == timer ? .semibold : .medium))
        }
    }
}

/// One of a blind's three moves (up, favourite, down) or stop: a quiet outlined button with its symbol.
struct MoveButton: View {
    let symbol: String
    let title: String
    var prominent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 13, weight: .semibold))
                Text(verbatim: title).font(AppFont.text(13, weight: .medium)).lineLimit(1).minimumScaleFactor(0.8)
            }
            .foregroundStyle(prominent ? AppAccent.arestia.color : Ink.primary)
            .frame(maxWidth: .infinity, minHeight: 40)
            .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Ink.field))
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(prominent ? AppAccent.arestia.color.opacity(0.5) : Ink.edge, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .frame(minHeight: 44)
        }
        .buttonStyle(PressedScale())
        .accessibilityLabel(title)
    }
}

/// A blind drawn as its window: the fabric hangs down to its position (percent closed), with its slats, a grip on the
/// hem; drag it up or down to send the blind there (sent when the finger lets go). The window's glass shows the wall's
/// light, the fabric is ink, so it reads in light and dark.
struct BlindWindow: View {
    /// Percent closed, nil while flatd has not read the blind yet.
    let position: Int?
    let moving: RolloMotion?
    var target: Int?
    /// While dragging: the new position; at the end: send it.
    let onDrag: (Int) -> Void
    let onRelease: (Int) -> Void
    @State private var start: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let size = CGSize(width: 58, height: 78)

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
        let closed = CGFloat(position ?? 0) / 100
        GeometryReader { box in
            let inner = CGSize(width: box.size.width - 8, height: box.size.height - 8)
            ZStack(alignment: .top) {
                // The glass: the day outside, faint.
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(LinearGradient(colors: [AppAccent.arestia.deep.opacity(0.10), Ink.card2.opacity(0.4)],
                                         startPoint: .top, endPoint: .bottom))
                // The window's cross.
                Rectangle().fill(Ink.line).frame(width: 1).frame(maxHeight: .infinity)
                // The fabric with its slats, down to the position.
                VStack(spacing: 0) {
                    Canvas { context, size in
                        context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Ink.secondary.opacity(0.55)))
                        var y: CGFloat = 5
                        while y < size.height - 1 {
                            context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)),
                                         with: .color(Ink.background.opacity(0.35)))
                            y += 5
                        }
                    }
                    // Never past the window: the hem below it stays inside too (no clip: a clip is drawn offscreen in
                    // every frame the fabric moves).
                    .frame(height: max(0, (inner.height - 6) * closed))
                    // The hem: the grip.
                    Capsule().fill(Ink.primary.opacity(0.75)).frame(width: inner.width * 0.36, height: 3)
                        .padding(.top, 3)
                }
                .frame(width: inner.width)
                if let target, moving != nil {
                    Rectangle().fill(AppAccent.arestia.color.opacity(0.8)).frame(height: 1.5)
                        .offset(y: min(inner.height - 1.5, (inner.height - 6) * CGFloat(target) / 100))
                }
            }
            .frame(width: inner.width, height: inner.height, alignment: .top)
            .padding(4)
            .contentShape(shape)
            .gesture(
                DragGesture(minimumDistance: 3)
                    .onChanged { value in
                        let from = start ?? (position ?? 0)
                        if start == nil { start = from }
                        onDrag(Self.position(from: from, drag: value.translation.height, height: inner.height))
                    }
                    .onEnded { value in
                        let from = start ?? (position ?? 0)
                        start = nil
                        onRelease(Self.position(from: from, drag: value.translation.height, height: inner.height))
                    }
            )
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background(shape.fill(Ink.field))
        .overlay(shape.strokeBorder(Ink.edge, lineWidth: 1))
        .animation(start == nil && !reduceMotion ? .easeInOut(duration: 0.35) : nil, value: position)
    }

    /// The position a drag reaches: the hem follows the finger, kept between open and closed.
    static func position(from start: Int, drag: CGFloat, height: CGFloat) -> Int {
        guard height > 0 else { return start }
        return min(100, max(0, start + Int((drag / height * 100).rounded())))
    }
}

/// A calm card for a state with one way on: a symbol, a title, a line, and a quiet button.
struct CalmCard: View {
    let symbol: String
    let title: String
    let text: String
    var action: (title: String, run: () -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Image(systemName: symbol).font(.system(size: 20, weight: .medium)).foregroundStyle(Ink.secondary)
                .accessibilityHidden(true)
            Text(verbatim: title).font(AppFont.text(17, weight: .semibold)).foregroundStyle(Ink.primary)
                .padding(.top, 12)
            Text(verbatim: text).font(AppFont.text(14)).foregroundStyle(Ink.secondary).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true).padding(.top, 5)
            if let action {
                Button(action: action.run) { Text(verbatim: action.title) }
                    .buttonStyle(FormButtonStyle(kind: .secondary, accent: .arestia))
                    .padding(.top, 18)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }
}

/// A small round light: green while live, muted while not.
struct LiveDot: View {
    let live: Bool

    var body: some View {
        Circle().fill(live ? StatusTone.activeColor : Ink.muted).frame(width: 7, height: 7)
            .accessibilityHidden(true)
    }
}
