import Foundation

/// A change made outside the utility's own container. Written to the ledger before it is applied
/// and removed after it is undone (Constitution V, data-model.md).
public struct OutsideChange: Codable, Sendable, Hashable, Identifiable {
    public enum Kind: String, Codable, Sendable {
        /// `target` is the registration bundle's path.
        case iconRegistration
        /// `target` is the Favorite's folder path; `osType` is the code set on it.
        case sidebarOverride
        /// `target` is an opted-in folder whose own Finder icon was set (004 research D8);
        /// `fingerprint` and `backupFileName` say how to undo it.
        case folderIcon
    }

    public var id: UUID
    public var kind: Kind
    public var target: String
    public var osType: String?
    public var appliedAt: Date
    public var macOSBuild: String
    /// `folderIcon` only: SHA-256 of the folder's `Icon\r` resource fork after it was set. Undo
    /// touches the folder only while this still matches. Nil until the set succeeded.
    public var fingerprint: String?
    /// `folderIcon` only: the folder's earlier custom icon, in `FolderIconBackups/`.
    public var backupFileName: String?
    /// `folderIcon` only: the fingerprint just before the latest set (nil: no `Icon\r`). With
    /// `fingerprint` still nil it tells whether an interrupted set happened (review H1).
    public var previousFingerprint: String?
    /// `folderIcon` only: true when that earlier icon was also ours (a new picture replaced ours).
    public var previousIsOurs: Bool?

    public init(
        id: UUID = UUID(),
        kind: Kind,
        target: String,
        osType: String? = nil,
        appliedAt: Date = Date(),
        macOSBuild: String = SystemInfo.macOSBuild,
        fingerprint: String? = nil,
        backupFileName: String? = nil,
        previousFingerprint: String? = nil,
        previousIsOurs: Bool? = nil
    ) {
        self.id = id
        self.kind = kind
        self.target = target
        self.osType = osType
        self.appliedAt = appliedAt
        self.macOSBuild = macOSBuild
        self.fingerprint = fingerprint
        self.backupFileName = backupFileName
        self.previousFingerprint = previousFingerprint
        self.previousIsOurs = previousIsOurs
    }

    /// True when both describe the same effect, ignoring identity and timestamps.
    public func describesSameEffect(as other: OutsideChange) -> Bool {
        kind == other.kind && target == other.target && osType == other.osType
    }
}
