import Foundation

/// Aresium's red mode and its transitions, independent of SwiftUI and wall-clock time. Light or dark is the app's
/// appearance (Settings → General → Appearance, shared by every app; brief 42 took the header's sun button away), so
/// this keeps only whether red is on: the band enters and leaves it, the header's X leaves it, and it stays on across
/// launches.
nonisolated struct ThemeState {
    static let preferenceKey = "aresium.red"

    enum Action { case band, header }

    struct Transition: Equatable {
        let id = UUID()
        let entering: Bool              // into red; false: back to the appearance's light or dark
    }

    private(set) var red: Bool
    private(set) var transition: Transition?
    var isAnimating: Bool { transition != nil }

    init(red: Bool = false) {
        self.red = red
    }

    /// The look on screen over the appearance's light or dark (`base`).
    func theme(over base: AppTheme) -> AppTheme { red ? .red : base }

    /// The band enters or leaves red; the header's X leaves it. The header shows its X only in red, so outside red
    /// `.header` does nothing. Taps while a transition runs are ignored.
    mutating func send(_ action: Action, reduceMotion: Bool) {
        guard !isAnimating, action == .band || red else { return }
        if reduceMotion {
            red.toggle()
        } else {
            transition = Transition(entering: !red)
        }
    }

    mutating func advance(to progress: Double) {
        guard let transition else { return }
        if progress >= IntroTimeline.swapAt { red = transition.entering }
        if progress >= 1 { self.transition = nil }
    }

    mutating func finishImmediately() {
        advance(to: 1)
    }
}

/// Values from web/public/app/aresium-intro.js. Y is in viewport-height units;
/// X is in points. Easing belongs to the segment *following* its keyframe (WAAPI).
nonisolated enum IntroTimeline {
    static let duration = 1.5
    static let backgroundFraction = 0.5
    static let swapAt = 0.56

    struct Frame {
        var y: Double
        var x: Double = 0
        var rotation: Double = 0
        var scale: Double = 1.18
        var opacity: Double = 1
    }

    enum Easing {
        case linear, impact, settle, flyOut, background

        func value(at progress: Double) -> Double {
            guard progress > 0 else { return 0 }
            guard progress < 1 else { return 1 }
            let points: (Double, Double, Double, Double)
            switch self {
            case .linear: return progress
            case .impact: points = (0.16, 0.84, 0.3, 1.12)
            case .settle: points = (0.5, 0, 0.18, 1)
            case .flyOut: points = (0.4, 0, 0.7, 0.25)
            case .background: points = (0.4, 0, 0.2, 1)
            }
            func cubic(_ t: Double, _ a: Double, _ b: Double) -> Double {
                3 * (1 - t) * (1 - t) * t * a + 3 * (1 - t) * t * t * b + t * t * t
            }
            var low = 0.0
            var high = 1.0
            for _ in 0..<24 {
                let t = (low + high) / 2
                if cubic(t, points.0, points.2) < progress { low = t } else { high = t }
            }
            return cubic((low + high) / 2, points.1, points.3)
        }
    }

    struct Keyframe {
        let offset: Double
        let frame: Frame
        var easing: Easing = .linear
    }

    static let enter: [Keyframe] = [
        .init(offset: 0, frame: .init(y: 60, scale: 1.04, opacity: 0)),
        .init(offset: 0.26, frame: .init(y: -30), easing: .impact),
        .init(offset: 0.30, frame: .init(y: -30, x: -8, rotation: -0.5)),
        .init(offset: 0.345, frame: .init(y: -30.6, x: 7, rotation: 0.5)),
        .init(offset: 0.39, frame: .init(y: -29.6, x: -5, rotation: -0.3)),
        .init(offset: 0.435, frame: .init(y: -30, x: 4, rotation: 0.2)),
        .init(offset: 0.48, frame: .init(y: -30), easing: .settle),
        .init(offset: 1, frame: .init(y: 0, scale: 1))
    ]
    static let exit: [Keyframe] = [
        .init(offset: 0, frame: .init(y: 0, scale: 1)),
        .init(offset: 0.30, frame: .init(y: -30), easing: .impact),
        .init(offset: 0.345, frame: .init(y: -30, x: -8, rotation: -0.5)),
        .init(offset: 0.39, frame: .init(y: -30.6, x: 7, rotation: 0.5)),
        .init(offset: 0.435, frame: .init(y: -29.6, x: -5, rotation: -0.3)),
        .init(offset: 0.48, frame: .init(y: -30, x: 4, rotation: 0.2)),
        .init(offset: 0.54, frame: .init(y: -30), easing: .flyOut),
        .init(offset: 1, frame: .init(y: 70, scale: 1.04, opacity: 0))
    ]

    static func frame(at progress: Double, entering: Bool) -> Frame {
        let frames = entering ? enter : exit
        let p = min(1, max(0, progress))
        guard let index = frames.indices.dropLast().first(where: { p < frames[$0 + 1].offset }) else {
            return frames[frames.count - 1].frame
        }
        let start = frames[index]
        let end = frames[index + 1]
        let t = start.easing.value(at: (p - start.offset) / (end.offset - start.offset))
        func mix(_ a: Double, _ b: Double) -> Double { a + (b - a) * t }
        // Only these opacity anchors are specified by the website; missing values interpolate.
        let opacity = entering ? min(1, p / 0.26) : max(0, 1 - Easing.impact.value(at: (p - 0.30) / 0.70))
        return Frame(y: mix(start.frame.y, end.frame.y), x: mix(start.frame.x, end.frame.x),
                     rotation: mix(start.frame.rotation, end.frame.rotation),
                     scale: mix(start.frame.scale, end.frame.scale), opacity: opacity)
    }

    static func backgroundOpacity(at progress: Double) -> Double {
        Easing.background.value(at: progress / backgroundFraction)
    }
}
