import Foundation
import Testing
@testable import SidebarIconCore

@Suite struct AssetImporterTests {
    let dir: TemporaryDirectory
    init() throws { dir = try TemporaryDirectory() }

    @Test func detectsFormatFromContentNotExtension() throws {
        let png = try writeTestPNG(in: dir.url, name: "really-a-png.pdf")
        #expect(try AssetImporter.detectFormat(of: png) == .png)
    }

    @Test(arguments: [
        ("%PDF-1.7\n", IconAsset.SourceFormat.pdf),
        ("icns\u{0}\u{0}\u{0}\u{8}", .icns),
        ("<?xml version=\"1.0\"?>\n<svg xmlns=\"http://www.w3.org/2000/svg\"/>", .svg),
        ("  <svg viewBox=\"0 0 1 1\"></svg>", .svg),
    ])
    func detectsOtherFormats(_ content: String, _ expected: IconAsset.SourceFormat) throws {
        #expect(try AssetImporter.detectFormat(ofContent: Data(content.utf8), name: "x") == expected)
    }

    @Test func rejectsUnsupportedContent() {
        #expect(throws: AssetImportError.unsupportedContent("x.png")) {
            try AssetImporter.detectFormat(ofContent: Data("GIF89a".utf8), name: "x.png")
        }
        #expect(throws: AssetImportError.unsupportedContent("x.svg")) {
            try AssetImporter.detectFormat(ofContent: Data("<?xml version=\"1.0\"?><html/>".utf8), name: "x.svg")
        }
    }

    @Test func copyLandsAtIconsUUIDExtension() throws {
        let source = try writeTestPNG(in: dir.url, name: "chosen.pdf")
        let icons = dir.url.appending(path: "Icons", directoryHint: .isDirectory)
        let asset = try AssetImporter.importFile(at: source, into: icons)
        #expect(asset.sourceFormat == .png)
        #expect(asset.fileName == "\(asset.id.uuidString).png")
        let copy = icons.appending(path: asset.fileName)
        #expect(try Data(contentsOf: copy) == Data(contentsOf: source))
    }

    @Test func originalIsUntouched() throws {
        let source = try writeTestPNG(in: dir.url, name: "original.png")
        let before = try Data(contentsOf: source)
        let attributesBefore = try FileManager.default.attributesOfItem(atPath: source.path)
        _ = try AssetImporter.importFile(at: source, into: dir.url.appending(path: "Icons", directoryHint: .isDirectory))
        #expect(try Data(contentsOf: source) == before)
        let attributesAfter = try FileManager.default.attributesOfItem(atPath: source.path)
        #expect(attributesAfter[.modificationDate] as? Date == attributesBefore[.modificationDate] as? Date)
    }

    @Test func copySurvivesDeletingTheOriginal() throws {
        let source = try writeTestPNG(in: dir.url, name: "desktop-copy.png")
        let icons = dir.url.appending(path: "Icons", directoryHint: .isDirectory)
        let asset = try AssetImporter.importFile(at: source, into: icons)
        try FileManager.default.removeItem(at: source)
        #expect(FileManager.default.fileExists(atPath: icons.appending(path: asset.fileName).path))
    }
}
