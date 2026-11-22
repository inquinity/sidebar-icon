import Foundation

public enum AssetImportError: Error, Sendable, Equatable {
    case unsupportedContent(String)
    case unreadable(String)
}

/// Copies a chosen image into the container's `Icons/` folder so the icon no longer depends on
/// the original file (spec US2-3). The original is only read, never moved or changed.
public enum AssetImporter {
    /// Detects the format from the file's bytes, not its extension.
    public static func detectFormat(of url: URL) throws -> IconAsset.SourceFormat {
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: url)
        } catch {
            throw AssetImportError.unreadable(url.lastPathComponent)
        }
        defer { try? handle.close() }
        let head = (try? handle.read(upToCount: 4096)) ?? Data()
        return try detectFormat(ofContent: head, name: url.lastPathComponent)
    }

    static func detectFormat(ofContent head: Data, name: String) throws -> IconAsset.SourceFormat {
        let bytes = [UInt8](head)
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]) { return .png }
        if bytes.starts(with: Array("%PDF-".utf8)) { return .pdf }
        if bytes.starts(with: Array("icns".utf8)) { return .icns }
        if let text = String(data: head, encoding: .utf8) ?? String(data: head, encoding: .isoLatin1) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if (trimmed.hasPrefix("<?xml") || trimmed.hasPrefix("<svg") || trimmed.hasPrefix("<!DOCTYPE svg")
                || trimmed.hasPrefix("<!--")) && text.contains("<svg") {
                return .svg
            }
        }
        throw AssetImportError.unsupportedContent(name)
    }

    /// Copies `source` to `Icons/<id>.<ext>` and returns the new asset. An existing file for the
    /// same id is replaced.
    public static func importFile(at source: URL, into iconsDirectory: URL, id: UUID = UUID()) throws -> IconAsset {
        let format = try detectFormat(of: source)
        let asset = IconAsset(id: id, sourceFormat: format)
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: iconsDirectory, withIntermediateDirectories: true)
        let destination = iconsDirectory.appending(path: asset.fileName)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        // Copy the file a link points to, never the link: the copy must not depend on the original
        // (FR-003; final review M-4).
        try fileManager.copyItem(at: source.resolvingSymlinksInPath(), to: destination)
        return asset
    }
}
