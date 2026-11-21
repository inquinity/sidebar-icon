import Foundation
import Testing
@testable import SidebarIconCore

@Suite struct MappingManagerAddTests {
    @Test func addSavesAppliesAndReportsApplied() async throws {
        let fixture = try ManagerFixture()
        let manager = try await fixture.manager()

        let result = try await manager.add(folder: URL(fileURLWithPath: fixture.dev), image: fixture.png)

        #expect(result.rows.count == 1)
        #expect(result.rows[0].folderPath == fixture.dev)
        #expect(result.rows[0].state == .applied)
        #expect(result.needsRefresh)
        #expect(fixture.system.state.withLock { $0.favorites.first { $0.path == fixture.dev }?.overrideIcon } == "S001")
        let config = try ConfigStore(container: fixture.container).load()
        #expect(config.mappings.map(\.osType) == ["S001"])
        let asset = try #require(config.assets.first)
        #expect(asset.sourceFormat == .png)
        #expect(asset.icnsFileName == "\(asset.id.uuidString).icns")
        #expect(FileManager.default.fileExists(atPath: fixture.container.iconsDirectory.appending(path: asset.fileName).path))
        #expect(ICNSConverter.isUsableICNS(at: fixture.container.iconsDirectory.appending(path: asset.icnsFileName!)))
        #expect(result.rows[0].iconFile == fixture.container.iconsDirectory.appending(path: asset.fileName))
    }

    @Test func originalImageIsNotNeededAfterAdd() async throws {
        let fixture = try ManagerFixture()
        let manager = try await fixture.manager()
        _ = try await manager.add(folder: URL(fileURLWithPath: fixture.dev), image: fixture.png)
        try FileManager.default.removeItem(at: fixture.png)
        let rows = await manager.rows()
        #expect(FileManager.default.fileExists(atPath: rows[0].iconFile.path))
        #expect(rows[0].state == .applied)
    }

    @Test(arguments: ["not an image at all", "\u{89}PNG\r\n\u{1A}\nbut-not-really"])
    func unreadableImageChangesNothing(contents: String) async throws {
        let fixture = try ManagerFixture()
        let manager = try await fixture.manager()
        _ = try await manager.add(folder: URL(fileURLWithPath: fixture.dev), image: fixture.png)
        let before = try fixture.snapshot()
        let calls = fixture.system.calls.count
        let bad = fixture.dir.url.appending(path: "bad.png")
        try Data(contents.utf8).write(to: bad)

        await #expect(throws: ManagerError.imageUnreadable("bad.png")) {
            try await manager.add(folder: URL(fileURLWithPath: fixture.docs), image: bad)
        }

        #expect(try fixture.snapshot() == before)
        #expect(fixture.system.calls.count == calls)
        #expect(await manager.rows().count == 1)
    }

    @Test func sameFolderByAnotherSpellingIsADuplicate() async throws {
        let fixture = try ManagerFixture()
        let manager = try await fixture.manager()
        _ = try await manager.add(folder: URL(fileURLWithPath: fixture.dev), image: fixture.png)
        let link = fixture.dir.url.appending(path: "link-to-dev")
        try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: fixture.dev)
        let before = try fixture.snapshot()

        for spelling in [fixture.dev + "/", fixture.dev + "/./", link.path] {
            await #expect(throws: ManagerError.duplicateFolder(existing: fixture.dev)) {
                try await manager.add(folder: URL(fileURLWithPath: spelling), image: fixture.png)
            }
        }
        #expect(try fixture.snapshot() == before)
    }

    @Test func aFileIsNotAFolder() async throws {
        let fixture = try ManagerFixture()
        let manager = try await fixture.manager()
        await #expect(throws: ManagerError.notAFolder(PathStandardizer.standardize(fixture.png.path))) {
            try await manager.add(folder: fixture.png, image: fixture.png)
        }
        await #expect(throws: ManagerError.self) {
            try await manager.add(folder: fixture.dir.url.appending(path: "missing"), image: fixture.png)
        }
        #expect(try ConfigStore(container: fixture.container).load().mappings.isEmpty)
    }

    @Test func folderNotInFavoritesIsSavedAsNotInSidebar() async throws {
        let fixture = try ManagerFixture { dev, _ in [dev] }
        let manager = try await fixture.manager()

        let result = try await manager.add(folder: URL(fileURLWithPath: fixture.docs), image: fixture.png)

        #expect(result.rows.map(\.state) == [.notInSidebar])
        #expect(result.messages.contains { $0.hasPrefix("Saved.") && $0.contains("Apply Now") })
        #expect(try ConfigStore(container: fixture.container).load().mappings.count == 1)
    }

    @Test func claimedCodesAreSkipped() async throws {
        let fixture = try ManagerFixture()
        fixture.system.state.withLock {
            $0.claims["S001"] = [LSClaimOwner(name: "Other", identifier: "com.example.other", path: "/Applications/Other.app")]
        }
        let manager = try await fixture.manager()
        _ = try await manager.add(folder: URL(fileURLWithPath: fixture.dev), image: fixture.png)
        #expect(try ConfigStore(container: fixture.container).load().mappings.map(\.osType) == ["S002"])
    }

    @Test func codesStayUniqueAcrossMappings() async throws {
        let fixture = try ManagerFixture()
        let manager = try await fixture.manager()
        _ = try await manager.add(folder: URL(fileURLWithPath: fixture.dev), image: fixture.png)
        let result = try await manager.add(folder: URL(fileURLWithPath: fixture.docs), image: fixture.png)
        let config = try ConfigStore(container: fixture.container).load()
        #expect(config.mappings.map(\.osType) == ["S001", "S002"])
        // The same source image gets its own asset per mapping.
        #expect(Set(config.assets.map(\.id)).count == 2)
        #expect(result.rows.map(\.state) == [.applied, .applied])
    }

    @Test func rowsMakeNoOutsideChanges() async throws {
        let fixture = try ManagerFixture()
        _ = try await fixture.manager().add(folder: URL(fileURLWithPath: fixture.dev), image: fixture.png)
        let system = FakeLaunchServices(favoritePaths: [fixture.dev])
        let manager = MappingManager(container: fixture.container, system: system, restartFinder: {})
        try await manager.load()

        let rows = await manager.rows()

        #expect(rows.count == 1)
        #expect(system.calls.isEmpty)
        #expect(rows[0].state == .notApplied)
    }

    @Test func mappingsPersistAcrossManagers() async throws {
        let fixture = try ManagerFixture()
        let first = try await fixture.manager()
        let added = try await first.add(folder: URL(fileURLWithPath: fixture.dev), image: fixture.png)

        let second = try await fixture.manager()

        #expect(await second.rows() == added.rows)
    }

    @Test func applyNowAppliesAFolderAddedToFavoritesLater() async throws {
        let fixture = try ManagerFixture { dev, _ in [dev] }
        let manager = try await fixture.manager()
        _ = try await manager.add(folder: URL(fileURLWithPath: fixture.docs), image: fixture.png)
        fixture.system.state.withLock {
            $0.favorites.append(FavoriteItem(displayName: "DevDocs", path: fixture.docs, overrideIcon: nil))
        }
        #expect(await manager.rows().map(\.state) == [.notApplied])

        let result = try await manager.applyNow()

        #expect(result.rows.map(\.state) == [.applied])
    }

    @Test func readOnlyManagerRefusesChanges() async throws {
        let fixture = try ManagerFixture()
        try FileManager.default.createDirectory(at: fixture.container.root, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: fixture.container.configURL)
        let manager = MappingManager(container: fixture.container, system: fixture.system, restartFinder: {})
        await #expect(throws: ManagerError.self) { try await manager.load() }

        #expect(await manager.readOnlyReason != nil)
        await #expect(throws: ManagerError.readOnly) {
            try await manager.add(folder: URL(fileURLWithPath: fixture.dev), image: fixture.png)
        }
        await #expect(throws: ManagerError.readOnly) { try await manager.applyNow() }
        #expect(try String(contentsOf: fixture.container.configURL, encoding: .utf8) == "not json")
    }

    @Test func unreadableFavoritesBlockAdd() async throws {
        let fixture = try ManagerFixture()
        fixture.system.state.withLock { $0.favoritesUnavailable = true }
        let manager = try await fixture.manager()
        await #expect(throws: ManagerError.favoritesUnavailable) {
            try await manager.add(folder: URL(fileURLWithPath: fixture.dev), image: fixture.png)
        }
        _ = await manager.rows()
        #expect(await manager.favoritesReadable == false)
    }
}
