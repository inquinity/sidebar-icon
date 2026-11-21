import AppKit
import UniformTypeIdentifiers

/// Add Folder…: choose a folder, then an image. Cancelling either step does nothing.
@MainActor
enum AddMappingFlow {
    static func run(model: AppModel) {
        let folderPanel = NSOpenPanel()
        folderPanel.title = "Choose a Folder"
        folderPanel.message = "Choose a folder that is in Finder's sidebar Favorites."
        folderPanel.prompt = "Choose Folder"
        folderPanel.canChooseDirectories = true
        folderPanel.canChooseFiles = false
        folderPanel.allowsMultipleSelection = false
        guard folderPanel.runModal() == .OK, let folder = folderPanel.url else { return }

        let imagePanel = NSOpenPanel()
        imagePanel.title = "Choose an icon for \(folder.lastPathComponent)"
        imagePanel.message = "Choose a PDF, PNG or SVG image. Sidebar Icons keeps its own copy."
        imagePanel.prompt = "Choose Icon"
        imagePanel.canChooseDirectories = false
        imagePanel.canChooseFiles = true
        imagePanel.allowsMultipleSelection = false
        imagePanel.allowedContentTypes = [.pdf, .png, .svg]
        guard imagePanel.runModal() == .OK, let image = imagePanel.url else { return }

        model.add(folder: folder, image: image)
    }
}
