import SwiftUI
import CoreText

struct Palette {
    let dark: Bool
    var background: Color { Color(hex: dark ? "050507" : "ECEDF2") }
    var ink: Color { Color(hex: dark ? "F6F7FB" : "0A0C12") }
    var secondary: Color { Color(hex: dark ? "B3B9C6" : "525A69") }
    var muted: Color { Color(hex: dark ? "6B7280" : "88919F") }
    var line: Color { (dark ? Color.white : Color(hex: "0F1428")).opacity(dark ? 0.08 : 0.10) }
    var grid: Color { (dark ? Color.white : Color(hex: "0F1428")).opacity(dark ? 0.05 : 0.07) }
    var card: Color { dark ? Color(hex: "0F1015").opacity(0.55) : Color.white.opacity(0.74) }
    var card2: Color { Color(hex: dark ? "1A1C23" : "F7F8FB").opacity(dark ? 0.62 : 0.82) }
    var expense: Color { Color(hex: dark ? "FF2D4B" : "E11030") }
    var balance: Color { Color(hex: dark ? "2E8BFF" : "1452F0") }
    var income: Color { Color(hex: "34E27A") }
}

extension Color {
    init(hex: String) {
        let value = UInt64(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0x9AA6B8
        self.init(.sRGB, red: Double((value >> 16) & 255) / 255,
                  green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255, opacity: 1)
    }
}

enum AppFont {
    static let textName = "SpaceGrotesk-Light_Regular"
    static let numberName = "JetBrainsMono-Regular"
    static func text(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .custom(textName, size: size, relativeTo: .body).weight(weight)
    }
    static func number(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .custom(numberName, size: size, relativeTo: .body).weight(weight)
    }
    static func register() {
        for name in ["SpaceGrotesk-Variable", "JetBrainsMono-Variable"] {
            if let url = Bundle.main.url(forResource: name, withExtension: "ttf") {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
    }
}

struct Wall: View {
    let palette: Palette
    var body: some View {
        palette.background.overlay(alignment: .top) {
            RadialGradient(colors: [Color(hex: "D81A34").opacity(palette.dark ? 0.24 : 0.10), .clear],
                           center: UnitPoint(x: 0.5, y: -0.12), startRadius: 0, endRadius: 360)
        }.ignoresSafeArea()
    }
}
