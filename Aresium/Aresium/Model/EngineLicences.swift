import Foundation

extension BundledLicence {
    /// The outside packages whose code is in the engine bundle, under Settings → About → Fonts & licences → Code. The
    /// engine build lists them from the bundle itself (aresium `npm run engine`, dist/engine-licences.json) and
    /// scripts/aresium-engine.sh writes each one's licence to Engine/engine-package-<name>.txt. `EngineLicenceTests`
    /// checks this list against that list, so a package added to the engine fails the tests until it has a row here.
    /// A function, so the purposes follow a language switch.
    static func enginePackages() -> [BundledLicence] {
        [
            package("csv-parse", purpose: String(localized: "Reading CSV files")),
            package("fast-xml-parser", purpose: String(localized: "Reading CAMT and Excel files")),
            package("fflate", purpose: String(localized: "Opening ZIP and Excel files")),
            package("strnum", purpose: String(localized: "Part of fast-xml-parser")),
        ]
    }

    /// The bundle's file for a package's licence; the script names it the same way.
    static func enginePackageFile(_ name: String) -> String {
        "engine-package-" + name.replacingOccurrences(of: "@", with: "").replacingOccurrences(of: "/", with: "-")
    }

    private static func package(_ name: String, purpose: String) -> BundledLicence {
        BundledLicence(name: name, purpose: purpose, licenceName: "MIT", file: enginePackageFile(name), kind: .code)
    }
}
