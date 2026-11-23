import Foundation
import Synchronization
import Testing
@testable import SidebarIconCore

@Suite struct MappingManagerResetTests {
    private func twoMappings(_ fixture: ManagerFixture) async throws -> MappingManager {
        let manager = try await fixture.manager()
        _ = try await manager.add(folder: URL(fileURLWithPath: fixture.dev), image: fixture.png)
        _ = try await manager.add(folder: URL(fileURLWithPath: fixture.docs), image: fixture.png)
        return manager
    }

    @Test func resetUndoesEverythingAndEmptiesTheList() async throws {
        let fixture = try ManagerFixture()
        let manager = try await twoMappings(fixture)

        let result = try await manager.resetAll()

        #expect(result.rows.isEmpty)
        #expect(fixture.system.state.withLock { $0.favorites.allSatisfy { $0.overrideIcon == nil } })
        #expect(fixture.system.state.withLock { $0.registered.isEmpty })
        #expect(try LedgerStore(url: fixture.container.ledgerURL).entries().isEmpty)
        #expect(try registryBundlesOnDisk(fixture.container).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: fixture.container.configURL.path))
        #expect(!FileManager.default.fileExists(atPath: fixture.container.iconsDirectory.path))
        #expect(try ConfigStore(container: fixture.container).load() == AppConfiguration())
        #expect(await manager.rows().isEmpty)
    }

    @Test func partialFailureKeepsTheMappingsStillRecorded() async throws {
        let fixture = try ManagerFixture()
        let manager = try await twoMappings(fixture)
        fixture.system.state.withLock { $0.failClearing = ["S002"] }

        let result = try await manager.resetAll()

        #expect(result.rows.map(\.folderPath) == [fixture.docs])
        #expect(result.messages.contains { $0.contains("Reset All again") })
        let config = try ConfigStore(container: fixture.container).load()
        #expect(config.mappings.map(\.osType) == ["S002"])
        #expect(config.assets.count == 1)
        // The registration stays while an override still points at it.
        #expect(fixture.system.state.withLock { !$0.registered.isEmpty })
        let iconFiles = try FileManager.default.contentsOfDirectory(atPath: fixture.container.iconsDirectory.path)
        #expect(Set(iconFiles) == Set([config.assets[0].fileName, config.assets[0].icnsFileName!]))

        fixture.system.state.withLock { $0.failClearing = [] }
        #expect(try await manager.resetAll().rows.isEmpty)
    }

    @Test func resetWithNothingMakesNoCalls() async throws {
        let fixture = try ManagerFixture()
        let manager = try await fixture.manager()

        let result = try await manager.resetAll()

        #expect(result.rows.isEmpty)
        #expect(fixture.system.calls.isEmpty)
        #expect(try await manager.resetAll().rows.isEmpty)
    }

    @Test func resetWorksWithAnUnreadableConfig() async throws {
        let fixture = try ManagerFixture()
        _ = try await twoMappings(fixture)
        try Data(#"{"schemaVersion": 9}"#.utf8).write(to: fixture.container.configURL)
        let manager = MappingManager(container: fixture.container, system: fixture.system, restartFinder: {})
        await #expect(throws: ManagerError.self) { try await manager.load() }

        let result = try await manager.resetAll()

        #expect(result.rows.isEmpty)
        #expect(await manager.readOnlyReason == nil)
        #expect(fixture.system.state.withLock { $0.favorites.allSatisfy { $0.overrideIcon == nil } })
        #expect(try ConfigStore(container: fixture.container).load() == AppConfiguration())
        _ = try await manager.add(folder: URL(fileURLWithPath: fixture.dev), image: fixture.png)
    }

    @Test func resetWorksWhenFavoritesAreUnreadable() async throws {
        let fixture = try ManagerFixture()
        let manager = try await fixture.manager()
        fixture.system.state.withLock { $0.favoritesUnavailable = true }
        #expect(try await manager.resetAll().rows.isEmpty)
    }

    @Test func refreshAppliesThenRestartsFinder() async throws {
        let fixture = try ManagerFixture { dev, _ in [dev] }
        let restarts = Mutex(0)
        let manager = MappingManager(container: fixture.container, system: fixture.system) {
            restarts.withLock { $0 += 1 }
        }
        try await manager.load()
        _ = try await manager.add(folder: URL(fileURLWithPath: fixture.docs), image: fixture.png)
        fixture.system.state.withLock {
            $0.favorites.append(FavoriteItem(displayName: "DevDocs", path: fixture.docs, overrideIcon: nil))
        }

        let result = try await manager.refreshFinder()

        #expect(restarts.withLock { $0 } == 1)
        #expect(result.rows.map(\.state) == [.applied])
        #expect(result.messages.last == "Finder restarted.")
    }

    @Test func failedRestartIsReportedNotThrown() async throws {
        let fixture = try ManagerFixture()
        let manager = MappingManager(container: fixture.container, system: fixture.system) { throw TestError() }
        try await manager.load()
        let result = try await manager.refreshFinder()
        #expect(result.messages.contains { $0.hasPrefix("Finder could not be restarted") })
    }
}
