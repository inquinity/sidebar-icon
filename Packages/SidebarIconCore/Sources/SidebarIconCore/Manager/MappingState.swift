import Foundation

/// The opted-in folder icon's status (004 data-model.md), shown as a row badge.
public enum FolderIconState: Sendable, Equatable {
    /// No folder icon is set (not opted in, or the mapping is off).
    case notSet
    /// The folder shows the icon the app set.
    case set
    /// Something else changed the folder's icon since; the app leaves it.
    case changedElsewhere
    /// The opt-in is on but the icon couldn't be set; the message says why.
    case failed(String)
    /// The icon is recorded but the folder can't be found; the record is kept until the folder is
    /// back, re-pointed or removed (not "changed elsewhere", research D8; final review 3).
    case folderMissing
}

/// A mapping's status as shown in the list (FR-008, research D7). Derived, never stored; computing
/// it is read-only.
public enum MappingState: Sendable, Equatable {
    /// The override is set to this mapping's code and the registry bundle is registered.
    case applied
    /// The mapping is turned off.
    case off
    /// The folder exists but is not in Finder's sidebar Favorites.
    case notInSidebar
    /// The folder does not exist.
    case folderMissing
    /// The folder is in Favorites but the override is absent, or the bundle is not registered.
    case notApplied
    /// A duplicate Favorite, another tool's override, unreadable Favorites, or the last apply
    /// failed for this mapping.
    case error(String)

    /// Whether Apply Now can help.
    public var offersApplyNow: Bool {
        switch self {
        case .notInSidebar, .notApplied, .error: true
        case .applied, .off, .folderMissing: false
        }
    }

    public static func state(
        for mapping: SidebarMapping,
        status: MappingStatus,
        bundleRegistered: Bool,
        lastFailure: String?
    ) -> MappingState {
        // A mapping turned off whose override could not be cleared is not really off.
        guard mapping.enabled else { return lastFailure.map { .error($0) } ?? .off }
        guard status.folderExists else { return .folderMissing }
        guard let count = status.favoriteCount else {
            return .error(SidebarIconError.favoritesUnavailable.message)
        }
        if count == 0 { return .notInSidebar }
        if count > 1 { return .error(SidebarIconError.folderInFavoritesMoreThanOnce(mapping.folderPath).message) }
        // The last apply's failure wins over a still-set override: the registry may no longer
        // declare the code (claimed elsewhere, unreadable icon). Failures are rebuilt on every apply.
        if let lastFailure { return .error(lastFailure) }
        if status.activeOverride == mapping.osType && bundleRegistered { return .applied }
        if let active = status.activeOverride, active != mapping.osType {
            return .error(SidebarIconError.foreignOverride(path: mapping.folderPath, code: active).message)
        }
        return .notApplied
    }
}
