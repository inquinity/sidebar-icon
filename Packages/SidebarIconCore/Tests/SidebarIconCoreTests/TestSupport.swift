import Foundation
import Synchronization
@testable import SidebarIconCore

/// A fresh directory under the system temporary directory, removed when the value is released.
final class TemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appending(path: "SidebarIconCoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}

struct TestError: Error, Equatable {}

/// Records every system call in order and simulates the Favorites list.
final class FakeLaunchServices: LaunchServicesSystem {
    struct State {
        var favorites: [FavoriteItem] = []
        var calls: [String] = []
        var registered: Set<String> = []
        var failClearing: Set<String> = []
        var failSetting: Set<String> = []
        var failUnregister = false
        var unregisterFailsWhenMissing = false
        var claims: [String: [LSClaimOwner]] = [:]
        var favoritesUnavailable = false
        var failClaims = false
    }

    let state = Mutex(State())

    init(favoritePaths: [String]) {
        state.withLock { state in
            state.favorites = favoritePaths.map { FavoriteItem(displayName: ($0 as NSString).lastPathComponent, path: $0, overrideIcon: nil) }
        }
    }

    var calls: [String] { state.withLock { $0.calls } }

    func listFavorites() throws -> [FavoriteItem] {
        try state.withLock { state in
            if state.favoritesUnavailable { throw SidebarIconError.favoritesUnavailable }
            return state.favorites
        }
    }

    func setOverrideIcon(_ code: String, forFavoriteAt path: String) throws {
        try state.withLock { state in
            state.calls.append("set \(code) \(path)")
            if state.failSetting.contains(path) { throw SidebarIconError.propertyRejected(path, -2) }
            for index in state.favorites.indices where state.favorites[index].path == path {
                state.favorites[index].overrideIcon = code
            }
        }
    }

    func clearOverrideIcon(_ code: String) throws -> Int {
        try state.withLock { state in
            state.calls.append("clear \(code)")
            if state.failClearing.contains(code) { throw SidebarIconError.propertyRejected(code, -1) }
            var cleared = 0
            for index in state.favorites.indices where state.favorites[index].overrideIcon == code {
                state.favorites[index].overrideIcon = nil
                cleared += 1
            }
            return cleared
        }
    }

    func register(bundleAt url: URL) throws {
        state.withLock { state in
            state.calls.append("register")
            state.registered.insert(url.path)
        }
    }

    func unregister(bundleAt url: URL) throws {
        try state.withLock { state in
            state.calls.append("unregister")
            if state.failUnregister { throw SidebarIconError.toolFailed("fake") }
            if state.unregisterFailsWhenMissing, !FileManager.default.fileExists(atPath: url.path) {
                state.registered.remove(url.path)
                throw SidebarIconError.toolFailed("lsregister -u exited with 1")
            }
            state.registered.remove(url.path)
        }
    }

    func claims(on codes: Set<String>) throws -> [String: [LSClaimOwner]] {
        try state.withLock { state in
            state.calls.append("claims")
            if state.failClaims { throw SidebarIconError.toolFailed("lsregister -dump exited with 1") }
            return state.claims.filter { codes.contains($0.key) }
        }
    }

    func isRegistered(bundleAt url: URL) throws -> Bool {
        state.withLock { $0.registered.contains(url.path) }
    }
}

/// A container with two real folders and one PNG asset.
struct ProviderFixture {
    let dir: TemporaryDirectory
    let container: ContainerLocator
    let dev: String
    let docs: String
    let asset: IconAsset

    init() throws {
        dir = try TemporaryDirectory()
        container = ContainerLocator(root: dir.url.appending(path: "Container", directoryHint: .isDirectory))
        try container.prepare()
        let home = dir.url.appending(path: "home", directoryHint: .isDirectory)
        dev = PathStandardizer.standardize(home.appending(path: "dev").path)
        docs = PathStandardizer.standardize(home.appending(path: "DevDocs").path)
        for path in [dev, docs] {
            try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        }
        let png = try writeTestPNG(in: dir.url)
        asset = try AssetImporter.importFile(at: png, into: container.iconsDirectory)
    }

    func mappings(docsEnabled: Bool = true) -> [SidebarMapping] {
        [
            SidebarMapping(folderPath: dev, iconAssetID: asset.id, osType: "S001"),
            SidebarMapping(folderPath: docs, iconAssetID: asset.id, osType: "S002", enabled: docsEnabled),
        ]
    }
}

/// A container, two real folders (`dev` in Favorites by default), a PNG, and a manager over a fake.
struct ManagerFixture {
    let dir: TemporaryDirectory
    let container: ContainerLocator
    let dev: String
    let docs: String
    let png: URL
    let system: FakeLaunchServices

    init(favorites: ((String, String) -> [String])? = nil) throws {
        dir = try TemporaryDirectory()
        container = ContainerLocator(root: dir.url.appending(path: "Container", directoryHint: .isDirectory))
        let home = dir.url.appending(path: "home", directoryHint: .isDirectory)
        dev = PathStandardizer.standardize(home.appending(path: "dev").path)
        docs = PathStandardizer.standardize(home.appending(path: "DevDocs").path)
        for path in [dev, docs] {
            try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
        }
        png = try writeTestPNG(in: dir.url)
        system = FakeLaunchServices(favoritePaths: favorites?(dev, docs) ?? [dev, docs])
    }

    func manager() async throws -> MappingManager {
        let manager = MappingManager(container: container, system: system, restartFinder: {})
        try await manager.load()
        return manager
    }

    /// Bytes of every file the manager owns, to prove a failed action changed nothing.
    func snapshot() throws -> [String: Data] {
        var files: [String: Data] = [:]
        let root = container.root
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey]) else {
            return files
        }
        for case let url as URL in enumerator where (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true {
            files[url.path] = try Data(contentsOf: url)
        }
        return files
    }
}

/// The registry bundle version the ledger records last (0.3.0 writes `IconRegistry-<hash>.app`).
func currentRegistryBundle(_ container: ContainerLocator) throws -> URL {
    guard let entry = try LedgerStore(url: container.ledgerURL).entries().last(where: { $0.kind == .iconRegistration }) else {
        throw TestError()
    }
    return URL(fileURLWithPath: entry.target, isDirectory: true)
}

/// Every `IconRegistry*.app` directly in the container.
func registryBundlesOnDisk(_ container: ContainerLocator) throws -> [String] {
    guard FileManager.default.fileExists(atPath: container.root.path) else { return [] }
    return try FileManager.default.contentsOfDirectory(atPath: container.root.path)
        .filter { $0.hasPrefix("IconRegistry") && $0.hasSuffix(".app") }
}

