import Foundation
import Synchronization
import Testing
@testable import SidebarIconCore

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
    }

    let state = Mutex(State())

    init(favoritePaths: [String]) {
        state.withLock { state in
            state.favorites = favoritePaths.map { FavoriteItem(displayName: ($0 as NSString).lastPathComponent, path: $0, overrideIcon: nil) }
        }
    }

    var calls: [String] { state.withLock { $0.calls } }

    func listFavorites() throws -> [FavoriteItem] {
        state.withLock { $0.favorites }
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
        state.withLock { state in
            state.calls.append("claims")
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

@Suite struct ApplyTests {
    @Test func registersBeforeSettingOverridesAndRecordsEverything() async throws {
        let fixture = try ProviderFixture()
        let system = FakeLaunchServices(favoritePaths: [fixture.dev, fixture.docs])
        let provider = LaunchServicesOverrideProvider(container: fixture.container, system: system)

        let report = try await provider.apply(fixture.mappings(), assets: [fixture.asset])

        #expect(report.applied.count == 2)
        #expect(report.skipped.isEmpty)
        #expect(system.calls == ["claims", "register", "set S001 \(fixture.dev)", "set S002 \(fixture.docs)"])
        let ledger = try provider.ledgerEntries()
        #expect(ledger.map(\.kind) == [.iconRegistration, .sidebarOverride, .sidebarOverride])
        #expect(FileManager.default.fileExists(atPath: fixture.container.registryBundleURL.appending(path: "Contents/Info.plist").path))
    }

    @Test func applyIsIdempotent() async throws {
        let fixture = try ProviderFixture()
        let system = FakeLaunchServices(favoritePaths: [fixture.dev, fixture.docs])
        let provider = LaunchServicesOverrideProvider(container: fixture.container, system: system)
        _ = try await provider.apply(fixture.mappings(), assets: [fixture.asset])
        _ = try await provider.apply(fixture.mappings(), assets: [fixture.asset])
        #expect(try provider.ledgerEntries().count == 3)
    }

    @Test func skipsFoldersNotInFavoritesMissingOrDuplicated() async throws {
        let fixture = try ProviderFixture()
        let missing = PathStandardizer.standardize(fixture.dir.url.appending(path: "home/nope").path)
        let system = FakeLaunchServices(favoritePaths: [fixture.docs, fixture.docs])
        let provider = LaunchServicesOverrideProvider(container: fixture.container, system: system)
        var mappings = fixture.mappings()
        mappings.append(SidebarMapping(folderPath: missing, iconAssetID: fixture.asset.id, osType: "S003"))

        let report = try await provider.apply(mappings, assets: [fixture.asset])

        #expect(report.applied.isEmpty)
        #expect(report.skipped.map(\.reason) == [
            .folderNotInFavorites(fixture.dev),
            .folderInFavoritesMoreThanOnce(fixture.docs),
            .folderMissing(missing),
        ])
        #expect(system.calls.isEmpty)
        #expect(try provider.ledgerEntries().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: missing))
    }

    @Test func refusesCodesClaimedByAnotherBundle() async throws {
        let fixture = try ProviderFixture()
        let system = FakeLaunchServices(favoritePaths: [fixture.dev, fixture.docs])
        system.state.withLock { $0.claims = ["S002": [LSClaimOwner(name: "Other", identifier: "com.example.other", path: "/Applications/Other.app")]] }
        let provider = LaunchServicesOverrideProvider(container: fixture.container, system: system)

        await #expect(throws: SidebarIconError.self) {
            try await provider.apply(fixture.mappings(), assets: [fixture.asset])
        }
        #expect(system.calls == ["claims"])
        #expect(try provider.ledgerEntries().isEmpty)
    }

    @Test func ignoresClaimsByItsOwnRegistrationBundle() async throws {
        let fixture = try ProviderFixture()
        let system = FakeLaunchServices(favoritePaths: [fixture.dev, fixture.docs])
        system.state.withLock {
            $0.claims = ["S001": [LSClaimOwner(name: "IconRegistry", identifier: IconRegistryBundle.bundleIdentifier, path: fixture.container.registryBundleURL.path)]]
        }
        let provider = LaunchServicesOverrideProvider(container: fixture.container, system: system)
        let report = try await provider.apply(fixture.mappings(), assets: [fixture.asset])
        #expect(report.applied.count == 2)
    }

    @Test(arguments: ["firmlink", "trailingSlash", "noPath"])
    func recognisesItsOwnBundleHoweverTheDumpSpellsThePath(_ spelling: String) async throws {
        let fixture = try ProviderFixture()
        let own = fixture.container.registryBundleURL.path
        let path: String? = switch spelling {
        case "firmlink": "/System/Volumes/Data" + own
        case "trailingSlash": own + "/"
        default: nil
        }
        let system = FakeLaunchServices(favoritePaths: [fixture.dev, fixture.docs])
        system.state.withLock {
            $0.claims = ["S001": [LSClaimOwner(name: "IconRegistry", identifier: IconRegistryBundle.bundleIdentifier, path: path)]]
        }
        let provider = LaunchServicesOverrideProvider(container: fixture.container, system: system)
        let report = try await provider.apply(fixture.mappings(), assets: [fixture.asset])
        #expect(report.applied.count == 2)
    }

    @Test func samePathTreatsSpellingsAlike() {
        #expect(LaunchServicesOverrideProvider.samePath("/System/Volumes/Data/Users/x/a.app", "/Users/x/a.app"))
        #expect(LaunchServicesOverrideProvider.samePath("/Users/x/a.app/", "/Users/x/./a.app"))
        #expect(!LaunchServicesOverrideProvider.samePath("/Users/x/a.app", "/Users/y/a.app"))
    }

    @Test func flagsAStaleCopyOfItsOwnBundleElsewhere() async throws {
        let fixture = try ProviderFixture()
        let system = FakeLaunchServices(favoritePaths: [fixture.dev, fixture.docs])
        system.state.withLock {
            $0.claims = ["S001": [LSClaimOwner(name: "IconRegistry", identifier: IconRegistryBundle.bundleIdentifier, path: "/old/container/IconRegistry.app")]]
        }
        let provider = LaunchServicesOverrideProvider(container: fixture.container, system: system)
        await #expect(throws: SidebarIconError.self) {
            try await provider.apply(fixture.mappings(), assets: [fixture.asset])
        }
        #expect(system.calls == ["claims"])
    }

    @Test func neverOverwritesAnotherToolsOverride() async throws {
        let fixture = try ProviderFixture()
        let system = FakeLaunchServices(favoritePaths: [fixture.dev, fixture.docs])
        system.state.withLock { $0.favorites[0].overrideIcon = "D001" }
        let provider = LaunchServicesOverrideProvider(container: fixture.container, system: system)

        let report = try await provider.apply(fixture.mappings(), assets: [fixture.asset])

        #expect(report.skipped.map(\.reason) == [.foreignOverride(path: fixture.dev, code: "D001")])
        #expect(!system.calls.contains("set S001 \(fixture.dev)"))
        #expect(try system.listFavorites()[0].overrideIcon == "D001")
    }

    @Test func keepsCodesStillInUseInTheBundle() async throws {
        let fixture = try ProviderFixture()
        let system = FakeLaunchServices(favoritePaths: [fixture.dev, fixture.docs])
        let provider = LaunchServicesOverrideProvider(container: fixture.container, system: system)
        _ = try await provider.apply(fixture.mappings(), assets: [fixture.asset])

        // DevDocs is now in Favorites twice, so it is skipped, but its earlier override remains.
        system.state.withLock { state in
            state.favorites.append(FavoriteItem(displayName: "DevDocs", path: fixture.docs, overrideIcon: nil))
        }
        _ = try await provider.apply(fixture.mappings(), assets: [fixture.asset])

        let info = try Data(contentsOf: fixture.container.registryBundleURL.appending(path: "Contents/Info.plist"))
        let plist = try #require(PropertyListSerialization.propertyList(from: info, format: nil) as? [String: Any])
        let codes = (plist["CFBundleDocumentTypes"] as? [[String: Any]])?.compactMap { ($0["CFBundleTypeOSTypes"] as? [String])?.first }
        #expect(codes == ["S001", "S002"])
    }

    @Test func failedOverrideIsReportedAndNotRecorded() async throws {
        let fixture = try ProviderFixture()
        let system = FakeLaunchServices(favoritePaths: [fixture.dev, fixture.docs])
        system.state.withLock { $0.failSetting = [fixture.docs] }
        let provider = LaunchServicesOverrideProvider(container: fixture.container, system: system)

        let report = try await provider.apply(fixture.mappings(), assets: [fixture.asset])

        #expect(report.applied.count == 1)
        #expect(report.skipped.map(\.reason) == [.propertyRejected(fixture.docs, -2)])
        #expect(try provider.ledgerEntries().filter { $0.kind == .sidebarOverride }.map(\.target) == [fixture.dev])
    }

    @Test func disablingAMappingClearsItsOverride() async throws {
        let fixture = try ProviderFixture()
        let system = FakeLaunchServices(favoritePaths: [fixture.dev, fixture.docs])
        let provider = LaunchServicesOverrideProvider(container: fixture.container, system: system)
        _ = try await provider.apply(fixture.mappings(), assets: [fixture.asset])

        let report = try await provider.apply(fixture.mappings(docsEnabled: false), assets: [fixture.asset])

        #expect(report.cleared == [fixture.docs])
        #expect(system.calls.last == "clear S002")
        #expect(try provider.ledgerEntries().filter { $0.kind == .sidebarOverride }.map(\.target) == [fixture.dev])
    }

    @Test func changingACodeReplacesTheLedgerEntry() async throws {
        let fixture = try ProviderFixture()
        let system = FakeLaunchServices(favoritePaths: [fixture.dev, fixture.docs])
        let provider = LaunchServicesOverrideProvider(container: fixture.container, system: system)
        var mappings = fixture.mappings()
        _ = try await provider.apply(mappings, assets: [fixture.asset])
        mappings[1].osType = "S003"
        _ = try await provider.apply(mappings, assets: [fixture.asset])
        let overrides = try provider.ledgerEntries().filter { $0.kind == .sidebarOverride }
        #expect(overrides.compactMap(\.osType).sorted() == ["S001", "S003"])
    }

    @Test func invalidMappingsChangeNothing() async throws {
        let fixture = try ProviderFixture()
        let system = FakeLaunchServices(favoritePaths: [fixture.dev])
        let provider = LaunchServicesOverrideProvider(container: fixture.container, system: system)
        let bad = [SidebarMapping(folderPath: fixture.dev, iconAssetID: fixture.asset.id, osType: "D001")]
        await #expect(throws: SidebarIconError.self) { try await provider.apply(bad, assets: [fixture.asset]) }
        #expect(system.calls.isEmpty)
    }

    @Test func statusIsReadOnly() async throws {
        let fixture = try ProviderFixture()
        let system = FakeLaunchServices(favoritePaths: [fixture.dev])
        let provider = LaunchServicesOverrideProvider(container: fixture.container, system: system)
        let status = try await provider.status(for: fixture.mappings())
        #expect(status.map(\.favoriteCount) == [1, 0])
        #expect(system.calls.isEmpty)
        #expect(try provider.ledgerEntries().isEmpty)
    }
}

@Suite struct LSRegisterDumpParserTests {
    static let dump = """
    --------------------------------------------------------------------------------
    bundle id:                  Other (0x2244)
    path:                       /Applications/Other.app (0x40ec)
    name:                       Other
    identifier:                 com.example.other
    --------------------------------------------------------------------------------
    claim id:                   20784 (0x5130)
    bundle:                     Other (0x2244)
    bindings:                   .*, 'fold', 'S002'
    --------------------------------------------------------------------------------
    bundle id:                  IconRegistry (0x3000)
    path:                       /Users/someone/Library/Group Containers/X/IconRegistry.app (0x4100)
    identifier:                 com.altmansoftwaredesign.SidebarIcons.IconRegistry
    --------------------------------------------------------------------------------
    claim id:                   Sidebar Icons S001 (0x5200)
    bundle:                     IconRegistry (0x3000)
    bindings:                   'S001'
    """

    @Test func findsOwnersOfEachCode() {
        let claims = LSRegisterDumpParser.claims(on: ["S001", "S002", "S003"], in: Self.dump)
        #expect(claims["S002"] == [LSClaimOwner(name: "Other", identifier: "com.example.other", path: "/Applications/Other.app")])
        #expect(claims["S001"]?.first?.identifier == IconRegistryBundle.bundleIdentifier)
        #expect(claims["S003"] == nil)
    }

    @Test func doesNotMatchCodesInsideOtherWords() {
        #expect(LSRegisterDumpParser.claims(on: ["fol"], in: Self.dump).isEmpty)
    }

    @Test func readsWrappedBindings() {
        let dump = Self.dump + "\n" + """
        --------------------------------------------------------------------------------
        claim id:                   Wrapped (0x6000)
        bundle:                     Other (0x2244)
        bindings:                   'AAAA', 'BBBB',
                                    'S009'
        """
        #expect(LSRegisterDumpParser.claims(on: ["S009"], in: dump)["S009"]?.first?.name == "Other")
    }

    @Test func listsRegisteredBundlePaths() {
        #expect(LSRegisterDumpParser.registeredPaths(in: Self.dump) == [
            "/Applications/Other.app",
            "/Users/someone/Library/Group Containers/X/IconRegistry.app",
        ])
    }
}
