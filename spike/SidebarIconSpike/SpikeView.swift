import SidebarIconCore
import SwiftUI

/// Placeholder window. The experiment buttons (List Favorites, Apply A, Apply B, Use runtime icon,
/// Refresh Finder, Reset) and the status log arrive with the tasks in `tasks.md`.
struct SpikeView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sidebar Icon Spike")
                .font(.title2)
            Text("SidebarIconCore \(SidebarIconCoreInfo.version)")
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(minWidth: 420, minHeight: 240, alignment: .topLeading)
    }
}

#Preview {
    SpikeView()
}
