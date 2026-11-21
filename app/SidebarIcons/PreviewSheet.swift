import AppKit
import SidebarIconCore
import SwiftUI

/// An image picked in Add Folder… or Change Icon…, waiting for the owner to apply or cancel it.
struct PendingIcon: Identifiable {
    enum Purpose {
        case add(folder: URL)
        case change(MappingRow)
    }

    let id = UUID()
    let purpose: Purpose
    let image: URL
    let advice: PreviewAdvice

    var folderName: String {
        switch purpose {
        case .add(let folder): folder.lastPathComponent
        case .change(let row): row.displayName
        }
    }
}

/// The preview before applying (Story 3, FR-007, research D9): the picked image as the sidebar
/// draws it, next to the folder name, at 16 and 20 pt on a light and a dark sidebar, with any
/// warnings. Warnings never block Apply; Cancel saves nothing.
struct PreviewSheet: View {
    let pending: PendingIcon
    let apply: () -> Void
    let cancel: () -> Void
    private let image: NSImage?

    init(pending: PendingIcon, apply: @escaping () -> Void, cancel: @escaping () -> Void) {
        self.pending = pending
        self.apply = apply
        self.cancel = cancel
        // The owner's original file, read once and never cached: it may change between picks.
        self.image = NSImage(contentsOf: pending.image)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Preview for \(pending.folderName)").font(.headline)
            HStack(spacing: 12) {
                ForEach([false, true], id: \.self) { dark in
                    VStack(alignment: .leading, spacing: 6) {
                        SidebarSample(image: image, name: pending.folderName, size: 16, dark: dark)
                        SidebarSample(image: image, name: pending.folderName, size: 20, dark: dark)
                    }
                    .padding(10)
                    .frame(width: 200, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8).fill(dark ? Color(white: 0.17) : Color(white: 0.93)))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(dark ? "Preview on a dark sidebar" : "Preview on a light sidebar")
                }
            }
            if image == nil {
                Label("This file can't be shown as an image; adding it will fail.", systemImage: "xmark.octagon.fill")
                    .foregroundStyle(.red)
            }
            ForEach(Array(pending.advice.warnings.enumerated()), id: \.offset) { _, warning in
                Label {
                    Text(warning.message).fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
                .font(.callout)
            }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: cancel)
                    .keyboardShortcut(.cancelAction)
                Button("Apply", action: apply)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 452)
    }
}

/// One sidebar row: the icon at `size` points and the folder name, in sidebar text colours.
private struct SidebarSample: View {
    let image: NSImage?
    let name: String
    let size: CGFloat
    let dark: Bool

    var body: some View {
        HStack(spacing: 6) {
            Group {
                if let image {
                    Image(nsImage: image).resizable().scaledToFit()
                } else {
                    Image(systemName: "questionmark.square.dashed").foregroundStyle(.secondary)
                }
            }
            .frame(width: size, height: size)
            Text(name)
                .font(.system(size: 13))
                .foregroundStyle(dark ? Color(white: 0.92) : Color(white: 0.1))
                .lineLimit(1)
            Text("\(Int(size)) pt")
                .font(.caption2)
                .foregroundStyle(dark ? Color(white: 0.6) : Color(white: 0.45))
        }
    }
}
