import Foundation
import Testing
@testable import SidebarIconCore

/// 004 T009: one registry bundle version per content (research D2).
@Suite struct VersionedRegistryTests {
    private func setup() throws -> (ProviderFixture, FakeLaunchServices, LaunchServicesOverrideProvider) {
        let fixture = try ProviderFixture()
        let system = FakeLaunchServices(favoritePaths: [fixture.dev, fixture.docs])
        return (fixture, system, LaunchServicesOverrideProvider(container: fixture.container, system: system))
    }

    @Test func writesAVersionedBundleBeforeSettingOverrides() async throws {
        let (fixture, system, provider) = try setup()
        _ = try await provider.apply(fixture.mappings(), assets: [fixture.asset])
        let bundle = try currentRegistryBundle(fixture.container)
        #expect(bundle.lastPathComponent.hasPrefix("IconRegistry-") && bundle.lastPathComponent.hasSuffix(".app"))
        #expect(system.calls.prefix(2) == ["claims", "register"])
        #expect(try registryBundlesOnDisk(fixture.container) == [bundle.lastPathComponent])
    }

    @Test func sameContentReusesTheVersion() async throws {
        let (fixture, system, provider) = try setup()
        _ = try await provider.apply(fixture.mappings(), assets: [fixture.asset])
        let first = try currentRegistryBundle(fixture.container)
        system.state.withLock { $0.calls = [] }
        _ = try await provider.apply(fixture.mappings(), assets: [fixture.asset])
        #expect(try currentRegistryBundle(fixture.container) == first)
        #expect(!system.calls.contains("unregister"))
        #expect(try registryBundlesOnDisk(fixture.container).count == 1)
    }

    @Test func styleChangeSwitchesVersionsAndKeepsCodes() async throws {
        let (fixture, system, provider) = try setup()
        var mappings = fixture.mappings()
        _ = try await provider.apply(mappings, assets: [fixture.asset])
        let first = try currentRegistryBundle(fixture.container)
        mappings[0].sidebarStyle = .systemSymbol(name: "hammer")
        system.state.withLock { $0.calls = [] }

        _ = try await provider.apply(mappings, assets: [fixture.asset])

        let second = try currentRegistryBundle(fixture.container)
        #expect(second != first)
        #expect(try registryBundlesOnDisk(fixture.container) == [second.lastPathComponent])
        #expect(system.calls.last == "unregister")
        #expect(try provider.ledgerEntries().filter { $0.kind == .iconRegistration }.count == 1)
        #expect(try system.listFavorites().first { $0.path == fixture.dev }?.overrideIcon == "S001")
        let info = try String(contentsOf: second.appending(path: "Contents/Info.plist"), encoding: .utf8)
        #expect(info.contains("<string>hammer</string>"))
    }

    @Test func retiresTheUnversionedBundleOfZeroTwo() async throws {
        let (fixture, _, provider) = try setup()
        let legacy = fixture.container.registryBundleURL
        try FileManager.default.createDirectory(at: legacy.appending(path: "Contents"), withIntermediateDirectories: true)
        try LedgerStore(url: fixture.container.ledgerURL).record(OutsideChange(kind: .iconRegistration, target: legacy.path)) {}

        _ = try await provider.apply(fixture.mappings(), assets: [fixture.asset])

        #expect(!FileManager.default.fileExists(atPath: legacy.path))
        #expect(try provider.ledgerEntries().filter { $0.kind == .iconRegistration }.map(\.target) == [try currentRegistryBundle(fixture.container).path])
    }

    @Test func anyVersionInTheContainerIsOurOwnClaim() async throws {
        let (fixture, system, provider) = try setup()
        let ours = fixture.container.registryBundleURL(named: "IconRegistry-deadbeef.app").path
        // The identifier-only claim counts as ours because the ledger records that version.
        try LedgerStore(url: fixture.container.ledgerURL).record(OutsideChange(kind: .iconRegistration, target: ours)) {}
        system.state.withLock {
            $0.claims = ["S001": [LSClaimOwner(name: "IconRegistry", identifier: "com.altmansoftwaredesign.sidebaricons.iconregistry.deadbeef", path: ours)],
                         "S002": [LSClaimOwner(name: "IconRegistry", identifier: "com.altmansoftwaredesign.sidebaricons.iconregistry.deadbeef", path: nil)]]
        }
        let report = try await provider.apply(fixture.mappings(), assets: [fixture.asset])
        #expect(report.applied.count == 2)
    }

    @Test func resetRemovesEveryVersionAndUnrecordedLeftovers() async throws {
        let (fixture, system, provider) = try setup()
        var mappings = fixture.mappings()
        _ = try await provider.apply(mappings, assets: [fixture.asset])
        mappings[1].sidebarStyle = .systemSymbol(name: "doc")
        _ = try await provider.apply(mappings, assets: [fixture.asset])
        let stray = fixture.container.registryBundleURL(named: "IconRegistry-0badf00d.app")
        try FileManager.default.createDirectory(at: stray, withIntermediateDirectories: true)
        let staging = fixture.container.root.appending(path: ".IconRegistry-0badf00d.app.staging-1")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)

        let report = try await provider.reset()
        _ = provider.removeUnrecordedRegistryFiles()

        #expect(report.succeeded)
        #expect(try registryBundlesOnDisk(fixture.container).isEmpty)
        #expect(!FileManager.default.fileExists(atPath: staging.path))
        #expect(try provider.ledgerEntries().isEmpty)
        #expect(system.state.withLock { $0.registered.isEmpty })
    }

    // Review findings on 9e9da31.

    @Test func failedReRegistrationKeepsARecordedVersion() async throws {
        let (fixture, system, provider) = try setup()
        _ = try await provider.apply(fixture.mappings(), assets: [fixture.asset])
        let bundle = try currentRegistryBundle(fixture.container)
        system.state.withLock { $0.failRegister = true; $0.calls = [] }

        await #expect(throws: (any Error).self) { try await provider.apply(fixture.mappings(), assets: [fixture.asset]) }

        #expect(FileManager.default.fileExists(atPath: bundle.path))
        #expect(!system.calls.contains("unregister"))
        #expect(try currentRegistryBundle(fixture.container) == bundle)
    }

    @Test func failedFirstRegistrationRemovesTheNewBundle() async throws {
        let (fixture, system, provider) = try setup()
        system.state.withLock { $0.failRegister = true }
        await #expect(throws: (any Error).self) { try await provider.apply(fixture.mappings(), assets: [fixture.asset]) }
        #expect(try registryBundlesOnDisk(fixture.container).isEmpty)
        #expect(try provider.ledgerEntries().isEmpty)
    }

    @Test func damagedVersionIsRewrittenBeforeRegistering() async throws {
        let (fixture, _, provider) = try setup()
        _ = try await provider.apply(fixture.mappings(), assets: [fixture.asset])
        let bundle = try currentRegistryBundle(fixture.container)
        let info = bundle.appending(path: "Contents/Info.plist")
        let original = try Data(contentsOf: info)
        try Data("damaged".utf8).write(to: info)

        _ = try await provider.apply(fixture.mappings(), assets: [fixture.asset])

        #expect(try Data(contentsOf: info) == original)
    }

    @Test func overrideWhoseIconIsUnavailableIsClearedBeforeRetiring() async throws {
        let (fixture, system, provider) = try setup()
        var mappings = fixture.mappings()
        _ = try await provider.apply(mappings, assets: [fixture.asset])
        // The docs mapping becomes a custom glyph with no car: its code can't be declared.
        mappings[1].sidebarStyle = .customGlyph(glyphID: UUID())
        mappings[0].sidebarStyle = .systemSymbol(name: "hammer")

        let report = try await provider.apply(mappings, assets: [fixture.asset])

        #expect(report.cleared.contains(fixture.docs))
        #expect(try system.listFavorites().first { $0.path == fixture.docs }?.overrideIcon == nil)
        #expect(try provider.ledgerEntries().filter { $0.kind == .sidebarOverride }.compactMap(\.osType) == ["S001"])
    }

    @Test func unreadableCarOnlyAffectsCustomGlyphs() async throws {
        let (fixture, _, provider) = try setup()
        var mappings = fixture.mappings()
        let glyph = CustomGlyph(name: "git")
        mappings[1].sidebarStyle = .customGlyph(glyphID: glyph.id)
        let missingCar = fixture.container.root.appending(path: "nope/Assets.car")

        let report = try await provider.apply(mappings, assets: [fixture.asset], glyphs: [glyph], assetsCar: missingCar)

        #expect(report.applied == [mappings[0].id])
        #expect(report.skipped.map(\.mappingID) == [mappings[1].id])
    }

    @Test func carChangesDontMakeVersionsWithoutGlyphs() async throws {
        let (fixture, _, provider) = try setup()
        let car = fixture.container.root.appending(path: "a.car")
        try Data("one".utf8).write(to: car)
        _ = try await provider.apply(fixture.mappings(), assets: [fixture.asset], glyphs: [], assetsCar: car)
        let first = try currentRegistryBundle(fixture.container)
        try Data("two".utf8).write(to: car)
        _ = try await provider.apply(fixture.mappings(), assets: [fixture.asset], glyphs: [], assetsCar: car)
        #expect(try currentRegistryBundle(fixture.container) == first)
        #expect(!FileManager.default.fileExists(atPath: first.appending(path: "Contents/Resources/Assets.car").path))
    }

    @Test func unrecordedVersionIdentifierIsNotOurs() async throws {
        let (fixture, system, provider) = try setup()
        system.state.withLock {
            $0.claims = ["S001": [LSClaimOwner(name: "Impostor", identifier: "com.altmansoftwaredesign.sidebaricons.iconregistry.deadbeef", path: nil)]]
        }
        let report = try await provider.apply(fixture.mappings(), assets: [fixture.asset])
        #expect(report.skipped.contains { if case .codeClaimedElsewhere = $0.reason { true } else { false } })
    }
}
