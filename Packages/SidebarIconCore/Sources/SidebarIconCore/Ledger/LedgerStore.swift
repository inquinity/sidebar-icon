import Foundation

/// The change ledger, `ledger.json`. Every outside change is written here **before** it is made
/// and removed only after it is undone (Constitution V), so reset can always find it.
///
/// The store keeps no state in memory; every call reads and atomically rewrites the file.
public struct LedgerStore: Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    private struct File: Codable {
        var schemaVersion: Int
        var entries: [OutsideChange]
    }

    /// All entries. A missing or empty file is an empty ledger.
    public func entries() throws -> [OutsideChange] {
        let data: Data
        do {
            data = try ContainerFile.read(url)
        } catch CocoaError.fileReadNoSuchFile {
            return []
        } catch {
            throw SidebarIconError.ledgerIOFailed(String(describing: error))
        }
        // The writer always writes `{schemaVersion, entries}`, so an empty file means a write was
        // lost (for example power loss before the data reached the disk). Treating it as "nothing
        // recorded" would let Reset All succeed while overrides stay set, so it is an error.
        if data.isEmpty { throw SidebarIconError.ledgerIOFailed("ledger.json is empty; its records were lost") }
        do {
            return try Self.decoder.decode(File.self, from: data).entries
        } catch {
            throw SidebarIconError.ledgerIOFailed("ledger.json is unreadable: \(error)")
        }
    }

    /// Writes `change` to the ledger, then runs `apply`. If `apply` throws, the entry is removed
    /// again and the error is rethrown. If an entry describing the same effect already exists, it
    /// is kept (no duplicate is written) and `apply` still runs, so re-applying is idempotent.
    @discardableResult
    public func record<T>(_ change: OutsideChange, apply: () throws -> T) throws -> T {
        let existing = try entries()
        let alreadyRecorded = existing.contains { $0.describesSameEffect(as: change) }
        if !alreadyRecorded {
            try write(existing + [change])
        }
        do {
            return try apply()
        } catch {
            if !alreadyRecorded {
                try write(try entries().filter { $0.id != change.id })
            }
            throw error
        }
    }

    /// Replaces the entry with `change`'s id, for details learned after the change was made (a
    /// folder icon's fingerprint). Throws if there is no such entry.
    public func update(_ change: OutsideChange) throws {
        var all = try entries()
        guard let index = all.firstIndex(where: { $0.id == change.id }) else {
            throw SidebarIconError.ledgerIOFailed("no ledger entry \(change.id) to update")
        }
        all[index] = change
        try write(all)
    }

    /// Removes the entry with `change`'s id without undoing anything.
    public func forget(_ change: OutsideChange) throws {
        try write(try entries().filter { $0.id != change.id })
    }

    /// Runs `undo` for `change`, then removes the entry. If `undo` throws, the entry stays and the
    /// error is rethrown.
    public func undo(_ change: OutsideChange, using undo: () throws -> Void) throws {
        try undo()
        try write(try entries().filter { $0.id != change.id })
    }

    private func write(_ entries: [OutsideChange]) throws {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try Self.encoder.encode(File(schemaVersion: 1, entries: entries))
            // Temp file, forced to disk, then renamed over the ledger: a crash leaves either the old
            // or the new ledger, never a truncated one (as `ConfigStore.save`).
            // A new, uniquely named file that must not exist yet and is never a link (security
            // review L7): a planted `ledger.json.tmp` link can't redirect the write.
            let temp = url.deletingLastPathComponent().appending(path: ".\(url.lastPathComponent).\(UUID().uuidString).tmp")
            let fd = open(temp.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o644)
            guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
            do {
                try handle.write(contentsOf: data)
                _ = fcntl(fd, F_FULLFSYNC)
                try handle.close()
            } catch {
                try? FileManager.default.removeItem(at: temp)
                throw error
            }
            guard rename(temp.path, url.path) == 0 else {
                let code = POSIXErrorCode(rawValue: errno) ?? .EIO
                try? FileManager.default.removeItem(at: temp)
                throw POSIXError(code)
            }
        } catch {
            throw SidebarIconError.ledgerIOFailed(String(describing: error))
        }
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
