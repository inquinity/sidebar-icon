import Foundation
import Testing
@testable import SidebarIconCore

@Suite struct MappingManagerManageTests {
    /// `dev` (S001) and `docs` (S002), both applied.
    private func twoMappings(_ fixture: ManagerFixture) async throws -> (MappingManager, dev: MappingRow, docs: MappingRow) {
        let manager = try await fixture.manager()
        _ = try await manager.add(folder: URL(fileURLWithPath: fixture.dev), image: fixture.png)
        let rows = try await manager.add(folder: URL(fileURLWithPath: fixture.docs), image: fixture.png).rows
        return (manager, rows[0], rows[1])
    }

    private func override(_ fixture: ManagerFixture, _ path: String) -> String? {
        fixture.system.state.withLock { $0.favorites.first { $0.path == path }?.overrideIcon }
    }

    private func iconFiles(_ fixture: ManagerFixture) throws -> Set<String> {
        Set(try FileManager.default.contentsOfDirectory(atPath: fixture.container.iconsDirectory.path))
    }

    @Test func turningOffClearsOnlyThatOverrideAndKeepsTheMapping() async throws {
        let fixture = try ManagerFixture()
        let (manager, dev, _) = try await twoMappings(fixture)

        let result = try await manager.setEnabled(false, for: dev.id)

        #expect(override(fixture, fixture.dev) == nil)
        #expect(override(fixture, fixture.docs) == "S002")
        #expect(result.rows.map(\.state) == [.off, .applied])
        #expect(try ConfigStore(container: fixture.container).load().mappings.map(\.enabled) == [false, true])
    }

    @Test func turningOnRestoresTheIcon() async throws {
        let fixture = try ManagerFixture()
        let (manager, dev, _) = try await twoMappings(fixture)
        _ = try await manager.setEnabled(false, for: dev.id)

        let result = try await manager.setEnabled(true, for: dev.id)

        #expect(override(fixture, fixture.dev) == "S001")
        #expect(result.rows.map(\.state) == [.applied, .applied])
    }

    @Test func removeClearsTheOverrideAndDeletesOnlyThatAssetsFiles() async throws {
        let fixture = try ManagerFixture()
        let (manager, dev, _) = try await twoMappings(fixture)
        let before = try ConfigStore(container: fixture.container).load()
        let devAsset = try #require(before.assets.first { $0.id == before.mappings[0].iconAssetID })

        let result = try await manager.remove(dev.id)

        #expect(result.rows.map(\.folderPath) == [fixture.docs])
        #expect(override(fixture, fixture.dev) == nil)
        #expect(override(fixture, fixture.docs) == "S002")
        let files = try iconFiles(fixture)
        #expect(!files.contains(devAsset.fileName))
        #expect(!files.contains(devAsset.icnsFileName!))
        #expect(files.count == 2)
        #expect(FileManager.default.fileExists(atPath: fixture.dev))
    }

    @Test func removingTheLastEnabledMappingUnregistersTheBundle() async throws {
        let fixture = try ManagerFixture()
        let (manager, dev, docs) = try await twoMappings(fixture)
        _ = try await manager.setEnabled(false, for: docs.id)

        _ = try await manager.remove(dev.id)

        #expect(fixture.system.state.withLock { $0.registered.isEmpty })
        #expect(!FileManager.default.fileExists(atPath: fixture.container.registryBundleURL.path))
        #expect(try LedgerStore(url: fixture.container.ledgerURL).entries().isEmpty)
        // The disabled mapping is kept, and turning it on registers again.
        let result = try await manager.setEnabled(true, for: docs.id)
        #expect(result.rows.map(\.state) == [.applied])
    }

    @Test func changeIconKeepsTheCodeAndReplacesTheAsset() async throws {
        let fixture = try ManagerFixture()
        let (manager, dev, _) = try await twoMappings(fixture)
        let before = try ConfigStore(container: fixture.container).load()
        let oldAsset = try #require(before.assets.first { $0.id == before.mappings[0].iconAssetID })
        let newImage = try writeTestPNG(in: fixture.dir.url, name: "new.png", width: 64, height: 64)

        let result = try await manager.changeIcon(for: dev.id, image: newImage)

        let after = try ConfigStore(container: fixture.container).load()
        #expect(after.mappings[0].osType == "S001")
        #expect(after.mappings[0].iconAssetID != oldAsset.id)
        #expect(result.rows[0].state == .applied)
        #expect(result.needsRefresh)
        let files = try iconFiles(fixture)
        #expect(!files.contains(oldAsset.fileName))
        #expect(!files.contains(oldAsset.icnsFileName!))
        // The registry declares the new asset's type (a new type id, so Finder's cache is not stale).
        let plist = try String(contentsOf: fixture.container.registryBundleURL.appending(path: "Contents/Info.plist"), encoding: .utf8)
        #expect(plist.contains(after.mappings[0].iconAssetID.uuidString.lowercased()))
        #expect(!plist.contains(oldAsset.id.uuidString.lowercased()))
    }

    @Test func changeIconWithAnUnreadableImageChangesNothing() async throws {
        let fixture = try ManagerFixture()
        let (manager, dev, _) = try await twoMappings(fixture)
        let before = try fixture.snapshot()
        let bad = fixture.dir.url.appending(path: "bad.png")
        try Data("nope".utf8).write(to: bad)

        await #expect(throws: ManagerError.imageUnreadable("bad.png")) {
            try await manager.changeIcon(for: dev.id, image: bad)
        }
        #expect(try fixture.snapshot() == before)
    }

    @Test func eachMappingGetsItsOwnCopyOfTheSameImage() async throws {
        let fixture = try ManagerFixture()
        _ = try await twoMappings(fixture)
        let config = try ConfigStore(container: fixture.container).load()
        #expect(Set(config.mappings.map(\.iconAssetID)).count == 2)
        #expect(Set(config.assets.map(\.fileName)).count == 2)
    }

    @Test func repointMovesAMappingToAnotherFolder() async throws {
        let fixture = try ManagerFixture { dev, docs in [dev, docs] }
        let manager = try await fixture.manager()
        let row = try await manager.add(folder: URL(fileURLWithPath: fixture.docs), image: fixture.png).rows[0]

        let result = try await manager.repoint(row.id, to: URL(fileURLWithPath: fixture.dev))

        #expect(result.rows.map(\.folderPath) == [fixture.dev])
        #expect(result.rows[0].state == .applied)
        #expect(override(fixture, fixture.dev) == row.osType)
        // The old Favorite must not keep the override, and the ledger must match the sidebar.
        #expect(override(fixture, fixture.docs) == nil)
        let ledger = try LedgerStore(url: fixture.container.ledgerURL).entries().filter { $0.kind == .sidebarOverride }
        #expect(ledger.map(\.target) == [fixture.dev])
    }

    @Test func repointRefusesAFolderThatIsAlreadyMapped() async throws {
        let fixture = try ManagerFixture()
        let (manager, dev, docs) = try await twoMappings(fixture)
        await #expect(throws: ManagerError.duplicateFolder(existing: fixture.docs)) {
            try await manager.repoint(dev.id, to: URL(fileURLWithPath: fixture.docs + "/"))
        }
        // Re-pointing to its own folder is not a duplicate.
        _ = try await manager.repoint(docs.id, to: URL(fileURLWithPath: fixture.docs))
    }

    @Test func unknownMappingIsReported() async throws {
        let fixture = try ManagerFixture()
        let manager = try await fixture.manager()
        await #expect(throws: ManagerError.unknownMapping) { try await manager.remove(UUID()) }
        await #expect(throws: ManagerError.unknownMapping) { try await manager.setEnabled(false, for: UUID()) }
    }
}

/// Regression tests for the Story 2 review.
@Suite struct Story2ReviewFixTests {
    private func twoMappings(_ fixture: ManagerFixture) async throws -> (MappingManager, dev: MappingRow, docs: MappingRow) {
        let manager = try await fixture.manager()
        _ = try await manager.add(folder: URL(fileURLWithPath: fixture.dev), image: fixture.png)
        let rows = try await manager.add(folder: URL(fileURLWithPath: fixture.docs), image: fixture.png).rows
        return (manager, rows[0], rows[1])
    }

    private func override(_ fixture: ManagerFixture, _ path: String) -> String? {
        fixture.system.state.withLock { $0.favorites.first { $0.path == path }?.overrideIcon }
    }

    // #1: a registration failure must not stop Off or Remove from clearing.
    @Test func offAndRemoveClearEvenWhenRegistrationFails() async throws {
        let fixture = try ManagerFixture()
        let (manager, dev, docs) = try await twoMappings(fixture)
        fixture.system.state.withLock { $0.failClaims = true }

        let off = try await manager.setEnabled(false, for: dev.id)
        #expect(override(fixture, fixture.dev) == nil)
        #expect(off.rows.first { $0.id == dev.id }?.state == .off)

        _ = try await manager.remove(docs.id)
        #expect(override(fixture, fixture.docs) == nil)
        #expect(try LedgerStore(url: fixture.container.ledgerURL).entries().filter { $0.kind == .sidebarOverride }.isEmpty)
    }

    // #2: a failed clear keeps the code registered and the row says so.
    @Test func failedClearKeepsTheCodeRegisteredAndShowsAnError() async throws {
        let fixture = try ManagerFixture()
        let (manager, dev, _) = try await twoMappings(fixture)
        fixture.system.state.withLock { $0.failClearing = ["S001"] }

        let result = try await manager.setEnabled(false, for: dev.id)

        #expect(override(fixture, fixture.dev) == "S001")
        guard case .error = result.rows.first(where: { $0.id == dev.id })?.state else {
            Issue.record("expected an error row"); return
        }
        let plist = try String(contentsOf: fixture.container.registryBundleURL.appending(path: "Contents/Info.plist"), encoding: .utf8)
        #expect(plist.contains(">S001<"))

        fixture.system.state.withLock { $0.failClearing = [] }
        let retried = try await manager.setEnabled(false, for: dev.id)
        #expect(override(fixture, fixture.dev) == nil)
        #expect(retried.rows.first { $0.id == dev.id }?.state == .off)
    }

    // #4: once saved, an apply failure is a message, not an error.
    @Test func storyTwoActionsReportPostSaveFailuresAsMessages() async throws {
        let fixture = try ManagerFixture()
        let (manager, dev, _) = try await twoMappings(fixture)
        fixture.system.state.withLock { $0.favoritesUnavailable = true }

        let result = try await manager.remove(dev.id)

        #expect(result.messages.contains { $0.hasPrefix("Saved, but not applied") })
        #expect(try ConfigStore(container: fixture.container).load().mappings.count == 1)
    }

    // #5: the refresh hint follows the mapping whose icon changed.
    @Test func changeIconOnADisabledMappingDoesNotAskForARefresh() async throws {
        let fixture = try ManagerFixture()
        let (manager, dev, _) = try await twoMappings(fixture)
        _ = try await manager.setEnabled(false, for: dev.id)
        let image = try writeTestPNG(in: fixture.dir.url, name: "other.png", width: 40, height: 40)

        #expect(try await manager.changeIcon(for: dev.id, image: image).needsRefresh == false)
    }
}
