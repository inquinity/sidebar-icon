import AppKit
import UniformTypeIdentifiers

/// The open panels for Add Folder…, Change Icon… and Re-point…. Cancelling any step does nothing.
@MainActor
enum AddMappingFlow {
    static func run(model: AppModel) {
        guard let folder = chooseFolder(), let image = chooseImage(for: folder.lastPathComponent) else { return }
        model.preview(image, for: .add(folder: folder))
    }

    static func chooseFolder(title: String = "Choose a Folder",
                             message: String = "Choose a folder that is in Finder's sidebar Favorites.") -> URL? {
        let panel = NSOpenPanel()
        panel.title = title
        panel.message = message
        panel.prompt = "Choose Folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func chooseImage(for folderName: String) -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Choose an icon for \(folderName)"
        panel.message = "Choose a PDF, PNG or SVG image. Sidebar Icons keeps its own copy."
        panel.prompt = "Choose Icon"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.pdf, .png, .svg]
        return panel.runModal() == .OK ? panel.url : nil
    }
}
