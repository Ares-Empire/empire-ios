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

    /// The separately bundled ODbL list. Like the shop notice, its title and link labels follow language switches.
    static func localPlaces() -> BundledLicence {
        BundledLicence(name: String(localized: "© OpenStreetMap contributors"),
                       purpose: String(localized: "Local places for sorting"),
                       licenceName: "ODbL 1.0", file: "local-places-licence", links: [
                        .init(title: String(localized: "OpenStreetMap copyright and contributors"),
                              url: URL(string: "https://www.openstreetmap.org/copyright")!),
                        .init(title: String(localized: "Open Database License (ODbL) 1.0"),
                              url: URL(string: "https://opendatacommons.org/licenses/odbl/1-0/")!),
                        .init(title: String(localized: "Download the local places list"),
                              url: URL(string: "https://aresium.de/osm/local-places-de.places.bin.gz")!),
                       ])
    }
}
