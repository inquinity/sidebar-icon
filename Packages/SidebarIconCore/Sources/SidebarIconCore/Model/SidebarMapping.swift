import Foundation

/// One Finder sidebar Favorite paired with one icon (data-model.md).
public struct SidebarMapping: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    /// Absolute and standardized; see `PathStandardizer`.
    public var folderPath: String
    public var iconAssetID: UUID
    /// `S` plus three base-36 characters; see `OSTypeCode`.
    public var osType: String
    public var enabled: Bool

    public init(id: UUID = UUID(), folderPath: String, iconAssetID: UUID, osType: String, enabled: Bool = true) {
        self.id = id
        self.folderPath = folderPath
        self.iconAssetID = iconAssetID
        self.osType = osType
        self.enabled = enabled
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
