import Foundation
import ImageIO
import Testing
@testable import SidebarIconCore

/// A square PNG filled with one colour.
func writeSolidPNG(in directory: URL, name: String, pixels: Int, red: Double = 0.1, green: Double = 0.4, blue: Double = 0.9) throws -> URL {
    let context = try #require(CGContext(
        data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    context.setFillColor(CGColor(red: red, green: green, blue: blue, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: pixels, height: pixels))
    let url = directory.appending(path: name)
    let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
    CGImageDestinationAddImage(destination, try #require(context.makeImage()), nil)
    #expect(CGImageDestinationFinalize(destination))
    return url
}

/// 004 T035: folder art to `.icns` (research D7).
@Suite struct FolderArtBuilderTests {
    let dir: TemporaryDirectory
    init() throws { dir = try TemporaryDirectory() }

    /// (pixel size, dpi, red channel of the centre pixel) of every representation.
    private func representations(_ icns: URL) throws -> [(pixels: Int, dpi: Int, red: UInt8)] {
        let source = try #require(CGImageSourceCreateWithURL(icns as CFURL, nil))
        return try (0..<CGImageSourceGetCount(source)).map { index in
            let image = try #require(CGImageSourceCreateImageAtIndex(source, index, nil))
            let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] ?? [:]
            let dpi = (properties[kCGImagePropertyDPIWidth] as? Int) ?? 72
            let context = try #require(CGContext(
                data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            let centre = CGFloat(image.width) / 2
            context.draw(image, in: CGRect(x: -centre, y: -centre, width: CGFloat(image.width), height: CGFloat(image.height)))
            let red = context.data!.load(as: UInt8.self)
            return (image.width, dpi, red)
        }
    }

    @Test func aPNGMasterMakesTenRepresentations() throws {
        let master = try writeSolidPNG(in: dir.url, name: "master.png", pixels: 1024)
        let icns = dir.url.appending(path: "folder.icns")

        try FolderArtBuilder.build(master: master, overrides: [:], to: icns)

        let reps = try representations(icns)
        #expect(reps.count == 10)
        #expect(Set(reps.map(\.pixels)) == [16, 32, 64, 128, 256, 512, 1024])
    }

    @Test func vectorMastersAreAccepted() throws {
        let svg = dir.url.appending(path: "art.svg")
        try Data(##"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10"><rect width="10" height="10" fill="#1a66e6"/></svg>"##.utf8).write(to: svg)
        let icns = dir.url.appending(path: "svg.icns")

        try FolderArtBuilder.build(master: svg, overrides: [:], to: icns)

        #expect(try representations(icns).count == 10)
    }

    @Test func anOverrideReplacesExactlyItsRepresentation() throws {
        let master = try writeSolidPNG(in: dir.url, name: "master.png", pixels: 1024, red: 0.1)
        let small = try writeSolidPNG(in: dir.url, name: "red16.png", pixels: 16, red: 1, green: 0, blue: 0)
        let icns = dir.url.appending(path: "folder.icns")

        try FolderArtBuilder.build(master: master, overrides: ["icon_16x16": small], to: icns)

        let reps = try representations(icns)
        #expect(reps.count == 10)
        let red = reps.filter { $0.red > 200 }
        #expect(red.count == 1)
        #expect(red.first?.pixels == 16)
    }

    @Test func anIconsetIsReadByAppleNames() throws {
        let iconset = dir.url.appending(path: "art.iconset", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
        _ = try writeSolidPNG(in: iconset, name: "icon_16x16.png", pixels: 16)
        _ = try writeSolidPNG(in: iconset, name: "icon_16x16@2x.png", pixels: 32)
        _ = try writeSolidPNG(in: iconset, name: "icon_512x512@2x.png", pixels: 1024)
        try Data("notes".utf8).write(to: iconset.appending(path: "README.txt"))

        let found = try FolderArtBuilder.overrides(inIconset: iconset)

        #expect(Set(found.keys) == ["icon_16x16", "icon_16x16@2x", "icon_512x512@2x"])
    }

    @Test func aWrongPixelSizeIsRefused() throws {
        let iconset = dir.url.appending(path: "bad.iconset", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
        _ = try writeSolidPNG(in: iconset, name: "icon_32x32.png", pixels: 64)

        #expect(throws: FolderArtError.wrongSize(name: "icon_32x32.png", expected: 32, actualWidth: 64, actualHeight: 64)) {
            try FolderArtBuilder.overrides(inIconset: iconset)
        }
    }

    @Test func masterRules() throws {
        let small = try writeSolidPNG(in: dir.url, name: "small.png", pixels: 512)
        #expect(throws: FolderArtError.masterTooSmall(name: "small.png", pixels: 512)) { try FolderArtBuilder.checkMaster(small) }

        let wide = try writeTestPNG(in: dir.url, name: "wide.png", width: 2048, height: 1024)
        #expect(throws: FolderArtError.masterNotSquare(name: "wide.png", width: 2048, height: 1024)) { try FolderArtBuilder.checkMaster(wide) }

        let text = dir.url.appending(path: "notes.png")
        try Data("not an image".utf8).write(to: text)
        #expect(throws: FolderArtError.unsupportedMaster("notes.png")) { try FolderArtBuilder.checkMaster(text) }

        let empty = dir.url.appending(path: "empty.iconset", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        #expect(throws: FolderArtError.emptyIconset("empty.iconset")) { try FolderArtBuilder.overrides(inIconset: empty) }

        let png = try writeSolidPNG(in: dir.url, name: "x.png", pixels: 16)
        #expect(throws: FolderArtError.unknownSize("icon_20x20")) { try FolderArtBuilder.checkOverride(png, name: "icon_20x20") }
    }
}

/// The real writer's read-only checks, on a temporary folder (never `setIcon`).
@Suite struct SystemFolderIconWriterTests {
    @Test func detectsIconFileAndFinderInfoFlag() throws {
        let dir = try TemporaryDirectory()
        let folder = dir.url.appending(path: "Plain", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let writer = SystemFolderIconWriter()
        #expect(!writer.hasCustomIcon(at: folder))
        #expect(writer.fingerprint(of: folder) == nil)

        // The custom-icon flag alone (FinderInfo byte 8, 0x04).
        var info = [UInt8](repeating: 0, count: 32)
        info[8] = 0x04
        #expect(setxattr(folder.path, "com.apple.FinderInfo", &info, info.count, 0, 0) == 0)
        #expect(writer.hasCustomIcon(at: folder))

        // An Icon\r with a resource fork gets a fingerprint.
        let other = dir.url.appending(path: "WithIcon", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        let icon = other.appending(path: "Icon\r")
        try Data().write(to: icon)
        var fork = [UInt8](repeating: 7, count: 64)
        #expect(setxattr(icon.path, "com.apple.ResourceFork", &fork, fork.count, 0, 0) == 0)
        #expect(writer.hasCustomIcon(at: other))
        #expect(writer.fingerprint(of: other)?.count == 64)
    }
}
