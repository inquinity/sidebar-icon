import Foundation

/// A change made outside the utility's own container. Written to the ledger before it is applied
/// and removed after it is undone (Constitution V, data-model.md).
public struct OutsideChange: Codable, Sendable, Hashable, Identifiable {
    public enum Kind: String, Codable, Sendable {
        /// `target` is the registration bundle's path.
        case iconRegistration
        /// `target` is the Favorite's folder path; `osType` is the code set on it.
        case sidebarOverride
    }

    public var id: UUID
    public var kind: Kind
    public var target: String
    public var osType: String?
    public var appliedAt: Date
    public var macOSBuild: String

    public init(
        id: UUID = UUID(),
        kind: Kind,
        target: String,
        osType: String? = nil,
        appliedAt: Date = Date(),
        macOSBuild: String = SystemInfo.macOSBuild
    ) {
        self.id = id
        self.kind = kind
        self.target = target
        self.osType = osType
        self.appliedAt = appliedAt
        self.macOSBuild = macOSBuild
    }

    /// True when both describe the same effect, ignoring identity and timestamps.
    public func describesSameEffect(as other: OutsideChange) -> Bool {
        kind == other.kind && target == other.target && osType == other.osType
    }
}
