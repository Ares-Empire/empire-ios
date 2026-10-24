import SwiftUI
import UIKit

/// The hub's crown language, one-to-one from ares-empire/web/app/styles.css (`:root`) and mobile.css.
/// Gold is an accent only (the wordmark, province names, status words, the chronicle); see the design notes in
/// ares-empire/EMPIRE.md and the approved phone hub.
enum EmpireStyle {
    static let background = Color(hex: 0x070708)       // --bg
    static let ink = Color(hex: 0xF3F1EA)               // --ink
    static let ink2 = Color(hex: 0xA6A39A)              // --ink-2
    static let ink3 = Color(hex: 0x67645C)              // --ink-3
    static let gold2 = Color(hex: 0xCFA24F)             // --gold-2
    static let cardRadius: CGFloat = 16                 // --r-card

    /// --gold-text: the wordmark and headings.
    static let goldText = LinearGradient(stops: [
        .init(color: Color(hex: 0xFFF6DB), location: 0), .init(color: Color(hex: 0xF6DD9C), location: 0.19),
        .init(color: Color(hex: 0xE8C778), location: 0.38), .init(color: Color(hex: 0xCCA052), location: 0.55),
        .init(color: Color(hex: 0xA87C31), location: 0.72), .init(color: Color(hex: 0xECCE85), location: 0.88),
        .init(color: Color(hex: 0x8C6420), location: 1)], startPoint: .top, endPoint: .bottom)

    /// --gold-name: province names on the ring tabs.
    static let goldName = LinearGradient(stops: [
        .init(color: Color(hex: 0xFFF3CF), location: 0), .init(color: Color(hex: 0xF6D886), location: 0.22),
        .init(color: Color(hex: 0xE6BD62), location: 0.46), .init(color: Color(hex: 0xCB9A3E), location: 0.68),
        .init(color: Color(hex: 0xB07F2C), location: 0.86), .init(color: Color(hex: 0xF0D289), location: 1)],
        startPoint: .top, endPoint: .bottom)

    /// Status words on the tabs (.st-live, .st-wip, .st-hold, .st-scout, .st-muster).
    static func statusColor(_ status: String) -> Color {
        switch status {
        case "CONQUERED": Color(hex: 0x6FCF9B)
        case "FORTIFYING": Color(hex: 0x84B6FF)
        case "MUSTERING": Color(hex: 0xC8A25F)
        case "BESIEGING": ink2
        default: ink3
        }
    }
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255, opacity: opacity)
    }
}

extension View {
    /// Fills text with one of the hub's gold gradients (CSS background-clip: text).
    func goldFill(_ gradient: LinearGradient = EmpireStyle.goldText) -> some View {
        foregroundStyle(gradient)
    }
}

/// A province's mark: its image when loaded, else its initial in a quiet tile (.tab-mono).
struct ProvinceMarkView: View {
    let name: String
    let image: UIImage?
    var size: CGFloat = 50

    var body: some View {
        if let image {
            Image(uiImage: image).resizable().scaledToFit().frame(width: size, height: size)
                .shadow(color: .black.opacity(0.55), radius: 9, y: 8)
        } else {
            Text(String(name.prefix(1)).uppercased())
                .font(AppFont.text(size * 0.44, weight: .bold)).foregroundStyle(EmpireStyle.ink)
                .frame(width: size * 0.92, height: size * 0.92)
                .background(RadialGradient(colors: [.white.opacity(0.08), .black.opacity(0.2)], center: .init(x: 0.3, y: 0.2),
                                           startRadius: 0, endRadius: size), in: .rect(cornerRadius: 13))
                .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(.white.opacity(0.12)))
        }
    }
}
