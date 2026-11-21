import Foundation
import Synchronization
import Testing
@testable import SidebarIconCore

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

    @Test func skipsOnlyTheMappingWhoseCodeAnotherBundleClaims() async throws {
        let fixture = try ProviderFixture()
        let system = FakeLaunchServices(favoritePaths: [fixture.dev, fixture.docs])
        let owners = [LSClaimOwner(name: "Other", identifier: "com.example.other", path: "/Applications/Other.app")]
        system.state.withLock { $0.claims = ["S002": owners] }
        let provider = LaunchServicesOverrideProvider(container: fixture.container, system: system)
        let mappings = fixture.mappings()

        let report = try await provider.apply(mappings, assets: [fixture.asset])

        #expect(report.applied == [mappings[0].id])
        #expect(report.skipped == [.init(mappingID: mappings[1].id, reason: .codeClaimedElsewhere(code: "S002", owners: owners.map(\.description)))])
        #expect(system.calls == ["claims", "register", "set S001 \(fixture.dev)"])
        let plist = try Data(contentsOf: fixture.container.registryBundleURL.appending(path: "Contents/Info.plist"))
        #expect(String(decoding: plist, as: UTF8.self).contains("S001"))
        #expect(!String(decoding: plist, as: UTF8.self).contains(">S002<"))
        #expect(try provider.ledgerEntries().compactMap(\.osType) == ["S001"])
    }

    @Test func registersNothingWhenEveryCodeIsClaimed() async throws {
        let fixture = try ProviderFixture()
        let system = FakeLaunchServices(favoritePaths: [fixture.dev, fixture.docs])
        let owners = [LSClaimOwner(name: "Other", identifier: "com.example.other", path: "/Applications/Other.app")]
        system.state.withLock { $0.claims = ["S001": owners, "S002": owners] }
        let provider = LaunchServicesOverrideProvider(container: fixture.container, system: system)

        let report = try await provider.apply(fixture.mappings(), assets: [fixture.asset])

        #expect(report.applied.isEmpty)
        #expect(report.skipped.count == 2)
        #expect(system.calls == ["claims"])
        #expect(try provider.ledgerEntries().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: fixture.container.registryBundleURL.path))
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
        let report = try await provider.apply(fixture.mappings(), assets: [fixture.asset])
        // The stale copy's code is skipped; the other mapping is still applied.
        #expect(report.skipped.map(\.reason) == [.codeClaimedElsewhere(code: "S001", owners: [
            "IconRegistry — \(IconRegistryBundle.bundleIdentifier) — /old/container/IconRegistry.app",
        ])])
        #expect(report.applied.count == 1)
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
        let codes = (plist["UTExportedTypeDeclarations"] as? [[String: Any]])?
            .compactMap { ($0["UTTypeTagSpecification"] as? [String: [String]])?["com.apple.ostype"]?.first }
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

    /// Review T042 #1: a mapping that keeps its code but moves to another folder must keep the
    /// override it was just given.
    @Test func movingAMappingToAnotherFolderKeepsItsOverride() async throws {
        let fixture = try ProviderFixture()
        let system = FakeLaunchServices(favoritePaths: [fixture.dev, fixture.docs])
        let provider = LaunchServicesOverrideProvider(container: fixture.container, system: system)
        let original = SidebarMapping(folderPath: fixture.dev, iconAssetID: fixture.asset.id, osType: "S001")
        _ = try await provider.apply([original], assets: [fixture.asset])

        var moved = original
        moved.folderPath = fixture.docs
        let report = try await provider.apply([moved], assets: [fixture.asset])

        #expect(report.applied == [moved.id])
        #expect(try system.listFavorites().first { $0.path == fixture.docs }?.overrideIcon == "S001")
        let overrides = try provider.ledgerEntries().filter { $0.kind == .sidebarOverride }
        #expect(overrides.map(\.target) == [fixture.docs])
    }

    /// Review T042 #2: stored file names must stay inside `Icons/`.
    @Test func rejectsAssetFileNamesThatLeaveTheIconsFolder() async throws {
        let fixture = try ProviderFixture()
        let system = FakeLaunchServices(favoritePaths: [fixture.dev])
        let provider = LaunchServicesOverrideProvider(container: fixture.container, system: system)
        let bad = IconAsset(id: fixture.asset.id, sourceFormat: .png, fileName: "../../escape.png")
        let report = try await provider.apply([fixture.mappings()[0]], assets: [bad])
        #expect(report.applied.isEmpty)
        #expect(report.skipped.map(\.reason) == [.assetConversionFailed(fixture.asset.id)])
    }

    /// Review T042 #3: a symbolic link in place of the registry bundle is never registered.
    @Test func refusesASymlinkedRegistryBundle() async throws {
        let fixture = try ProviderFixture()
        let system = FakeLaunchServices(favoritePaths: [fixture.dev, fixture.docs])
        let elsewhere = fixture.dir.url.appending(path: "Other.app", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: fixture.container.registryBundleURL, withDestinationURL: elsewhere)
        let provider = LaunchServicesOverrideProvider(container: fixture.container, system: system)
        await #expect(throws: SidebarIconError.self) {
            try await provider.apply(fixture.mappings(), assets: [fixture.asset])
        }
        #expect(!system.calls.contains { $0.hasPrefix("register") })
    }

    @Test func failedClearForADisabledMappingIsNotedAndKept() async throws {
        let fixture = try ProviderFixture()
        let system = FakeLaunchServices(favoritePaths: [fixture.dev, fixture.docs])
        let provider = LaunchServicesOverrideProvider(container: fixture.container, system: system)
        _ = try await provider.apply(fixture.mappings(), assets: [fixture.asset])
        system.state.withLock { $0.failClearing = ["S002"] }

        let report = try await provider.apply(fixture.mappings(docsEnabled: false), assets: [fixture.asset])

        #expect(report.applied.count == 1)
        #expect(report.cleared.isEmpty)
        #expect(report.notes.contains { $0.contains("S002") && $0.contains(fixture.docs) })
        #expect(try provider.ledgerEntries().filter { $0.kind == .sidebarOverride }.map(\.target).sorted() == [fixture.dev, fixture.docs].sorted())
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

    @Test func typeDeclarationsTaggedWithACodeCountAsClaims() {
        let dump = Self.dump + "\n" + """
        --------------------------------------------------------------------------------
        type id:                    com.example.other.s005 (0x7000)
        bundle:                     Other (0x2244)
        uti:                        com.example.other.s005
        icons:                      1 values (1 (0x1))
                                    {
                                        'S006' = x;
                                    }
        conforms to:                public.data
        tags:                       .s5, 'AAAA',
                                    'S005'
        --------------------------------------------------------------------------------
        claim id:                   Also (0x7004)
        bundle:                     Other (0x2244)
        bindings:                   'S005'
        """
        let claims = LSRegisterDumpParser.claims(on: ["S005", "S006"], in: dump)
        #expect(claims["S005"] == [LSClaimOwner(name: "Other", identifier: "com.example.other", path: "/Applications/Other.app")])
        #expect(claims["S006"] == nil)
    }

    /// The registry bundle declares only exported types, so our type record is the one that tags
    /// the code; it must resolve to our bundle's path so the provider exempts it.
    @Test func ownTypeDeclarationResolvesToOurBundle() {
        let dump = Self.dump + "\n" + """
        --------------------------------------------------------------------------------
        type id:                    com.altmansoftwaredesign.sidebaricons.icon.s001.5b1c0de0-0001-4000-8000-0000000000a1 (0x7100)
        bundle:                     IconRegistry (0x3000)
        uti:                        com.altmansoftwaredesign.sidebaricons.icon.s001.5b1c0de0-0001-4000-8000-0000000000a1
        tags:                       'S001'
        """
        #expect(LSRegisterDumpParser.claims(on: ["S001"], in: dump)["S001"] == [LSClaimOwner(
            name: "IconRegistry",
            identifier: IconRegistryBundle.bundleIdentifier,
            path: "/Users/someone/Library/Group Containers/X/IconRegistry.app"
        )])
    }

    @Test func listsRegisteredBundlePaths() {
        #expect(LSRegisterDumpParser.registeredPaths(in: Self.dump) == [
            "/Applications/Other.app",
            "/Users/someone/Library/Group Containers/X/IconRegistry.app",
        ])
    }
}
