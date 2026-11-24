import AppKit
import ImageIO
import SidebarIconCore
import SwiftUI
import UniformTypeIdentifiers

/// Which mapping the folder icon sheet is for.
struct FolderArtRequest: Identifiable {
    let id = UUID()
    let rowID: UUID
    let folderName: String
    let folderPath: String
    /// The folder icon is on now, so the sheet offers Turn Off.
    let isOn: Bool
    /// Art chosen earlier (in the wizard), shown already picked.
    var master: URL?
}

/// The folder icon opt-in sheet (contracts/ui.md, 004 Story 4): master art, optional hand-tuned
/// small sizes, a preview at 16, 32, 128 and 512 pt, and the replace warning when the folder
/// already has a custom icon. Nothing is copied or changed until Set Folder Icon (or Replace).
struct FolderArtOptInView: View {
    let request: FolderArtRequest
    let model: AppModel
    let close: () -> Void

    @State private var master: URL?
    @State private var masterProblem: String?
    /// The master as a ≤ 1024-pixel image, loaded off the main actor once it passes the check.
    @State private var masterPreview: NSImage?
    @State private var overrides: [String: URL] = [:]
    @State private var overridesLabel: String?
    @State private var overridesProblem: String?
    @State private var needsConfirmation: Bool?
    @State private var working = false

    init(request: FolderArtRequest, model: AppModel, close: @escaping () -> Void) {
        self.request = request
        self.model = model
        self.close = close
        _master = State(initialValue: request.master)
    }

    private var canSet: Bool {
        master != nil && masterProblem == nil && overridesProblem == nil && needsConfirmation != nil && model.canChange && !working
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Use full-colour art as this folder's Finder icon").font(.headline)
            Text("Sidebar Icons will add a hidden file named Icon to the folder and mark the folder as having a custom icon. The folder's modification date changes. Git shows the file as untracked; sync services copy it. Turning this off, Remove and Reset All put the folder's icon back.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if needsConfirmation == true {
                Label("This folder already has a custom icon. Replace it? The current icon is kept and restored when you turn this off.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Button(master == nil ? "Choose Art…" : "Choose Other Art…") {
                        if let url = Self.chooseMaster() { pickMaster(url) }
                    }
                    if let master {
                        Text(master.lastPathComponent).font(.caption).foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                    } else {
                        Text("A 1024-pixel PNG, a PDF or an SVG.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let masterProblem {
                    Text(masterProblem).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                }
                HStack {
                    Button("Small Sizes…") { pickOverrides() }
                    if let overridesLabel {
                        Text(overridesLabel).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        Button("Clear") {
                            overrides = [:]
                            self.overridesLabel = nil
                            overridesProblem = nil
                        }
                        .buttonStyle(.link)
                    } else {
                        Text("Optional: hand-tuned PNGs or an .iconset folder.").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let overridesProblem {
                    Text(overridesProblem).font(.caption).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                }
            }

            if master != nil, masterProblem == nil, let masterPreview {
                FolderArtPreview(master: masterPreview, overrides: overrides)
            }

            if let error = model.lastError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button("Cancel", role: .cancel, action: close)
                    .keyboardShortcut(.cancelAction)
                if request.isOn {
                    Button("Turn Off") { submit(nil, confirm: false) }
                        .disabled(!model.canChange || working)
                }
                Spacer()
                if working { ProgressView().controlSize(.small) }
                if needsConfirmation == true {
                    Button("Replace", role: .destructive) { submitArt(confirm: true) }
                        .disabled(!canSet)
                } else {
                    Button("Set Folder Icon") { submitArt(confirm: false) }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!canSet)
                }
            }
        }
        .padding(20)
        .frame(width: 500)
        .task {
            needsConfirmation = await model.folderNeedsConfirmation(request.folderPath)
            if let master { pickMaster(master) }
        }
    }

    // MARK: - Actions

    private func submitArt(confirm: Bool) {
        guard let master else { return }
        submit(FolderArt(master: master, overrides: overrides), confirm: confirm)
    }

    private func submit(_ art: FolderArt?, confirm: Bool) {
        working = true
        model.setFolderIcon(art, forRow: request.rowID, confirmReplace: confirm) { succeeded in
            working = false
            if succeeded { close() }
        }
    }

    /// Checked off the main actor: a PDF or SVG is opened to see that it draws.
    private func pickMaster(_ url: URL) {
        master = url
        masterProblem = nil
        masterPreview = nil
        Task {
            let (problem, preview) = await Task.detached { () -> (String?, NSImage?) in
                do {
                    try FolderArtBuilder.checkMaster(url)
                    return (nil, Self.previewImage(url))
                } catch let error as FolderArtError {
                    return (error.message, nil)
                } catch {
                    return (error.localizedDescription, nil)
                }
            }.value
            guard master == url else { return }
            masterProblem = problem
            masterPreview = preview
        }
    }

    /// A downsampled copy (at most 1024 pixels) for the preview, so a huge file is decoded once,
    /// off the main actor, and never at full size (review L4).
    nonisolated static func previewImage(_ url: URL) -> NSImage? {
        if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
               kCGImageSourceCreateThumbnailFromImageAlways: true,
               kCGImageSourceThumbnailMaxPixelSize: 1024,
               kCGImageSourceCreateThumbnailWithTransform: true,
           ] as CFDictionary) {
            return NSImage(cgImage: thumbnail, size: NSSize(width: thumbnail.width, height: thumbnail.height))
        }
        // PDF and SVG: vector, drawn at the preview's size.
        return NSImage(contentsOf: url)
    }

    private func pickOverrides() {
        let panel = NSOpenPanel()
        panel.title = "Choose Small Sizes"
        panel.message = "Choose PNG files named like icon_16x16.png or icon_16x16@2x.png, or an .iconset folder."
        panel.prompt = "Choose"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.png, .folder]
        guard panel.runModal() == .OK else { return }
        do {
            var found: [String: URL] = [:]
            for url in panel.urls {
                if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    found.merge(try FolderArtBuilder.overrides(inIconset: url)) { _, new in new }
                } else {
                    let name = url.deletingPathExtension().lastPathComponent
                    try FolderArtBuilder.checkOverride(url, name: name)
                    found[name] = url
                }
            }
            overrides = found
            overridesLabel = found.count == 1 ? "1 size" : "\(found.count) sizes"
            overridesProblem = nil
        } catch let error as FolderArtError {
            overridesProblem = error.message
        } catch {
            overridesProblem = error.localizedDescription
        }
    }

    static func chooseMaster() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Choose Folder Art"
        panel.message = "Choose a full-colour PNG (at least 1024 pixels), PDF or SVG."
        panel.prompt = "Choose Art"
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.png, .pdf, .svg]
        return panel.runModal() == .OK ? panel.url : nil
    }
}

/// The art at 16, 32, 128 and 512 pt, as Finder lists, columns and icon view show it. A
/// hand-tuned size is shown where one was chosen. 512 pt is drawn smaller to fit the sheet.
private struct FolderArtPreview: View {
    let master: NSImage
    let overrides: [String: URL]

    var body: some View {
        let masterImage: NSImage? = master
        HStack(alignment: .bottom, spacing: 16) {
            ForEach([16, 32, 128], id: \.self) { points in
                sample(image(points, masterImage), points: points, shown: CGFloat(points))
            }
            sample(image(512, masterImage), points: 512, shown: 160)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(.background.secondary))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Folder icon preview at 16, 32, 128 and 512 points")
    }

    private func image(_ points: Int, _ masterImage: NSImage?) -> NSImage? {
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let name = scale > 1 ? "icon_\(points)x\(points)@2x" : "icon_\(points)x\(points)"
        let fallback = scale > 1 ? "icon_\(points)x\(points)" : "icon_\(points)x\(points)@2x"
        if let url = overrides[name] ?? overrides[fallback], let image = NSImage(contentsOf: url) { return image }
        return masterImage
    }

    private func sample(_ image: NSImage?, points: Int, shown: CGFloat) -> some View {
        VStack(spacing: 4) {
            Group {
                if let image {
                    Image(nsImage: image).resizable().interpolation(.high).scaledToFit()
                } else {
                    Image(systemName: "questionmark.square.dashed").resizable().scaledToFit().foregroundStyle(.secondary)
                }
            }
            .frame(width: shown, height: shown)
            Text(points == 512 ? "512 pt (smaller)" : "\(points) pt").font(.caption2).foregroundStyle(.secondary)
        }
    }
}
