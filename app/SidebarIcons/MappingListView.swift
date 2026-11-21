import AppKit
import SidebarIconCore
import SwiftUI

/// The list of mappings with a light and dark preview, the folder, and its status.
struct MappingListView: View {
    let model: AppModel
    @State private var pendingRemoval: MappingRow?

    var body: some View {
        if model.rows.isEmpty, model.readOnlyReason != nil {
            ContentUnavailableView {
                Label("Mappings can't be shown", systemImage: "lock")
            } description: {
                Text("config.json can't be read, so its mappings aren't listed and nothing will be changed. Reset All undoes every recorded change and deletes the mappings and copied images.")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if model.rows.isEmpty {
            ContentUnavailableView {
                Label("No mappings yet", systemImage: "folder.badge.plus")
            } description: {
                Text("Add a folder that is in Finder's sidebar Favorites.")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(model.rows) { row in
                MappingRowView(row: row, model: model)
                    .contextMenu {
                        Button("Change Icon…") { model.changeIcon(for: row) }
                        if row.state == .folderMissing {
                            Button("Re-point…") { model.repoint(row) }
                        }
                        Divider()
                        Button("Remove…", role: .destructive) { pendingRemoval = row }
                    }
                    .disabled(!model.canChange)
            }
            .confirmationDialog(
                "Remove mapping?",
                isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }),
                presenting: pendingRemoval
            ) { row in
                Button("Remove", role: .destructive) { model.remove(row) }
                Button("Cancel", role: .cancel) {}
            } message: { row in
                Text("Remove the mapping for \(row.displayName)? The folder itself is not changed.")
            }
        }
    }
}

struct MappingRowView: View {
    let row: MappingRow
    let model: AppModel

    var body: some View {
        HStack(spacing: 10) {
            IconSwatch(file: row.iconFile, dark: false)
            IconSwatch(file: row.iconFile, dark: true)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.displayName)
                Text(PathStandardizer.abbreviatingHome(row.folderPath))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            StateBadge(state: row.state)
            if row.state == .folderMissing {
                Button("Re-point…") { model.repoint(row) }
                    .disabled(!model.canChange)
            } else if row.state.offersApplyNow {
                Button("Apply Now", action: model.applyNow)
                    .disabled(!model.canChange)
            }
            Toggle("On", isOn: Binding(get: { row.enabled }, set: { model.setEnabled($0, for: row) }))
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
                .disabled(!model.canChange)
                .help(row.enabled ? "Turn off: the folder shows its normal icon; the mapping is kept." : "Turn on")
                .accessibilityLabel("Use this icon")
        }
        .padding(.vertical, 2)
    }
}

/// The copied image at the sidebar's 20 pt size on a light or dark sidebar-coloured swatch
/// (research D9). The sidebar draws the `.icns` in full colour, so a plain render is faithful.
struct IconSwatch: View {
    let file: URL
    let dark: Bool

    var body: some View {
        Group {
            if let image = IconImageCache.image(for: file) {
                Image(nsImage: image).resizable().scaledToFit()
            } else {
                Image(systemName: "questionmark.square.dashed").foregroundStyle(.secondary)
            }
        }
        .frame(width: 20, height: 20)
        .padding(5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(dark ? Color(white: 0.17) : Color(white: 0.93))
        )
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
        .help(dark ? "Dark sidebar" : "Light sidebar")
        .accessibilityLabel(dark ? "Icon on a dark sidebar" : "Icon on a light sidebar")
    }
}

/// Copied images never change (a new pick gets a new file, research D5), so caching by path is safe.
@MainActor
enum IconImageCache {
    private static let cache = NSCache<NSURL, NSImage>()

    static func image(for url: URL) -> NSImage? {
        if let cached = cache.object(forKey: url as NSURL) { return cached }
        guard let image = NSImage(contentsOf: url) else { return nil }
        cache.setObject(image, forKey: url as NSURL)
        return image
    }
}

struct StateBadge: View {
    let state: MappingState

    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: symbol).foregroundStyle(color)
        }
        .font(.callout)
        .help(detail)
    }

    private var title: String {
        switch state {
        case .applied: "Applied"
        case .off: "Off"
        case .notInSidebar: "Not in sidebar"
        case .folderMissing: "Folder missing"
        case .notApplied: "Not applied"
        case .error: "Error"
        }
    }

    private var detail: String {
        switch state {
        case .applied: "The Favorite shows this icon."
        case .off: "This mapping is turned off."
        case .notInSidebar: "Drag the folder into Finder's sidebar Favorites, then click Apply Now."
        case .folderMissing: "The folder no longer exists."
        case .notApplied: "The Favorite doesn't have this icon yet. Click Apply Now."
        case .error(let reason): reason
        }
    }

    private var symbol: String {
        switch state {
        case .applied: "checkmark.circle.fill"
        case .off: "circle"
        case .notInSidebar, .notApplied: "circle.dashed"
        case .folderMissing, .error: "exclamationmark.triangle.fill"
        }
    }

    private var color: Color {
        switch state {
        case .applied: .green
        case .off: .secondary
        case .notInSidebar, .notApplied: .orange
        case .folderMissing, .error: .red
        }
    }
}
