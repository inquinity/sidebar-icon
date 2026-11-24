import Foundation

/// The opt-in to set a folder's own Finder icon from full-colour art (004 data-model.md, FR-011).
public struct FolderIconSetting: Codable, Sendable, Hashable {
    public var enabled: Bool
    /// The master art (PNG of at least 1024 px, PDF or SVG).
    public var artAssetID: UUID
    /// Hand-tuned sizes keyed by `.iconset` file name without extension, for example `icon_16x16@2x`.
    public var overrideAssetIDs: [String: UUID]
    /// True only after the owner confirmed replacing the folder's existing custom icon (FR-013).
    public var replaceExisting: Bool
    /// The fingerprint of the icon the owner agreed to replace. Turning the mapping on again
    /// replaces only that icon (as put back by Off); any other needs a new yes (review M2).
    public var confirmedFingerprint: String?

    public init(enabled: Bool = true, artAssetID: UUID, overrideAssetIDs: [String: UUID] = [:], replaceExisting: Bool = false,
                confirmedFingerprint: String? = nil) {
        self.confirmedFingerprint = confirmedFingerprint
        self.enabled = enabled
        self.artAssetID = artAssetID
        self.overrideAssetIDs = overrideAssetIDs
        self.replaceExisting = replaceExisting
    }
}
