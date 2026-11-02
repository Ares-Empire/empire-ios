import Foundation

extension BundledLicence {
    /// The town coordinates behind thing searches (brief 129): the Arestemis server looks up a thing search's towns on
    /// OpenStreetMap (Nominatim) for IKEA Preowned's and eBay's pickup searches. The app ships no OpenStreetMap data, but
    /// what it searches with comes from it, so Settings → About → Fonts & licences credits it as Aresium credits its
    /// local places (`localPlaces()` there), without a download link. A function, so its words follow a language switch.
    static func townLocations(language: AppLanguage = .current) -> BundledLicence {
        BundledLicence(name: language.string("© OpenStreetMap contributors"),
                       purpose: language.string("Town locations for thing searches"),
                       licenceName: "ODbL 1.0", file: "town-locations-licence", links: [
                        .init(title: language.string("OpenStreetMap copyright and contributors"),
                              url: URL(string: "https://www.openstreetmap.org/copyright")!),
                        .init(title: language.string("Open Database License (ODbL) 1.0"),
                              url: URL(string: "https://opendatacommons.org/licenses/odbl/1-0/")!),
                       ])
    }
}
