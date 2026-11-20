import FinderSync
import SidebarIconCore
import os

/// Finder Sync extension for the spike. T018 sets `directoryURLs` to the two test folders;
/// until then it only logs that Finder loaded it.
final class FinderSync: FIFinderSync {
    private let logger = Logger(subsystem: "com.altmansoftwaredesign.SidebarIcons", category: "FinderSync")

    override init() {
        super.init()
        logger.info("SpikeFinderSync loaded (SidebarIconCore \(SidebarIconCoreInfo.version, privacy: .public))")
    }
}
