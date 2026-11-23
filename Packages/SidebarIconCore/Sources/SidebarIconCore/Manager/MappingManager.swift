import AppKit
import Foundation

/// One row of the mapping list (contracts/mapping-manager.md).
public struct MappingRow: Sendable, Equatable, Identifiable {
    public var id: UUID
    public var folderPath: String
    /// The folder's name.
    public var displayName: String
    /// The copied image in `Icons/`, for the preview.
    public var iconFile: URL
    /// How the Favorite is drawn in the sidebar.
    public var style: SidebarStyle
    public var enabled: Bool
    public var osType: String
    public var state: MappingState
}

/// What an action did, for the window (contracts/mapping-manager.md).
public struct ActionResult: Sendable, Equatable {
    /// Fresh status after the action.
    public var rows: [MappingRow]
    /// Plain-language notes for the status line.
    public var messages: [String]
    /// True when the owner may need to click Refresh Finder to see the change.
    public var needsRefresh: Bool

    public init(rows: [MappingRow], messages: [String] = [], needsRefresh: Bool = false) {
        self.rows = rows
        self.messages = messages
        self.needsRefresh = needsRefresh
    }
}

/// The only engine object the app talks to. It owns the configuration and drives the Path B
/// adapter. Every method that changes something outside the container is named for an explicit
/// owner action (research D6); `load()` and `rows()` only read.
///
/// An actor, so the slow system calls run off the main thread. The adapter's methods suspend, so
/// actor isolation alone would let a second action start while one is waiting; every action
/// therefore runs through `exclusive`, which refuses to start one while another is in progress
/// (the ledger is rewritten whole and must have one writer).
public actor MappingManager {
    public nonisolated let container: ContainerLocator
    let store: ConfigStore
    let provider: LaunchServicesOverrideProvider
    let restartFinder: @Sendable () async throws -> Void
    /// Whether an SF Symbol name exists on this Mac (FR-003); injectable for tests.
    let isValidSystemSymbol: @Sendable (String) -> Bool
    /// Xcode's asset tool, for custom glyphs only (004 research D5); injectable for tests.
    nonisolated let glyphTool: ActoolRunner

    private var config = AppConfiguration()
    /// Set when `config.json` can't be read (D3). No method writes the config then, except
    /// `resetAll`, which deletes it.
    public private(set) var readOnlyReason: String?
    /// False when the last read of the Favorites list failed (B1, D8).
    public private(set) var favoritesReadable = true
    /// Why the last apply failed, per mapping, for the status column.
    private var lastFailures: [UUID: String] = [:]
    /// True while an action runs (see `exclusive`).
    private var actionInProgress = false

    public init(
        container: ContainerLocator,
        system: any LaunchServicesSystem = SystemLaunchServices(),
        restartFinder: @escaping @Sendable () async throws -> Void = { _ = try await FinderRestarter.restart() },
        isValidSystemSymbol: @escaping @Sendable (String) -> Bool = MappingManager.systemSymbolExists,
        glyphTool: ActoolRunner = ActoolRunner()
    ) {
        self.glyphTool = glyphTool
        self.container = container
        self.store = ConfigStore(container: container)
        self.provider = LaunchServicesOverrideProvider(container: container, system: system)
        self.restartFinder = restartFinder
        self.isValidSystemSymbol = isValidSystemSymbol
    }

    /// An SF Symbol name is valid when AppKit can load it on this Mac (004 research D6).
    public static func systemSymbolExists(_ name: String) -> Bool {
        !name.isEmpty && NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil
    }

    /// Whether this macOS build is one the mechanism was verified on (D8).
    public nonisolated var macOSBuildVerified: Bool {
        SidebarIconCoreInfo.isVerified(build: SystemInfo.macOSBuild)
    }

    // MARK: - Reading

    /// Reads `config.json`. On `configUnreadable` the manager becomes read-only and rethrows.
    public func load() throws {
        do {
            config = try store.load()
            readOnlyReason = nil
        } catch let error as ManagerError {
            config = AppConfiguration()
            readOnlyReason = error.message
            throw error
        }
    }

    /// Read-only status of every mapping (research D7). Makes no outside changes.
    public func rows() async -> [MappingRow] {
        let mappings = config.mappings
        guard !mappings.isEmpty else {
            favoritesReadable = (try? provider.listFavorites()) != nil
            return []
        }
        var statuses: [UUID: MappingStatus] = [:]
        do {
            for status in try await provider.status(for: mappings) {
                statuses[status.mappingID] = status
            }
            favoritesReadable = true
        } catch {
            favoritesReadable = false
        }
        // `lsregister -dump` is slow, so it runs only when some override is in place.
        let anyOverrideSet = mappings.contains { statuses[$0.id]?.activeOverride == $0.osType }
        let registered = anyOverrideSet && ((try? provider.registrationStillListed()) ?? false)

        // An Off mapping whose override is still recorded could not be cleared. Taken from the
        // ledger, so it survives a relaunch (final review M-2).
        let recordedCodes = Set(((try? provider.ledgerEntries()) ?? []).filter { $0.kind == .sidebarOverride }.compactMap(\.osType))

        return mappings.map { mapping in
            let status = statuses[mapping.id] ?? MappingStatus(
                mappingID: mapping.id,
                folderPath: mapping.folderPath,
                folderExists: FileManager.default.fileExists(atPath: mapping.folderPath),
                favoriteCount: nil
            )
            var state = MappingState.state(
                for: mapping, status: status, bundleRegistered: registered,
                lastFailure: lastFailures[mapping.id]
                    ?? (!mapping.enabled && recordedCodes.contains(mapping.osType) ? Self.notClearedMessage : nil)
            )
            // The folder was renamed (case), or replaced by a link, since it was added: the stored
            // path no longer names the folder the sidebar shows. Reported, never rewritten.
            if mapping.enabled, status.folderExists {
                let now = PathStandardizer.standardize(mapping.folderPath)
                if now != mapping.folderPath {
                    state = .error(
                        "\(PathStandardizer.abbreviatingHome(mapping.folderPath)) now resolves to \(PathStandardizer.abbreviatingHome(now)), so this mapping no longer matches its folder."
                    )
                }
            }
            return MappingRow(
                id: mapping.id,
                folderPath: mapping.folderPath,
                displayName: URL(fileURLWithPath: mapping.folderPath).lastPathComponent,
                iconFile: iconFile(for: mapping),
                style: mapping.sidebarStyle,
                enabled: mapping.enabled,
                osType: mapping.osType,
                state: state
            )
        }
    }

    // MARK: - Story 1

    /// Adds a mapping for `folder` with a copy of `image`, then applies every enabled mapping
    /// (contracts/mapping-manager.md). If the image can't be read or converted, nothing is saved.
    public func add(folder: URL, image: URL) async throws -> ActionResult {
        try await exclusive { try await self.performAdd(folder: folder, icon: .image(image)) }
    }

    /// Adds a mapping drawn with a glyph style (system or custom), then applies (004 Stories 1–3).
    public func add(folder: URL, style: SidebarStyle) async throws -> ActionResult {
        try await exclusive { try await self.performAdd(folder: folder, icon: .style(style)) }
    }

    private enum NewIcon {
        case image(URL)
        case style(SidebarStyle)
    }

    private func performAdd(folder: URL, icon: NewIcon) async throws -> ActionResult {
        try requireWritable()
        guard (try? provider.listFavorites()) != nil else {
            favoritesReadable = false
            throw ManagerError.favoritesUnavailable
        }

        // 1. The folder: an existing directory, not already mapped by any spelling (FR-004).
        let path = try validatedNewFolder(folder, excluding: nil)

        // 2. The icon: copy and convert an image, or check a glyph style.
        var asset: IconAsset?
        let style: SidebarStyle
        switch icon {
        case .image(let image):
            let imported = try importAsset(image)
            asset = imported
            style = .fullColour(assetID: imported.id)
        case .style(let chosen):
            try validateGlyphStyle(chosen)
            style = chosen
        }

        // 3–4. Allocate a code and save; on failure the copied files are removed again.
        do {
            let code = try allocateCode()
            var next = config
            next.mappings.append(SidebarMapping(folderPath: path, sidebarStyle: style, osType: code))
            if let asset { next.assets.append(asset) }
            config = try store.save(next)
        } catch {
            if let asset { store.deleteFiles(of: asset) }
            throw Self.managerError(error)
        }

        // 5. Apply. The mapping is already saved, so a failure here is reported, not thrown.
        var result = await applyAfterSave()
        if result.rows.first(where: { $0.folderPath == path })?.state == .notInSidebar, !result.messages.contains(where: { $0.hasPrefix("Saved, but") }) {
            let shown = PathStandardizer.abbreviatingHome(path)
            result.messages.removeAll { $0 == SidebarIconError.folderNotInFavorites(path).message }
            result.messages.insert(
                "Saved. \(shown) isn't in Finder's sidebar Favorites yet; drag it there, then click Apply Now.", at: 0
            )
        }
        return result
    }

    /// Applies every enabled mapping again (Apply Now).
    public func applyNow() async throws -> ActionResult {
        try await exclusive {
            try await self.requireWritable()
            return try await self.applyAll()
        }
    }

    /// Changes how a mapping is drawn in the sidebar to a glyph style; its code stays the same
    /// (004 research D2). Full colour is set with `changeIcon(for:image:)`.
    public func setStyle(_ style: SidebarStyle, for id: UUID) async throws -> ActionResult {
        try await exclusive {
            try await self.validateGlyphStyle(style)
            try await self.change(id) { $0.mappings[$1].sidebarStyle = style }
            return await self.applyAfterSave(iconChangedFor: id)
        }
    }

    /// A system glyph must exist on this Mac (FR-003); a custom glyph must be one of the owner's.
    private func validateGlyphStyle(_ style: SidebarStyle) throws {
        switch style {
        case .systemSymbol(let name):
            guard isValidSystemSymbol(name) else { throw ManagerError.unknownSymbol(name) }
        case .customGlyph(let glyphID):
            guard config.glyph(glyphID) != nil else { throw ManagerError.unknownMapping }
        case .fullColour:
            throw ManagerError.unknownMapping
        }
    }

    // MARK: - Custom glyphs (004 Story 2)

    /// The owner's custom glyphs, for the Custom glyph tab.
    public func glyphs() -> [CustomGlyph] { config.glyphs }

    /// Whether custom glyphs can be built on this Mac (runs `xcrun --find actool`).
    public nonisolated func glyphToolStatus() -> ToolStatus { glyphTool.toolStatus() }

    /// Imports a symbol template under `name` (the manual process, research D4b). A new name adds
    /// a glyph; an existing name gets a new version, so Finder shows the new drawing at once.
    /// The combined car is rebuilt first; if that fails nothing is saved.
    public func importGlyph(name: String, template: URL) async throws -> ActionResult {
        try await exclusive { try await self.performImportGlyph(name: name, template: template) }
    }

    private func performImportGlyph(name rawName: String, template: URL) async throws -> ActionResult {
        try requireWritable()
        let name = rawName.trimmingCharacters(in: .whitespaces)
        guard CustomGlyph.isValidName(name) else { throw ManagerError.invalidGlyphName(name) }
        let data: Data
        do {
            data = try Data(contentsOf: template)
        } catch {
            throw ManagerError.glyphBuild(.templateUnreadable(template.lastPathComponent))
        }
        guard data.count <= SVGShapeReader.maximumFileSize else {
            throw ManagerError.glyphBuild(.templateUnreadable("\(template.lastPathComponent) is larger than 1 MB"))
        }
        guard SymbolTemplateWriter.hasRequiredGlyph(String(decoding: data, as: UTF8.self)) else {
            throw ManagerError.glyphBuild(.missingRequiredGlyph(template.lastPathComponent))
        }
        if case .unavailable(let reason) = glyphTool.toolStatus() {
            throw ManagerError.glyphBuild(.toolUnavailable(reason))
        }

        var next = config
        let glyph: CustomGlyph
        if let index = next.glyphs.firstIndex(where: { $0.name == name }) {
            glyph = CustomGlyph(id: next.glyphs[index].id, name: name)
            next.glyphs[index] = glyph
        } else {
            glyph = CustomGlyph(name: name)
            next.glyphs.append(glyph)
        }
        try refuseLinkedGlyphFolders()
        let templateCopy = container.glyphsDirectory.appending(path: glyph.templateFileName)
        do {
            try FileManager.default.createDirectory(at: container.glyphsDirectory, withIntermediateDirectories: true)
            try data.write(to: templateCopy)
            try buildCar(for: next.glyphs)
            config = try store.save(next)
        } catch {
            try? FileManager.default.removeItem(at: templateCopy)
            throw Self.managerError(error)
        }
        var result = await applyAfterSave()
        result.messages.insert("Imported the glyph \(name).", at: 0)
        return result
    }

    /// Deletes a glyph. Mappings that use it switch to `replacement` first (FR-010); without
    /// one, a glyph in use is refused.
    public func deleteGlyph(_ id: UUID, replacement: SidebarStyle? = nil) async throws -> ActionResult {
        try await exclusive { try await self.performDeleteGlyph(id, replacement: replacement) }
    }

    private func performDeleteGlyph(_ id: UUID, replacement: SidebarStyle?) async throws -> ActionResult {
        try requireWritable()
        guard let glyph = config.glyph(id) else { throw ManagerError.unknownMapping }
        var next = config
        let users = next.mappings.indices.filter { next.mappings[$0].glyphID == id }
        if !users.isEmpty {
            guard let replacement else { throw ManagerError.glyphInUse(glyph.name) }
            if case .customGlyph(let other) = replacement, other == id { throw ManagerError.glyphInUse(glyph.name) }
            try validateGlyphStyle(replacement)
            for index in users { next.mappings[index].sidebarStyle = replacement }
        }
        next.glyphs.removeAll { $0.id == id }
        do {
            config = try store.save(next)
        } catch {
            throw Self.managerError(error)
        }
        // The old car still holds every remaining glyph, so a failed rebuild is harmless: apply
        // keeps using it until the next successful build.
        if next.glyphs.isEmpty {
            removeCar()
        } else if case .available = glyphTool.toolStatus() {
            try? buildCar(for: next.glyphs)
        }
        var result = await applyAfterSave()
        result.messages.insert("Deleted the glyph \(glyph.name).", at: 0)
        return result
    }

    /// Builds the combined car for `glyphs` in `Build/<id>/` and installs it as
    /// `Glyphs/Assets.car` with `Glyphs/Assets.key` (their sorted version IDs). The previous car
    /// stays until the new one is built; the build folder is always deleted.
    private func buildCar(for glyphs: [CustomGlyph]) throws {
        try refuseLinkedGlyphFolders()
        let fileManager = FileManager.default
        let build = container.buildDirectory.appending(path: UUID().uuidString.lowercased(), directoryHint: .isDirectory)
        defer { try? fileManager.removeItem(at: build) }
        let items = glyphs.map {
            AssetCatalogWriter.Item(symbolName: $0.symbolName, template: container.glyphsDirectory.appending(path: $0.templateFileName))
        }
        let output = build.appending(path: "out", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: output, withIntermediateDirectories: true)
        try AssetCatalogWriter.write(items, to: build.appending(path: "Glyphs.xcassets", directoryHint: .isDirectory))
        let car = try glyphTool.compile(catalog: build.appending(path: "Glyphs.xcassets"), outputDirectory: output,
                                        partialInfoPlist: build.appending(path: "partial.plist"))
        let target = container.glyphsDirectory.appending(path: "Assets.car")
        if fileManager.fileExists(atPath: target.path) {
            _ = try fileManager.replaceItemAt(target, withItemAt: car)
        } else {
            try fileManager.moveItem(at: car, to: target)
        }
        try Data(Self.carKey(glyphs).utf8).write(to: container.glyphsDirectory.appending(path: "Assets.key"), options: .atomic)
    }

    private func removeCar() {
        guard !container.isSymbolicLink(container.glyphsDirectory) else { return }
        for name in ["Assets.car", "Assets.key"] {
            try? FileManager.default.removeItem(at: container.glyphsDirectory.appending(path: name))
        }
    }

    private func refuseLinkedGlyphFolders() throws {
        for folder in [container.glyphsDirectory, container.buildDirectory] where container.isSymbolicLink(folder) {
            throw ManagerError.sidebar(.unexpectedLedgerTarget(folder.path))
        }
    }

    static func carKey(_ glyphs: [CustomGlyph]) -> String {
        glyphs.map { $0.versionID.uuidString.lowercased() }.sorted().joined(separator: "\n") + "\n"
    }

    private func carKeyOnDisk() -> Set<String> {
        let url = container.glyphsDirectory.appending(path: "Assets.key")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return Set(text.split(separator: "\n").map(String.init))
    }

    // MARK: - Story 2

    /// Turns a mapping on or off. Off clears its override and keeps the mapping (FR-005).
    public func setEnabled(_ enabled: Bool, for id: UUID) async throws -> ActionResult {
        try await exclusive {
            try await self.change(id) { $0.mappings[$1].enabled = enabled }
            return await self.applyAfterSave()
        }
    }

    /// Removes a mapping: its override is cleared and its copied image deleted. The folder is not
    /// changed. Removing the last enabled mapping also unregisters the registry bundle.
    public func remove(_ id: UUID) async throws -> ActionResult {
        try await exclusive {
            try await self.change(id) { config, index in
                let mapping = config.mappings.remove(at: index)
                self.lastFailures[mapping.id] = nil
            }
            return await self.applyAfterSave()
        }
    }

    /// Gives a mapping a new image. The code is kept; the image gets a new asset id, so the type id
    /// changes and Finder's icon cache can't show the old art (research D5). The old asset's files
    /// are deleted when the config is saved; the registry bundle holds its own copy until rewritten.
    public func changeIcon(for id: UUID, image: URL) async throws -> ActionResult {
        try await exclusive {
            try await self.requireWritable()
            guard await self.config.mappings.contains(where: { $0.id == id }) else { throw ManagerError.unknownMapping }
            let asset = try await self.importAsset(image)
            do {
                try await self.change(id) { config, index in
                    config.mappings[index].sidebarStyle = .fullColour(assetID: asset.id)
                    config.assets.append(asset)
                }
            } catch {
                await self.store.deleteFiles(of: asset)
                throw error
            }
            return await self.applyAfterSave(iconChangedFor: id)
        }
    }

    /// Points a mapping at another folder (for example after the folder moved). Same folder checks
    /// as Add (FR-004); the mapping keeps its code and icon.
    public func repoint(_ id: UUID, to folder: URL) async throws -> ActionResult {
        try await exclusive {
            try await self.requireWritable()
            let path = try await self.validatedNewFolder(folder, excluding: id)
            try await self.change(id) { $0.mappings[$1].folderPath = path }
            return await self.applyAfterSave()
        }
    }

    /// Applies `edit` to a copy of the config for mapping `id` and saves it.
    private func change(_ id: UUID, _ edit: (inout AppConfiguration, Int) -> Void) throws {
        try requireWritable()
        guard let index = config.mappings.firstIndex(where: { $0.id == id }) else { throw ManagerError.unknownMapping }
        var next = config
        edit(&next, index)
        do {
            config = try store.save(next)
        } catch {
            throw Self.managerError(error)
        }
    }

    // MARK: - Story 4

    /// Applies, then restarts Finder (Refresh Finder). A Finder that fails to restart is reported,
    /// not thrown.
    public func refreshFinder() async throws -> ActionResult {
        try await exclusive { try await self.performRefreshFinder() }
    }

    private func performRefreshFinder() async throws -> ActionResult {
        var messages: [String] = []
        if readOnlyReason == nil, !config.mappings.isEmpty {
            do {
                messages += try await applyAll().messages
            } catch let error as ManagerError {
                messages.append(error.message)
            }
        }
        do {
            try await restartFinder()
            messages.append("Finder restarted.")
        } catch {
            messages.append("Finder could not be restarted: \(error)")
        }
        return ActionResult(rows: await rows(), messages: messages)
    }

    /// Undoes every recorded change, then deletes the mappings and copied images (Reset All).
    /// Works in read-only mode and with unreadable Favorites (FR-010). If some changes can't be
    /// undone, only the mappings whose changes are still recorded are kept.
    public func resetAll() async throws -> ActionResult {
        try await exclusive { try await self.performResetAll() }
    }

    private func performResetAll() async throws -> ActionResult {
        let report: ResetReport
        do {
            report = try await provider.reset()
        } catch {
            throw Self.managerError(error)
        }
        lastFailures = [:]
        var messages: [String] = []

        if report.succeeded {
            messages += provider.removeUnrecordedRegistryFiles()
            try store.remove()
            if FileManager.default.fileExists(atPath: container.iconsDirectory.path) {
                do {
                    try FileManager.default.removeItem(at: container.iconsDirectory)
                } catch {
                    messages.append("The copied images could not all be deleted: \(error.localizedDescription)")
                }
            }
            for folder in [container.glyphsDirectory, container.buildDirectory]
            where FileManager.default.fileExists(atPath: folder.path) || container.isSymbolicLink(folder) {
                do {
                    try FileManager.default.removeItem(at: folder)
                } catch {
                    messages.append("\(folder.lastPathComponent) could not be deleted: \(error.localizedDescription)")
                }
            }
            config = AppConfiguration()
            readOnlyReason = nil
            messages.insert(
                report.undone.isEmpty
                    ? "Nothing to reset; your mappings and copied images were removed."
                    : "Removed every custom sidebar icon, mapping and copied image.",
                at: 0
            )
        } else {
            messages += report.failed.map(\.reason.message)
            if readOnlyReason == nil {
                // Errors here are added to the messages so the list of failures above is kept.
                do {
                    let recorded = Set(try provider.ledgerEntries().filter { $0.kind == .sidebarOverride }.compactMap(\.osType))
                    var next = config
                    next.mappings = config.mappings.filter { recorded.contains($0.osType) }
                    config = try store.save(next)
                } catch {
                    messages.append(Self.managerError(error).message)
                }
            }
            messages.append("Some changes could not be undone and are still recorded. Fix the cause, then click Reset All again.")
        }
        return ActionResult(rows: await rows(), messages: messages, needsRefresh: report.succeeded && !report.undone.isEmpty)
    }

    // MARK: - Helpers

    /// Runs one action at a time; a second action while one is running is refused.
    private func exclusive<T: Sendable>(_ action: () async throws -> T) async throws -> T {
        guard !actionInProgress else { throw ManagerError.busy }
        actionInProgress = true
        defer { actionInProgress = false }
        return try await action()
    }

    /// The standardized path of `folder` if it is an existing directory that no other mapping
    /// (other than `excluding`) already uses, by any spelling (FR-004).
    private func validatedNewFolder(_ folder: URL, excluding id: UUID?) throws -> String {
        let path = PathStandardizer.standardize(folder.path)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw ManagerError.notAFolder(path)
        }
        if let existing = config.mappings.first(where: { $0.id != id && PathStandardizer.standardize($0.folderPath) == path }) {
            throw ManagerError.duplicateFolder(existing: existing.folderPath)
        }
        return path
    }

    private func requireWritable() throws {
        if readOnlyReason != nil { throw ManagerError.readOnly }
    }

    /// The combined car holding every custom glyph, kept in `Glyphs/` (004 research D4b, T028).
    /// Rebuilt only when the glyph set changed (`Assets.key`); without the tool, an existing car
    /// that holds every glyph the enabled mappings use is still used.
    func currentAssetsCar() -> URL? {
        let car = container.glyphsDirectory.appending(path: "Assets.car")
        let needed = Set(config.mappings.filter(\.enabled).compactMap(\.glyphID).compactMap { config.glyph($0) }
            .map { $0.versionID.uuidString.lowercased() })
        guard !needed.isEmpty, !container.isSymbolicLink(container.glyphsDirectory) else { return nil }
        let all = Set(config.glyphs.map { $0.versionID.uuidString.lowercased() })
        let onDisk = carKeyOnDisk()
        let carExists = FileManager.default.fileExists(atPath: car.path)
        if carExists, onDisk == all { return car }
        if case .available = glyphTool.toolStatus(), (try? buildCar(for: config.glyphs)) != nil { return car }
        return carExists && needed.isSubset(of: onDisk) ? car : nil
    }

    private func iconFile(for mapping: SidebarMapping) -> URL {
        let name = config.asset(for: mapping)?.fileName ?? ""
        return container.iconsDirectory.appending(path: LaunchServicesOverrideProvider.isPlainFileName(name) ? name : "missing")
    }

    /// Copies `image` into `Icons/` under a new asset id and converts it (research D5).
    private func importAsset(_ image: URL) throws -> IconAsset {
        guard !container.iconsDirectoryIsSymbolicLink else {
            throw ManagerError.sidebar(.unexpectedLedgerTarget(container.iconsDirectory.path))
        }
        let id = UUID()
        var asset: IconAsset
        do {
            asset = try AssetImporter.importFile(at: image, into: container.iconsDirectory, id: id)
        } catch {
            throw ManagerError.imageUnreadable(image.lastPathComponent)
        }
        if asset.sourceFormat == .icns {
            guard ICNSConverter.isUsableICNS(at: container.iconsDirectory.appending(path: asset.fileName)) else {
                store.deleteFiles(of: asset)
                throw ManagerError.imageUnreadable(image.lastPathComponent)
            }
            return asset
        }
        asset.icnsFileName = "\(id.uuidString).icns"
        do {
            _ = try provider.icnsFile(for: asset)
        } catch {
            store.deleteFiles(of: asset)
            throw ManagerError.imageUnreadable(image.lastPathComponent)
        }
        return asset
    }

    /// The next code not used by a mapping or the ledger and not claimed by another registered
    /// bundle or type (research D4). One `lsregister -dump` checks a window of 32 candidates; if
    /// every one is claimed, the next window is checked. Only checked codes are handed out.
    private func allocateCode() throws -> String {
        var excluded = Set(config.mappings.map(\.osType)).union(try provider.ledgerEntries().compactMap(\.osType))
        while true {
            let candidates = try OSTypeAllocator.allocate(32, excluding: excluded)
            let claimed = try provider.codesClaimedElsewhere(among: Set(candidates))
            if let code = candidates.first(where: { !claimed.contains($0) }) {
                return code
            }
            excluded.formUnion(candidates)
        }
    }

    /// Applies every enabled mapping and records per-mapping failures for the status column.
    /// Applies after a change was saved. The change stands, so an apply failure is returned as a
    /// message ("Saved, but not applied: …"), never thrown (the row would otherwise vanish while
    /// the alert says the action failed).
    private func applyAfterSave(iconChangedFor changed: UUID? = nil) async -> ActionResult {
        do {
            return try await applyAll(iconChangedFor: changed)
        } catch {
            return ActionResult(rows: await rows(), messages: ["Saved, but not applied: \(Self.managerError(error).message)"])
        }
    }

    /// `iconChangedFor` asks for the refresh hint when that mapping was applied even though its
    /// override didn't change (Change Icon keeps the code; the new art arrives through a new type).
    private func applyAll(iconChangedFor changed: UUID? = nil) async throws -> ActionResult {
        var messages: [String] = []
        var needsRefresh = false
        // Which overrides are already in place, so the refresh hint only follows a real change.
        let before = (try? provider.listFavorites()) ?? []
        do {
            let report = try await provider.apply(config.mappings, assets: config.assets, glyphs: config.glyphs,
                                                  assetsCar: currentAssetsCar())
            for id in report.applied {
                lastFailures[id] = nil
            }
            for skip in report.skipped {
                switch skip.reason {
                case .folderNotInFavorites, .folderMissing:
                    lastFailures[skip.mappingID] = nil
                default:
                    lastFailures[skip.mappingID] = skip.reason.message
                }
                messages.append(skip.reason.message)
            }
            // A mapping turned off whose override is still recorded could not be cleared (#2).
            let recordedCodes = Set(try provider.ledgerEntries().filter { $0.kind == .sidebarOverride }.compactMap(\.osType))
            for mapping in config.mappings where !mapping.enabled {
                lastFailures[mapping.id] = recordedCodes.contains(mapping.osType) ? Self.notClearedMessage : nil
            }
            // The R7 note is a diagnostic for the spike's log, not for the owner.
            messages += report.notes.filter { !$0.hasPrefix("R7:") }
            let applied = Set(report.applied)
            needsRefresh = changed.map(applied.contains) == true || config.mappings.contains { mapping in
                applied.contains(mapping.id)
                    && !before.contains { $0.path == mapping.folderPath && $0.overrideIcon == mapping.osType }
            }
        } catch {
            let error = LaunchServicesOverrideProvider.sidebarError(error)
            if error == .favoritesUnavailable {
                favoritesReadable = false
                throw ManagerError.favoritesUnavailable
            }
            let affected: [SidebarMapping]
            if case .codeClaimedElsewhere(let code, _) = error {
                affected = config.mappings.filter { $0.osType == code }
            } else {
                affected = config.mappings.filter(\.enabled)
            }
            for mapping in affected {
                lastFailures[mapping.id] = error.message
            }
            messages.append(error.message)
        }
        return ActionResult(rows: await rows(), messages: messages, needsRefresh: needsRefresh)
    }

    static let notClearedMessage = "Its sidebar icon could not be removed. Try again, or use Reset All."

    static func managerError(_ error: any Error) -> ManagerError {
        switch error {
        case let error as ManagerError: error
        case let error as SidebarIconError: .sidebar(error)
        case let error as GlyphBuildError: .glyphBuild(error)
        case OSTypeAllocationError.exhausted: .sidebar(.invalidMapping("no unused type code is left"))
        default: .sidebar(.toolFailed(String(describing: error)))
        }
    }
}
