import AppKit
import Foundation
import ImageIO
import Testing
@testable import SidebarIconCore

/// Writes a solid-color PNG of the given size and returns its URL.
func writeTestPNG(in directory: URL, name: String = "art.png", width: Int = 300, height: Int = 200) throws -> URL {
    let context = try #require(CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    context.setFillColor(CGColor(red: 0.1, green: 0.4, blue: 0.9, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let image = try #require(context.makeImage())
    let url = directory.appending(path: name)
    let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil)
    #expect(CGImageDestinationFinalize(destination))
    return url
}

@Suite struct IconRegistryBundleTests {
    let dir: TemporaryDirectory
    init() throws { dir = try TemporaryDirectory() }

    private func entries() -> [IconRegistryBundle.Entry] {
        let icns = dir.url.appending(path: "x.icns")
        return [
            .init(osType: "S002", assetID: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, icnsSource: icns),
            .init(osType: "S001", assetID: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, icnsSource: icns),
        ]
    }

    private func plist(_ data: Data) throws -> [String: Any] {
        try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }

    /// The shape the Finder sidebar draws in full colour on 26B131 (research R3, 2026-11-20).
    @Test func exportsOneTypeTaggedWithEachCode() throws {
        let info = try plist(IconRegistryBundle.infoPlist(for: entries()))
        #expect(info["CFBundleDocumentTypes"] == nil)
        let types = try #require(info["UTExportedTypeDeclarations"] as? [[String: Any]])
        #expect(types.map { $0["UTTypeIdentifier"] as? String } == [
            "com.altmansoftwaredesign.sidebaricons.icon.s001.00000000-0000-0000-0000-000000000001",
            "com.altmansoftwaredesign.sidebaricons.icon.s002.00000000-0000-0000-0000-000000000002",
        ])
        #expect(types.map { ($0["UTTypeTagSpecification"] as? [String: [String]])?["com.apple.ostype"] } == [["S001"], ["S002"]])
        let icons = types.map { $0["UTTypeIcons"] as? [String: String] }
        #expect(icons.map { $0?["UTTypeIconFile"] } == [
            "00000000-0000-0000-0000-000000000001.icns",
            "00000000-0000-0000-0000-000000000002.icns",
        ])
        #expect(icons.allSatisfy { $0?["UTTypeSymbolName"] == IconRegistryBundle.missingSymbolName })
        #expect(types.allSatisfy { $0["UTTypeIconFile"] == nil })
        #expect(types.allSatisfy { $0["UTTypeConformsTo"] as? [String] == ["public.data"] })
    }

    @Test func rejectsInvalidOrDuplicateCodes() {
        let icns = dir.url.appending(path: "x.icns")
        #expect(throws: SidebarIconError.self) {
            try IconRegistryBundle.infoPlist(for: [.init(osType: "PDF ", assetID: UUID(), icnsSource: icns)])
        }
        #expect(throws: SidebarIconError.self) {
            try IconRegistryBundle.infoPlist(for: [
                .init(osType: "S001", assetID: UUID(), icnsSource: icns),
                .init(osType: "S001", assetID: UUID(), icnsSource: icns),
            ])
        }
    }

    /// Icons are cached per type, so a new icon for the same code must get a new type.
    @Test func typeIdentifierChangesWithTheIcon() {
        let first = IconRegistryBundle.typeIdentifier(for: "S001", assetID: UUID())
        let second = IconRegistryBundle.typeIdentifier(for: "S001", assetID: UUID())
        #expect(first != second)
        #expect(first.hasPrefix("com.altmansoftwaredesign.sidebaricons.icon.s001."))
        #expect(first == first.lowercased())
    }

    @Test func versionChangesWithTheMapping() throws {
        let original = try plist(IconRegistryBundle.infoPlist(for: entries()))["CFBundleVersion"] as? String
        var changed = entries()
        changed[0].assetID = UUID(uuidString: "00000000-0000-0000-0000-000000000003")!
        let updated = try plist(IconRegistryBundle.infoPlist(for: changed))["CFBundleVersion"] as? String
        let dropped = try plist(IconRegistryBundle.infoPlist(for: [entries()[1]]))["CFBundleVersion"] as? String
        let version = try #require(original)
        #expect(UInt32(version) != nil)
        #expect(Set([original, updated, dropped]).count == 3)
    }

    @Test func usesTheApprovedIdentifierAndNeverLaunches() throws {
        let info = try plist(IconRegistryBundle.infoPlist(for: entries()))
        #expect(info["CFBundleIdentifier"] as? String == "com.altmansoftwaredesign.SidebarIcons.IconRegistry")
        #expect(info["CFBundlePackageType"] as? String == "APPL")
        #expect(info["LSUIElement"] as? Bool == true)
        #expect(info["CFBundleExecutable"] == nil)
    }

    @Test func outputIsDeterministic() throws {
        let first = try IconRegistryBundle.infoPlist(for: entries())
        let second = try IconRegistryBundle.infoPlist(for: entries().reversed())
        #expect(first == second)
    }

    @Test func writesACompleteBundleAndReplacesIt() throws {
        let png = try writeTestPNG(in: dir.url)
        let icns = dir.url.appending(path: "a.icns")
        try ICNSConverter.convert(png, to: icns)
        let bundle = dir.url.appending(path: "IconRegistry.app")
        let id = UUID()
        try IconRegistryBundle.write([.init(osType: "S001", assetID: id, icnsSource: icns)], to: bundle)
        let fileManager = FileManager.default
        #expect(fileManager.fileExists(atPath: bundle.appending(path: "Contents/Info.plist").path))
        #expect(fileManager.fileExists(atPath: bundle.appending(path: "Contents/Resources/\(id.uuidString).icns").path))

        let newID = UUID()
        try IconRegistryBundle.write([.init(osType: "S001", assetID: newID, icnsSource: icns)], to: bundle)
        #expect(!fileManager.fileExists(atPath: bundle.appending(path: "Contents/Resources/\(id.uuidString).icns").path))
        #expect(fileManager.fileExists(atPath: bundle.appending(path: "Contents/Resources/\(newID.uuidString).icns").path))
        let leftovers = try fileManager.contentsOfDirectory(atPath: dir.url.path).filter { $0.contains("staging") }
        #expect(leftovers.isEmpty)
    }
}

@Suite struct ICNSConverterTests {
    @Test func writesEverySizeAsSquareImages() throws {
        let dir = try TemporaryDirectory()
        let png = try writeTestPNG(in: dir.url, width: 1326, height: 1098)
        let icns = dir.url.appending(path: "out.icns")
        try ICNSConverter.convert(png, to: icns)

        let source = try #require(CGImageSourceCreateWithURL(icns as CFURL, nil))
        #expect(CGImageSourceGetType(source) as String? == "com.apple.icns")
        let sizes = (0..<CGImageSourceGetCount(source)).compactMap { index -> Int? in
            guard let image = CGImageSourceCreateImageAtIndex(source, index, nil) else { return nil }
            #expect(image.width == image.height)
            return image.width
        }
        #expect(Set(sizes) == Set(ICNSConverter.pixelSizes))
    }

    @Test func rejectsNonImages() throws {
        let dir = try TemporaryDirectory()
        let text = dir.url.appending(path: "note.png")
        try Data("hello".utf8).write(to: text)
        #expect(throws: ICNSConversionError.self) {
            try ICNSConverter.convert(text, to: dir.url.appending(path: "out.icns"))
        }
    }
}
