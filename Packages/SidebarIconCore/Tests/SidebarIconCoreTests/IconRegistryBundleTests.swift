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

    let assetOne = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    let versionOne = UUID(uuidString: "00000000-0000-0000-0000-0000000000a1")!

    /// One entry of each style (004 research D3).
    private func entries() -> [IconRegistryBundle.Entry] {
        let icns = dir.url.appending(path: "x.icns")
        return [
            .init(osType: "S003", style: .customGlyph(symbolName: "git-repo.\(versionOne.uuidString.lowercased())", versionID: versionOne)),
            .init(osType: "S002", style: .systemSymbol(name: "hammer")),
            .init(osType: "S001", assetID: assetOne, icnsSource: icns),
        ]
    }

    private func plist(_ data: Data) throws -> [String: Any] {
        try #require(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }

    @Test func declaresEachStyle() throws {
        let info = try plist(IconRegistryBundle.infoPlist(for: entries(), hash: "0123abcd"))
        #expect(info["CFBundleDocumentTypes"] == nil)
        let types = try #require(info["UTExportedTypeDeclarations"] as? [[String: Any]])
        #expect(types.map { $0["UTTypeIdentifier"] as? String } == [
            "com.altmansoftwaredesign.sidebaricons.icon.s001.00000000-0000-0000-0000-000000000001",
            "com.altmansoftwaredesign.sidebaricons.icon.s002.sf.hammer",
            "com.altmansoftwaredesign.sidebaricons.icon.s003.glyph.00000000-0000-0000-0000-0000000000a1",
        ])
        #expect(types.map { ($0["UTTypeTagSpecification"] as? [String: [String]])?["com.apple.ostype"] } == [["S001"], ["S002"], ["S003"]])
        let icons = types.map { $0["UTTypeIcons"] as? [String: String] }
        #expect(icons[0] == ["UTTypeIconFile": "00000000-0000-0000-0000-000000000001.icns",
                             "UTTypeSymbolName": IconRegistryBundle.missingSymbolName])
        #expect(icons[1] == ["UTTypeSymbolName": "hammer"])
        #expect(icons[2] == ["UTTypeSymbolName": "git-repo.00000000-0000-0000-0000-0000000000a1"])
        #expect(types.allSatisfy { $0["UTTypeConformsTo"] as? [String] == ["public.data"] })
    }

    @Test func rejectsInvalidOrDuplicateCodes() {
        #expect(throws: SidebarIconError.self) {
            try IconRegistryBundle.infoPlist(for: [.init(osType: "PDF ", style: .systemSymbol(name: "doc"))], hash: "00000000")
        }
        #expect(throws: SidebarIconError.self) {
            try IconRegistryBundle.infoPlist(for: [
                .init(osType: "S001", style: .systemSymbol(name: "doc")),
                .init(osType: "S001", style: .systemSymbol(name: "hammer")),
            ], hash: "00000000")
        }
    }

    /// Icons are cached per type, so a new icon or style for the same code must get a new type.
    @Test func typeIdentifierChangesWithTheStyle() {
        let icns = dir.url.appending(path: "x.icns")
        let keys = [
            IconRegistryBundle.Entry(osType: "S001", assetID: UUID(), icnsSource: icns).styleKey,
            IconRegistryBundle.Entry(osType: "S001", assetID: UUID(), icnsSource: icns).styleKey,
            IconRegistryBundle.Entry(osType: "S001", style: .systemSymbol(name: "hammer")).styleKey,
            IconRegistryBundle.Entry(osType: "S001", style: .customGlyph(symbolName: "a.b", versionID: UUID())).styleKey,
        ]
        #expect(Set(keys).count == 4)
        let identifier = IconRegistryBundle.typeIdentifier(for: "S001", styleKey: keys[2])
        #expect(identifier == identifier.lowercased())
    }

    @Test func contentHashNamesTheVersion() {
        let hash = IconRegistryBundle.contentHash(entries: entries(), assetsCar: Data("car".utf8))
        #expect(hash.count == 8 && hash.allSatisfy { "0123456789abcdef".contains($0) })
        #expect(IconRegistryBundle.contentHash(entries: entries().reversed(), assetsCar: Data("car".utf8)) == hash)
        #expect(IconRegistryBundle.contentHash(entries: entries(), assetsCar: Data("car2".utf8)) != hash)
        #expect(IconRegistryBundle.contentHash(entries: Array(entries().dropFirst()), assetsCar: Data("car".utf8)) != hash)
        #expect(IconRegistryBundle.bundleName(forHash: hash) == "IconRegistry-\(hash).app")
    }

    @Test func versionedIdentifierAndNeverLaunches() throws {
        let info = try plist(IconRegistryBundle.infoPlist(for: entries(), hash: "0123abcd"))
        #expect(info["CFBundleIdentifier"] as? String == "com.altmansoftwaredesign.sidebaricons.iconregistry.0123abcd")
        #expect(info["CFBundlePackageType"] as? String == "APPL")
        #expect(info["LSUIElement"] as? Bool == true)
        #expect(info["CFBundleExecutable"] == nil)
    }

    @Test func outputIsDeterministic() throws {
        let first = try IconRegistryBundle.infoPlist(for: entries(), hash: "0123abcd")
        let second = try IconRegistryBundle.infoPlist(for: entries().reversed(), hash: "0123abcd")
        #expect(first == second)
    }

    @Test func writesACompleteBundleWithTheCar() throws {
        let png = try writeTestPNG(in: dir.url)
        let icns = dir.url.appending(path: "a.icns")
        try ICNSConverter.convert(png, to: icns)
        let car = dir.url.appending(path: "Assets.car")
        try Data("not really a car".utf8).write(to: car)
        let bundle = dir.url.appending(path: "IconRegistry-0123abcd.app")
        let id = UUID()
        try IconRegistryBundle.write([.init(osType: "S001", assetID: id, icnsSource: icns),
                                      .init(osType: "S002", style: .systemSymbol(name: "hammer"))],
                                     assetsCar: car, hash: "0123abcd", to: bundle)
        let fileManager = FileManager.default
        #expect(fileManager.fileExists(atPath: bundle.appending(path: "Contents/Info.plist").path))
        #expect(fileManager.fileExists(atPath: bundle.appending(path: "Contents/Resources/\(id.uuidString).icns").path))
        #expect(try Data(contentsOf: bundle.appending(path: "Contents/Resources/Assets.car")) == Data("not really a car".utf8))
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
