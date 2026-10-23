import SwiftUI
import CoreText

/// The Empire's two typefaces (Shared/Fonts, OFL): Space Grotesk for text, JetBrains Mono for numbers.
/// Call `register()` once at launch in every app and extension.
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
