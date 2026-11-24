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
                        Button("Folder Icon…") { model.openFolderIcon(for: row) }
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
            IconSwatch(row: row, glyphTemplate: model.templateURL(for: row.style), dark: false)
            IconSwatch(row: row, glyphTemplate: model.templateURL(for: row.style), dark: true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(row.displayName)
                    Text(styleLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(PathStandardizer.abbreviatingHome(row.folderPath))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if row.folderIconOptedIn || row.folderIcon != .notSet {
                FolderIconBadge(state: row.folderIcon)
            }
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

    private var styleLabel: String {
        switch row.style {
        case .systemSymbol(let name): "\(row.style.title): \(name)"
        case .customGlyph(let id): "\(row.style.title): \(model.glyphs.first { $0.id == id }?.name ?? "missing")"
        case .fullColour: row.style.title
        }
    }
}

/// The row's sidebar icon at 20 pt on a light or dark sidebar-coloured swatch (research D9):
/// a system glyph tinted with the accent colour like the sidebar draws it, or the copied image
/// in full colour.
struct IconSwatch: View {
    let row: MappingRow
    let glyphTemplate: URL?
    let dark: Bool

    var body: some View {
        Group {
            switch row.style {
            case .systemSymbol(let name):
                Image(systemName: name).resizable().scaledToFit().foregroundStyle(.tint)
            case .customGlyph:
                GlyphImage(template: glyphTemplate)
            case .fullColour:
                if let image = IconImageCache.image(for: row.iconFile) {
                    Image(nsImage: image).resizable().scaledToFit()
                } else {
                    Image(systemName: "questionmark.square.dashed").foregroundStyle(.secondary)
                }
            }
        }
        .frame(width: 20, height: 20)
        .padding(5)
        .background(RoundedRectangle(cornerRadius: 6).fill(SidebarSwatch.fill(dark: dark)))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
        .environment(\.colorScheme, dark ? .dark : .light)
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

/// The folder icon's status next to the row's state (004 Story 4).
struct FolderIconBadge: View {
    let state: FolderIconState

    var body: some View {
        Image(systemName: symbol)
            .foregroundStyle(tint)
            .help(help)
            .accessibilityLabel(help)
    }

    private var symbol: String {
        switch state {
        case .set: "folder.fill"
        case .notSet: "folder"
        case .changedElsewhere: "folder.badge.questionmark"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    private var tint: Color {
        switch state {
        case .set: .accentColor
        case .notSet: .secondary
        case .changedElsewhere: .orange
        case .failed: .red
        }
    }

    private var help: String {
        switch state {
        case .set: "Folder icon set"
        case .notSet: "Folder icon on, not set (the mapping is off)"
        case .changedElsewhere: "This folder's icon was changed by something else, so it was left as it is."
        case .failed(let message): message
        }
    }
}
