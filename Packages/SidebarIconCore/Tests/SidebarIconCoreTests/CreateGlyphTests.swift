import Foundation
import Testing
@testable import SidebarIconCore

/// 004 T031: the wizard's path, a plain SVG drawing in and a glyph out.
@Suite struct CreateGlyphTests {
    private func manager(_ setup: ManagerFixture, _ fake: FakeActool = FakeActool()) async throws -> MappingManager {
        let manager = MappingManager(container: setup.container, system: setup.system, restartFinder: {},
                                     isValidSystemSymbol: { $0 == "folder" }, glyphTool: fake.runner())
        try await manager.load()
        return manager
    }

    private func glyphFile(_ setup: ManagerFixture, _ name: String) -> URL {
        setup.container.glyphsDirectory.appending(path: name)
    }

    private func info(_ setup: ManagerFixture) throws -> String {
        try String(contentsOf: try currentRegistryBundle(setup.container).appending(path: "Contents/Info.plist"), encoding: .utf8)
    }

    @Test func createKeepsTheSourceAndTheGeneratedTemplate() async throws {
        let setup = try ManagerFixture()
        let manager = try await manager(setup)
        let svg = try fixture("layers-filled.svg")

        _ = try await manager.createGlyph(name: "layers", svg: svg)

        let glyph = try #require(await manager.glyphs().first)
        let version = glyph.versionID.uuidString.lowercased()
        #expect(glyph.name == "layers")
        #expect(glyph.sourceFileName == "\(version).svg")
        #expect(try Data(contentsOf: glyphFile(setup, "\(version).svg")) == Data(contentsOf: svg))
        // The template is what make-symbol-template would write for the same drawing.
        let expected = SymbolTemplateWriter.template(for: try SVGShapeReader.read(contentsOf: svg))
        #expect(try String(contentsOf: glyphFile(setup, glyph.templateFileName), encoding: .utf8) == expected)
        #expect(try String(contentsOf: glyphFile(setup, "Assets.car"), encoding: .utf8) == "car:\(glyph.symbolName).symbolset")
        #expect(try ConfigStore(container: setup.container).load().glyphs == [glyph])
    }

    @Test(arguments: [
        ("stroked.svg", SVGReadError.strokeGuidance),
        ("text.svg", SVGReadError.textGuidance),
        ("transform.svg", SVGReadError.transformGuidance),
    ])
    func refusedDrawingsSaveNothing(file: String, guidance: String) async throws {
        let setup = try ManagerFixture()
        let fake = FakeActool()
        let manager = try await manager(setup, fake)

        do {
            _ = try await manager.createGlyph(name: "bad", svg: try fixture(file))
            Issue.record("\(file) was accepted")
        } catch ManagerError.drawingRefused(.unsupportedSVG(let detail)) {
            #expect(detail.contains(guidance))
        }

        #expect(await manager.glyphs().isEmpty)
        #expect(fake.compileCount == 0)
        let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: setup.container.glyphsDirectory.path)) ?? []
        #expect(leftovers.isEmpty)
    }

    @Test(arguments: ["empty.svg", "no-viewbox.svg"])
    func drawingsWithNothingToUseAreRefused(file: String) async throws {
        let setup = try ManagerFixture()
        let manager = try await manager(setup)

        await #expect(throws: ManagerError.self) { try await manager.createGlyph(name: "bad", svg: try fixture(file)) }
        #expect(await manager.glyphs().isEmpty)
    }

    @Test func aNameInUseIsRefused() async throws {
        let setup = try ManagerFixture()
        let manager = try await manager(setup)
        _ = try await manager.createGlyph(name: "layers", svg: try fixture("layers-filled.svg"))
        let first = try #require(await manager.glyphs().first)

        await #expect(throws: ManagerError.glyphNameTaken("layers")) {
            try await manager.createGlyph(name: "layers", svg: try fixture("shapes.svg"))
        }
        #expect(await manager.glyphs() == [first])
    }

    @Test func anInvalidNameIsRefusedBeforeReading() async throws {
        let setup = try ManagerFixture()
        let manager = try await manager(setup)

        await #expect(throws: ManagerError.invalidGlyphName("Layers!")) {
            try await manager.createGlyph(name: "Layers!", svg: try fixture("stroked.svg"))
        }
    }

    @Test func aFailedBuildSavesNothing() async throws {
        let setup = try ManagerFixture()
        let fake = FakeActool()
        fake.state.withLock { $0.compileError = try? Data(contentsOf: try fixture("actool-err.plist")) }
        let manager = try await manager(setup, fake)

        await #expect(throws: ManagerError.self) {
            try await manager.createGlyph(name: "layers", svg: try fixture("layers-filled.svg"))
        }
        #expect(await manager.glyphs().isEmpty)
        let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: setup.container.glyphsDirectory.path)) ?? []
        #expect(leftovers.isEmpty)
    }

    @Test func updateMakesANewVersionAndSwitchesItsFolders() async throws {
        let setup = try ManagerFixture()
        let manager = try await manager(setup)
        _ = try await manager.createGlyph(name: "layers", svg: try fixture("layers-filled.svg"))
        let first = try #require(await manager.glyphs().first)
        _ = try await manager.add(folder: URL(fileURLWithPath: setup.dev), style: .customGlyph(glyphID: first.id))
        #expect(try info(setup).contains(first.symbolName))

        let result = try await manager.updateGlyph(first.id, svg: try fixture("shapes.svg"))

        let second = try #require(await manager.glyphs().first)
        #expect(await manager.glyphs().count == 1)
        #expect(second.id == first.id && second.name == "layers" && second.versionID != first.versionID)
        #expect(result.rows.map(\.state) == [.applied])
        #expect(try info(setup).contains(second.symbolName))
        #expect(try !info(setup).contains(first.symbolName))
        // The old version's files are gone; the new source is kept.
        #expect(!FileManager.default.fileExists(atPath: glyphFile(setup, first.templateFileName).path))
        #expect(!FileManager.default.fileExists(atPath: glyphFile(setup, try #require(first.sourceFileName)).path))
        #expect(try Data(contentsOf: glyphFile(setup, try #require(second.sourceFileName))) == Data(contentsOf: try fixture("shapes.svg")))
    }

    @Test func updateOfAMissingGlyphIsRefused() async throws {
        let setup = try ManagerFixture()
        let manager = try await manager(setup)

        await #expect(throws: ManagerError.unknownGlyph) {
            try await manager.updateGlyph(UUID(), svg: try fixture("layers-filled.svg"))
        }
    }

    @Test func aRefusedUpdateKeepsTheCurrentVersion() async throws {
        let setup = try ManagerFixture()
        let manager = try await manager(setup)
        _ = try await manager.createGlyph(name: "layers", svg: try fixture("layers-filled.svg"))
        let first = try #require(await manager.glyphs().first)

        await #expect(throws: ManagerError.self) { try await manager.updateGlyph(first.id, svg: try fixture("stroked.svg")) }

        #expect(await manager.glyphs() == [first])
        #expect(FileManager.default.fileExists(atPath: glyphFile(setup, first.templateFileName).path))
    }

    @Test func anImportedTemplateReplacesTheWizardSource() async throws {
        let setup = try ManagerFixture()
        let manager = try await manager(setup)
        _ = try await manager.createGlyph(name: "layers", svg: try fixture("layers-filled.svg"))
        let first = try #require(await manager.glyphs().first)

        _ = try await manager.importGlyph(name: "layers", template: try fixture("template-regular-m.svg"))

        let second = try #require(await manager.glyphs().first)
        #expect(second.sourceFileName == nil)
        #expect(!FileManager.default.fileExists(atPath: glyphFile(setup, try #require(first.sourceFileName)).path))
    }

    // MARK: - Failure paths (review of Story 3)

    /// The car, its key and the existing glyph's files, to compare before and after a failure.
    private func snapshot(_ setup: ManagerFixture) throws -> [String: Data] {
        let folder = setup.container.glyphsDirectory
        var files: [String: Data] = [:]
        for name in try FileManager.default.contentsOfDirectory(atPath: folder.path) {
            files[name] = try Data(contentsOf: folder.appending(path: name))
        }
        return files
    }

    @Test func aFailedCreateLeavesTheExistingGlyphsAlone() async throws {
        let setup = try ManagerFixture()
        let fake = FakeActool()
        let manager = try await manager(setup, fake)
        _ = try await manager.createGlyph(name: "layers", svg: try fixture("layers-filled.svg"))
        let before = try snapshot(setup)
        fake.state.withLock { $0.compileError = try? Data(contentsOf: try fixture("actool-err.plist")) }

        await #expect(throws: ManagerError.self) { try await manager.createGlyph(name: "shapes", svg: try fixture("shapes.svg")) }

        #expect(try snapshot(setup) == before)
        #expect(await manager.glyphs().map(\.name) == ["layers"])
    }

    @Test func aFailedUpdateBuildKeepsTheCurrentVersion() async throws {
        let setup = try ManagerFixture()
        let fake = FakeActool()
        let manager = try await manager(setup, fake)
        _ = try await manager.createGlyph(name: "layers", svg: try fixture("layers-filled.svg"))
        let first = try #require(await manager.glyphs().first)
        let before = try snapshot(setup)
        fake.state.withLock { $0.compileError = try? Data(contentsOf: try fixture("actool-err.plist")) }

        await #expect(throws: ManagerError.self) { try await manager.updateGlyph(first.id, svg: try fixture("shapes.svg")) }

        #expect(try snapshot(setup) == before)
        #expect(await manager.glyphs() == [first])
    }

    @Test func aFailedSaveLeavesTheInstalledCarAlone() async throws {
        let setup = try ManagerFixture()
        let manager = try await manager(setup)
        _ = try await manager.createGlyph(name: "layers", svg: try fixture("layers-filled.svg"))
        let before = try snapshot(setup)
        // config.json can't be replaced while the container folder is read-only.
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: setup.container.root.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: setup.container.root.path) }

        await #expect(throws: ManagerError.self) { try await manager.createGlyph(name: "shapes", svg: try fixture("shapes.svg")) }

        #expect(try snapshot(setup) == before)
        #expect(await manager.glyphs().count == 1)
    }

    @Test func withoutTheToolAGoodDrawingIsRefusedAndABadOneIsExplained() async throws {
        let setup = try ManagerFixture()
        let fake = FakeActool()
        fake.state.withLock { $0.findOutput = ProcessOutput(exitCode: 72) }
        let manager = try await manager(setup, fake)

        do {
            _ = try await manager.createGlyph(name: "layers", svg: try fixture("layers-filled.svg"))
            Issue.record("built without the tool")
        } catch ManagerError.glyphBuild(.toolUnavailable) {}
        // The drawing is checked first, so its problem is explained even without Xcode.
        do {
            _ = try await manager.createGlyph(name: "bad", svg: try fixture("stroked.svg"))
            Issue.record("a stroked drawing was accepted")
        } catch ManagerError.drawingRefused(.unsupportedSVG) {}
        #expect(await manager.glyphs().isEmpty)
    }

    @Test func anOversizedDrawingIsRefusedWithoutLoadingIt() async throws {
        let setup = try ManagerFixture()
        let manager = try await manager(setup)
        let big = setup.container.root.deletingLastPathComponent().appending(path: "big.svg")
        try Data(count: SVGShapeReader.maximumFileSize + 10).write(to: big)

        await #expect(throws: ManagerError.drawingRefused(.tooLarge)) { try await manager.createGlyph(name: "big", svg: big) }
    }

    @Test func aMissingOrSpecialFileIsUnreadable() async throws {
        let setup = try ManagerFixture()
        let manager = try await manager(setup)
        let missing = setup.container.root.deletingLastPathComponent().appending(path: "missing.svg")

        for url in [missing, URL(fileURLWithPath: "/dev/zero")] {
            do {
                _ = try await manager.createGlyph(name: "nope", svg: url)
                Issue.record("\(url.path) was read")
            } catch ManagerError.drawingRefused(.unreadable) {}
        }
    }

    @Test func theDrawingBytesAreBuiltAsGiven() async throws {
        let setup = try ManagerFixture()
        let manager = try await manager(setup)
        let data = try Data(contentsOf: try fixture("layers-filled.svg"))

        _ = try await manager.createGlyph(name: "  layers  ", drawing: data)

        let glyph = try #require(await manager.glyphs().first)
        #expect(glyph.name == "layers")
        #expect(try Data(contentsOf: glyphFile(setup, try #require(glyph.sourceFileName))) == data)
    }

    @Test func aReadOnlyConfigurationRefusesCreate() async throws {
        let setup = try ManagerFixture()
        try FileManager.default.createDirectory(at: setup.container.root, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: setup.container.configURL)
        let manager = MappingManager(container: setup.container, system: setup.system, restartFinder: {},
                                     isValidSystemSymbol: { _ in true }, glyphTool: FakeActool().runner())
        try? await manager.load()

        await #expect(throws: ManagerError.readOnly) {
            try await manager.createGlyph(name: "layers", svg: try fixture("layers-filled.svg"))
        }
    }
}
