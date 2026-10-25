import SwiftUI
import Testing
import UIKit
@testable import Empire

/// Light mode (Shared/Settings/Appearance.swift, Shared/Design/EmpireDesign.swift): the saved choice, what the window
/// is told, and the shared colours resolving to their light or dark value.
struct AppearanceTests {
    @Test func savedChoiceFallsBackToTheIPhone() {
        #expect(Appearance(saved: nil) == .iPhone)
        #expect(Appearance(saved: "sepia") == .iPhone)
        #expect(Appearance(saved: "light") == .light)
        #expect(Appearance(saved: "dark") == .dark)
        #expect(Appearance(saved: Appearance.iPhone.rawValue) == .iPhone)
    }

    @Test func choiceTellsTheWindow() {
        #expect(Appearance.iPhone.colorScheme == nil)
        #expect(Appearance.light.colorScheme == .light)
        #expect(Appearance.dark.colorScheme == .dark)
    }

    /// Aresium's sun button: a fixed choice of the other look than the one shown.
    @Test func toggledIsTheOtherLook() {
        #expect(Appearance.toggled(from: .dark) == .light)
        #expect(Appearance.toggled(from: .light) == .dark)
    }

    @Test func namesInBothLanguages() {
        AppLanguage.$scoped.withValue(.english) {
            #expect(Appearance.allCases.map(\.name) == ["Like the iPhone", "Light", "Dark"])
        }
        AppLanguage.$scoped.withValue(.german) {
            #expect(Appearance.allCases.map(\.name) == ["Wie das iPhone", "Hell", "Dunkel"])
        }
    }

    /// The pairs resolve per look, so a screen built from them follows the window by itself.
    @Test func sharedColoursResolvePerLook() {
        #expect(hex(Ink.background, .light) == 0xECEDF2)
        #expect(hex(Ink.background, .dark) == 0x050507)
        #expect(hex(Ink.primary, .light) == 0x0A0C12)
        #expect(hex(Ink.primary, .dark) == 0xF6F7FB)
        #expect(hex(AppAccent.aresus.color, .light) == 0x2A62E0)
        #expect(hex(AppAccent.aresus.color, .dark) == 0x6AA8FF)
    }

    /// Text in the accents and status colours reads on the light wall (WCAG: 4.5:1 for text).
    @Test func lightAccentsReadOnTheLightWall() {
        let wall = Ink.background
        for color in [AppAccent.arestemis.color, AppAccent.aresus.color, AppAccent.arestoteles.color,
                      StatusTone.activeColor, StatusTone.issueColor, Ink.primary, Ink.secondary] {
            #expect(contrast(color, wall, .light) >= 4.5)
        }
        #expect(contrast(Ink.muted, wall, .light) >= 3.8)        // small grey captions, as the dark wall's 4.2
    }

    // MARK: helpers

    private func resolved(_ color: Color, _ style: UIUserInterfaceStyle) -> (Double, Double, Double) {
        let ui = UIColor(color).resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        ui.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return (Double(red), Double(green), Double(blue))
    }

    private func hex(_ color: Color, _ style: UIUserInterfaceStyle) -> UInt32 {
        let (r, g, b) = resolved(color, style)
        func byte(_ value: Double) -> UInt32 { UInt32((value * 255).rounded()) }
        return byte(r) << 16 | byte(g) << 8 | byte(b)
    }

    private func contrast(_ a: Color, _ b: Color, _ style: UIUserInterfaceStyle) -> Double {
        func luminance(_ color: Color) -> Double {
            let (r, g, b) = resolved(color, style)
            func linear(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
            return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
        }
        let (high, low) = (max(luminance(a), luminance(b)), min(luminance(a), luminance(b)))
        return (high + 0.05) / (low + 0.05)
    }
}
