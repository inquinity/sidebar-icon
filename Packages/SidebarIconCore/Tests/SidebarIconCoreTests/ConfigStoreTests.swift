import Foundation
import Testing
@testable import SidebarIconCore

@Suite struct ConfigStoreTests {
    private func makeStore() throws -> (TemporaryDirectory, ContainerLocator, ConfigStore) {
        let dir = try TemporaryDirectory()
        let container = ContainerLocator(root: dir.url.appending(path: "Container", directoryHint: .isDirectory))
        return (dir, container, ConfigStore(container: container))
    }

    private func sampleConfig(in container: ContainerLocator, folder: String) throws -> AppConfiguration {
        let asset = IconAsset(id: UUID(), sourceFormat: .png)
        try FileManager.default.createDirectory(at: container.iconsDirectory, withIntermediateDirectories: true)
        try Data("png".utf8).write(to: container.iconsDirectory.appending(path: asset.fileName))
        let mapping = SidebarMapping(folderPath: folder, iconAssetID: asset.id, osType: "S001")
        return AppConfiguration(mappings: [mapping], assets: [asset])
    }

    @Test func missingFileLoadsEmpty() throws {
        let (_, _, store) = try makeStore()
        let config = try store.load()
        #expect(config == AppConfiguration())
        #expect(config.schemaVersion == 2)
    }

    @Test func saveThenLoadRoundTrips() throws {
        let (dir, container, store) = try makeStore()
        let config = try sampleConfig(in: container, folder: PathStandardizer.standardize(dir.url.path))
        try store.save(config)
        #expect(try store.load() == config)
    }

    @Test func leftoverTempFileDoesNotAffectTheConfig() throws {
        let (dir, container, store) = try makeStore()
        let config = try sampleConfig(in: container, folder: PathStandardizer.standardize(dir.url.path))
        try store.save(config)
        // A crash between writing the temp file and replacing the config leaves this behind.
        try Data("{ truncated".utf8).write(to: store.tempURL)
        #expect(try store.load() == config)
        try store.save(config)
        #expect(!FileManager.default.fileExists(atPath: store.tempURL.path))
        #expect(try store.load() == config)
    }

    @Test(arguments: [
        #"{"schemaVersion": 2, "mappings": [], "assets": []}"#,
        "not json",
        #"{"schemaVersion": 1, "mappings": [{"id": 1}], "assets": []}"#,
    ])
    func unknownSchemaOrBadJSONIsUnreadableAndNeverOverwritten(contents: String) throws {
        let (_, container, store) = try makeStore()
        try FileManager.default.createDirectory(at: container.root, withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: container.configURL)

        #expect(throws: ManagerError.self) { try store.load() }
        do {
            _ = try store.load()
        } catch let error as ManagerError {
            guard case .configUnreadable = error else { Issue.record("wrong error \(error)"); return }
        }
        #expect(throws: ManagerError.self) { try store.save(AppConfiguration()) }
        #expect(try String(contentsOf: container.configURL, encoding: .utf8) == contents)
    }

    @Test func mappingWithUnknownAssetIsUnreadable() throws {
        let (dir, container, store) = try makeStore()
        let mapping = SidebarMapping(folderPath: PathStandardizer.standardize(dir.url.path), iconAssetID: UUID(), osType: "S001")
        #expect(!AppConfiguration(mappings: [mapping], assets: []).problems.isEmpty)
        #expect(throws: ManagerError.self) { try store.save(AppConfiguration(mappings: [mapping], assets: [])) }
        #expect(!FileManager.default.fileExists(atPath: container.configURL.path))
    }

    @Test func unreferencedAssetsArePrunedWithTheirFiles() throws {
        let (dir, container, store) = try makeStore()
        var config = try sampleConfig(in: container, folder: PathStandardizer.standardize(dir.url.path))
        var orphan = IconAsset(id: UUID(), sourceFormat: .png)
        orphan.icnsFileName = "\(orphan.id.uuidString).icns"
        for name in [orphan.fileName, orphan.icnsFileName!] {
            try Data("x".utf8).write(to: container.iconsDirectory.appending(path: name))
        }
        config.assets.append(orphan)

        try store.save(config)

        let saved = try store.load()
        #expect(saved.assets.map(\.id) == [config.mappings[0].iconAssetID])
        #expect(!FileManager.default.fileExists(atPath: container.iconsDirectory.appending(path: orphan.fileName).path))
        #expect(!FileManager.default.fileExists(atPath: container.iconsDirectory.appending(path: orphan.icnsFileName!).path))
        #expect(FileManager.default.fileExists(atPath: container.iconsDirectory.appending(path: saved.assets[0].fileName).path))
    }

    @Test func pruningNeverDeletesOutsideTheIconsFolder() throws {
        let (dir, container, store) = try makeStore()
        let victim = dir.url.appending(path: "victim.txt")
        try Data("keep".utf8).write(to: victim)
        let orphan = IconAsset(id: UUID(), sourceFormat: .png, fileName: "../../victim.txt")
        try store.save(AppConfiguration(mappings: [], assets: [orphan]))
        #expect(FileManager.default.fileExists(atPath: victim.path))
        _ = container
    }

    @Test func removeDeletesAnUnreadableConfig() throws {
        let (_, container, store) = try makeStore()
        try FileManager.default.createDirectory(at: container.root, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: container.configURL)
        try store.remove()
        #expect(try store.load() == AppConfiguration())
    }
}
