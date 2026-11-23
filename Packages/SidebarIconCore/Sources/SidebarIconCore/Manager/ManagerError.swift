import Foundation

/// Errors `MappingManager` and `ConfigStore` report to the app (contracts/mapping-manager.md).
public enum ManagerError: Error, Sendable, Equatable {
    /// D3: the app opens read-only, with Reset All available.
    case configUnreadable(String)
    case saveFailed(String)
    /// FR-004; names the existing mapping's folder.
    case duplicateFolder(existing: String)
    case notAFolder(String)
    /// The image could not be copied or converted; nothing was saved.
    case imageUnreadable(String)
    /// B1 fails: Add and Apply are disabled, Reset All is allowed.
    case favoritesUnavailable
    case readOnly
    /// Another action is still running.
    case busy
    case unknownMapping
    /// An SF Symbol name that doesn't exist on this Mac (FR-003).
    case unknownSymbol(String)
    /// A custom glyph name that breaks the naming rules (004 data-model.md).
    case invalidGlyphName(String)
    /// The glyph is used by mappings and no replacement style was given (FR-010).
    case glyphInUse(String)
    /// A custom glyph couldn't be built; nothing was changed.
    case glyphBuild(GlyphBuildError)
    /// The adapter's error, passed through with its message.
    case sidebar(SidebarIconError)

    public var message: String {
        switch self {
        case .configUnreadable(let detail):
            "Your mappings can't be loaded, so nothing will be changed. \(detail) Reset All still works."
        case .saveFailed(let detail):
            "Your mappings could not be saved: \(detail)"
        case .duplicateFolder(let existing):
            "\(PathStandardizer.abbreviatingHome(existing)) is already mapped. Change its icon instead."
        case .notAFolder(let path):
            "\(PathStandardizer.abbreviatingHome(path)) is not a folder."
        case .imageUnreadable(let name):
            "\(name) could not be read as an image (PDF, PNG or SVG). Nothing was saved."
        case .favoritesUnavailable:
            SidebarIconError.favoritesUnavailable.message
        case .readOnly:
            "Your mappings can't be loaded, so nothing will be changed. Reset All still works."
        case .busy:
            "Another action is still running; try again when it finishes."
        case .unknownSymbol(let name):
            "\"\(name)\" isn't a system glyph on this Mac."
        case .unknownMapping:
            "That mapping no longer exists."
        case .invalidGlyphName(let name):
            "\"\(name)\" can't be a glyph name: use lowercase letters, digits, dots and hyphens (up to 48), starting with a letter or digit."
        case .glyphInUse(let name):
            "The glyph \(name) is used by a folder; choose another style for it first."
        case .glyphBuild(let error):
            error.message
        case .sidebar(let error):
            error.message
        }
    }
}
