import AppKit
import ImageIO

/// Why folder art can't be used. Each message says what to change.
public enum FolderArtError: Error, Sendable, Equatable {
    case unreadable(String)
    /// Only PNG, PDF and SVG masters are accepted (FR-012).
    case unsupportedMaster(String)
    case masterTooSmall(name: String, pixels: Int)
    case masterNotSquare(name: String, width: Int, height: Int)
    /// Bigger than the app decodes (security review L6): a few MB of PNG can decode to gigabytes.
    case masterTooLarge(name: String)
    /// A small size whose name is not one of Apple's `.iconset` names.
    case unknownSize(String)
    case wrongSize(name: String, expected: Int, actualWidth: Int, actualHeight: Int)
    case notPNG(String)
    case emptyIconset(String)

    public var message: String {
        switch self {
        case .unreadable(let name): "\(name) can't be read as an image."
        case .unsupportedMaster(let name): "\(name) isn't a PNG, PDF or SVG; folder art must be one of those."
        case .masterTooSmall(let name, let pixels):
            "\(name) is \(pixels) pixels; the master must be at least \(FolderArtBuilder.minimumMasterPixels) pixels square (or a PDF or SVG)."
        case .masterNotSquare(let name, let width, let height):
            "\(name) is \(width) × \(height) pixels; a PNG master must be square (1024 × 1024 or larger)."
        case .masterTooLarge(let name):
            "\(name) is too large; use art of at most \(FolderArtBuilder.maximumMasterPixels) pixels square and \(FolderArtBuilder.maximumFileSize / 1_048_576) MB."
        case .unknownSize(let name): "\(name) isn't an icon set size name (icon_16x16 … icon_512x512@2x)."
        case .wrongSize(let name, let expected, let width, let height):
            "\(name) is \(width) × \(height) pixels; it must be exactly \(expected) × \(expected)."
        case .notPNG(let name): "\(name) isn't a PNG; small sizes must be PNG images."
        case .emptyIconset(let name): "\(name) has no files named like icon_16x16.png."
        }
    }
}

/// Makes a folder's `.icns` from the owner's art (004 research D7): a master (PNG of at least
/// 1024 px, PDF or SVG) rendered at every size, with optional hand-tuned sizes that replace their
/// rendered representation. ImageIO only; `iconutil` isn't needed.
public enum FolderArtBuilder {
    /// One `.icns` representation, named as in an `.iconset` folder.
    public struct Slot: Sendable, Equatable {
        public let name: String
        public let pixels: Int
        public let dpi: Int
    }

    /// Apple's `.iconset` names, `icon_16x16` … `icon_512x512@2x`, in `.icns` order.
    public static let slots: [Slot] = [16, 32, 128, 256, 512].flatMap { points in
        [Slot(name: "icon_\(points)x\(points)", pixels: points, dpi: 72),
         Slot(name: "icon_\(points)x\(points)@2x", pixels: points * 2, dpi: 144)]
    }

    public static let minimumMasterPixels = 1024
    /// 8192 × 8192 decodes to 256 MB; larger art gains nothing at 512 pt @2x (1024 pixels).
    public static let maximumMasterPixels = 8192
    public static let maximumFileSize = 64 * 1_048_576

    /// Checks the master without loading it whole into the container.
    public static func checkMaster(_ url: URL) throws {
        let name = url.lastPathComponent
        if let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, size > maximumFileSize {
            throw FolderArtError.masterTooLarge(name: name)
        }
        let format: IconAsset.SourceFormat
        do {
            format = try AssetImporter.detectFormat(of: url)
        } catch {
            throw FolderArtError.unsupportedMaster(name)
        }
        switch format {
        case .png:
            guard let size = pixelSize(of: url) else { throw FolderArtError.unreadable(name) }
            guard size.width == size.height else {
                throw FolderArtError.masterNotSquare(name: name, width: size.width, height: size.height)
            }
            guard size.width >= minimumMasterPixels else { throw FolderArtError.masterTooSmall(name: name, pixels: size.width) }
            guard size.width <= maximumMasterPixels else { throw FolderArtError.masterTooLarge(name: name) }
        case .pdf, .svg:
            guard let image = NSImage(contentsOf: url), image.size.width > 0, image.size.height > 0 else {
                throw FolderArtError.unreadable(name)
            }
        case .icns:
            throw FolderArtError.unsupportedMaster(name)
        }
    }

    /// Checks one hand-tuned size: a PNG of exactly the slot's pixel size.
    public static func checkOverride(_ url: URL, name: String) throws {
        guard let slot = slots.first(where: { $0.name == name }) else { throw FolderArtError.unknownSize(name) }
        guard (try? AssetImporter.detectFormat(of: url)) == .png else { throw FolderArtError.notPNG(url.lastPathComponent) }
        guard let size = pixelSize(of: url) else { throw FolderArtError.unreadable(url.lastPathComponent) }
        guard size.width == slot.pixels, size.height == slot.pixels else {
            throw FolderArtError.wrongSize(name: url.lastPathComponent, expected: slot.pixels,
                                           actualWidth: size.width, actualHeight: size.height)
        }
    }

    /// The hand-tuned sizes in an `.iconset` folder, by Apple's file names (`icon_16x16.png`, …).
    /// Other files are ignored; each size found is checked.
    public static func overrides(inIconset folder: URL) throws -> [String: URL] {
        var found: [String: URL] = [:]
        for slot in slots {
            let file = folder.appending(path: "\(slot.name).png")
            guard FileManager.default.fileExists(atPath: file.path) else { continue }
            try checkOverride(file, name: slot.name)
            found[slot.name] = file
        }
        guard !found.isEmpty else { throw FolderArtError.emptyIconset(folder.lastPathComponent) }
        return found
    }

    /// Writes the `.icns`: every slot rendered from `master`, except those in `overrides` (slot
    /// name → PNG), which are used as they are. Checks everything first.
    public static func build(master: URL, overrides: [String: URL], to destination: URL) throws {
        try checkMaster(master)
        for (name, url) in overrides { try checkOverride(url, name: name) }
        guard let image = NSImage(contentsOf: master), image.size.width > 0, image.size.height > 0 else {
            throw FolderArtError.unreadable(master.lastPathComponent)
        }
        var images: [(image: CGImage, dpi: Int)] = []
        var rendered: [Int: CGImage] = [:]
        for slot in slots {
            if let url = overrides[slot.name] {
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                      let override = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                    throw FolderArtError.unreadable(url.lastPathComponent)
                }
                images.append((override, slot.dpi))
            } else {
                let render = try rendered[slot.pixels] ?? ICNSConverter.render(image, size: slot.pixels)
                rendered[slot.pixels] = render
                images.append((render, slot.dpi))
            }
        }
        try ICNSConverter.write(images, to: destination)
    }

    /// Pixel width and height from the file's header, without decoding the image.
    static func pixelSize(of url: URL) -> (width: Int, height: Int)? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { return nil }
        return (width, height)
    }
}
