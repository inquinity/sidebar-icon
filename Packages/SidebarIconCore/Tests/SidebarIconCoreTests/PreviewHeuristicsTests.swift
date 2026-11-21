import AppKit
import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import SidebarIconCore

@Suite struct PreviewHeuristicsTests {
    let dir: TemporaryDirectory
    init() throws { dir = try TemporaryDirectory() }

    /// A 256-pixel PNG made of a 16 × 16 grid of random-colour blocks: still 256 different colours
    /// once shrunk to 16 px. (Per-pixel noise would average out to plain gray at that size.)
    private func writeNoisePNG(size: Int = 256) throws -> URL {
        var generator = SystemRandomNumberGenerator()
        let block = size / 16
        var colours: [[UInt8]] = []
        for _ in 0..<256 { colours.append((0..<3).map { _ in UInt8.random(in: 0...255, using: &generator) }) }
        var pixels = [UInt8](repeating: 255, count: size * size * 4)
        for y in 0..<size {
            for x in 0..<size {
                let colour = colours[(y / block) * 16 + x / block]
                for channel in 0..<3 { pixels[(y * size + x) * 4 + channel] = colour[channel] }
            }
        }
        let provider = try #require(CGDataProvider(data: Data(pixels) as CFData))
        let image = try #require(CGImage(
            width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: size * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        ))
        let url = dir.url.appending(path: "noise.png")
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return url
    }

    @Test func simpleSquareImageHasNoWarnings() throws {
        let png = try writeTestPNG(in: dir.url, name: "square.png", width: 256, height: 256)
        #expect(PreviewAdvice.evaluate(imageAt: png).warnings.isEmpty)
    }

    @Test(arguments: [(300, 200), (200, 300), (100, 79)])
    func aspectRatioOutsideTheRangeWarns(width: Int, height: Int) throws {
        let png = try writeTestPNG(in: dir.url, name: "wide.png", width: width, height: height)
        let warnings = PreviewAdvice.evaluate(imageAt: png).warnings
        #expect(warnings == [.notSquare(width: width, height: height)])
    }

    @Test(arguments: [(100, 80), (100, 125), (125, 100)])
    func aspectRatioInsideTheRangeIsFine(width: Int, height: Int) throws {
        let png = try writeTestPNG(in: dir.url, name: "near.png", width: width, height: height)
        #expect(PreviewAdvice.evaluate(imageAt: png).warnings.isEmpty)
    }

    @Test func highDetailAtSixteenPixelsWarns() throws {
        let warnings = PreviewAdvice.evaluate(imageAt: try writeNoisePNG()).warnings
        guard case .tooDetailed(let clusters)? = warnings.first else {
            Issue.record("expected a detail warning, got \(warnings)"); return
        }
        #expect(clusters > PreviewAdvice.detailClusterLimit)
    }

    /// A 16 × 16 PNG of four flat quadrants with the given alpha (0–1) each.
    private func writeQuadrantPNG(alphas: [CGFloat]) throws -> URL {
        let context = try #require(CGContext(
            data: nil, width: 16, height: 16, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let colours: [(CGFloat, CGFloat, CGFloat)] = [(0.9, 0.1, 0.1), (0.1, 0.8, 0.2), (0.1, 0.2, 0.9), (0.95, 0.85, 0.1)]
        for (index, colour) in colours.enumerated() {
            context.setFillColor(CGColor(red: colour.0, green: colour.1, blue: colour.2, alpha: alphas[index]))
            context.fill(CGRect(x: (index % 2) * 8, y: (index / 2) * 8, width: 8, height: 8))
        }
        let url = dir.url.appending(path: "quadrants-\(UUID().uuidString).png")
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try #require(context.makeImage()), nil)
        #expect(CGImageDestinationFinalize(destination))
        return url
    }

    /// Pins the pixel decoding (byte order, stride, un-premultiplying): four flat colours, one of
    /// them translucent, are exactly four clusters; pixels below the alpha cut-off are ignored.
    @Test func countsExactlyTheFlatColoursAtSixteenPixels() throws {
        let image = try #require(NSImage(contentsOf: try writeQuadrantPNG(alphas: [1, 1, 1, 0.85])))
        #expect(PreviewAdvice.colourClusters(in: image) == 4)
        let faint = try #require(NSImage(contentsOf: try writeQuadrantPNG(alphas: [0.5, 0.5, 0.5, 0.5])))
        #expect(PreviewAdvice.colourClusters(in: faint) == 0)
    }

    @Test func warningsNeverBlockAndHavePlainMessages() throws {
        let advice = PreviewAdvice.evaluate(imageAt: try writeNoisePNG())
        #expect(!advice.warnings.isEmpty)
        #expect(advice.warnings.allSatisfy { !$0.message.isEmpty })
        // An unreadable file gives no advice, never an error: Add reports it instead.
        let bad = dir.url.appending(path: "bad.png")
        try Data("nope".utf8).write(to: bad)
        #expect(PreviewAdvice.evaluate(imageAt: bad).warnings.isEmpty)
    }
}
