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
    /// Another glyph already has this name (004 US3 scenario 2).
    case glyphNameTaken(String)
    /// The wizard's drawing can't become a glyph; the reader's message says what to change.
    case drawingRefused(SVGReadError)
    /// The glyph no longer exists.
    case unknownGlyph
    /// The glyph is used by mappings and no replacement style was given (FR-010).
    case glyphInUse(String)
    /// A custom glyph couldn't be built; nothing was changed.
    case glyphBuild(GlyphBuildError)
    /// The folder has a custom icon that isn't ours; the owner must confirm replacing it (FR-013).
    case folderIconNeedsConfirmation(existing: Bool)
    /// macOS refused to change the folder's icon (for example a protected location).
    case folderIconFailed(String)
    /// The folder's current icon couldn't be saved, so it wasn't replaced.
    case folderIconBackupFailed(String)
    /// The app can't tell whether the folder's icon is still the one it set, so it left it.
    case folderIconUnverified(String)
    /// The path isn't a plain folder (for example a link), so its icon isn't touched.
    case folderIconUnsafe(String)
    /// The folder can't be found, so its icon wasn't set.
    case folderIconMissing(String)
    /// The folder art can't be used; the message says what to change.
    case folderArtRefused(FolderArtError)
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
        case .glyphNameTaken(let name):
            "You already have a glyph named \(name). Choose another name, or change that glyph's drawing instead."
        case .drawingRefused(let error):
            "\(error.message) Nothing was saved."
        case .unknownGlyph:
            "That glyph no longer exists."
        case .glyphInUse(let name):
            "The glyph \(name) is used by a folder; choose another style for it first."
        case .glyphBuild(let error):
            error.message
        case .folderIconNeedsConfirmation:
            "This folder already has a custom icon. Replace it? The current icon is kept and restored when you turn this off."
        case .folderIconFailed(let path):
            "macOS didn't allow changing \(PathStandardizer.abbreviatingHome(path)). Allow Sidebar Icons in System Settings › Privacy & Security › Files and Folders, then try again. The sidebar glyph is unaffected."
        case .folderIconBackupFailed(let path):
            "The current icon of \(PathStandardizer.abbreviatingHome(path)) couldn't be saved, so it wasn't replaced. Check that the disk has free space, then try again."
        case .folderIconUnverified(let path):
            "Sidebar Icons can't tell whether the icon of \(PathStandardizer.abbreviatingHome(path)) is still the one it set, so it left the folder as it is. In Get Info, select the folder's icon and press Delete to remove it, then try again; its earlier icon is put back if Sidebar Icons saved one."
        case .folderIconMissing(let path):
            "\(PathStandardizer.abbreviatingHome(path)) can't be found, so its folder icon wasn't set."
        case .folderIconUnsafe(let path):
            "\(PathStandardizer.abbreviatingHome(path)) isn't a plain folder (it may be a link), so its icon wasn't changed."
        case .folderArtRefused(let error):
            "\(error.message) Nothing was changed."
        case .sidebar(let error):
            error.message
        }
    }
}
