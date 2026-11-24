import Foundation
import Security

public enum ContainerError: Error, Sendable, Equatable {
    /// The running binary has no App Group entitlement ending in `appGroupSuffix` (unsigned build?).
    case appGroupEntitlementMissing
    case containerUnavailable(String)
    /// The data folder or a folder above it in the container is a link (see `requireRealRoot`).
    case linkedRoot(String)
}

/// Locates the utility's storage: `<App Group container>/Library/Application Support/SidebarIcons/`
/// (data-model.md, Container layout).
public struct ContainerLocator: Sendable {
    /// The App Group identifier without its team-ID prefix.
    public static let appGroupSuffix = "com.altmansoftwaredesign.sidebaricons"

    public let root: URL
    /// The App Group container the root lives in, when known. Every folder from it down to the
    /// root must be a real directory (security review M1).
    public let groupContainer: URL?

    public init(root: URL, groupContainer: URL? = nil) {
        self.root = root
        self.groupContainer = groupContainer
    }

    /// Throws `ContainerError.linkedRoot` when the root, or any folder between the App Group
    /// container and it, is a symbolic link, or when the root resolves outside the container.
    /// A link there would send every read, write and deletion (Reset All included) into another
    /// folder, possibly one the app may write to only because the user chose it. A root that
    /// doesn't exist yet is fine.
    public func requireRealRoot() throws {
        var chain: [URL] = [root]
        if let groupContainer {
            let base = groupContainer.standardizedFileURL.pathComponents
            let parts = root.standardizedFileURL.pathComponents
            guard parts.count >= base.count, Array(parts.prefix(base.count)) == base else {
                throw ContainerError.linkedRoot(root.path)
            }
            chain = (base.count..<parts.count).map { end in
                URL(fileURLWithPath: NSString.path(withComponents: Array(parts.prefix(end + 1))))
            }
        }
        for folder in chain {
            var info = stat()
            guard lstat(folder.path, &info) == 0 else {
                if errno == ENOENT { return }
                throw ContainerError.linkedRoot(folder.path)
            }
            guard info.st_mode & S_IFMT == S_IFDIR else { throw ContainerError.linkedRoot(folder.path) }
        }
        if let groupContainer, let base = Self.realPath(groupContainer.path), let real = Self.realPath(root.path),
           !(real == base || real.hasPrefix(base + "/")) {
            throw ContainerError.linkedRoot(root.path)
        }
    }

    static func realPath(_ path: String) -> String? {
        guard let resolved = realpath(path, nil) else { return nil }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    public var iconsDirectory: URL { root.appending(path: "Icons", directoryHint: .isDirectory) }
    public var ledgerURL: URL { root.appending(path: "ledger.json", directoryHint: .notDirectory) }
    public var configURL: URL { root.appending(path: "config.json", directoryHint: .notDirectory) }
    /// 0.2.0's unversioned registration bundle. Since 0.3.0 each version has its own name (see
    /// `registryBundleURL(named:)`); this one is only ever removed.
    public var registryBundleURL: URL { root.appending(path: "IconRegistry.app", directoryHint: .isDirectory) }
    /// Custom glyph sources and templates, and the last combined `Assets.car`.
    public var glyphsDirectory: URL { root.appending(path: "Glyphs", directoryHint: .isDirectory) }
    /// Temporary asset catalogs while `actool` runs.
    public var buildDirectory: URL { root.appending(path: "Build", directoryHint: .isDirectory) }
    /// Previous custom folder icons, kept to restore them.
    public var folderIconBackupsDirectory: URL { root.appending(path: "FolderIconBackups", directoryHint: .isDirectory) }

    /// A registry bundle version (`IconRegistry-<hash>.app`), directly in the root.
    public func registryBundleURL(named name: String) -> URL {
        root.appending(path: name, directoryHint: .isDirectory)
    }

    /// True for a registry bundle of this utility: a real directory (not a link) named
    /// `IconRegistry.app` or `IconRegistry-<hash>.app`, directly in the root.
    public func isOwnRegistryBundle(path: String) -> Bool {
        let url = URL(fileURLWithPath: path)
        let name = url.lastPathComponent
        guard name == "IconRegistry.app" || (name.hasPrefix("IconRegistry-") && name.hasSuffix(".app")) else { return false }
        // `lsregister -dump` may spell the path through the /System/Volumes/Data firmlink.
        guard LaunchServicesOverrideProvider.samePath(url.deletingLastPathComponent().path, root.path) else { return false }
        return !isSymbolicLink(url)
    }

    public func isSymbolicLink(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true
    }

    /// True when `Icons/` is a symbolic link. A link planted in the shared App Group container could
    /// send copies, conversions and deletions elsewhere, so callers refuse to use it.
    public var iconsDirectoryIsSymbolicLink: Bool {
        (try? iconsDirectory.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true
    }

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
        return ContainerLocator(root: root, groupContainer: container)
    }
}
