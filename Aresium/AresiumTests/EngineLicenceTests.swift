import Foundation
import Testing
@testable import Aresium

/// The licences of the outside packages in the engine (brief 315): the app lists exactly the packages the engine build
/// found in the bundle (Engine/engine-licences.json, copied by scripts/aresium-engine.sh with the bundle), each with
/// its licence file in the app, as Settings → About → Fonts & licences → Code shows them.
@MainActor
struct EngineLicenceTests {
    private struct Package: Decodable {
        let name: String
        let version: String
        let licence: String
        let homepage: String
        let text: String
    }

    private func builtList() throws -> [Package] {
        let bundle = Bundle(for: EngineLicenceAnchor.self)
        let url = try #require(bundle.url(forResource: "engine-licences", withExtension: "json", subdirectory: "Engine")
            ?? bundle.url(forResource: "engine-licences", withExtension: "json"))
        return try JSONDecoder().decode([Package].self, from: Data(contentsOf: url))
    }

    @Test func theAppListsEveryPackageInTheEngineWithItsLicence() throws {
        let built = try builtList()
        let listed = BundledLicence.enginePackages()
        #expect(listed.map(\.name).sorted() == built.map(\.name).sorted())
        for package in built {
            let licence = try #require(listed.first { $0.name == package.name }, "not in the app: \(package.name)")
            #expect(licence.licenceName == package.licence, "\(package.name)")
            #expect(licence.kind == .code)
            #expect(!licence.purpose.isEmpty)
            let text = try #require(licence.text(), "no licence file in the app for \(package.name)")
            #expect(text.hasPrefix("Aresium includes \(package.name) \(package.version) (\(package.homepage)) "
                                   + "under the \(package.licence) licence:\n\n"))
            // The package's own licence text, whole, with its copyright line.
            #expect(text.contains(package.text), "\(package.name)'s licence text differs")
            let copyright = try #require(package.text.split(separator: "\n").first { $0.hasPrefix("Copyright") })
            #expect(LicenceParagraph.paragraphs(text).contains { $0.text == String(copyright) })
        }
    }

    @Test func packagesAreListedUnderCodeAndTheDataStaysUnderData() {
        let licences = [BundledLicence.shopList(), .localPlaces()] + BundledLicence.enginePackages()
        #expect(licences.filter { $0.kind == .data }.map(\.name)
                == ["name-suggestion-index", BundledLicence.localPlaces().name])
        #expect(licences.filter { $0.kind == .code }.map(\.name) == ["csv-parse", "fast-xml-parser", "fflate", "strnum"])
        #expect(Set(licences.map(\.id)).count == licences.count)
    }

    @Test func packageFileNamesNeverMeet() {
        #expect(BundledLicence.enginePackageFile("csv-parse") == "engine-package-csv-parse")
        #expect(BundledLicence.enginePackageFile("@scope/name") == "engine-package-@scope+name")
        #expect(BundledLicence.enginePackageFile("@scope/name") != BundledLicence.enginePackageFile("scope-name"))
    }

    @Test func purposesAreInGerman() {
        let german = AppLanguage.$scoped.withValue(.german) { BundledLicence.enginePackages() }
        #expect(german.map(\.purpose) == ["CSV-Dateien lesen", "CAMT- und Excel-Dateien lesen",
                                          "ZIP- und Excel-Dateien öffnen", "Teil von fast-xml-parser"])
    }
}

private final class EngineLicenceAnchor: NSObject {}
