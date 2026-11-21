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
    private(set) var busy = false
    private(set) var statusLine = ""
    var alert: Alert?
    /// A picked image shown in the preview sheet until Apply or Cancel (Story 3).
    var pendingIcon: PendingIcon?
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
        guard let image = AddMappingFlow.chooseImage(for: row.displayName) else { return }
        preview(image, for: .change(row))
    }

    /// Shows the preview sheet for a picked image. Nothing is copied or saved yet.
    func preview(_ image: URL, for purpose: PendingIcon.Purpose) {
        pendingIcon = PendingIcon(purpose: purpose, image: image, advice: PreviewAdvice.evaluate(imageAt: image))
    }

    func applyPendingIcon() {
        guard let pending = pendingIcon else { return }
        pendingIcon = nil
        switch pending.purpose {
        case .add(let folder):
            add(folder: folder, image: pending.image)
        case .change(let row):
            run { try await $0.changeIcon(for: row.id, image: pending.image) }
        }
    }

    func cancelPendingIcon() {
        pendingIcon = nil
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

    private func run(_ action: @escaping @Sendable (MappingManager) async throws -> ActionResult) {
        guard let manager, !busy else { return }
        busy = true
        statusLine = "Working…"
        Task {
            defer { busy = false }
            do {
                let result = try await action(manager)
                rows = result.rows
                statusLine = Self.summary(of: result)
            } catch {
                statusLine = ""
                alert = Alert(title: "Sidebar Icons", message: Self.message(for: error))
                rows = await manager.rows()
            }
            readOnlyReason = await manager.readOnlyReason
            favoritesUnavailable = !(await manager.favoritesReadable)
        }
    }

    private func reloadRows(from manager: MappingManager) async {
        rows = await manager.rows()
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
