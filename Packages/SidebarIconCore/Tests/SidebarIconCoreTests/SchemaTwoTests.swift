import Foundation
import Testing
@testable import SidebarIconCore

/// 004 T004: schema 2, no migration from 0.2.0.
@Suite struct SchemaTwoTests {
    private func store() throws -> (TemporaryDirectory, ContainerLocator, ConfigStore) {
        let dir = try TemporaryDirectory()
        let container = ContainerLocator(root: dir.url.appending(path: "Container", directoryHint: .isDirectory))
        try FileManager.default.createDirectory(at: container.root, withIntermediateDirectories: true)
        return (dir, container, ConfigStore(container: container))
    }

    @Test func stylesRoundTrip() throws {
        for style in [SidebarStyle.systemSymbol(name: "hammer"), .customGlyph(glyphID: UUID()), .fullColour(assetID: UUID())] {
            let data = try JSONEncoder().encode(style)
            #expect(try JSONDecoder().decode(SidebarStyle.self, from: data) == style)
        }
    }

    @Test func problemsCoverStylesAndGlyphNames() {
        let path = "/Users/x/dev"
        let missingAsset = AppConfiguration(mappings: [SidebarMapping(folderPath: path, iconAssetID: UUID(), osType: "S001")])
        #expect(missingAsset.problems.contains { $0.contains("missing icon") })
        let missingGlyph = AppConfiguration(mappings: [SidebarMapping(folderPath: path, sidebarStyle: .customGlyph(glyphID: UUID()), osType: "S001")])
        #expect(missingGlyph.problems.contains { $0.contains("missing glyph") })
        let badName = AppConfiguration(glyphs: [CustomGlyph(name: "Git Repo")])
        #expect(badName.problems.contains { $0.contains("not valid") })
        let duplicate = AppConfiguration(glyphs: [CustomGlyph(name: "git"), CustomGlyph(name: "git")])
        #expect(duplicate.problems.contains { $0.contains("used twice") })
        #expect(AppConfiguration(mappings: [SidebarMapping(folderPath: path, sidebarStyle: .systemSymbol(name: "hammer"), osType: "S001")]).problems.isEmpty)
    }

    @Test func glyphNameRules() {
        for good in ["git", "git-repo", "dev.folder", "a1"] { #expect(CustomGlyph.isValidName(good)) }
        for bad in ["", "Git", "-git", ".git", "git repo", "gït", String(repeating: "a", count: 49)] { #expect(!CustomGlyph.isValidName(bad)) }
    }

    @Test func schemaOneIsRefusedAndLeftAlone() throws {
        let (dir, container, store) = try store()
        _ = dir  // keep the temporary directory alive
        let original = #"{"schemaVersion": 1, "mappings": [], "assets": []}"#
        try Data(original.utf8).write(to: container.configURL)
        do {
            _ = try store.load()
            Issue.record("schema 1 must not load")
        } catch let ManagerError.configUnreadable(message) {
            #expect(message.contains("made by Sidebar Icons 0.2.0"))
        }
        #expect(try String(contentsOf: container.configURL, encoding: .utf8) == original)
        #expect(throws: ManagerError.self) { try store.save(AppConfiguration()) }
    }

    @Test func schemaTwoRoundTripsAndPrunesGlyphFiles() throws {
        let (dir, container, store) = try store()
        let glyph = CustomGlyph(name: "git", sourceFileName: "src.svg")
        try FileManager.default.createDirectory(at: container.glyphsDirectory, withIntermediateDirectories: true)
        for name in [glyph.templateFileName, "src.svg"] {
            try Data("svg".utf8).write(to: container.glyphsDirectory.appending(path: name))
        }
        let mapping = SidebarMapping(folderPath: PathStandardizer.standardize(dir.url.path), sidebarStyle: .customGlyph(glyphID: glyph.id), osType: "S001")
        let config = AppConfiguration(mappings: [mapping], glyphs: [glyph])
        try store.save(config)
        #expect(try store.load() == config)

        try store.save(AppConfiguration())
        #expect(try FileManager.default.contentsOfDirectory(atPath: container.glyphsDirectory.path).isEmpty)
    }
}
