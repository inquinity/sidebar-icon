import Foundation
import Testing
@testable import SidebarIconCore

/// 004 T013: system glyphs through the manager.
@Suite struct SystemGlyphTests {
    private func manager(_ fixture: ManagerFixture, valid: Set<String> = ["hammer", "doc"]) async throws -> MappingManager {
        let manager = MappingManager(container: fixture.container, system: fixture.system, restartFinder: {},
                                     isValidSystemSymbol: { valid.contains($0) })
        try await manager.load()
        return manager
    }

    @Test func addsAFolderWithASystemGlyph() async throws {
        let fixture = try ManagerFixture()
        let manager = try await manager(fixture)

        let result = try await manager.add(folder: URL(fileURLWithPath: fixture.dev), style: .systemSymbol(name: "hammer"))

        #expect(result.rows.map(\.state) == [.applied])
        #expect(result.rows[0].style == .systemSymbol(name: "hammer"))
        let info = try String(contentsOf: try currentRegistryBundle(fixture.container).appending(path: "Contents/Info.plist"), encoding: .utf8)
        #expect(info.contains("<string>hammer</string>"))
        #expect(info.contains("icon.s001.sf.hammer"))
    }

    @Test func unknownSymbolSavesNothing() async throws {
        let fixture = try ManagerFixture()
        let manager = try await manager(fixture)
        await #expect(throws: ManagerError.unknownSymbol("not.a.symbol")) {
            try await manager.add(folder: URL(fileURLWithPath: fixture.dev), style: .systemSymbol(name: "not.a.symbol"))
        }
        #expect(try ConfigStore(container: fixture.container).load().mappings.isEmpty)
        #expect(fixture.system.calls.isEmpty)
    }

    @Test func styleChangeKeepsTheCode() async throws {
        let fixture = try ManagerFixture()
        let manager = try await manager(fixture)
        let row = try await manager.add(folder: URL(fileURLWithPath: fixture.dev), image: fixture.png).rows[0]
        let firstBundle = try currentRegistryBundle(fixture.container)

        let result = try await manager.setStyle(.systemSymbol(name: "doc"), for: row.id)

        #expect(result.rows[0].osType == row.osType)
        #expect(result.rows[0].style == .systemSymbol(name: "doc"))
        #expect(result.rows[0].state == .applied)
        #expect(try currentRegistryBundle(fixture.container) != firstBundle)
        // The full-colour image is no longer referenced, so its files are gone.
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.container.iconsDirectory.path).isEmpty)
    }

    @Test func realValidatorKnowsCommonSymbols() {
        #expect(MappingManager.systemSymbolExists("hammer"))
        #expect(MappingManager.systemSymbolExists("folder"))
        #expect(!MappingManager.systemSymbolExists("definitely.not.a.symbol.name"))
        #expect(!MappingManager.systemSymbolExists(""))
    }
}
