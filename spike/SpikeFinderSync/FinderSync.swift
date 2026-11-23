import FinderSync
import SidebarIconCore
import os

/// Path A (FR-005, experiment A1): watch the two test folders with the public Finder Sync API.
/// The SDK has no per-folder sidebar-icon API (research R1), so this only sets `directoryURLs`
/// and logs; experiment A1 records what Finder shows.
///
/// The folder names repeat `SidebarIconSpike/SpikeMappings.swift`; the spike keeps no shared
/// configuration file (FR-010).
final class FinderSync: FIFinderSync {
    private static let folders = ["dev", "DevDocs"]
    private let logger = Logger(subsystem: "com.altmansoftwaredesign.sidebaricons", category: "FinderSync")

    override init() {
        super.init()
        // Expand from the real home: inside the sandbox, NSHomeDirectory() is the extension's container.
        let home = PathStandardizer.realHomeDirectory
        let roots = Set(Self.folders.map { URL(fileURLWithPath: home).appending(path: $0, directoryHint: .isDirectory) })
        FIFinderSyncController.default().directoryURLs = roots
        let paths = roots.map(\.path).sorted().joined(separator: ", ")
        logger.info("SpikeFinderSync loaded (SidebarIconCore \(SidebarIconCoreInfo.version, privacy: .public)); watching \(paths, privacy: .public)")
    }

    override func beginObservingDirectory(at url: URL) {
        logger.info("Finder began observing \(url.path, privacy: .public)")
    }

    override func endObservingDirectory(at url: URL) {
        logger.info("Finder ended observing \(url.path, privacy: .public)")
    }
}
