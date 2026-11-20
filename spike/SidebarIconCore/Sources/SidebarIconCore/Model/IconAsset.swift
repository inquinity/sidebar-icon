import Foundation

/// An image file the utility owns, stored in `Icons/` inside the container (data-model.md).
public struct IconAsset: Codable, Sendable, Hashable, Identifiable {
    public enum SourceFormat: String, Codable, Sendable, CaseIterable {
        case pdf, png, svg, icns
    }

    public var id: UUID
    /// Taken from the file's content, not its extension.
    public var sourceFormat: SourceFormat
    /// `<id>.<ext>` inside `Icons/`.
    public var fileName: String
    /// `<id>.icns`, generated for Path B only.
    public var icnsFileName: String?

    public init(id: UUID, sourceFormat: SourceFormat, fileName: String? = nil, icnsFileName: String? = nil) {
        self.id = id
        self.sourceFormat = sourceFormat
        self.fileName = fileName ?? "\(id.uuidString).\(sourceFormat.rawValue)"
        self.icnsFileName = icnsFileName
    }
}
