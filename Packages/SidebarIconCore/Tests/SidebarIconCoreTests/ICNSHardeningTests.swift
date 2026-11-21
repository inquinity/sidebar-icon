import Foundation
import Testing
@testable import SidebarIconCore

@Suite struct ICNSHardeningTests {
    private func icnsAsset(_ fixture: ProviderFixture) -> (IconAsset, URL) {
        var asset = fixture.asset
        asset.icnsFileName = "\(asset.id.uuidString).icns"
        return (asset, fixture.container.iconsDirectory.appending(path: asset.icnsFileName!))
    }

    private func leftovers(in directory: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasSuffix(".tmp") }
    }

    @Test func conversionLeavesNoTempFile() throws {
        let fixture = try ProviderFixture()
        let provider = LaunchServicesOverrideProvider(container: fixture.container, system: FakeLaunchServices(favoritePaths: []))
        let (asset, icns) = icnsAsset(fixture)

        #expect(try provider.icnsFile(for: asset) == icns)
        #expect(ICNSConverter.isUsableICNS(at: icns))
        #expect(try leftovers(in: fixture.container.iconsDirectory).isEmpty)
    }

    @Test func emptyOrUnreadableICNSIsRebuilt() throws {
        let fixture = try ProviderFixture()
        let provider = LaunchServicesOverrideProvider(container: fixture.container, system: FakeLaunchServices(favoritePaths: []))
        let (asset, icns) = icnsAsset(fixture)

        for junk in [Data(), Data("icns-but-truncated".utf8)] {
            try junk.write(to: icns)
            #expect(!ICNSConverter.isUsableICNS(at: icns))
            _ = try provider.icnsFile(for: asset)
            #expect(ICNSConverter.isUsableICNS(at: icns))
        }
        #expect(try leftovers(in: fixture.container.iconsDirectory).isEmpty)
    }

    @Test func validICNSIsReused() throws {
        let fixture = try ProviderFixture()
        let provider = LaunchServicesOverrideProvider(container: fixture.container, system: FakeLaunchServices(favoritePaths: []))
        let (asset, icns) = icnsAsset(fixture)
        _ = try provider.icnsFile(for: asset)
        let before = try FileManager.default.attributesOfItem(atPath: icns.path)[.systemFileNumber] as? Int

        _ = try provider.icnsFile(for: asset)

        let after = try FileManager.default.attributesOfItem(atPath: icns.path)[.systemFileNumber] as? Int
        #expect(before != nil && before == after)
    }

    @Test func failedConversionLeavesNoTempFileAndNoICNS() throws {
        let dir = try TemporaryDirectory()
        let bad = dir.url.appending(path: "bad.png")
        try Data("not an image".utf8).write(to: bad)
        let icns = dir.url.appending(path: "out.icns")
        #expect(throws: ICNSConversionError.self) { try ICNSConverter.convert(bad, to: icns) }
        #expect(!FileManager.default.fileExists(atPath: icns.path))
        #expect(try leftovers(in: dir.url).isEmpty)
    }
}
