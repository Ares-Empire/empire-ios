import SwiftUI
import UIKit

/// The hub's crown language, one-to-one from ares-empire/web/app/styles.css (`:root`) and mobile.css.
/// Gold is an accent only (the wordmark, province names, status words, the chronicle); see the design notes in
/// ares-empire/EMPIRE.md and the approved phone hub.
///
/// Light mode (2026-10-25): the throne room by day, a "marble hall": a warm ivory wall in place of the black one,
/// antique gold (the same polished gradient, deeper, so it reads on ivory), the bust as a faint grey relief. Every
/// colour is a light/dark pair; the dark values are the approved hub's, unchanged. The greys of mobile.css keep their
/// exact dark value at each place and take the light value of their role (`title`, `heading`, `body`, `quiet`, `icon`).
enum EmpireStyle {
    static let background = Color(light: Color(hex: 0xEFEDE6), dark: Color(hex: 0x070708))       // --bg
    static let ink = Color(light: Color(hex: 0x1A1813), dark: Color(hex: 0xF3F1EA))              // --ink
    static let ink2 = Color(light: Color(hex: 0x5E5A50), dark: Color(hex: 0xA6A39A))             // --ink-2
    static let ink3 = Color(light: Color(hex: 0x777268), dark: Color(hex: 0x67645C))             // --ink-3
    static let gold2 = Color(light: Color(hex: 0x9A6B1F), dark: Color(hex: 0xCFA24F))            // --gold-2
    static let cardRadius: CGFloat = 16                 // --r-card

    /// A sheet's background (mobile.css `.em-sheet`).
    static let sheetBackground = Color(light: Color(hex: 0xF5F3EE), dark: Color(hex: 0x0A0C0E))
    /// A card on a sheet (.em-account, .em-catalog-card).
    static let card = Color(light: Color(hex: 0xFFFFFF, opacity: 0.72), dark: Color(hex: 0x111417))

    // The text roles, light values (on the ivory wall: title 15:1, heading 10:1, body 7:1, quiet 4.2:1).
    private static let lightTitle = Color(hex: 0x1A1813)
    private static let lightHeading = Color(hex: 0x3A3934)
    private static let lightBody = Color(hex: 0x4E4F4A)
    private static let lightQuiet = Color(hex: 0x6E716B)
    private static let lightIcon = Color(hex: 0x55564F)

    /// Names on pages and cards (dark: #EEEEE8 and its neighbours).
    static func title(dark: UInt32) -> Color { Color(light: lightTitle, dark: Color(hex: dark)) }
    /// Section titles, a province's live line (dark: #C2C4BF and its neighbours).
    static func heading(dark: UInt32) -> Color { Color(light: lightHeading, dark: Color(hex: dark)) }
    /// Running text (dark: #ADB2AD and its neighbours).
    static func body(dark: UInt32) -> Color { Color(light: lightBody, dark: Color(hex: dark)) }
    /// Quiet lines, captions, small labels (dark: #8F9390 and its neighbours).
    static func quiet(dark: UInt32) -> Color { Color(light: lightQuiet, dark: Color(hex: dark)) }
    /// Header and empty-state icons (dark: #A8A9A7 and its neighbours).
    static func icon(dark: UInt32) -> Color { Color(light: lightIcon, dark: Color(hex: dark)) }
    /// A hairline between parts (dark: white at this opacity).
    static func hairline(dark opacity: Double) -> Color {
        Color(light: Color(hex: 0x1A1813, opacity: 0.09), dark: .white.opacity(opacity))
    }
    /// A card's or circle's thin edge (dark: white at this opacity).
    static func edge(dark opacity: Double) -> Color {
        Color(light: Color(hex: 0x1A1813, opacity: 0.13), dark: .white.opacity(opacity))
    }
    /// A quiet fill (a note, a secondary button, an initial's circle; dark: white at this opacity).
    static func fill(dark opacity: Double) -> Color {
        Color(light: .white.opacity(0.55), dark: .white.opacity(opacity))
    }
    /// The shadow under a raised piece (the crest, a ring tab; dark: black at this opacity).
    static func shadow(dark opacity: Double) -> Color {
        Color(light: Color(hex: 0x2A2418, opacity: opacity * 0.3), dark: .black.opacity(opacity))
    }

    /// --gold-text: the wordmark and headings. Light: the same polish, deeper (antique gold), so small caps read on
    /// ivory (the body about 4:1).
    static let goldText = LinearGradient(stops: [
        .init(color: Color(light: Color(hex: 0xC9A050), dark: Color(hex: 0xFFF6DB)), location: 0),
        .init(color: Color(light: Color(hex: 0xB4893A), dark: Color(hex: 0xF6DD9C)), location: 0.19),
        .init(color: Color(light: Color(hex: 0x9C7428), dark: Color(hex: 0xE8C778)), location: 0.38),
        .init(color: Color(light: Color(hex: 0x7D5818), dark: Color(hex: 0xCCA052)), location: 0.55),
        .init(color: Color(light: Color(hex: 0x8E6620), dark: Color(hex: 0xA87C31)), location: 0.72),
        .init(color: Color(light: Color(hex: 0xB08440), dark: Color(hex: 0xECCE85)), location: 0.88),
        .init(color: Color(light: Color(hex: 0x5E3F0E), dark: Color(hex: 0x8C6420)), location: 1)],
        startPoint: .top, endPoint: .bottom)

    /// --gold-name: province names on the ring tabs.
    static let goldName = LinearGradient(stops: [
        .init(color: Color(light: Color(hex: 0xC09443), dark: Color(hex: 0xFFF3CF)), location: 0),
        .init(color: Color(light: Color(hex: 0xA97E30), dark: Color(hex: 0xF6D886)), location: 0.22),
        .init(color: Color(light: Color(hex: 0x926823), dark: Color(hex: 0xE6BD62)), location: 0.46),
        .init(color: Color(light: Color(hex: 0x7A5517), dark: Color(hex: 0xCB9A3E)), location: 0.68),
        .init(color: Color(light: Color(hex: 0x6A4810), dark: Color(hex: 0xB07F2C)), location: 0.86),
        .init(color: Color(light: Color(hex: 0x9C7330), dark: Color(hex: 0xF0D289)), location: 1)],
        startPoint: .top, endPoint: .bottom)

    /// A status code from the hub ("CONQUERED", …, "COMING SOON", "PLANNED") in the app's language; codes stay codes
    /// (they pick the colour), only the shown word is translated.
    static func statusWord(_ status: String) -> String {
        switch status {
        case "CONQUERED": String(localized: LocalizedStringResource("CONQUERED", locale: .appLanguage,
                                                                    comment: "Province status: live and held"))
        case "FORTIFYING": String(localized: LocalizedStringResource("FORTIFYING", locale: .appLanguage,
                                                                     comment: "Province status: live, in maintenance"))
        case "MUSTERING": String(localized: LocalizedStringResource("MUSTERING", locale: .appLanguage,
                                                                    comment: "Province status: getting ready"))
        case "BESIEGING": String(localized: LocalizedStringResource("BESIEGING", locale: .appLanguage,
                                                                    comment: "Province status: being built"))
        case "SCOUTED": String(localized: LocalizedStringResource("SCOUTED", locale: .appLanguage,
                                                                  comment: "Province status: an idea"))
        case "COMING SOON":
            String(localized: LocalizedStringResource("COMING SOON", locale: .appLanguage,
                                                      comment: "Province status for members: not open yet"))
        case "PLANNED": String(localized: LocalizedStringResource("PLANNED", locale: .appLanguage,
                                                                  comment: "An expansion's status"))
        default: status
        }
    }

    /// Status words on the tabs (.st-live, .st-wip, .st-hold, .st-scout, .st-muster).
    static func statusColor(_ status: String) -> Color {
        switch status {
        case "CONQUERED": StatusTone.activeColor
        case "FORTIFYING": Color(light: Color(hex: 0x2D5FC4), dark: Color(hex: 0x84B6FF))
        case "MUSTERING": Color(light: Color(hex: 0x8C6418), dark: Color(hex: 0xC8A25F))
        case "BESIEGING": ink2
        default: ink3
        }
    }
}

extension View {
    /// Fills text with one of the hub's gold gradients (CSS background-clip: text).
    func goldFill(_ gradient: LinearGradient = EmpireStyle.goldText) -> some View {
        foregroundStyle(gradient)
    }
}
