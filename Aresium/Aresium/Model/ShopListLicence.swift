import Foundation

extension BundledLicence {
    /// The brand names in the engine's shop list (name-suggestion-index, BSD-3-Clause). The engine bundle ships them in
    /// both modes, so the notice is always on Settings → About → Fonts & licences. Its text is the header of
    /// aresium/src/engine/sorting/shops.de.json, written next to the engine by scripts/aresium-engine.sh. A function, so
    /// its words follow a language switch.
    static func shopList() -> BundledLicence {
        BundledLicence(name: "name-suggestion-index", purpose: String(localized: "Shop names for sorting"),
                       licenceName: "BSD-3-Clause", file: "name-suggestion-index-licence")
    }
}
