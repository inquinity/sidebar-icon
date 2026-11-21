import Foundation

/// Reads and writes `config.json` in the container (research D3).
///
/// - A missing file is an empty configuration.
/// - Writes go to `config.json.tmp` first and then replace the file, so a crash never leaves a
///   half-written configuration.
/// - A file with an unknown `schemaVersion`, invalid JSON, or invalid contents throws
///   `ManagerError.configUnreadable` and is never overwritten; only `remove()` (Reset All) deletes it.
/// - On save, assets no mapping refers to are dropped, and their files in `Icons/` are deleted.
public struct ConfigStore: Sendable {
    public let container: ContainerLocator

    public init(container: ContainerLocator) {
        self.container = container
    }

    public var url: URL { container.configURL }
    var tempURL: URL { url.deletingLastPathComponent().appending(path: url.lastPathComponent + ".tmp") }

    private struct Header: Decodable {
        var schemaVersion: Int
    }

    public func load() throws -> AppConfiguration {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch CocoaError.fileReadNoSuchFile {
            return AppConfiguration()
        } catch {
            throw ManagerError.configUnreadable("config.json could not be read: \(error.localizedDescription)")
        }
        let decoder = JSONDecoder()
        let config: AppConfiguration
        do {
            let header = try decoder.decode(Header.self, from: data)
            guard header.schemaVersion <= AppConfiguration.currentSchemaVersion else {
                throw ManagerError.configUnreadable(
                    "config.json uses schema \(header.schemaVersion), written by a newer version of Sidebar Icons."
                )
            }
            config = try decoder.decode(AppConfiguration.self, from: data)
        } catch let error as ManagerError {
            throw error
        } catch {
            throw ManagerError.configUnreadable("config.json is not valid: \(error)")
        }
        if let problem = config.problems.first {
            throw ManagerError.configUnreadable("config.json is not valid: \(problem)")
        }
        return config
    }

    /// Saves `config`, then deletes the files of assets it no longer refers to. Returns the
    /// configuration as saved (pruned).
    @discardableResult
    public func save(_ config: AppConfiguration) throws -> AppConfiguration {
        if let problem = config.problems.first {
            throw ManagerError.configUnreadable("refusing to save an invalid configuration: \(problem)")
        }
        // Never overwrite a file this build cannot read (D3).
        let previous = try load()

        var pruned = config
        let referenced = Set(config.mappings.map(\.iconAssetID))
        pruned.assets = config.assets.filter { referenced.contains($0.id) }
        let removed = (config.assets + previous.assets).filter { !referenced.contains($0.id) }

        let fileManager = FileManager.default
        do {
            try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            if fileManager.fileExists(atPath: tempURL.path) {
                try fileManager.removeItem(at: tempURL)
            }
            try encoder.encode(pruned).write(to: tempURL)
            // Force the bytes to disk before the rename, so a power loss can't leave an empty file.
            let handle = try FileHandle(forWritingTo: tempURL)
            _ = fcntl(handle.fileDescriptor, F_FULLFSYNC)
            try handle.close()
            if fileManager.fileExists(atPath: url.path) {
                _ = try fileManager.replaceItemAt(url, withItemAt: tempURL)
            } else {
                try fileManager.moveItem(at: tempURL, to: url)
            }
        } catch {
            try? fileManager.removeItem(at: tempURL)
            throw ManagerError.saveFailed("config.json could not be saved: \(error.localizedDescription)")
        }

        // Only after the new file is in place, so a failed save never loses a referenced image.
        for asset in removed {
            deleteFiles(of: asset)
        }
        return pruned
    }

    /// Deletes the asset's copied image and converted icon from `Icons/`. Only plain file names
    /// are accepted, so stored data can never point the delete outside `Icons/`.
    public func deleteFiles(of asset: IconAsset) {
        guard !container.iconsDirectoryIsSymbolicLink else { return }
        for name in [asset.fileName, asset.icnsFileName].compactMap({ $0 })
        where LaunchServicesOverrideProvider.isPlainFileName(name) {
            try? FileManager.default.removeItem(at: container.iconsDirectory.appending(path: name))
        }
    }

    /// Deletes `config.json` whatever its contents (Reset All, FR-010).
    public func remove() throws {
        for file in [url, tempURL] where FileManager.default.fileExists(atPath: file.path) {
            do {
                try FileManager.default.removeItem(at: file)
            } catch {
                throw ManagerError.saveFailed("\(file.lastPathComponent) could not be deleted: \(error.localizedDescription)")
            }
        }
    }
}
