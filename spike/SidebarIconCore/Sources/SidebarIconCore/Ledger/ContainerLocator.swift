import Foundation
import Security

public enum ContainerError: Error, Sendable, Equatable {
    /// The running binary has no App Group entitlement ending in `appGroupSuffix` (unsigned build?).
    case appGroupEntitlementMissing
    case containerUnavailable(String)
}

/// Locates the utility's storage: `<App Group container>/Library/Application Support/SidebarIcons/`
/// (data-model.md, Container layout).
public struct ContainerLocator: Sendable {
    /// The App Group identifier without its team-ID prefix.
    public static let appGroupSuffix = "com.altmansoftwaredesign.SidebarIcons"

    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    public var iconsDirectory: URL { root.appending(path: "Icons", directoryHint: .isDirectory) }
    public var ledgerURL: URL { root.appending(path: "ledger.json", directoryHint: .notDirectory) }
    public var configURL: URL { root.appending(path: "config.json", directoryHint: .notDirectory) }
    /// Path B registration bundle, an application-type bundle that declares the icon types (see
    /// `IconRegistryBundle`).
    public var registryBundleURL: URL { root.appending(path: "IconRegistry.app", directoryHint: .isDirectory) }

    /// Creates the root and `Icons/` if they are missing.
    public func prepare() throws {
        try FileManager.default.createDirectory(at: iconsDirectory, withIntermediateDirectories: true)
    }

    /// The team-prefixed App Group identifier, read from this process's own signed entitlements so
    /// the team ID is never hard-coded.
    public static func appGroupIdentifierFromEntitlements() throws -> String {
        guard let task = SecTaskCreateFromSelf(nil),
              let value = SecTaskCopyValueForEntitlement(task, "com.apple.security.application-groups" as CFString, nil),
              let groups = value as? [String],
              let group = groups.first(where: { $0.hasSuffix("." + appGroupSuffix) })
        else {
            throw ContainerError.appGroupEntitlementMissing
        }
        return group
    }

    /// The locator for the signed app or extension that is running.
    public static func forRunningProcess() throws -> ContainerLocator {
        let group = try appGroupIdentifierFromEntitlements()
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else {
            throw ContainerError.containerUnavailable(group)
        }
        let root = container
            .appending(path: "Library/Application Support/SidebarIcons", directoryHint: .isDirectory)
        return ContainerLocator(root: root)
    }
}
