import AppKit
import Foundation

/// Advice shown with the preview before an icon is applied (Story 3, research D9). It only warns;
/// it never blocks the choice.
public struct PreviewAdvice: Sendable, Equatable {
    public enum Warning: Sendable, Equatable {
        /// Width divided by height (in points) is outside `squareRange`; the sidebar fits it into a
        /// square.
        case notSquare(width: Int, height: Int)
        /// More than `detailClusterLimit` distinct colour clusters remain at 16 px.
        case tooDetailed(clusters: Int)

        public var message: String {
            switch self {
            case .notSquare:
                "This image is wider or taller than square; it is scaled to fit the sidebar's square icon and looks smaller."
            case .tooDetailed:
                "This image has a lot of detail; check the preview at sidebar size."
            }
        }
    }

    /// Aspect ratios (width / height) treated as square enough.
    public static let squareRange: ClosedRange<Double> = 0.8...1.25
    /// Distinct colour clusters at 16 × 16 above which the image counts as too detailed.
    public static let detailClusterLimit = 64

    public var warnings: [Warning]

    /// Reads the image and returns its warnings. An image that can't be read gives no warnings:
    /// adding it then fails with a clear message, so the preview never has to.
    public static func evaluate(imageAt url: URL) -> PreviewAdvice {
        guard let image = NSImage(contentsOf: url), image.size.width > 0, image.size.height > 0 else {
            return PreviewAdvice(warnings: [])
        }
        var warnings: [Warning] = []
        // Points, not pixels: the `.icns` renderer fits the image by its point size.
        let ratio = Double(image.size.width / image.size.height)
        if !squareRange.contains(ratio) {
            warnings.append(.notSquare(width: Int(image.size.width.rounded()), height: Int(image.size.height.rounded())))
        }
        if let clusters = colourClusters(in: image), clusters > detailClusterLimit {
            warnings.append(.tooDetailed(clusters: clusters))
        }
        return PreviewAdvice(warnings: warnings)
    }

    /// Renders the image at 16 × 16 the way the `.icns` is made, then counts distinct colours among
    /// the mostly opaque pixels, with each channel reduced to 8 levels.
    static func colourClusters(in image: NSImage) -> Int? {
        guard let render = try? ICNSConverter.render(image, size: 16),
              let data = render.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data)
        else { return nil }
        let bytesPerRow = render.bytesPerRow
        var clusters = Set<Int>()
        for y in 0..<render.height {
            for x in 0..<render.width {
                let pixel = bytes + y * bytesPerRow + x * 4
                let alpha = Int(pixel[3])
                guard alpha >= 200 else { continue }
                // Premultiplied RGBA: undo the alpha before reducing.
                let channels = (0..<3).map { min(255, Int(pixel[$0]) * 255 / alpha) >> 5 }
                clusters.insert(channels[0] << 6 | channels[1] << 3 | channels[2])
            }
        }
        return clusters.count
    }
}
