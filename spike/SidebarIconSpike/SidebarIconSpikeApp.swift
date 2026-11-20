import SwiftUI

/// Host app for the sidebar icon feasibility spike (feature 001).
///
/// It is not sandboxed so it can call the Launch Services APIs that Path B needs; see
/// `specs/001-sidebar-icon-spike/plan.md` (Complexity Tracking) and `PRIVATE_API.md`.
@main
struct SidebarIconSpikeApp: App {
    var body: some Scene {
        WindowGroup("Sidebar Icon Spike") {
            SpikeView()
        }
    }
}
