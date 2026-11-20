import Foundation
import SidebarIconCore

/// The spike's two hard-coded mappings (FR-010, spec Assumptions). The Finder Sync extension
/// keeps its own copy of the two folder names in `SpikeFinderSync/FinderSync.swift`.
enum SpikeMappings {
    struct Definition {
        var folder: String
        var resource: String
        var mappingID: UUID
        var assetID: UUID
        var osType: String

        var folderPath: String { PathStandardizer.standardize("~/\(folder)") }
    }

    static let dev = Definition(
        folder: "dev",
        resource: "macOS-dev-folder-icon",
        mappingID: UUID(uuidString: "5B1C0DE0-0001-4000-8000-000000000001")!,
        assetID: UUID(uuidString: "5B1C0DE0-0001-4000-8000-0000000000A1")!,
        osType: "S001"
    )

    static let devDocs = Definition(
        folder: "DevDocs",
        resource: "git-repo-2-layers",
        mappingID: UUID(uuidString: "5B1C0DE0-0001-4000-8000-000000000002")!,
        assetID: UUID(uuidString: "5B1C0DE0-0001-4000-8000-0000000000A2")!,
        osType: "S002"
    )

    static let all = [dev, devDocs]

    /// Copies each bundled PNG into `Icons/` (once) so built-in and runtime icons are handled the
    /// same way, and returns the mappings for folders that exist. Missing folders are logged and
    /// skipped, never created.
    static func load(into container: ContainerLocator, log: (String) -> Void) -> (mappings: [SidebarMapping], assets: [IconAsset]) {
        var mappings: [SidebarMapping] = []
        var assets: [IconAsset] = []
        for definition in all {
            let asset = IconAsset(id: definition.assetID, sourceFormat: .png)
            let copy = container.iconsDirectory.appending(path: asset.fileName)
            if !FileManager.default.fileExists(atPath: copy.path) {
                guard let bundled = Bundle.main.url(forResource: definition.resource, withExtension: "png") else {
                    log("Bundled icon \(definition.resource).png is missing from the app; skipping ~/\(definition.folder).")
                    continue
                }
                do {
                    _ = try AssetImporter.importFile(at: bundled, into: container.iconsDirectory, id: definition.assetID)
                } catch {
                    log("Could not copy \(definition.resource).png into the container: \(error)")
                    continue
                }
            }
            assets.append(asset)

            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: definition.folderPath, isDirectory: &isDirectory), isDirectory.boolValue else {
                log("~/\(definition.folder) does not exist; it was skipped and not created.")
                continue
            }
            mappings.append(SidebarMapping(
                id: definition.mappingID,
                folderPath: definition.folderPath,
                iconAssetID: definition.assetID,
                osType: definition.osType
            ))
        }
        return (mappings, assets)
    }
}
