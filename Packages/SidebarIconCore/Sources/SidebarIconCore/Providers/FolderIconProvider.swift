import AppKit
import CryptoKit
import Foundation

/// The folder calls `FolderIconProvider` makes; faked in tests.
public protocol FolderIconWriting: Sendable {
    /// True when the folder has a custom icon: an `Icon\r` file or the Finder custom-icon flag.
    func hasCustomIcon(at folder: URL) -> Bool
    /// Saves the folder's current icon as an `.icns` (the backup before replacing it).
    func writeCurrentIcon(of folder: URL, to icns: URL) throws
    /// Sets the folder's icon from an `.icns`, or clears it with nil. False when macOS refused.
    func setIcon(_ icns: URL?, on folder: URL) -> Bool
    /// SHA-256 of the folder's `Icon\r` resource fork, or nil when there is none.
    func fingerprint(of folder: URL) -> String?
}

/// The real folder calls: `NSWorkspace.setIcon`, `NSWorkspace.icon(forFile:)`, the `FinderInfo`
/// flag and the `Icon\r` resource fork (public API; 004 research D8, spike S6).
public struct SystemFolderIconWriter: FolderIconWriting {
    public init() {}

    static let iconFileName = "Icon\r"
    static let customIconFlag: UInt16 = 0x0400

    public func hasCustomIcon(at folder: URL) -> Bool {
        if FileManager.default.fileExists(atPath: folder.appending(path: Self.iconFileName).path) { return true }
        var info = [UInt8](repeating: 0, count: 32)
        let count = getxattr(folder.path, "com.apple.FinderInfo", &info, info.count, 0, XATTR_NOFOLLOW)
        guard count >= 10 else { return false }
        return (UInt16(info[8]) << 8 | UInt16(info[9])) & Self.customIconFlag != 0
    }

    public func writeCurrentIcon(of folder: URL, to icns: URL) throws {
        try ICNSConverter.write(NSWorkspace.shared.icon(forFile: folder.path), to: icns)
    }

    public func setIcon(_ icns: URL?, on folder: URL) -> Bool {
        var image: NSImage?
        if let icns {
            guard let loaded = NSImage(contentsOf: icns) else { return false }
            image = loaded
        }
        return NSWorkspace.shared.setIcon(image, forFile: folder.path, options: [])
    }

    public func fingerprint(of folder: URL) -> String? {
        let path = folder.appending(path: Self.iconFileName).path
        let size = getxattr(path, "com.apple.ResourceFork", nil, 0, 0, XATTR_NOFOLLOW)
        guard size > 0, size <= 64 * 1024 * 1024 else { return nil }
        var data = Data(count: size)
        let read = data.withUnsafeMutableBytes { getxattr(path, "com.apple.ResourceFork", $0.baseAddress, size, 0, XATTR_NOFOLLOW) }
        guard read == size else { return nil }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// Why a folder icon couldn't be set or put back.
public enum FolderIconError: Error, Sendable, Equatable {
    /// The folder has a custom icon that isn't ours; replacing it needs the owner's yes (FR-013).
    case needsConfirmation
    /// macOS refused (for example a protected folder the app may not change).
    case setFailed(String)
    /// The folder's current icon couldn't be saved, so it wasn't replaced.
    case backupFailed(String)
    /// After setting, the app couldn't read back what it set, so it put the folder back; or an
    /// earlier set was interrupted and it can't tell whether the icon is ours (review H1).
    case unverified(String)
    /// The path is not a plain folder (a link, or not in stored form), so it is not touched.
    case unsafeTarget(String)
    /// The folder isn't there (moved or deleted).
    case folderMissing(String)
}

/// What undoing a folder icon did.
public enum FolderIconUndo: Sendable, Equatable {
    /// The earlier custom icon was put back.
    case restored
    /// The folder's plain icon was put back.
    case cleared
    /// The icon was changed by something else since, so the folder was left as it is (FR-014).
    case leftChangedElsewhere
    /// An interrupted set never reached the folder; the entry was dropped.
    case nothingWasSet
    /// The folder isn't there (moved or deleted). Nothing was changed and the entry is kept; the
    /// caller decides whether to keep waiting or forget it (review H2).
    case folderMissing
}

/// Sets and undoes an opted-in folder's own Finder icon (004 research D8). Every set is recorded in
/// the ledger before it happens (FR-015); undo touches the folder only while its icon is still the
/// one the app set, judged by the fingerprint. A backup is deleted only once the folder is back.
public struct FolderIconProvider: Sendable {
    let writer: any FolderIconWriting
    let ledger: LedgerStore
    let backupsDirectory: URL

    public init(writer: any FolderIconWriting, ledger: LedgerStore, backupsDirectory: URL) {
        self.writer = writer
        self.ledger = ledger
        self.backupsDirectory = backupsDirectory
    }

    /// The recorded folder icon for `folderPath`, if any.
    public func entry(for folderPath: String) throws -> OutsideChange? {
        try ledger.entries().first { $0.kind == .folderIcon && $0.target == folderPath }
    }

    /// Every recorded folder icon.
    public func entries() throws -> [OutsideChange] {
        try ledger.entries().filter { $0.kind == .folderIcon }
    }

    /// True when the folder shows the icon recorded in `entry` (nothing changed it since).
    public func isUnchanged(_ entry: OutsideChange) -> Bool {
        guard let recorded = entry.fingerprint else { return false }
        return writer.fingerprint(of: URL(fileURLWithPath: entry.target)) == recorded
    }

    /// The folder's current fingerprint (nil: no `Icon\r`).
    public func currentFingerprint(of folderPath: String) -> String? {
        writer.fingerprint(of: URL(fileURLWithPath: folderPath))
    }

    /// True when setting an icon on `folderPath` would replace a custom icon that isn't ours.
    public func needsConfirmation(folderPath: String) throws -> Bool {
        if let entry = try entry(for: folderPath), isUnchanged(entry) { return false }
        return writer.hasCustomIcon(at: URL(fileURLWithPath: folderPath))
    }

    /// Sets `icns` as the folder's icon. A custom icon that isn't ours is replaced only with
    /// `confirmReplace`, and is saved first so undo can put it back.
    @discardableResult
    public func set(_ icns: URL, on folderPath: String, confirmReplace: Bool) throws -> OutsideChange {
        try requireSafeTarget(folderPath, mustExist: true)
        try requirePlainBackupsDirectory()
        let folder = URL(fileURLWithPath: folderPath)
        let before = writer.fingerprint(of: folder)
        var change: OutsideChange
        var newBackup: URL?
        var reSet = false
        if let existing = try entry(for: folderPath) {
            guard existing.fingerprint != nil else { throw FolderIconError.unverified(folderPath) }
            if isUnchanged(existing) {
                // Ours already: a new picture replaces it; the original backup stays the one to restore.
                change = existing
                reSet = true
            } else {
                // Changed elsewhere since: that icon is the one to keep now, not ours or our backup.
                try forget(existing)
                change = OutsideChange(kind: .folderIcon, target: folderPath)
            }
        } else {
            change = OutsideChange(kind: .folderIcon, target: folderPath)
        }
        if !reSet, writer.hasCustomIcon(at: folder) {
            guard confirmReplace else { throw FolderIconError.needsConfirmation }
            let name = "\(change.id.uuidString).icns"
            let backup = backupsDirectory.appending(path: name)
            do {
                try FileManager.default.createDirectory(at: backupsDirectory, withIntermediateDirectories: true)
                try writer.writeCurrentIcon(of: folder, to: backup)
            } catch {
                try? FileManager.default.removeItem(at: backup)
                throw FolderIconError.backupFailed(folderPath)
            }
            change.backupFileName = name
            newBackup = backup
        }
        // The intent is recorded before the folder changes: no fingerprint yet, and what was there.
        change.fingerprint = nil
        change.previousFingerprint = before
        change.previousIsOurs = reSet
        do {
            if reSet {
                try ledger.update(change)
                guard writer.setIcon(icns, on: folder) else {
                    // Nothing changed: the entry describes our earlier icon again.
                    var restored = change
                    restored.fingerprint = before
                    try? ledger.update(restored)
                    throw FolderIconError.setFailed(folderPath)
                }
            } else {
                try ledger.record(change) {
                    guard writer.setIcon(icns, on: folder) else { throw FolderIconError.setFailed(folderPath) }
                }
            }
        } catch {
            if let newBackup { try? FileManager.default.removeItem(at: newBackup) }
            throw error
        }
        // Read back what was set. Without a fingerprint undo could never tell the icon is ours, so
        // the folder is put back now instead (review H1).
        guard let after = writer.fingerprint(of: folder) else {
            rollBack(change, on: folder)
            throw FolderIconError.unverified(folderPath)
        }
        change.fingerprint = after
        do {
            try ledger.update(change)
        } catch {
            rollBack(change, on: folder)
            throw error
        }
        return change
    }

    /// Puts the folder back after a set that can't be recorded: the backup or the plain icon, then
    /// the entry and backup go. Best effort; a failure leaves the entry for Reset All.
    private func rollBack(_ change: OutsideChange, on folder: URL) {
        let backup = backupURL(change).flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
        guard writer.setIcon(backup, on: folder) else { return }
        try? forget(change)
    }

    /// Puts the folder back: the backup or the plain icon if the folder still shows our icon.
    /// A folder changed elsewhere is left and the entry dropped; a missing folder is left and the
    /// entry kept (see `FolderIconUndo`). Throws when macOS refuses, when the path isn't a plain
    /// folder, or when an interrupted set left it unclear whether the icon is ours; the entry and
    /// backup stay then.
    public func undo(_ entry: OutsideChange) throws -> FolderIconUndo {
        let folder = URL(fileURLWithPath: entry.target)
        guard FileManager.default.fileExists(atPath: entry.target) else { return .folderMissing }
        try requireSafeTarget(entry.target, mustExist: true)
        try requirePlainBackupsDirectory()
        let current = writer.fingerprint(of: folder)
        var entry = entry
        if entry.fingerprint == nil {
            // An interrupted set (review H1, N1, N2): decide from what the folder shows now.
            if !writer.hasCustomIcon(at: folder) {
                // No custom icon at all (never set, or the owner removed it in Get Info, as the
                // message suggests): nothing of ours is left, so the folder gets its own icon back.
                let backup = backupURL(entry).flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
                if let backup {
                    var outcome = FolderIconUndo.nothingWasSet
                    try ledger.undo(entry) {
                        guard writer.setIcon(backup, on: folder) else { throw FolderIconError.setFailed(entry.target) }
                        outcome = .restored
                    }
                    removeBackup(entry)
                    return outcome
                }
                try forget(entry)
                return .nothingWasSet
            }
            // A readable icon equal to the one before: the set never reached the folder.
            guard let current, current == entry.previousFingerprint else { throw FolderIconError.unverified(entry.target) }
            if entry.previousIsOurs == true {
                entry.fingerprint = current
            } else {
                try forget(entry)
                return .nothingWasSet
            }
        }
        guard current == entry.fingerprint else {
            try forget(entry)
            return .leftChangedElsewhere
        }
        var outcome = FolderIconUndo.cleared
        try ledger.undo(entry) {
            if let backup = backupURL(entry), FileManager.default.fileExists(atPath: backup.path) {
                guard writer.setIcon(backup, on: folder) else { throw FolderIconError.setFailed(entry.target) }
                outcome = .restored
            } else {
                guard writer.setIcon(nil, on: folder) else { throw FolderIconError.setFailed(entry.target) }
            }
        }
        removeBackup(entry)
        return outcome
    }

    /// Drops an entry and its backup without touching the folder (changed elsewhere, or a missing
    /// folder the owner removed the mapping for).
    public func forget(_ entry: OutsideChange) throws {
        try requirePlainBackupsDirectory()
        try ledger.forget(entry)
        removeBackup(entry)
    }

    /// Re-point (review H2): when the folder moved and still shows our icon at `newPath`, the entry
    /// follows it, so the backup and undo keep working. Returns true when it moved.
    public func follow(_ oldPath: String, to newPath: String) throws -> Bool {
        guard var entry = try entry(for: oldPath), let recorded = entry.fingerprint,
              writer.fingerprint(of: URL(fileURLWithPath: newPath)) == recorded else { return false }
        try requireSafeTarget(newPath, mustExist: true)
        entry.target = newPath
        try ledger.update(entry)
        return true
    }

    /// Only a real folder in stored form, never a link, and never a link named `Icon\r` inside it
    /// (review L1, L2): a tampered ledger or a swapped path can't steer the app at another folder.
    func requireSafeTarget(_ path: String, mustExist: Bool) throws {
        guard PathStandardizer.isStoredForm(path) else { throw FolderIconError.unsafeTarget(path) }
        var info = stat()
        guard lstat(path, &info) == 0 else {
            if mustExist { throw FolderIconError.folderMissing(path) }
            return
        }
        guard info.st_mode & S_IFMT == S_IFDIR else { throw FolderIconError.unsafeTarget(path) }
        var iconInfo = stat()
        if lstat(path + "/Icon\r", &iconInfo) == 0, iconInfo.st_mode & S_IFMT == S_IFLNK {
            throw FolderIconError.unsafeTarget(path)
        }
    }

    private func requirePlainBackupsDirectory() throws {
        var info = stat()
        if lstat(backupsDirectory.path, &info) == 0, info.st_mode & S_IFMT != S_IFDIR {
            throw FolderIconError.unsafeTarget(backupsDirectory.path)
        }
    }

    /// The backup file, only for a plain file name: the ledger is trusted to name a file inside
    /// `FolderIconBackups/`, never a path elsewhere.
    func backupURL(_ entry: OutsideChange) -> URL? {
        guard let name = entry.backupFileName, !name.isEmpty, !name.hasPrefix("."),
              !name.contains("/"), name == (name as NSString).lastPathComponent else { return nil }
        return backupsDirectory.appending(path: name)
    }

    private func removeBackup(_ entry: OutsideChange) {
        if let backup = backupURL(entry) { try? FileManager.default.removeItem(at: backup) }
    }
}
