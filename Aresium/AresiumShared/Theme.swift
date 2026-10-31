import SwiftUI
import CoreText

struct Palette {
    let theme: AppTheme
    var dark: Bool { theme != .light }
    var red: Bool { theme == .red }
    var background: Color { Color(hex: red ? "34060F" : dark ? "050507" : "ECEDF2") }
    var ink: Color { Color(hex: red ? "FFF5F5" : dark ? "F6F7FB" : "0A0C12") }
    var secondary: Color { red ? Color(hex: "FFECEE").opacity(0.86) : Color(hex: dark ? "B3B9C6" : "525A69") }
    var muted: Color { red ? Color(hex: "FFD6DA").opacity(0.6) : Color(hex: dark ? "6B7280" : "88919F") }
    var line: Color { red ? Color(hex: "FFD2D8").opacity(0.16) : (dark ? Color.white : Color(hex: "0F1428")).opacity(dark ? 0.08 : 0.10) }
    var grid: Color { red ? Color(hex: "FFD2D8").opacity(0.10) : (dark ? Color.white : Color(hex: "0F1428")).opacity(dark ? 0.05 : 0.07) }
    /// The guide line under a finger reading a graph (the website's `--guide`, brief 56).
    var guide: Color { red ? Color(hex: "FFDCE1").opacity(0.45) : (dark ? Color.white : Color(hex: "0F1428")).opacity(dark ? 0.22 : 0.28) }
    var card: Color { red ? Color(hex: "2C050F").opacity(0.52) : dark ? Color(hex: "0F1015").opacity(0.55) : Color.white.opacity(0.74) }
    var card2: Color { red ? Color(hex: "400915").opacity(0.56) : Color(hex: dark ? "1A1C23" : "F7F8FB").opacity(dark ? 0.62 : 0.82) }
    /// The expense series in charts. On the red wall the light ink, as the widget's line and the expense text: the
    /// website's black (0A0A0A) all but vanished on the app's darker red wall (about 1.3:1, brief 46).
    var expense: Color { red ? ink : Color(hex: dark ? "FF2D4B" : "E11030") }
    /// Text in the expense colour (headings, amounts, errors): in red mode the light ink, since black text on the red
    /// wall cannot be read (about 1.3:1).
    var expenseText: Color { red ? ink : expense }
    var balance: Color { Color(hex: red ? "FFFFFF" : dark ? "2E8BFF" : "1452F0") }
    var income: Color { Color(hex: "34E27A") }

    func wordGradient(width: CGFloat, height: CGFloat) -> LinearGradient {
        let stops: [Gradient.Stop] = red ? [
            .init(color: .white.opacity(0.5), location: 0),
            .init(color: .white.opacity(0.16), location: 0.6),
            .init(color: .white.opacity(0.05), location: 1)
        ] : [
            .init(color: Color(hex: dark ? "F6F7FB" : "0A0C12"), location: 0),
            .init(color: Color(hex: "7F7F7F").opacity(0.18), location: 1)
        ]
        // The mobile gradient's final stop is at 116%, beyond the glyph bounds.
        return LinearGradient(cssAngle: 177, stops: stops, size: CGSize(width: width, height: height),
                              endFraction: red ? 1 : 1.16)
    }
}

private extension LinearGradient {
    init(cssAngle: Double, stops: [Gradient.Stop], size: CGSize, endFraction: Double = 1) {
        let angle = cssAngle * .pi / 180
        let dx = sin(angle)
        let dy = -cos(angle)
        let length = abs(size.width * dx) + abs(size.height * dy)
        let halfX = dx * length / (2 * max(1, size.width))
        let halfY = dy * length / (2 * max(1, size.height))
        let start = UnitPoint(x: 0.5 - halfX, y: 0.5 - halfY)
        self.init(stops: stops, startPoint: start,
                  endPoint: UnitPoint(x: start.x + 2 * halfX * endFraction,
                                      y: start.y + 2 * halfY * endFraction))
    }
}

private struct WallLinear: View {
    let angle: Double
    let stops: [Gradient.Stop]
    var body: some View {
        GeometryReader { geometry in
            LinearGradient(cssAngle: angle, stops: stops, size: geometry.size)
        }
    }
}

extension Color {
    init(hex: String) {
        let value = UInt64(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0x9AA6B8
        self.init(.sRGB, red: Double((value >> 16) & 255) / 255,
                  green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255, opacity: 1)
    }
}


/// CSS radial gradients use independent horizontal/vertical radii and may sit offscreen.
private struct WallGlow: View {
    let color: Color
    let center: UnitPoint
    let radius: CGSize
    let fade: Double

    var body: some View {
        Canvas { context, size in
            context.translateBy(x: size.width * center.x, y: size.height * center.y)
            context.scaleBy(x: size.width * radius.width, y: size.height * radius.height)
            let rect = CGRect(x: -10, y: -10, width: 20, height: 20)
            context.fill(Path(rect), with: .radialGradient(
                Gradient(stops: [.init(color: color, location: 0), .init(color: .clear, location: fade)]),
                center: .zero, startRadius: 0, endRadius: 1))
        }.allowsHitTesting(false)
    }
}

struct Wall: View {
    let palette: Palette
    var body: some View {
        ZStack {
            if palette.red {
                WallLinear(angle: 176, stops: [
                    .init(color: Color(hex: "520A1A"), location: 0),
                    .init(color: Color(hex: "320510"), location: 0.52),
                    .init(color: Color(hex: "140206"), location: 1)
                ])
                WallGlow(color: Color(hex: "140106").opacity(0.92), center: UnitPoint(x: 0.86, y: 1.22),
                         radius: CGSize(width: 0.72, height: 0.56), fade: 0.56)
                WallGlow(color: Color(hex: "9E142C").opacity(0.32), center: UnitPoint(x: 0.5, y: -0.16),
                         radius: CGSize(width: 0.62, height: 0.32), fade: 0.56)
                WallLinear(angle: 118, stops: [.init(color: .white.opacity(0.10), location: 0),
                                       .init(color: .white.opacity(0.02), location: 0.16),
                                       .init(color: .clear, location: 0.34)])
                WallGlow(color: Color(hex: "FF7887").opacity(0.15), center: UnitPoint(x: 0.5, y: 0.01),
                         radius: CGSize(width: 0.58, height: 0.26), fade: 0.60)
            } else {
                palette.background
                WallGlow(color: Color(hex: "D81A34").opacity(palette.dark ? 0.36 : 0.13),
                         center: UnitPoint(x: 0.5, y: -0.12), radius: CGSize(width: 0.72, height: 0.52), fade: 0.6)
                WallGlow(color: Color(hex: palette.dark ? "960E26" : "D81A34").opacity(palette.dark ? 0.24 : 0.07),
                         center: UnitPoint(x: 0.9, y: 1.2), radius: CGSize(width: 0.58, height: 0.5), fade: 0.56)
            }
        }.ignoresSafeArea()
    }
}
