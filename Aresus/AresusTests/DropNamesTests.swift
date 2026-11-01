import Foundation
import Testing
@testable import Aresus

struct DropNamesTests {
    @Test func eachNewNameRule() {
        #expect(DropNames.newName("") == .empty)
        #expect(DropNames.newName(String(repeating: "é", count: 101)) == .tooLong)
        #expect(DropNames.newName(String(repeating: "é", count: 100)) == nil)
        #expect(DropNames.newName(String(repeating: "e\u{301}", count: 100)) == nil)
        #expect(DropNames.normalized("e\u{301}.pdf") == "é.pdf")
        for name in ["a/b", "a\\b", "a:b", "a\nb", "a\u{0}b", "a\u{7f}b"] {
            #expect(DropNames.newName(name) == .forbiddenCharacter)
        }
        for name in [".", ".."] { #expect(DropNames.newName(name) == .dot) }
        #expect(DropNames.newName(".hidden") == .leadingDot)
        for name in ["x ", "x."] { #expect(DropNames.newName(name) == .trailingSpaceOrDot) }
        #expect(DropNames.newName("Floor plan (2).pdf") == nil)
    }

    @Test func existingFolderPartsHaveTheirOwnContract() {
        #expect(DropNames.folderPart("") == .empty)
        #expect(DropNames.folderPart(String(repeating: "a", count: 255)) == nil)
        #expect(DropNames.folderPart(String(repeating: "a", count: 256)) == .tooLong)
        #expect(DropNames.folderPart(String(repeating: "é", count: 128)) == .tooLong)
        #expect(DropNames.folderPart("a/b") == .forbiddenCharacter)
        #expect(DropNames.folderPart("a\tb") == .forbiddenCharacter)
        #expect(DropNames.folderPart(".") == .dot)
        #expect(DropNames.folderPart("..") == .dot)
        #expect(DropNames.folderPart(".hidden") == .leadingDot)
        for part in ["Notes: old", "Windows\\old", "Old.", "Old "] { #expect(DropNames.folderPart(part) == nil) }
        #expect(DropNames.folderPath("") == nil)
        #expect(DropNames.folderPath("Notes: old/Letters") == nil)
        for path in ["/a", "a/", "a//b"] { #expect(DropNames.folderPath(path) == .empty) }
        #expect(DropNames.folderPath("a/../b") == .dot)
        #expect(DropNames.folderPath(Array(repeating: "a", count: 8).joined(separator: "/")) == nil)
        #expect(DropNames.folderPath(Array(repeating: "a", count: 9).joined(separator: "/")) == .tooManyParts)
    }

    @Test func defaultsUseLocalTimeAndKeepTheExtension() {
        let date = at("2026-11-01T18:03:04Z")
        #expect(DropNames.defaultName(suggested: "My file.PDF", source: .file, date: date) == "My file.PDF")
        for source in [DropSource.photo, .camera] {
            #expect(DropNames.defaultName(suggested: "IMG_0001.heic", source: source, date: date,
                                          timeZone: berlin.timeZone) == "2026-11-01 19-03-04.heic")
        }
        #expect(DropNames.defaultName(suggested: "shot.jpg", source: .photo, date: date,
                                      timeZone: TimeZone(secondsFromGMT: 0)!) == "2026-11-01 18-03-04.jpg")
    }

    @Test func duplicatesGetSuffixBeforeTheLastExtension() {
        #expect(DropNames.unique(["a.pdf", "a.pdf", "a.pdf", "a (2).pdf"]) == ["a.pdf", "a (2).pdf", "a (3).pdf", "a (2) (2).pdf"])
        #expect(DropNames.unique(["notes", "notes", "archive.tar.gz", "archive.tar.gz"]) == ["notes", "notes (2)", "archive.tar.gz", "archive.tar (2).gz"])
        #expect(DropNames.unique(["é.jpg", "e\u{301}.jpg"]) == ["é.jpg", "é (2).jpg"])
    }
}
