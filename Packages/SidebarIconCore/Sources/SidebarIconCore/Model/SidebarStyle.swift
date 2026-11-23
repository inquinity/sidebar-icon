import Foundation

/// How a mapping's Favorite is drawn in the sidebar (004 data-model.md, research D3).
public enum SidebarStyle: Codable, Sendable, Hashable {
    /// An SF Symbol by name, tinted like the system glyphs. Needs no tools.
    case systemSymbol(name: String)
    /// A custom glyph the owner made (manual process or wizard), compiled into the registry's
    /// `Assets.car`, tinted like the system glyphs.
    case customGlyph(glyphID: UUID)
    /// The 0.2.0 style: the copied image drawn in full colour.
    case fullColour(assetID: UUID)

    /// A short label for the list and the style picker.
    public var title: String {
        switch self {
        case .systemSymbol: "System glyph"
        case .customGlyph: "Custom glyph"
        case .fullColour: "Full colour"
        }
    }
}
