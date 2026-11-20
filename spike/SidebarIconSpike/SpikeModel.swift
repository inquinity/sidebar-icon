import AppKit
import Observation
import SidebarIconCore
import UniformTypeIdentifiers
import os

/// State and actions behind the spike window. Every outside change happens only from a button
/// press (FR-007); nothing runs at launch except reading the container and copying the bundled
/// icons into it.
@MainActor
@Observable
final class SpikeModel {
    private(set) var log: [String] = []
    private(set) var busy = false
    private(set) var mappings: [SidebarMapping] = []
    private(set) var assets: [IconAsset] = []
    private(set) var container: ContainerLocator?

    private let logger = Logger(subsystem: "com.altmansoftwaredesign.SidebarIcons", category: "Spike")
    private let finderSync = FinderSyncProvider()
    private var launchServices: LaunchServicesOverrideProvider? {
        container.map { LaunchServicesOverrideProvider(container: $0) }
    }

    init() {
        write("Sidebar Icon Spike — \(SystemInfo.macOSDescription), SidebarIconCore \(SidebarIconCoreInfo.version)")
        do {
            let container = try ContainerLocator.forRunningProcess()
            try container.prepare()
            self.container = container
            write("Container: \(container.root.path)")
            let loaded = SpikeMappings.load(into: container) { write($0) }
            mappings = loaded.mappings
            assets = loaded.assets
            for mapping in mappings {
                write("Mapping: \(mapping.folderPath) → \(mapping.osType)")
            }
        } catch {
            write("No container: \(error). Is the app signed with the App Group? Path B and the ledger are unavailable.")
        }
    }

    // MARK: Actions

    /// Experiment B1 (read-only).
    func listFavorites() async {
        guard let provider = requireLaunchServices() else { return }
        await run("List Favorites") {
            let favorites = try await Task.detached { try provider.listFavorites() }.value
            self.write("Favorites (\(favorites.count)):")
            for (index, item) in favorites.enumerated() {
                let override = item.overrideIcon.map { " override=\($0)" } ?? ""
                self.write("  \(index + 1). \(item.displayName) — \(item.path ?? "(not a file)")\(override)")
            }
            for status in try await provider.status(for: self.mappings) {
                self.write("  Mapping \(status.folderPath): in Favorites \(status.favoriteCount ?? 0)×, override \(status.activeOverride ?? "none")")
            }
            let ledger = try provider.ledgerEntries()
            self.write("Ledger: \(ledger.count) entr\(ledger.count == 1 ? "y" : "ies")")
            for entry in ledger {
                self.write("  \(entry.kind.rawValue) \(entry.target)\(entry.osType.map { " \($0)" } ?? "") (\(entry.macOSBuild))")
            }
        }
    }

    /// Path A (FR-005): public Finder Sync only. Changes nothing.
    func applyPathA() async {
        await run("Apply (Path A)") {
            for status in try await self.finderSync.status(for: self.mappings) {
                self.write("  \(status.folderPath): \(status.note ?? "")")
            }
            self.writeReport(try await self.finderSync.apply(self.mappings, assets: self.assets))
        }
    }

    /// Path B with the current mappings and assets.
    func applyPathB() async {
        guard let provider = requireLaunchServices() else { return }
        await run("Apply (Path B)") {
            self.writeReport(try await provider.apply(self.mappings, assets: self.assets))
            self.write("Applied at \(Self.clockTime()). Check the sidebar; if nothing changed, use Refresh Finder.")
        }
    }

    /// Story 2: choose an image after the build and apply it to ~/DevDocs.
    func useRuntimeIconForDevDocs() async {
        guard let container, let provider = requireLaunchServices() else { return }
        guard let index = mappings.firstIndex(where: { $0.id == SpikeMappings.devDocs.mappingID }) else {
            write("~/DevDocs is not mapped (missing folder?).")
            return
        }
        let panel = NSOpenPanel()
        panel.title = "Choose an icon for ~/DevDocs"
        panel.allowedContentTypes = [.pdf, .png, .svg]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let source = panel.url else {
            write("Use runtime icon: cancelled.")
            return
        }
        let started = ContinuousClock.now
        await run("Use runtime icon for DevDocs") {
            let asset = try AssetImporter.importFile(at: source, into: container.iconsDirectory)
            self.write("  Copied \(source.lastPathComponent) as \(asset.fileName) (\(asset.sourceFormat.rawValue)); the original is untouched.")
            self.assets.append(asset)
            self.mappings[index].iconAssetID = asset.id
            self.writeReport(try await provider.apply(self.mappings, assets: self.assets))
            let elapsed = ContinuousClock.now - started
            self.write("Applied at \(Self.clockTime()), \(elapsed.formatted(.units(allowed: [.seconds, .milliseconds]))) after choosing. Note when the sidebar changes (SC-003: within 10 s).")
        }
    }

    /// Explicit Finder restart (research R8). The view confirms first.
    func refreshFinder() async {
        await run("Refresh Finder") {
            let took = try await FinderRestarter.restart()
            self.write("Finder restarted in \(took.formatted(.units(allowed: [.seconds, .milliseconds]))).")
        }
    }

    /// Story 3: undo every ledger entry, then check `lsregister -dump` (experiment B6).
    func reset() async {
        guard let provider = requireLaunchServices() else { return }
        await run("Reset") {
            let report = try await provider.reset()
            for entry in report.undone {
                self.write("  Undone: \(entry.kind.rawValue) \(entry.target)\(entry.osType.map { " \($0)" } ?? "")")
            }
            for failure in report.failed {
                self.write("  FAILED: \(failure.change.kind.rawValue) \(failure.change.target): \(failure.reason.message)")
            }
            report.notes.forEach { self.write("  \($0)") }
            let remaining = try provider.ledgerEntries().count
            self.write("Ledger entries remaining: \(remaining).")
            let listed = try await Task.detached { try provider.registrationStillListed() }.value
            self.write("lsregister -dump lists IconRegistry.app: \(listed ? "YES" : "no").")
            if report.succeeded && !report.undone.isEmpty {
                self.write("Use Refresh Finder to see the generic icons again.")
            }
        }
    }

    func copyLog() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(log.joined(separator: "\n"), forType: .string)
        write("Log copied to the clipboard.")
    }

    // MARK: Helpers

    private func requireLaunchServices() -> LaunchServicesOverrideProvider? {
        guard let provider = launchServices else {
            write("Path B is unavailable without the App Group container.")
            return nil
        }
        return provider
    }

    private func run(_ name: String, _ body: @MainActor () async throws -> Void) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        write("▶ \(name)")
        do {
            try await body()
        } catch let error as SidebarIconError {
            write("✖ \(name): \(error.message)")
        } catch {
            write("✖ \(name): \(error)")
        }
    }

    private func writeReport(_ report: ApplyReport) {
        for id in report.applied {
            write("  Applied: \(describe(id))")
        }
        for skip in report.skipped {
            write("  Skipped: \(describe(skip.mappingID)): \(skip.reason.message)")
        }
        for path in report.cleared {
            write("  Cleared: \(path)")
        }
        report.notes.forEach { write("  \($0)") }
    }

    private func describe(_ mappingID: UUID) -> String {
        mappings.first { $0.id == mappingID }.map { "\($0.folderPath) → \($0.osType)" } ?? mappingID.uuidString
    }

    private func write(_ line: String) {
        let stamped = "[\(Self.clockTime())] \(line)"
        log.append(stamped)
        logger.info("\(line, privacy: .public)")
    }

    private static func clockTime() -> String {
        Date.now.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).second(.twoDigits).secondFraction(.fractional(3)))
    }
}
