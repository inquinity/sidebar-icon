import Foundation

/// A custom outline glyph owned by the app (004 data-model.md). Every change of the drawing gets a
/// new `versionID`, which is part of the compiled symbol name, so Finder never shows a stale glyph.
public struct CustomGlyph: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    /// Lowercase letters, digits, dots and hyphens; see `isValidName`.
    public var name: String
    public var versionID: UUID
    /// The owner's plain SVG, when the glyph was made by the wizard (`<versionID>.svg` in `Glyphs/`).
    public var sourceFileName: String?
    /// The symbol template compiled into the car (`<versionID>.template.svg` in `Glyphs/`).
    public var templateFileName: String

    public init(id: UUID = UUID(), name: String, versionID: UUID = UUID(), sourceFileName: String? = nil,
                templateFileName: String? = nil) {
        self.id = id
        self.name = name
        self.versionID = versionID
        self.sourceFileName = sourceFileName
        self.templateFileName = templateFileName ?? "\(versionID.uuidString.lowercased()).template.svg"
    }

    /// The symbol's name inside `Assets.car` and in the registry's `UTTypeSymbolName`.
    public var symbolName: String { "\(name).\(versionID.uuidString.lowercased())" }

    /// `^[a-z0-9][a-z0-9.-]{0,47}$`
    public static func isValidName(_ name: String) -> Bool {
        name.range(of: "^[a-z0-9][a-z0-9.-]{0,47}$", options: .regularExpression) != nil
    }
}
