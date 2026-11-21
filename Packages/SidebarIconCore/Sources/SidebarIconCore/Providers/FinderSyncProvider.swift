import FinderSync
import Foundation

/// Path A: public Finder Sync API only (FR-005, research R1).
///
/// The Finder Sync extension watches the mapped folders (`directoryURLs`), but the SDK has no
/// per-folder sidebar-icon API, so `apply` and `reset` change nothing and say so. Experiment A1
/// records what Finder shows while the extension is enabled.
public struct FinderSyncProvider: SidebarIconProvider {
    public let mechanism = "finder-sync"

    public static let noPublicAPINote =
        "Finder Sync has no public sidebar-icon API (research R1); nothing was changed. "
        + "Record what the sidebar shows as experiment A1."

    public init() {}

    public func status(for mappings: [SidebarMapping]) async throws -> [MappingStatus] {
        let enabled = await MainActor.run { FIFinderSyncController.isExtensionEnabled }
        let note = enabled
            ? "Finder Sync extension enabled; the extension watches this folder."
            : "Finder Sync extension not enabled (System Settings → General → Login Items & Extensions)."
        return mappings.map { mapping in
            MappingStatus(
                mappingID: mapping.id,
                folderPath: mapping.folderPath,
                folderExists: FileManager.default.fileExists(atPath: mapping.folderPath),
                note: note
            )
        }
    }

    public func apply(_ mappings: [SidebarMapping], assets: [IconAsset]) async throws -> ApplyReport {
        var report = ApplyReport()
        report.notes.append(Self.noPublicAPINote)
        return report
    }

    public func reset() async throws -> ResetReport {
        var report = ResetReport()
        report.notes.append("Finder Sync makes no outside changes, so there is nothing to reset.")
        return report
    }
}
