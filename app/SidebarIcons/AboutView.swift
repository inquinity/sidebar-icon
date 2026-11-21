import AppKit
import SidebarIconCore
import SwiftUI

/// Replaces the standard About panel so it can name the private-API register (Constitution VI,
/// research D11).
struct AboutView: View {
    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "Version \(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            Text("Sidebar Icons").font(.title2.bold())
            Text(version).foregroundStyle(.secondary)
            Text("Sidebar Icons relies on undocumented macOS behavior to show custom icons in Finder's sidebar. Every such use is listed in PRIVATE_API.md in the project's source repository. Reset All removes every change the app made.")
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text("Engine \(SidebarIconCoreInfo.version) · \(SystemInfo.macOSDescription)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 380)
    }
}

/// The app menu's "About Sidebar Icons" item, opening `AboutView`.
struct AboutMenuItem: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("About Sidebar Icons") {
            openWindow(id: "about")
        }
    }
}
