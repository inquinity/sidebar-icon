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
            data = try Data(contentsOf: url)
        } catch CocoaError.fileReadNoSuchFile {
            return []
        } catch {
            throw SidebarIconError.ledgerIOFailed(String(describing: error))
        }
        if data.isEmpty { return [] }
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
            try data.write(to: url, options: .atomic)
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
