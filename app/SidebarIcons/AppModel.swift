import Foundation
import Observation
import SidebarIconCore

/// The window's state: a main-actor wrapper over `MappingManager`. Each action runs in a task,
/// disables the controls while it runs, and refreshes the rows when it ends.
@MainActor @Observable
final class AppModel {
    struct Alert: Identifiable {
        let id = UUID()
        var title: String
        var message: String
    }

    private(set) var rows: [MappingRow] = []
    /// The ledger records folder icons, so Reset All will put folders back (final review 6).
    private(set) var folderIconsRecorded = false
    /// The owner's custom glyphs (004 Story 2).
    private(set) var glyphs: [CustomGlyph] = []
    /// Whether custom glyphs can be built here; nil until checked.
    private(set) var glyphToolStatus: ToolStatus?
    private(set) var busy = false
    private(set) var statusLine = ""
    var alert: Alert?
    /// The last action's error, shown inside the style picker, whose sheet would hide the
    /// window's alert (review M4).
    private(set) var lastError: String?
    /// The open style picker (Add Folder… or Change Icon…) until Apply or Cancel.
    var styleRequest: StyleRequest?
    /// The open folder icon sheet (Folder Icon…), 004 Story 4.
    var folderArtRequest: FolderArtRequest?
    /// Folder art chosen in the wizard's folder-art step, set on the folder after the picker applies.
    var pendingFolderArt: URL?
    /// Set when `config.json` can't be read (research D3).
    private(set) var readOnlyReason: String?
    private(set) var favoritesUnavailable = false
    /// This macOS build is not in the verified list (research D8).
    let unverifiedBuild: Bool
    /// The app is not signed with its App Group, so it has no storage and does nothing.
    let startupError: String?

    private let manager: MappingManager?

    init() {
        do {
            let manager = MappingManager(container: try ContainerLocator.forRunningProcess())
            self.manager = manager
            unverifiedBuild = !manager.macOSBuildVerified
            startupError = nil
        } catch {
            manager = nil
            unverifiedBuild = false
            startupError = "Sidebar Icons keeps its data in its App Group, and this copy is signed without it. Build it with the project's signing settings."
        }
    }

    /// Add and Apply need readable config and Favorites (FR-010 keeps Reset All available).
    var canChange: Bool { manager != nil && !busy && readOnlyReason == nil && !favoritesUnavailable }
    var canReset: Bool { manager != nil && !busy }

    /// Launch: reads the config and shows status. Makes no outside change (research D6).
    /// Loads once, from whichever window opens first; it never runs during an action and never
    /// clears a busy flag it didn't set.
    func start() async {
        guard let manager, !busy, !started else { return }
        started = true
        busy = true
        defer { busy = false }
        do {
            try await manager.load()
        } catch {
            statusLine = Self.message(for: error)
        }
        await reloadRows(from: manager)
    }

    func add(folder: URL, image: URL) {
        run { try await $0.add(folder: folder, image: image) }
    }

    func applyNow() {
        run { try await $0.applyNow() }
    }

    func setEnabled(_ enabled: Bool, for row: MappingRow) {
        run { try await $0.setEnabled(enabled, for: row.id) }
    }

    func remove(_ row: MappingRow) {
        run { try await $0.remove(row.id) }
    }

    func changeIcon(for row: MappingRow) {
        styleRequest = StyleRequest(purpose: .change(row))
    }

    /// Opens the style picker for a folder just picked in Add Folder….
    func chooseStyle(forNewFolder folder: URL) {
        styleRequest = StyleRequest(purpose: .add(folder: folder))
    }

    func applyStyle(_ choice: StyleChoice) {
        guard let request = styleRequest else { return }
        styleRequest = nil
        let folderArt = pendingFolderArt
        pendingFolderArt = nil
        let folderPath: String = switch request.purpose {
        case .add(let folder): PathStandardizer.standardize(folder.path)
        case .change(let row): row.folderPath
        }
        // The wizard's folder art follows once the mapping exists.
        let then: @MainActor (Bool) -> Void = { [weak self] succeeded in
            if succeeded, let folderArt { self?.startFolderIcon(master: folderArt, folderPath: folderPath) }
        }
        switch (request.purpose, choice) {
        case (.add(let folder), .systemSymbol(let name)):
            run({ try await $0.add(folder: folder, style: .systemSymbol(name: name)) }, finished: then)
        case (.add(let folder), .image(let image)):
            run({ try await $0.add(folder: folder, image: image) }, finished: then)
        case (.change(let row), .systemSymbol(let name)):
            run({ try await $0.setStyle(.systemSymbol(name: name), for: row.id) }, finished: then)
        case (.change(let row), .image(let image)):
            run({ try await $0.changeIcon(for: row.id, image: image) }, finished: then)
        case (.add(let folder), .customGlyph(let id)):
            run({ try await $0.add(folder: folder, style: .customGlyph(glyphID: id)) }, finished: then)
        case (.change(let row), .customGlyph(let id)):
            run({ try await $0.setStyle(.customGlyph(glyphID: id), for: row.id) }, finished: then)
        }
    }

    // MARK: - Folder icons (Story 4)

    func openFolderIcon(for row: MappingRow) {
        lastError = nil
        folderArtRequest = FolderArtRequest(rowID: row.id, folderName: row.displayName, folderPath: row.folderPath,
                                            isOn: row.folderIconOptedIn)
    }

    func closeFolderIcon() {
        folderArtRequest = nil
        lastError = nil
    }

    func folderNeedsConfirmation(_ path: String) async -> Bool {
        await manager?.folderIconNeedsConfirmation(atPath: path) ?? false
    }

    /// Sets (or with nil turns off) a mapping's folder icon; `completion` says whether it worked.
    func setFolderIcon(_ art: FolderArt?, forRow id: UUID, confirmReplace: Bool, completion: @escaping @MainActor (Bool) -> Void) {
        run({ try await $0.setFolderIcon(art, for: id, confirmReplace: confirmReplace) }, finished: completion)
    }

    /// After the wizard: sets the art directly, or opens the sheet when the folder already has a
    /// custom icon, so the owner sees the replace warning (FR-013).
    private func startFolderIcon(master: URL, folderPath: String) {
        guard let row = rows.first(where: { $0.folderPath == folderPath }) else { return }
        Task {
            if await folderNeedsConfirmation(folderPath) {
                var request = FolderArtRequest(rowID: row.id, folderName: row.displayName, folderPath: row.folderPath,
                                               isOn: row.folderIconOptedIn)
                request.master = master
                folderArtRequest = request
            } else {
                setFolderIcon(FolderArt(master: master), forRow: row.id, confirmReplace: false) { [weak self] succeeded in
                    // A failure already shows its own alert; one that never started (another action
                    // was running) says so here, so the art isn't dropped without a word (review L5).
                    guard let self, !succeeded, self.alert == nil else { return }
                    self.alert = Alert(title: "Sidebar Icons",
                                       message: "The folder art for \(row.displayName) wasn't set. Use Folder Icon… on its row to set it.")
                }
            }
        }
    }

    // MARK: - Custom glyphs

    /// Runs `xcrun --find actool` off the main actor and records the result.
    func checkGlyphTool() async {
        guard let manager else { return }
        glyphToolStatus = await Task.detached { manager.glyphToolStatus() }.value
    }

    /// Checked each time a wizard is about to open, so installing Xcode or accepting its license
    /// is noticed without a relaunch. Nil when the tool is ready, otherwise what to do.
    func glyphToolProblem() async -> String? {
        await checkGlyphTool()
        switch glyphToolStatus {
        case .available?: return nil
        case .unavailable(let reason)?: return reason
        case nil: return GlyphBuildError.needsXcode
        }
    }

    private var started = false

    /// Imports a template (the manual process). `completion` says whether it succeeded.
    func importGlyph(name: String, template: URL, completion: (@MainActor (Bool) -> Void)? = nil) {
        run({ try await $0.importGlyph(name: name, template: template) }, alertOnFailure: false, finished: completion)
    }

    /// The wizard's build (Story 3). `completion` gets the new glyph's id, or nil on failure
    /// (the error is in `lastError`).
    func createGlyph(name: String, drawing: Data, completion: @escaping @MainActor (UUID?) -> Void) {
        let name = name.trimmingCharacters(in: .whitespaces)
        run({ try await $0.createGlyph(name: name, drawing: drawing) }, alertOnFailure: false) { [weak self] succeeded in
            completion(succeeded ? self?.glyphs.first(where: { $0.name == name })?.id : nil)
        }
    }

    /// A new drawing for an existing glyph; its folders switch to the new version.
    func updateGlyph(_ glyph: CustomGlyph, drawing: Data, completion: @escaping @MainActor (UUID?) -> Void) {
        let id = glyph.id
        run({ try await $0.updateGlyph(id, drawing: drawing) }, alertOnFailure: false) { succeeded in
            completion(succeeded ? id : nil)
        }
    }

    func clearLastError() {
        lastError = nil
    }

    /// Deletes a glyph; folders that use it switch to the standard folder glyph (FR-010).
    func deleteGlyph(_ glyph: CustomGlyph, completion: (@MainActor (Bool) -> Void)? = nil) {
        run({ try await $0.deleteGlyph(glyph.id, replacement: .systemSymbol(name: "folder")) },
            alertOnFailure: false, finished: completion)
    }

    func folderCount(using glyph: CustomGlyph) -> Int {
        rows.filter { $0.style == .customGlyph(glyphID: glyph.id) }.count
    }

    /// The stored template of a glyph, for previews.
    func templateURL(for glyph: CustomGlyph) -> URL? {
        guard let manager else { return nil }
        return manager.container.glyphsDirectory.appending(path: glyph.templateFileName)
    }

    func templateURL(for style: SidebarStyle) -> URL? {
        guard case .customGlyph(let id) = style, let glyph = glyphs.first(where: { $0.id == id }) else { return nil }
        return templateURL(for: glyph)
    }

    func cancelStyle() {
        styleRequest = nil
        pendingFolderArt = nil
        lastError = nil
    }

    func repoint(_ row: MappingRow) {
        guard let folder = AddMappingFlow.chooseFolder(
            title: "Re-point \(row.displayName)",
            message: "Choose the folder this mapping should use now. Its icon stays the same."
        ) else { return }
        run { try await $0.repoint(row.id, to: folder) }
    }

    func refreshFinder() {
        run { try await $0.refreshFinder() }
    }

    func resetAll() {
        run { try await $0.resetAll() }
    }

    /// `finished` runs on the main actor after the rows are refreshed, with whether the action
    /// succeeded. It also runs (with false) when the action couldn't start.
    /// `alertOnFailure` false: the sheet or window that started the action shows `lastError`
    /// itself (glyph actions, from the Glyph Library or a wizard), so no alert in the main window.
    private func run(_ action: @escaping @Sendable (MappingManager) async throws -> ActionResult,
                     alertOnFailure: Bool = true,
                     finished: (@MainActor (Bool) -> Void)? = nil) {
        guard let manager, !busy else {
            finished?(false)
            return
        }
        busy = true
        statusLine = "Working…"
        lastError = nil
        Task {
            var succeeded = false
            defer {
                busy = false
                finished?(succeeded)
            }
            do {
                let result = try await action(manager)
                rows = result.rows
                glyphs = await manager.glyphs()
                statusLine = Self.summary(of: result)
                succeeded = true
            } catch {
                statusLine = ""
                let message = Self.message(for: error)
                lastError = message
                if alertOnFailure && styleRequest == nil && folderArtRequest == nil {
                    alert = Alert(title: "Sidebar Icons", message: message)
                }
                rows = await manager.rows()
                glyphs = await manager.glyphs()
            }
            readOnlyReason = await manager.readOnlyReason
            favoritesUnavailable = !(await manager.favoritesReadable)
            folderIconsRecorded = await manager.hasFolderIconRecords()
        }
    }

    private func reloadRows(from manager: MappingManager) async {
        rows = await manager.rows()
        glyphs = await manager.glyphs()
        readOnlyReason = await manager.readOnlyReason
        favoritesUnavailable = !(await manager.favoritesReadable)
        folderIconsRecorded = await manager.hasFolderIconRecords()
    }

    static func summary(of result: ActionResult) -> String {
        var parts = result.messages
        if result.needsRefresh {
            parts.append("If the icon hasn't changed, click Refresh Finder.")
        }
        return parts.isEmpty ? "Done." : parts.joined(separator: " ")
    }

    static func message(for error: any Error) -> String {
        switch error {
        case let error as ManagerError: error.message
        case let error as SidebarIconError: error.message
        default: error.localizedDescription
        }
    }
}
