import Foundation
import Testing
@testable import SidebarIconCore

/// 004 T027: importing, versioning and deleting custom glyphs through the manager.
@Suite struct ImportGlyphTests {
    private func manager(_ setup: ManagerFixture, _ fake: FakeActool) async throws -> MappingManager {
        let manager = MappingManager(container: setup.container, system: setup.system, restartFinder: {},
                                     isValidSystemSymbol: { $0 == "hammer" }, glyphTool: fake.runner())
        try await manager.load()
        return manager
    }

    private func info(_ setup: ManagerFixture) throws -> String {
        try String(contentsOf: try currentRegistryBundle(setup.container).appending(path: "Contents/Info.plist"), encoding: .utf8)
    }

    private var car: (ManagerFixture) -> URL { { $0.container.glyphsDirectory.appending(path: "Assets.car") } }

    @Test func importCopiesBuildsAndSaves() async throws {
        let setup = try ManagerFixture()
        let fake = FakeActool()
        let manager = try await manager(setup, fake)

        _ = try await manager.importGlyph(name: "git-repo", template: try fixture("template-regular-m.svg"))

        let glyph = try #require(await manager.glyphs().first)
        #expect(glyph.name == "git-repo")
        #expect(FileManager.default.fileExists(atPath: setup.container.glyphsDirectory.appending(path: glyph.templateFileName).path))
        #expect(try String(contentsOf: car(setup), encoding: .utf8) == "car:\(glyph.symbolName).symbolset")
        #expect(try String(contentsOf: setup.container.glyphsDirectory.appending(path: "Assets.key"), encoding: .utf8)
            == glyph.versionID.uuidString.lowercased() + "\n")
        #expect(try ConfigStore(container: setup.container).load().glyphs == [glyph])
        // The build folder is gone.
        #expect(try FileManager.default.contentsOfDirectory(atPath: setup.container.buildDirectory.path).isEmpty)
    }

    @Test func mappingWithTheGlyphGetsItsSymbolAndTheCar() async throws {
        let setup = try ManagerFixture()
        let manager = try await manager(setup, FakeActool())
        _ = try await manager.importGlyph(name: "git", template: try fixture("template-regular-m.svg"))
        let glyph = try #require(await manager.glyphs().first)

        let result = try await manager.add(folder: URL(fileURLWithPath: setup.dev), style: .customGlyph(glyphID: glyph.id))

        #expect(result.rows.map(\.state) == [.applied])
        #expect(try info(setup).contains("<string>\(glyph.symbolName)</string>"))
        let bundleCar = try currentRegistryBundle(setup.container).appending(path: "Contents/Resources/Assets.car")
        #expect(try Data(contentsOf: bundleCar) == Data(contentsOf: car(setup)))
    }

    @Test func reimportMakesANewVersionAndRegistry() async throws {
        let setup = try ManagerFixture()
        let manager = try await manager(setup, FakeActool())
        _ = try await manager.importGlyph(name: "git", template: try fixture("template-regular-m.svg"))
        let first = try #require(await manager.glyphs().first)
        _ = try await manager.add(folder: URL(fileURLWithPath: setup.dev), style: .customGlyph(glyphID: first.id))
        let firstBundle = try currentRegistryBundle(setup.container)

        _ = try await manager.importGlyph(name: "git", template: try fixture("template-regular-m.svg"))

        let second = try #require(await manager.glyphs().first)
        #expect(await manager.glyphs().count == 1)
        #expect(second.id == first.id && second.versionID != first.versionID)
        #expect(try currentRegistryBundle(setup.container) != firstBundle)
        #expect(try info(setup).contains(second.symbolName))
        #expect(!FileManager.default.fileExists(atPath: setup.container.glyphsDirectory.appending(path: first.templateFileName).path))
        #expect(try registryBundlesOnDisk(setup.container).count == 1)
    }

    @Test func failingBuildSavesNothing() async throws {
        let setup = try ManagerFixture()
        let fake = FakeActool()
        fake.state.withLock { $0.compileError = try? Data(contentsOf: try fixture("actool-err.plist")) }
        let manager = try await manager(setup, fake)

        await #expect(throws: ManagerError.self) {
            try await manager.importGlyph(name: "git", template: try fixture("template-regular-m.svg"))
        }

        #expect(await manager.glyphs().isEmpty)
        #expect(try ConfigStore(container: setup.container).load().glyphs.isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: setup.container.glyphsDirectory.path).isEmpty)
        #expect(setup.system.calls.isEmpty)
    }

    @Test func refusals() async throws {
        let setup = try ManagerFixture()
        let fake = FakeActool()
        let manager = try await manager(setup, fake)
        await #expect(throws: ManagerError.invalidGlyphName("Git Repo")) {
            try await manager.importGlyph(name: "Git Repo", template: try fixture("template-regular-m.svg"))
        }
        await #expect(throws: ManagerError.glyphBuild(.missingRequiredGlyph("template-s-only.svg"))) {
            try await manager.importGlyph(name: "git", template: try fixture("template-s-only.svg"))
        }
        fake.state.withLock { $0.findOutput = ProcessOutput(exitCode: 72) }
        await #expect(throws: ManagerError.glyphBuild(.toolUnavailable(GlyphBuildError.needsXcode))) {
            try await manager.importGlyph(name: "git", template: try fixture("template-regular-m.svg"))
        }
        #expect(fake.compileCount == 0)
        #expect(await manager.glyphs().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: setup.container.configURL.path))
    }

    @Test func unchangedGlyphsReuseTheCarWithoutTheTool() async throws {
        let setup = try ManagerFixture()
        let fake = FakeActool()
        let manager = try await manager(setup, fake)
        _ = try await manager.importGlyph(name: "git", template: try fixture("template-regular-m.svg"))
        let glyph = try #require(await manager.glyphs().first)
        _ = try await manager.add(folder: URL(fileURLWithPath: setup.dev), style: .customGlyph(glyphID: glyph.id))
        let compiles = fake.compileCount
        fake.state.withLock { $0.findOutput = ProcessOutput(exitCode: 72) }

        let result = try await manager.applyNow()

        #expect(result.rows.map(\.state) == [.applied])
        #expect(fake.compileCount == compiles)
    }

    @Test func deleteSwitchesMappingsToTheReplacement() async throws {
        let setup = try ManagerFixture()
        let manager = try await manager(setup, FakeActool())
        _ = try await manager.importGlyph(name: "git", template: try fixture("template-regular-m.svg"))
        let glyph = try #require(await manager.glyphs().first)
        let row = try await manager.add(folder: URL(fileURLWithPath: setup.dev), style: .customGlyph(glyphID: glyph.id)).rows[0]

        await #expect(throws: ManagerError.glyphInUse("git")) { try await manager.deleteGlyph(glyph.id) }

        let result = try await manager.deleteGlyph(glyph.id, replacement: .systemSymbol(name: "hammer"))

        #expect(result.rows[0].style == .systemSymbol(name: "hammer"))
        #expect(result.rows[0].osType == row.osType)
        #expect(await manager.glyphs().isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: setup.container.glyphsDirectory.path).isEmpty)
        #expect(try !info(setup).contains(glyph.symbolName))
    }

    @Test func resetAllRemovesGlyphsAndBuild() async throws {
        let setup = try ManagerFixture()
        let manager = try await manager(setup, FakeActool())
        _ = try await manager.importGlyph(name: "git", template: try fixture("template-regular-m.svg"))
        let glyph = try #require(await manager.glyphs().first)
        _ = try await manager.add(folder: URL(fileURLWithPath: setup.dev), style: .customGlyph(glyphID: glyph.id))

        _ = try await manager.resetAll()

        #expect(!FileManager.default.fileExists(atPath: setup.container.glyphsDirectory.path))
        #expect(!FileManager.default.fileExists(atPath: setup.container.buildDirectory.path))
        #expect(try registryBundlesOnDisk(setup.container).isEmpty)
        #expect(await manager.glyphs().isEmpty)
    }

    /// Review question 2: a 0.2.0 configuration and ledger, reset from 0.3.0.
    @Test func resetAllUndoesAZeroTwoSetup() async throws {
        let setup = try ManagerFixture()
        try FileManager.default.createDirectory(at: setup.container.root, withIntermediateDirectories: true)
        try Data(#"{"schemaVersion": 1, "mappings": [], "assets": []}"#.utf8).write(to: setup.container.configURL)
        let legacy = setup.container.registryBundleURL
        try FileManager.default.createDirectory(at: legacy.appending(path: "Contents"), withIntermediateDirectories: true)
        let ledger = LedgerStore(url: setup.container.ledgerURL)
        try ledger.record(OutsideChange(kind: .iconRegistration, target: legacy.path)) {}
        try ledger.record(OutsideChange(kind: .sidebarOverride, target: setup.dev, osType: "S001")) {}
        let manager = MappingManager(container: setup.container, system: setup.system, restartFinder: {})
        try? await manager.load()
        #expect(await manager.readOnlyReason?.contains("0.2.0") == true)

        let result = try await manager.resetAll()

        #expect(result.messages.first?.hasPrefix("Removed") == true)
        #expect(!FileManager.default.fileExists(atPath: legacy.path))
        #expect(!FileManager.default.fileExists(atPath: setup.container.configURL.path))
        #expect(try LedgerStore(url: setup.container.ledgerURL).entries().isEmpty)
        #expect(await manager.readOnlyReason == nil)
    }

    // Review M2 and test gaps.

    @Test func failedSaveLeavesTheInstalledCarAlone() async throws {
        let setup = try ManagerFixture()
        let manager = try await manager(setup, FakeActool())
        _ = try await manager.importGlyph(name: "git", template: try fixture("template-regular-m.svg"))
        let key = setup.container.glyphsDirectory.appending(path: "Assets.key")
        let keyBefore = try Data(contentsOf: key)
        let carBefore = try Data(contentsOf: car(setup))
        // config.json can't be replaced while the container folder is read-only.
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: setup.container.root.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: setup.container.root.path) }

        await #expect(throws: ManagerError.self) {
            try await manager.importGlyph(name: "git", template: try fixture("template-regular-m.svg"))
        }

        #expect(try Data(contentsOf: key) == keyBefore)
        #expect(try Data(contentsOf: car(setup)) == carBefore)
        #expect(await manager.glyphs().count == 1)
        #expect(try FileManager.default.contentsOfDirectory(atPath: setup.container.glyphsDirectory.path).count == 3)
    }

    @Test func deletingTheLastUnusedGlyphRemovesTheCar() async throws {
        let setup = try ManagerFixture()
        let manager = try await manager(setup, FakeActool())
        _ = try await manager.importGlyph(name: "git", template: try fixture("template-regular-m.svg"))
        let glyph = try #require(await manager.glyphs().first)
        _ = try await manager.deleteGlyph(glyph.id)
        #expect(try FileManager.default.contentsOfDirectory(atPath: setup.container.glyphsDirectory.path).isEmpty)
        await #expect(throws: ManagerError.unknownGlyph) { try await manager.deleteGlyph(glyph.id) }
    }

    @Test func linkedBuildFolderIsRefused() async throws {
        let setup = try ManagerFixture()
        let manager = try await manager(setup, FakeActool())
        let elsewhere = setup.dir.url.appending(path: "elsewhere")
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: setup.container.root, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: setup.container.buildDirectory, withDestinationURL: elsewhere)

        await #expect(throws: ManagerError.self) {
            try await manager.importGlyph(name: "git", template: try fixture("template-regular-m.svg"))
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: elsewhere.path).isEmpty)
        #expect(await manager.glyphs().isEmpty)
    }
}
