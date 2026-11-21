import Foundation

/// The owner's mappings and the icon assets they use, stored as `config.json` (data-model.md,
/// research D3).
public struct AppConfiguration: Codable, Sendable, Equatable {
    /// The only schema this build reads and writes. A file with a higher number was written by a
    /// newer build and is never overwritten.
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var mappings: [SidebarMapping]
    public var assets: [IconAsset]

    public init(mappings: [SidebarMapping] = [], assets: [IconAsset] = []) {
        self.schemaVersion = Self.currentSchemaVersion
        self.mappings = mappings
        self.assets = assets
    }

    /// Valid when `SidebarMapping.validate` returns no problems and every `iconAssetID` resolves.
    /// Returns a description of each problem; empty means valid.
    public var problems: [String] {
        var problems = SidebarMapping.validate(mappings).map { String(describing: $0) }
        let assetIDs = Set(assets.map(\.id))
        for mapping in mappings where !assetIDs.contains(mapping.iconAssetID) {
            problems.append("mapping for \(mapping.folderPath) refers to a missing icon")
        }
        return problems
    }

    public func asset(for mapping: SidebarMapping) -> IconAsset? {
        assets.first { $0.id == mapping.iconAssetID }
    }
}
