import AppKit
import ImageIO
import UniformTypeIdentifiers

public enum ICNSConversionError: Error, Sendable, Equatable {
    case unreadableImage(String)
    case renderFailed(Int)
    case writeFailed(String)
}

/// Converts a PDF, PNG, SVG, or ICNS file to an `.icns` file with ImageIO (research R4).
///
/// Each size is rendered from the source, so vector art stays sharp. Non-square art is scaled to
/// fit and centered on a transparent square canvas.
public enum ICNSConverter {
    /// The standard icon representations: point sizes 16, 32, 128, 256, 512, each at 1x (72 dpi)
    /// and 2x (144 dpi). ImageIO drops 2x-only pixel sizes (64, 1024) unless they are marked 144 dpi.
    static let representations: [(pixels: Int, dpi: Int)] = [16, 32, 128, 256, 512].flatMap {
        [($0, 72), ($0 * 2, 144)]
    }

    /// Distinct pixel sizes written to the `.icns`, 16 through 1024.
    public static let pixelSizes = Array(Set(representations.map(\.pixels))).sorted()

    public static func convert(_ source: URL, to destination: URL) throws {
        guard let image = NSImage(contentsOf: source), image.size.width > 0, image.size.height > 0 else {
            throw ICNSConversionError.unreadableImage(source.lastPathComponent)
        }
        var renders: [Int: CGImage] = [:]
        for size in pixelSizes {
            renders[size] = try render(image, size: size)
        }

        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let output = CGImageDestinationCreateWithURL(
            destination as CFURL, UTType.icns.identifier as CFString, representations.count, nil
        ) else {
            throw ICNSConversionError.writeFailed(destination.lastPathComponent)
        }
        for (pixels, dpi) in representations {
            let properties = [kCGImagePropertyDPIWidth: dpi, kCGImagePropertyDPIHeight: dpi] as CFDictionary
            CGImageDestinationAddImage(output, renders[pixels]!, properties)
        }
        guard CGImageDestinationFinalize(output) else {
            throw ICNSConversionError.writeFailed(destination.lastPathComponent)
        }
    }

    static func render(_ image: NSImage, size: Int) throws -> CGImage {
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                  space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else {
            throw ICNSConversionError.renderFailed(size)
        }
        context.clear(CGRect(x: 0, y: 0, width: size, height: size))
        context.interpolationQuality = .high

        let side = CGFloat(size)
        let scale = min(side / image.size.width, side / image.size.height)
        let drawSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let rect = CGRect(
            x: (side - drawSize.width) / 2, y: (side - drawSize.height) / 2,
            width: drawSize.width, height: drawSize.height
        )

        let previous = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.current = previous

        guard let result = context.makeImage() else { throw ICNSConversionError.renderFailed(size) }
        return result
    }
}
