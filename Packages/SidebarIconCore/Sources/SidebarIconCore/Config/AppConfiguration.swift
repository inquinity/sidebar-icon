import Foundation

/// The owner's mappings, the icon assets and the custom glyphs, stored as `config.json` (schema 2,
/// 004 data-model.md). Schema 1 (0.2.0) is not migrated (004 research D1).
public struct AppConfiguration: Codable, Sendable, Equatable {
    /// The only schema this build reads and writes. A file with another number is never overwritten.
    public static let currentSchemaVersion = 2

    public var schemaVersion: Int
    public var mappings: [SidebarMapping]
    public var assets: [IconAsset]
    public var glyphs: [CustomGlyph]

    public init(mappings: [SidebarMapping] = [], assets: [IconAsset] = [], glyphs: [CustomGlyph] = []) {
        self.schemaVersion = Self.currentSchemaVersion
        self.mappings = mappings
        self.assets = assets
        self.glyphs = glyphs
    }

    /// Valid when `SidebarMapping.validate` returns no problems, every referenced asset and glyph
    /// resolves, and glyph names are valid and unique. Returns a description of each problem.
    public var problems: [String] {
        var problems = SidebarMapping.validate(mappings).map { String(describing: $0) }
        let assetIDs = Set(assets.map(\.id))
        let glyphIDs = Set(glyphs.map(\.id))
        for mapping in mappings {
            if !mapping.referencedAssetIDs.isSubset(of: assetIDs) {
                problems.append("mapping for \(mapping.folderPath) refers to a missing icon")
            }
            if let glyphID = mapping.glyphID, !glyphIDs.contains(glyphID) {
                problems.append("mapping for \(mapping.folderPath) refers to a missing glyph")
            }
            if case .systemSymbol(let name) = mapping.sidebarStyle, !SidebarStyle.isPlausibleSymbolName(name) {
                problems.append("mapping for \(mapping.folderPath) has an invalid glyph name")
            }
        }
        // Asset file names are derived from the ID, so a stored name can never point outside
        // Icons/ (security review L1).
        for asset in assets {
            let id = asset.id.uuidString
            if asset.fileName != "\(id).\(asset.sourceFormat.rawValue)"
                || (asset.icnsFileName.map { $0 != "\(id).icns" } ?? false) {
                problems.append("icon \(id) has unexpected file names")
            }
        }
        var names = Set<String>()
        for glyph in glyphs {
            if !CustomGlyph.isValidName(glyph.name) { problems.append("glyph name \"\(glyph.name)\" is not valid") }
            if !names.insert(glyph.name).inserted { problems.append("glyph name \"\(glyph.name)\" is used twice") }
            // File names are derived from the version, so a stored name can never point at
            // another file in Glyphs/ (for example the combined Assets.car).
            let version = glyph.versionID.uuidString.lowercased()
            if glyph.templateFileName != "\(version).template.svg"
                || (glyph.sourceFileName.map { $0 != "\(version).svg" } ?? false) {
                problems.append("glyph \"\(glyph.name)\" has unexpected file names")
            }
        }
        return problems
    }

    /// The full-colour image of a mapping, if it has one.
    public func asset(for mapping: SidebarMapping) -> IconAsset? {
        guard let assetID = mapping.iconAssetID else { return nil }
        return assets.first { $0.id == assetID }
    }

    public func glyph(_ id: UUID) -> CustomGlyph? {
        glyphs.first { $0.id == id }
    }
}
