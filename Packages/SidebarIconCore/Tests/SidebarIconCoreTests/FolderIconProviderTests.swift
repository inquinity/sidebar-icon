import Foundation
import Synchronization
import Testing
@testable import SidebarIconCore

/// A fake folder: an icon "file" per folder path whose fingerprint is its content.
final class FakeFolderIcons: FolderIconWriting {
    struct State {
        /// Folder path → the icon currently set (an identifying string), nil for plain.
        var icons: [String: String] = [:]
        var refuse = false
        /// Fingerprints can't be read (an unreadable resource fork).
        var blindFingerprints = false
        var calls: [String] = []
        /// What the ledger held when each set happened, to prove "recorded before set".
        var ledgerAtSet: [[OutsideChange]] = []
    }

    let state = Mutex(State())
    let ledger: LedgerStore?

    init(ledger: LedgerStore? = nil) { self.ledger = ledger }

    func preset(_ path: String, icon: String) { state.withLock { $0.icons[path] = icon } }
    func icon(_ path: String) -> String? { state.withLock { $0.icons[path] } }

    func hasCustomIcon(at folder: URL) -> Bool { icon(folder.path) != nil }

    func writeCurrentIcon(of folder: URL, to icns: URL) throws {
        try Data((icon(folder.path) ?? "plain").utf8).write(to: icns)
    }

    func setIcon(_ icns: URL?, on folder: URL) -> Bool {
        let recorded = (try? ledger?.entries()) ?? []
        return state.withLock { state in
            state.calls.append("set \(folder.lastPathComponent) \(icns?.lastPathComponent ?? "nil")")
            state.ledgerAtSet.append(recorded ?? [])
            if state.refuse { return false }
            if let icns {
                // Text test files by content; a real .icns by its bytes.
                let data = (try? Data(contentsOf: icns)) ?? Data()
                state.icons[folder.path] = String(data: data, encoding: .utf8) ?? "icns:\(data.count):\(data.hashValue)"
            } else {
                state.icons[folder.path] = nil
            }
            return true
        }
    }

    func fingerprint(of folder: URL) -> String? {
        if state.withLock({ $0.blindFingerprints }) { return nil }
        return icon(folder.path).map { "fp:\($0)" }
    }
}

/// 004 T036: setting and undoing a folder's own icon (research D8).
@Suite struct FolderIconProviderTests {
    let dir: TemporaryDirectory
    let ledger: LedgerStore
    let fake: FakeFolderIcons
    let provider: FolderIconProvider
    let folder: String
    let art: URL

    init() throws {
        dir = try TemporaryDirectory()
        ledger = LedgerStore(url: dir.url.appending(path: "ledger.json"))
        fake = FakeFolderIcons(ledger: ledger)
        provider = FolderIconProvider(writer: fake, ledger: ledger, backupsDirectory: dir.url.appending(path: "FolderIconBackups"))
        folder = PathStandardizer.standardize(dir.url.appending(path: "Projects").path)
        try FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        art = dir.url.appending(path: "art.icns")
        try Data("ours".utf8).write(to: art)
    }

    @Test func theEntryIsRecordedBeforeSetThenGetsTheFingerprint() throws {
        try provider.set(art, on: folder, confirmReplace: false)

        let atSet = fake.state.withLock { $0.ledgerAtSet }
        #expect(atSet.count == 1)
        #expect(atSet[0].map(\.kind) == [.folderIcon])
        #expect(atSet[0].first?.fingerprint == nil)
        let entry = try #require(try ledger.entries().first)
        #expect(entry.target == folder && entry.fingerprint == "fp:ours" && entry.backupFileName == nil)
        #expect(fake.icon(folder) == "ours")
    }

    @Test func anExistingCustomIconNeedsConfirmation() throws {
        fake.preset(folder, icon: "theirs")

        #expect(throws: FolderIconError.needsConfirmation) { try provider.set(art, on: folder, confirmReplace: false) }

        #expect(try ledger.entries().isEmpty)
        #expect(fake.icon(folder) == "theirs")
        #expect(try provider.needsConfirmation(folderPath: folder))
    }

    @Test func confirmingWritesABackupAndUndoRestoresIt() throws {
        fake.preset(folder, icon: "theirs")

        let entry = try provider.set(art, on: folder, confirmReplace: true)

        let backup = try #require(provider.backupURL(entry))
        #expect(try String(contentsOf: backup, encoding: .utf8) == "theirs")
        #expect(fake.icon(folder) == "ours")

        #expect(try provider.undo(entry) == .restored)
        #expect(fake.icon(folder) == "theirs")
        #expect(try ledger.entries().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: backup.path))
    }

    @Test func undoWithoutABackupClearsTheIcon() throws {
        let entry = try provider.set(art, on: folder, confirmReplace: false)

        #expect(try provider.undo(entry) == .cleared)
        #expect(fake.icon(folder) == nil)
        #expect(try ledger.entries().isEmpty)
    }

    @Test func aChangeMadeElsewhereIsLeftAlone() throws {
        let entry = try provider.set(art, on: folder, confirmReplace: false)
        fake.preset(folder, icon: "someone else")

        #expect(try provider.undo(entry) == .leftChangedElsewhere)
        #expect(fake.icon(folder) == "someone else")
        #expect(try ledger.entries().isEmpty)
    }

    @Test func aRefusedSetLeavesNoEntryAndNoBackup() throws {
        fake.preset(folder, icon: "theirs")
        fake.state.withLock { $0.refuse = true }

        #expect(throws: FolderIconError.setFailed(folder)) { try provider.set(art, on: folder, confirmReplace: true) }

        #expect(try ledger.entries().isEmpty)
        let backups = (try? FileManager.default.contentsOfDirectory(atPath: provider.backupsDirectory.path)) ?? []
        #expect(backups.isEmpty)
        #expect(fake.icon(folder) == "theirs")
    }

    @Test func settingAgainKeepsTheOriginalBackup() throws {
        fake.preset(folder, icon: "theirs")
        let first = try provider.set(art, on: folder, confirmReplace: true)
        let newer = dir.url.appending(path: "newer.icns")
        try Data("ours v2".utf8).write(to: newer)

        // Our own icon is not "someone else's": no confirmation, no second backup.
        let second = try provider.set(newer, on: folder, confirmReplace: false)

        #expect(second.id == first.id && second.backupFileName == first.backupFileName)
        #expect(second.fingerprint == "fp:ours v2")
        #expect(try ledger.entries().count == 1)
        #expect(try provider.undo(second) == .restored)
        #expect(fake.icon(folder) == "theirs")
    }

    @Test func aRefusedUndoKeepsTheEntry() throws {
        let entry = try provider.set(art, on: folder, confirmReplace: false)
        fake.state.withLock { $0.refuse = true }

        #expect(throws: FolderIconError.setFailed(folder)) { try provider.undo(entry) }

        #expect(try ledger.entries().count == 1)
    }

    @Test func anUnreadableFingerprintRollsBack() throws {
        fake.preset(folder, icon: "theirs")
        fake.state.withLock { $0.blindFingerprints = true }

        #expect(throws: FolderIconError.unverified(folder)) { try provider.set(art, on: folder, confirmReplace: true) }

        // Put back from the backup; no entry, no backup left.
        #expect(fake.icon(folder) == "theirs")
        #expect(try ledger.entries().isEmpty)
        #expect(((try? FileManager.default.contentsOfDirectory(atPath: provider.backupsDirectory.path)) ?? []).isEmpty)
    }

    @Test func anInterruptedSetThatNeverHappenedIsDropped() throws {
        // As left by a crash after recording and before setIcon: no fingerprint, nothing before.
        let entry = OutsideChange(kind: .folderIcon, target: folder, previousFingerprint: nil, previousIsOurs: false)
        try ledger.record(entry) {}

        #expect(try provider.undo(entry) == .nothingWasSet)
        #expect(try ledger.entries().isEmpty)
    }

    @Test func anInterruptedSetThatHappenedIsKeptWithItsBackup() throws {
        // A crash after setIcon and before the fingerprint was stored: the icon may be ours.
        let backups = provider.backupsDirectory
        try FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true)
        try Data("theirs".utf8).write(to: backups.appending(path: "b.icns"))
        let entry = OutsideChange(kind: .folderIcon, target: folder, backupFileName: "b.icns",
                                  previousFingerprint: "fp:theirs", previousIsOurs: false)
        try ledger.record(entry) {}
        fake.preset(folder, icon: "ours")

        #expect(throws: FolderIconError.unverified(folder)) { try provider.undo(entry) }
        #expect(try ledger.entries().count == 1)
        #expect(FileManager.default.fileExists(atPath: backups.appending(path: "b.icns").path))
        // And it is never re-set over, nor its backup replaced.
        #expect(throws: FolderIconError.unverified(folder)) { try provider.set(art, on: folder, confirmReplace: true) }
    }

    @Test func clearingTheIconInGetInfoReleasesAnInterruptedSet() throws {
        // Review N1: the advice in the message (remove the icon in Get Info) must unlock the folder,
        // and the saved original comes back.
        let backups = provider.backupsDirectory
        try FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true)
        try Data("theirs".utf8).write(to: backups.appending(path: "b.icns"))
        let entry = OutsideChange(kind: .folderIcon, target: folder, backupFileName: "b.icns",
                                  previousFingerprint: "fp:theirs", previousIsOurs: false)
        try ledger.record(entry) {}
        fake.preset(folder, icon: "ours")
        #expect(throws: FolderIconError.unverified(folder)) { try provider.undo(entry) }

        fake.state.withLock { $0.icons[folder] = nil }   // Get Info › Delete

        #expect(try provider.undo(entry) == .restored)
        #expect(fake.icon(folder) == "theirs")
        #expect(try ledger.entries().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: backups.appending(path: "b.icns").path))
    }

    @Test func anUnreadableIconIsNeverTakenForNothingSet() throws {
        // Review N2: no fingerprint before and none readable now, but a custom icon is there.
        let entry = OutsideChange(kind: .folderIcon, target: folder, previousFingerprint: nil, previousIsOurs: false)
        try ledger.record(entry) {}
        fake.preset(folder, icon: "ours")
        fake.state.withLock { $0.blindFingerprints = true }

        #expect(throws: FolderIconError.unverified(folder)) { try provider.undo(entry) }
        #expect(try ledger.entries().count == 1)
    }

    @Test func anInterruptedReSetOfOursStillUndoesNormally() throws {
        let first = try provider.set(art, on: folder, confirmReplace: false)
        // A crash during a second set, before it reached the folder.
        var inFlight = first
        inFlight.previousFingerprint = first.fingerprint
        inFlight.fingerprint = nil
        inFlight.previousIsOurs = true
        try ledger.update(inFlight)

        #expect(try provider.undo(inFlight) == .cleared)
        #expect(fake.icon(folder) == nil)
    }

    @Test func aMissingFolderIsLeftAndItsRecordKept() throws {
        fake.preset(folder, icon: "theirs")
        let entry = try provider.set(art, on: folder, confirmReplace: true)
        try FileManager.default.removeItem(atPath: folder)

        #expect(try provider.undo(entry) == .folderMissing)
        #expect(try ledger.entries().count == 1)
        #expect(FileManager.default.fileExists(atPath: try #require(provider.backupURL(entry)).path))
    }

    @Test func aLinkIsNeverTouched() throws {
        let link = PathStandardizer.standardize(dir.url.path) + "/Link"
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: folder)

        #expect(throws: FolderIconError.unsafeTarget(link)) { try provider.set(art, on: link, confirmReplace: true) }
        let tampered = OutsideChange(kind: .folderIcon, target: link, fingerprint: "fp:x")
        #expect(throws: FolderIconError.unsafeTarget(link)) { try provider.undo(tampered) }
        #expect(fake.state.withLock { $0.calls }.isEmpty)
    }

    @Test func aBackupNameCantLeaveTheBackupsFolder() {
        var entry = OutsideChange(kind: .folderIcon, target: folder)
        for name in ["../config.json", "/etc/passwd", ".hidden", "a/b.icns", ""] {
            entry.backupFileName = name
            #expect(provider.backupURL(entry) == nil, "\(name)")
        }
    }
}

/// 004 T039: folder icons through the manager.
@Suite struct FolderIconManagerTests {
    let setup: ManagerFixture
    let fake: FakeFolderIcons
    let master: URL

    init() throws {
        setup = try ManagerFixture()
        fake = FakeFolderIcons(ledger: LedgerStore(url: setup.container.ledgerURL))
        master = try writeSolidPNG(in: setup.dir.url, name: "folder-art.png", pixels: 1024)
    }

    private func manager() async throws -> MappingManager {
        let manager = MappingManager(container: setup.container, system: setup.system, restartFinder: {},
                                     isValidSystemSymbol: { $0 == "folder" }, glyphTool: FakeActool().runner(),
                                     folderIconWriter: fake)
        try await manager.load()
        return manager
    }

    private func addDev(_ manager: MappingManager) async throws -> UUID {
        let result = try await manager.add(folder: URL(fileURLWithPath: setup.dev), style: .systemSymbol(name: "folder"))
        return try #require(result.rows.first?.id)
    }

    private func ledgerFolderEntries() throws -> [OutsideChange] {
        try LedgerStore(url: setup.container.ledgerURL).entries().filter { $0.kind == .folderIcon }
    }

    @Test func settingSavesTheArtAndShowsSet() async throws {
        let manager = try await manager()
        let id = try await addDev(manager)

        let result = try await manager.setFolderIcon(FolderArt(master: master), for: id)

        #expect(result.rows.first?.folderIcon == .set)
        #expect(result.rows.first?.folderIconOptedIn == true)
        #expect(fake.icon(setup.dev) != nil)
        let saved = try ConfigStore(container: setup.container).load()
        let setting = try #require(saved.mappings.first?.folderIcon)
        #expect(saved.assets.contains { $0.id == setting.artAssetID })
        #expect(try ledgerFolderEntries().map(\.target) == [setup.dev])
        // The build folder is cleaned up.
        #expect(((try? FileManager.default.contentsOfDirectory(atPath: setup.container.buildDirectory.path)) ?? []).isEmpty)
    }

    @Test func anExistingIconNeedsConfirmationAndNothingIsSaved() async throws {
        let manager = try await manager()
        let id = try await addDev(manager)
        fake.preset(setup.dev, icon: "theirs")
        let before = try setup.snapshot()

        await #expect(throws: ManagerError.folderIconNeedsConfirmation(existing: true)) {
            try await manager.setFolderIcon(FolderArt(master: master), for: id)
        }

        #expect(try setup.snapshot() == before)
        #expect(fake.icon(setup.dev) == "theirs")
    }

    @Test func confirmedReplaceIsUndoneByOffAndRedoneByOn() async throws {
        let manager = try await manager()
        let id = try await addDev(manager)
        fake.preset(setup.dev, icon: "theirs")
        _ = try await manager.setFolderIcon(FolderArt(master: master), for: id, confirmReplace: true)
        let ours = fake.icon(setup.dev)
        #expect(ours != "theirs")

        let off = try await manager.setEnabled(false, for: id)
        #expect(fake.icon(setup.dev) == "theirs")
        #expect(off.rows.first?.folderIcon == .notSet)
        #expect(try ledgerFolderEntries().isEmpty)

        let on = try await manager.setEnabled(true, for: id)
        #expect(fake.icon(setup.dev) == ours)
        #expect(on.rows.first?.folderIcon == .set)

        _ = try await manager.setFolderIcon(nil, for: id)
        #expect(fake.icon(setup.dev) == "theirs")
        #expect(try ConfigStore(container: setup.container).load().mappings.first?.folderIcon == nil)
    }

    @Test func removePutsTheFolderBack() async throws {
        let manager = try await manager()
        let id = try await addDev(manager)
        _ = try await manager.setFolderIcon(FolderArt(master: master), for: id)

        _ = try await manager.remove(id)

        #expect(fake.icon(setup.dev) == nil)
        #expect(try ledgerFolderEntries().isEmpty)
    }

    @Test func aChangeElsewhereIsShownAndLeftOnRemove() async throws {
        let manager = try await manager()
        let id = try await addDev(manager)
        _ = try await manager.setFolderIcon(FolderArt(master: master), for: id)
        fake.preset(setup.dev, icon: "someone else")

        #expect(await manager.rows().first?.folderIcon == .changedElsewhere)
        let result = try await manager.remove(id)

        #expect(fake.icon(setup.dev) == "someone else")
        #expect(result.messages.contains { $0.contains("changed by something else") })
        #expect(try ledgerFolderEntries().isEmpty)
    }

    @Test func aRefusedSetSavesNothing() async throws {
        let manager = try await manager()
        let id = try await addDev(manager)
        fake.state.withLock { $0.refuse = true }
        let before = try setup.snapshot()

        await #expect(throws: ManagerError.folderIconFailed(setup.dev)) {
            try await manager.setFolderIcon(FolderArt(master: master), for: id)
        }

        #expect(try setup.snapshot() == before)
        #expect(try ledgerFolderEntries().isEmpty)
    }

    @Test func refusedArtCopiesNothing() async throws {
        let manager = try await manager()
        let id = try await addDev(manager)
        let small = try writeSolidPNG(in: setup.dir.url, name: "small.png", pixels: 256)
        let before = try setup.snapshot()

        await #expect(throws: ManagerError.folderArtRefused(.masterTooSmall(name: "small.png", pixels: 256))) {
            try await manager.setFolderIcon(FolderArt(master: small), for: id)
        }
        #expect(try setup.snapshot() == before)
        #expect(fake.state.withLock { $0.calls }.isEmpty)
    }

    @Test func resetAllPutsFoldersBackAndDeletesBackups() async throws {
        let manager = try await manager()
        let id = try await addDev(manager)
        fake.preset(setup.dev, icon: "theirs")
        _ = try await manager.setFolderIcon(FolderArt(master: master), for: id, confirmReplace: true)
        #expect(FileManager.default.fileExists(atPath: setup.container.folderIconBackupsDirectory.path))

        _ = try await manager.resetAll()

        #expect(fake.icon(setup.dev) == "theirs")
        #expect(try ledgerFolderEntries().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: setup.container.folderIconBackupsDirectory.path))
    }

    @Test func aRefusedRestoreKeepsTheMappingOnReset() async throws {
        let manager = try await manager()
        let id = try await addDev(manager)
        _ = try await manager.setFolderIcon(FolderArt(master: master), for: id)
        fake.state.withLock { $0.refuse = true }

        let result = try await manager.resetAll()

        #expect(result.rows.map(\.id) == [id])
        #expect(try ledgerFolderEntries().count == 1)
        #expect(result.messages.contains { $0.contains("Reset All again") })
    }

    @Test func foldersNotOptedInAreNeverTouched() async throws {
        let manager = try await manager()
        let id = try await addDev(manager)
        _ = try await manager.setEnabled(false, for: id)
        _ = try await manager.setEnabled(true, for: id)
        _ = try await manager.applyNow()
        _ = try await manager.remove(id)
        _ = try await manager.resetAll()

        #expect(fake.state.withLock { $0.calls }.isEmpty)
    }

    @Test func removeOfAMissingFolderForgetsItsRecord() async throws {
        let manager = try await manager()
        let id = try await addDev(manager)
        _ = try await manager.setFolderIcon(FolderArt(master: master), for: id)
        try FileManager.default.removeItem(atPath: setup.dev)

        let off = try await manager.setEnabled(false, for: id)
        #expect(try ledgerFolderEntries().count == 1)
        #expect(off.messages.contains { $0.contains("can't be found") })

        let removed = try await manager.remove(id)
        #expect(try ledgerFolderEntries().isEmpty)
        #expect(removed.messages.contains { $0.contains("Get Info") })
    }

    @Test func repointFollowsAMovedFolderThatStillShowsOurIcon() async throws {
        let manager = try await manager()
        let id = try await addDev(manager)
        fake.preset(setup.dev, icon: "theirs")
        _ = try await manager.setFolderIcon(FolderArt(master: master), for: id, confirmReplace: true)
        let ours = try #require(fake.icon(setup.dev))
        let entry = try #require(try ledgerFolderEntries().first)
        // The folder moves, with its Icon\r.
        let moved = PathStandardizer.standardize(URL(fileURLWithPath: setup.dev).deletingLastPathComponent().appending(path: "dev-moved").path)
        try FileManager.default.moveItem(atPath: setup.dev, toPath: moved)
        fake.preset(moved, icon: ours)

        _ = try await manager.repoint(id, to: URL(fileURLWithPath: moved))

        let followed = try #require(try ledgerFolderEntries().first)
        #expect(followed.id == entry.id && followed.target == moved && followed.backupFileName == entry.backupFileName)
        #expect(FileManager.default.fileExists(atPath: setup.container.folderIconBackupsDirectory.appending(path: try #require(entry.backupFileName)).path))
        _ = try await manager.remove(id)
        #expect(fake.icon(moved) == "theirs")
    }

    @Test func aConfirmedReplaceDoesNotCarryToAnotherFolder() async throws {
        let manager = try await manager()
        let id = try await addDev(manager)
        fake.preset(setup.dev, icon: "theirs")
        _ = try await manager.setFolderIcon(FolderArt(master: master), for: id, confirmReplace: true)
        let other = PathStandardizer.standardize(setup.dir.url.appending(path: "home/Other").path)
        try FileManager.default.createDirectory(atPath: other, withIntermediateDirectories: true)
        fake.preset(other, icon: "other's own")

        let result = try await manager.repoint(id, to: URL(fileURLWithPath: other))

        #expect(fake.icon(other) == "other's own")
        #expect(fake.icon(setup.dev) == "theirs")
        #expect(result.messages.contains { $0.contains("has a custom icon now") })
    }

    @Test func anIconChangedWhileOffIsNotReplacedOnOn() async throws {
        let manager = try await manager()
        let id = try await addDev(manager)
        fake.preset(setup.dev, icon: "theirs")
        _ = try await manager.setFolderIcon(FolderArt(master: master), for: id, confirmReplace: true)
        _ = try await manager.setEnabled(false, for: id)
        fake.preset(setup.dev, icon: "a newer icon")

        let on = try await manager.setEnabled(true, for: id)

        #expect(fake.icon(setup.dev) == "a newer icon")
        #expect(on.messages.contains { $0.contains("has a custom icon now") })
    }

    @Test func aFailedSaveOfNewArtKeepsTheEarlierArt() async throws {
        let manager = try await manager()
        let id = try await addDev(manager)
        _ = try await manager.setFolderIcon(FolderArt(master: master), for: id)
        let first = fake.icon(setup.dev)
        let other = try writeSolidPNG(in: setup.dir.url, name: "other-art.png", pixels: 1024, red: 1, green: 0, blue: 0)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: setup.container.root.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: setup.container.root.path) }

        await #expect(throws: ManagerError.self) { try await manager.setFolderIcon(FolderArt(master: other), for: id) }

        #expect(fake.icon(setup.dev) == first)
        #expect(await manager.rows().first?.folderIcon == .set)
    }

    @Test func anOffMappingSavesTheArtAndSetsItWhenTurnedOn() async throws {
        let manager = try await manager()
        let id = try await addDev(manager)
        _ = try await manager.setEnabled(false, for: id)

        let saved = try await manager.setFolderIcon(FolderArt(master: master), for: id)
        #expect(fake.icon(setup.dev) == nil)
        #expect(saved.messages.contains { $0.contains("when the mapping is turned on") })

        _ = try await manager.setEnabled(true, for: id)
        #expect(fake.icon(setup.dev) != nil)
    }
}
