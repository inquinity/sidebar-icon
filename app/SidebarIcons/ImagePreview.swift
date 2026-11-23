import AppKit
import SidebarIconCore
import SwiftUI

/// An image picked on the Full colour tab, with its warnings (Story 3 of 002, research D9).
struct PickedImage: Equatable {
    let url: URL
    let advice: PreviewAdvice

    init(url: URL) {
        self.url = url
        self.advice = PreviewAdvice.evaluate(imageAt: url)
    }

    static func == (lhs: PickedImage, rhs: PickedImage) -> Bool { lhs.url == rhs.url }
}

/// The full-colour preview (FR-007 of 002, research D9): the picked image as the sidebar draws
/// it, next to the folder name, at 16 and 20 pt on a light and a dark sidebar, with any warnings.
/// Warnings never block Apply.
struct ImagePreview: View {
    let picked: PickedImage
    let folderName: String
    private let image: NSImage?

    init(picked: PickedImage, folderName: String) {
        self.picked = picked
        self.folderName = folderName
        // The owner's original file, read once and never cached: it may change between picks.
        self.image = NSImage(contentsOf: picked.url)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ForEach([false, true], id: \.self) { dark in
                    VStack(alignment: .leading, spacing: 6) {
                        SidebarSample(image: image, name: folderName, size: 16, dark: dark)
                        SidebarSample(image: image, name: folderName, size: 20, dark: dark)
                    }
                    .padding(10)
                    .frame(width: 200, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 8).fill(SidebarSwatch.fill(dark: dark)))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(dark ? "Preview on a dark sidebar" : "Preview on a light sidebar")
                }
            }
            if image == nil {
                Label("This file can't be shown as an image; adding it will fail.", systemImage: "xmark.octagon.fill")
                    .foregroundStyle(.red)
            }
            ForEach(Array(picked.advice.warnings.enumerated()), id: \.offset) { _, warning in
                Label {
                    Text(warning.message).fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
                .font(.callout)
            }
        }
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
                .foregroundStyle(SidebarSwatch.text(dark: dark))
                .lineLimit(1)
            Text("\(Int(size)) pt")
                .font(.caption2)
                .foregroundStyle(SidebarSwatch.secondaryText(dark: dark))
        }
    }
}
