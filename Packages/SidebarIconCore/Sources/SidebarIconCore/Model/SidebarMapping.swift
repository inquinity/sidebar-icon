import Foundation

/// One Finder sidebar Favorite paired with its icon group (004 data-model.md).
public struct SidebarMapping: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    /// Absolute and standardized; see `PathStandardizer`.
    public var folderPath: String
    /// How the Favorite is drawn in the sidebar.
    public var sidebarStyle: SidebarStyle
    /// `S` plus three base-36 characters; see `OSTypeCode`. Stays the same across style changes.
    public var osType: String
    public var enabled: Bool
    /// The opt-in folder icon; nil means the folder itself is never touched.
    public var folderIcon: FolderIconSetting?

    public init(id: UUID = UUID(), folderPath: String, sidebarStyle: SidebarStyle, osType: String,
                enabled: Bool = true, folderIcon: FolderIconSetting? = nil) {
        self.id = id
        self.folderPath = folderPath
        self.sidebarStyle = sidebarStyle
        self.osType = osType
        self.enabled = enabled
        self.folderIcon = folderIcon
    }

    /// A full-colour mapping (the 0.2.0 style).
    public init(id: UUID = UUID(), folderPath: String, iconAssetID: UUID, osType: String, enabled: Bool = true) {
        self.init(id: id, folderPath: folderPath, sidebarStyle: .fullColour(assetID: iconAssetID), osType: osType, enabled: enabled)
    }

    /// The full-colour image's asset, or nil for the glyph styles.
    public var iconAssetID: UUID? {
        if case .fullColour(let assetID) = sidebarStyle { return assetID }
        return nil
    }

    /// Every asset this mapping needs: the full-colour image and the folder art with its sizes.
    public var referencedAssetIDs: Set<UUID> {
        var ids = Set<UUID>()
        if let iconAssetID { ids.insert(iconAssetID) }
        if let folderIcon {
            ids.insert(folderIcon.artAssetID)
            ids.formUnion(folderIcon.overrideAssetIDs.values)
        }
        return ids
    }

    /// The custom glyph this mapping draws, if any.
    public var glyphID: UUID? {
        if case .customGlyph(let glyphID) = sidebarStyle { return glyphID }
        return nil
    }
}

/// Problems that make a set of mappings unusable.
public enum MappingValidationError: Error, Sendable, Equatable {
    case pathNotStandardized(String)
    case duplicatePath(String)
    case invalidOSType(String)
    case duplicateOSType(String)
}

extension SidebarMapping {
    /// Checks the data-model rules: every path in stored form (`PathStandardizer.isStoredForm`;
    /// the filesystem is not consulted) and unique, every code well formed
    /// and unique. Returns every problem found, in mapping order.
    public static func validate(_ mappings: [SidebarMapping]) -> [MappingValidationError] {
        var problems: [MappingValidationError] = []
        var paths = Set<String>()
        var codes = Set<String>()
        for mapping in mappings {
            if !PathStandardizer.isStoredForm(mapping.folderPath) {
                problems.append(.pathNotStandardized(mapping.folderPath))
            }
            if !paths.insert(mapping.folderPath).inserted {
                problems.append(.duplicatePath(mapping.folderPath))
            }
            if !OSTypeCode.isValid(mapping.osType) {
                problems.append(.invalidOSType(mapping.osType))
            }
            if !codes.insert(mapping.osType).inserted {
                problems.append(.duplicateOSType(mapping.osType))
            }
        }
        return problems
    }
}
