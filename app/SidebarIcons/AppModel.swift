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
            startupError = "This copy of Sidebar Icons isn't signed with its App Group, so it can't store anything. Build it with the project's signing settings."
        }
    }

    /// Add and Apply need readable config and Favorites (FR-010 keeps Reset All available).
    var canChange: Bool { manager != nil && !busy && readOnlyReason == nil && !favoritesUnavailable }
    var canReset: Bool { manager != nil && !busy }

    /// Launch: reads the config and shows status. Makes no outside change (research D6).
    /// Runs again if the window is reopened; it never runs during an action and never clears a
    /// busy flag it didn't set.
    func start() async {
        guard let manager, !busy else { return }
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
        switch (request.purpose, choice) {
        case (.add(let folder), .systemSymbol(let name)):
            run { try await $0.add(folder: folder, style: .systemSymbol(name: name)) }
        case (.add(let folder), .image(let image)):
            add(folder: folder, image: image)
        case (.change(let row), .systemSymbol(let name)):
            run { try await $0.setStyle(.systemSymbol(name: name), for: row.id) }
        case (.change(let row), .image(let image)):
            run { try await $0.changeIcon(for: row.id, image: image) }
        case (.add(let folder), .customGlyph(let id)):
            run { try await $0.add(folder: folder, style: .customGlyph(glyphID: id)) }
        case (.change(let row), .customGlyph(let id)):
            run { try await $0.setStyle(.customGlyph(glyphID: id), for: row.id) }
        }
    }

    // MARK: - Custom glyphs

    /// Runs `xcrun --find actool` off the main actor and records the result.
    func checkGlyphTool() async {
        guard let manager else { return }
        glyphToolStatus = await Task.detached { manager.glyphToolStatus() }.value
    }

    func importGlyph(name: String, template: URL) {
        run { try await $0.importGlyph(name: name, template: template) }
    }

    /// The wizard's build (Story 3). `completion` gets the new glyph's id, or nil on failure
    /// (the error is in `lastError`).
    func createGlyph(name: String, drawing: Data, completion: @escaping @MainActor (UUID?) -> Void) {
        let name = name.trimmingCharacters(in: .whitespaces)
        run({ try await $0.createGlyph(name: name, drawing: drawing) }) { [weak self] succeeded in
            completion(succeeded ? self?.glyphs.first(where: { $0.name == name })?.id : nil)
        }
    }

    /// A new drawing for an existing glyph; its folders switch to the new version.
    func updateGlyph(_ glyph: CustomGlyph, drawing: Data, completion: @escaping @MainActor (UUID?) -> Void) {
        let id = glyph.id
        run({ try await $0.updateGlyph(id, drawing: drawing) }) { succeeded in
            completion(succeeded ? id : nil)
        }
    }

    func clearLastError() {
        lastError = nil
    }

    /// Deletes a glyph; folders that use it switch to the system folder glyph (FR-010).
    func deleteGlyph(_ glyph: CustomGlyph) {
        run { try await $0.deleteGlyph(glyph.id, replacement: .systemSymbol(name: "folder")) }
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
    private func run(_ action: @escaping @Sendable (MappingManager) async throws -> ActionResult,
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
                if styleRequest == nil {
                    alert = Alert(title: "Sidebar Icons", message: message)
                }
                rows = await manager.rows()
                glyphs = await manager.glyphs()
            }
            readOnlyReason = await manager.readOnlyReason
            favoritesUnavailable = !(await manager.favoritesReadable)
        }
    }

    private func reloadRows(from manager: MappingManager) async {
        rows = await manager.rows()
        glyphs = await manager.glyphs()
        readOnlyReason = await manager.readOnlyReason
        favoritesUnavailable = !(await manager.favoritesReadable)
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
