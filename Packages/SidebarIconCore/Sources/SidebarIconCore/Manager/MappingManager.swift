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
    /// The opted-in folder icon (004 Story 4).
    public var folderIcon: FolderIconState = .notSet
    /// Whether the owner opted in to a folder icon for this mapping.
    public var folderIconOptedIn = false
    /// The stored path now resolves to another folder (renamed, or replaced by a link), so the
    /// mapping no longer matches it; Re-point… fixes it (final review 2).
    public var resolvesElsewhere = false

    /// Re-point… helps: the folder is missing or now resolves elsewhere.
    public var offersRepoint: Bool { state == .folderMissing || resolvesElsewhere }

    /// Remove or Reset All would touch the folder: its icon is opted in or still recorded.
    public var hasFolderIcon: Bool { folderIconOptedIn || folderIcon != .notSet }
}

/// The owner's folder art (004 Story 4): a master (PNG of at least 1024 px, PDF or SVG) and
/// optional hand-tuned sizes keyed by `.iconset` name (`icon_16x16`, …).
public struct FolderArt: Sendable, Equatable {
    public var master: URL
    public var overrides: [String: URL]

    public init(master: URL, overrides: [String: URL] = [:]) {
        self.master = master
        self.overrides = overrides
    }
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
    /// The opt-in folder icons (004 Story 4, research D8).
    let folderIcons: FolderIconProvider

    private var config = AppConfiguration()
    /// Set when `config.json` can't be read (D3). No method writes the config then, except
    /// `resetAll`, which deletes it.
    public private(set) var readOnlyReason: String?
    /// False when the last read of the Favorites list failed (B1, D8).
    public private(set) var favoritesReadable = true
    /// Why the last apply failed, per mapping, for the status column.
    private var lastFailures: [UUID: String] = [:]
    /// Why the folder icon couldn't be set, per mapping, for the row badge.
    private var folderIconFailures: [UUID: String] = [:]
    /// True while an action runs (see `exclusive`).
    private var actionInProgress = false

    public init(
        container: ContainerLocator,
        system: any LaunchServicesSystem = SystemLaunchServices(),
        restartFinder: @escaping @Sendable () async throws -> Void = { _ = try await FinderRestarter.restart() },
        isValidSystemSymbol: @escaping @Sendable (String) -> Bool = MappingManager.systemSymbolExists,
        glyphTool: ActoolRunner = ActoolRunner(),
        folderIconWriter: any FolderIconWriting = SystemFolderIconWriter()
    ) {
        self.glyphTool = glyphTool
        self.folderIcons = FolderIconProvider(writer: folderIconWriter, ledger: LedgerStore(url: container.ledgerURL),
                                              backupsDirectory: container.folderIconBackupsDirectory)
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
            try requireRealContainer()
            config = try store.load()
            readOnlyReason = nil
        } catch let error as ManagerError {
            config = AppConfiguration()
            readOnlyReason = error.message
            throw error
        }
    }

    /// Whether the ledger records any folder icon, for the Reset All confirmation (final review 6):
    /// a read-only configuration shows no rows, but Reset All still puts those folders back.
    public func hasFolderIconRecords() -> Bool {
        ((try? provider.ledgerEntries()) ?? []).contains { $0.kind == .folderIcon }
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
        let ledgerEntries = (try? provider.ledgerEntries()) ?? []
        let recordedCodes = Set(ledgerEntries.filter { $0.kind == .sidebarOverride }.compactMap(\.osType))
        let folderIconEntries = Dictionary(ledgerEntries.filter { $0.kind == .folderIcon }.map { ($0.target, $0) },
                                           uniquingKeysWith: { first, _ in first })

        return mappings.map { mapping in
            let status = statuses[mapping.id] ?? MappingStatus(
                mappingID: mapping.id,
                folderPath: mapping.folderPath,
                folderExists: FileManager.default.fileExists(atPath: mapping.folderPath),
                favoriteCount: nil
            )
            var resolvesElsewhere = false
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
                    resolvesElsewhere = true
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
                state: state,
                folderIcon: folderIconState(for: mapping, entry: folderIconEntries[mapping.folderPath]),
                folderIconOptedIn: mapping.folderIcon?.enabled == true,
                resolvesElsewhere: resolvesElsewhere
            )
        }
    }

    private func folderIconState(for mapping: SidebarMapping, entry: OutsideChange?) -> FolderIconState {
        if let entry {
            if entry.fingerprint == nil { return .failed(ManagerError.folderIconUnverified(entry.target).message) }
            if !FileManager.default.fileExists(atPath: entry.target) { return .folderMissing }
            return folderIcons.isUnchanged(entry) ? .set : .changedElsewhere
        }
        if let failure = folderIconFailures[mapping.id] { return .failed(failure) }
        return .notSet
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
        // A bounded read: a huge, growing or special file is never loaded whole.
        let data: Data
        do {
            data = try SVGShapeReader.boundedData(contentsOf: template)
        } catch SVGReadError.tooLarge {
            throw ManagerError.glyphBuild(.templateUnreadable("\(template.lastPathComponent) is larger than 1 MB"))
        } catch {
            throw ManagerError.glyphBuild(.templateUnreadable(template.lastPathComponent))
        }
        guard SymbolTemplateWriter.hasRequiredGlyph(String(decoding: data, as: UTF8.self)) else {
            throw ManagerError.glyphBuild(.missingRequiredGlyph(template.lastPathComponent))
        }
        if case .unavailable(let reason) = glyphTool.toolStatus() {
            throw ManagerError.glyphBuild(.toolUnavailable(reason))
        }

        let existing = config.glyphs.first(where: { $0.name == name })
        let glyph = CustomGlyph(id: existing?.id ?? UUID(), name: name)
        return try await storeGlyph(glyph, template: data, source: nil, message: "Imported the glyph \(name).")
    }

    /// The wizard's path (004 US3): reads the owner's plain SVG, writes the symbol template as
    /// `make-symbol-template` would, and builds the glyph. The SVG is kept as
    /// `Glyphs/<versionID>.svg`. A name already in use is refused; `updateGlyph` changes a glyph.
    public func createGlyph(name: String, svg: URL) async throws -> ActionResult {
        try await exclusive { try await self.performCreateGlyph(name: name, drawing: { try Self.drawingData(svg) }) }
    }

    /// The same with the drawing's bytes, so the wizard builds exactly what it previewed.
    public func createGlyph(name: String, drawing: Data) async throws -> ActionResult {
        try await exclusive { try await self.performCreateGlyph(name: name, drawing: { drawing }) }
    }

    private func performCreateGlyph(name rawName: String, drawing: () throws -> Data) async throws -> ActionResult {
        try requireWritable()
        let name = rawName.trimmingCharacters(in: .whitespaces)
        guard CustomGlyph.isValidName(name) else { throw ManagerError.invalidGlyphName(name) }
        guard !config.glyphs.contains(where: { $0.name == name }) else { throw ManagerError.glyphNameTaken(name) }
        let (source, template) = try readDrawing(try drawing())
        let version = UUID()
        let glyph = CustomGlyph(name: name, versionID: version, sourceFileName: "\(version.uuidString.lowercased()).svg")
        return try await storeGlyph(glyph, template: template, source: source, message: "Created the glyph \(name).")
    }

    /// A new drawing for an existing glyph: a new version, so every folder using the glyph shows
    /// the new drawing without restarting Finder (FR-011).
    public func updateGlyph(_ id: UUID, svg: URL) async throws -> ActionResult {
        try await exclusive { try await self.performUpdateGlyph(id, drawing: { try Self.drawingData(svg) }) }
    }

    public func updateGlyph(_ id: UUID, drawing: Data) async throws -> ActionResult {
        try await exclusive { try await self.performUpdateGlyph(id, drawing: { drawing }) }
    }

    private func performUpdateGlyph(_ id: UUID, drawing: () throws -> Data) async throws -> ActionResult {
        try requireWritable()
        guard let current = config.glyph(id) else { throw ManagerError.unknownGlyph }
        let (source, template) = try readDrawing(try drawing())
        let version = UUID()
        let glyph = CustomGlyph(id: id, name: current.name, versionID: version,
                                sourceFileName: "\(version.uuidString.lowercased()).svg")
        return try await storeGlyph(glyph, template: template, source: source, message: "Updated the glyph \(current.name).")
    }

    /// The drawing's bytes and its symbol template. Refusals carry the reader's guidance; the tool
    /// is checked only after the drawing passes, so a refusal is explained even without Xcode.
    private func readDrawing(_ data: Data) throws -> (source: Data, template: Data) {
        let template: String
        do {
            template = SymbolTemplateWriter.template(for: try SVGShapeReader.read(data))
        } catch let error as SVGReadError {
            throw ManagerError.drawingRefused(error)
        }
        guard SymbolTemplateWriter.hasRequiredGlyph(template) else {
            throw ManagerError.glyphBuild(.missingRequiredGlyph("the drawing"))
        }
        if case .unavailable(let reason) = glyphTool.toolStatus() {
            throw ManagerError.glyphBuild(.toolUnavailable(reason))
        }
        return (data, Data(template.utf8))
    }

    /// A drawing file's bytes, read with the reader's size bound (never loaded whole).
    private static func drawingData(_ svg: URL) throws -> Data {
        do {
            return try SVGShapeReader.boundedData(contentsOf: svg)
        } catch let error as SVGReadError {
            throw ManagerError.drawingRefused(error)
        }
    }

    /// Adds `glyph`, or replaces the glyph with its id, then builds and applies. The new files and
    /// the staged car are the only things written before the save; the combined car in Glyphs/
    /// changes only after the save succeeds (review M2). The previous version's files are removed
    /// by the save.
    private func storeGlyph(_ glyph: CustomGlyph, template: Data, source: Data?, message: String) async throws -> ActionResult {
        var next = config
        if let index = next.glyphs.firstIndex(where: { $0.id == glyph.id }) {
            next.glyphs[index] = glyph
        } else {
            next.glyphs.append(glyph)
        }
        try refuseLinkedGlyphFolders()
        let written = [
            (glyph.templateFileName, template),
            glyph.sourceFileName.flatMap { name in source.map { (name, $0) } },
        ].compactMap { $0 }.map { (container.glyphsDirectory.appending(path: $0.0), $0.1) }
        let removeWritten = { for (url, _) in written { try? FileManager.default.removeItem(at: url) } }
        let staged: StagedCar
        do {
            try FileManager.default.createDirectory(at: container.glyphsDirectory, withIntermediateDirectories: true)
            for (url, data) in written { try data.write(to: url) }
            staged = try stageCar(for: next.glyphs)
        } catch {
            removeWritten()
            throw Self.managerError(error)
        }
        defer { staged.discard() }
        do {
            config = try store.save(next)
        } catch {
            removeWritten()
            throw Self.managerError(error)
        }
        var installNote: String?
        do {
            try installCar(staged)
        } catch {
            installNote = "The glyph was saved, but its build couldn't be stored (\(error.localizedDescription)); Apply Now builds it again."
        }
        var result = await applyAfterSave()
        result.messages.insert(message, at: 0)
        if let installNote { result.messages.insert(installNote, at: 1) }
        return result
    }

    /// Deletes a glyph. Mappings that use it switch to `replacement` first (FR-010); without
    /// one, a glyph in use is refused.
    public func deleteGlyph(_ id: UUID, replacement: SidebarStyle? = nil) async throws -> ActionResult {
        try await exclusive { try await self.performDeleteGlyph(id, replacement: replacement) }
    }

    private func performDeleteGlyph(_ id: UUID, replacement: SidebarStyle?) async throws -> ActionResult {
        try requireWritable()
        guard let glyph = config.glyph(id) else { throw ManagerError.unknownGlyph }
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
        } else if case .available = glyphTool.toolStatus(), let staged = try? stageCar(for: next.glyphs) {
            try? installCar(staged)
            staged.discard()
        }
        var result = await applyAfterSave()
        result.messages.insert("Deleted the glyph \(glyph.name).", at: 0)
        return result
    }

    /// A combined car built in `Build/<id>/`, not yet installed.
    struct StagedCar {
        let buildFolder: URL
        let car: URL
        let key: String

        func discard() { try? FileManager.default.removeItem(at: buildFolder) }
    }

    /// Builds the combined car for `glyphs` in `Build/<id>/`. Glyphs/ is not touched; on failure
    /// the build folder is deleted.
    private func stageCar(for glyphs: [CustomGlyph]) throws -> StagedCar {
        try refuseLinkedGlyphFolders()
        let fileManager = FileManager.default
        let build = container.buildDirectory.appending(path: UUID().uuidString.lowercased(), directoryHint: .isDirectory)
        do {
            let items = glyphs.map {
                AssetCatalogWriter.Item(symbolName: $0.symbolName, template: container.glyphsDirectory.appending(path: $0.templateFileName))
            }
            let output = build.appending(path: "out", directoryHint: .isDirectory)
            try fileManager.createDirectory(at: output, withIntermediateDirectories: true)
            let catalog = build.appending(path: "Glyphs.xcassets", directoryHint: .isDirectory)
            try AssetCatalogWriter.write(items, to: catalog)
            let car = try glyphTool.compile(catalog: catalog, outputDirectory: output,
                                            partialInfoPlist: build.appending(path: "partial.plist"))
            return StagedCar(buildFolder: build, car: car, key: Self.carKey(glyphs))
        } catch {
            try? fileManager.removeItem(at: build)
            throw error
        }
    }

    /// Installs a staged car as `Glyphs/Assets.car` with `Glyphs/Assets.key` (sorted version
    /// IDs). The key is removed first and written last, so a failure in between leaves no key:
    /// the car is then rebuilt rather than trusted.
    private func installCar(_ staged: StagedCar) throws {
        try refuseLinkedGlyphFolders()
        let fileManager = FileManager.default
        let key = container.glyphsDirectory.appending(path: "Assets.key")
        let target = container.glyphsDirectory.appending(path: "Assets.car")
        if fileManager.fileExists(atPath: key.path) { try fileManager.removeItem(at: key) }
        if fileManager.fileExists(atPath: target.path) {
            _ = try fileManager.replaceItemAt(target, withItemAt: staged.car)
        } else {
            try fileManager.moveItem(at: staged.car, to: target)
        }
        try Data(staged.key.utf8).write(to: key, options: .atomic)
    }

    private func removeCar() {
        guard !container.isSymbolicLink(container.glyphsDirectory) else { return }
        for name in ["Assets.car", "Assets.key"] {
            try? FileManager.default.removeItem(at: container.glyphsDirectory.appending(path: name))
        }
    }

    /// Security review M1: refuses to touch a data folder reached through a link.
    private func requireRealContainer() throws {
        do {
            try container.requireRealRoot()
        } catch {
            throw ManagerError.containerLinked(container.root.path)
        }
    }

    private func refuseLinkedGlyphFolders() throws {
        for folder in [container.glyphsDirectory, container.buildDirectory, container.folderIconBackupsDirectory]
        where container.isSymbolicLink(folder) {
            throw ManagerError.sidebar(.unexpectedLedgerTarget(folder.path))
        }
    }

    static func carKey(_ glyphs: [CustomGlyph]) -> String {
        glyphs.map { $0.versionID.uuidString.lowercased() }.sorted().joined(separator: "\n") + "\n"
    }

    private func carKeyOnDisk() -> Set<String> {
        let url = container.glyphsDirectory.appending(path: "Assets.key")
        guard let data = try? ContainerFile.read(url), let text = String(data: data, encoding: .utf8) else { return [] }
        return Set(text.split(separator: "\n").map(String.init))
    }

    // MARK: - Story 2

    /// Turns a mapping on or off. Off clears its override and keeps the mapping (FR-005).
    public func setEnabled(_ enabled: Bool, for id: UUID) async throws -> ActionResult {
        try await exclusive {
            try await self.change(id) { $0.mappings[$1].enabled = enabled }
            var result = await self.applyAfterSave()
            // An opted-in folder icon follows the mapping: Off puts the folder back (FR-014), On sets it again.
            if let mapping = await self.config.mappings.first(where: { $0.id == id }) {
                let notes = enabled ? await self.applyFolderIcon(for: mapping) : await self.undoFolderIcon(for: mapping)
                result.messages += notes
                result.rows = await self.rows()
            }
            return result
        }
    }

    /// Removes a mapping: its override is cleared and its copied image deleted. The folder is not
    /// changed. Removing the last enabled mapping also unregisters the registry bundle.
    public func remove(_ id: UUID) async throws -> ActionResult {
        try await exclusive {
            // The folder is put back first; if macOS refuses, the mapping stays so it can be tried again.
            var notes: [String] = []
            if let mapping = await self.config.mappings.first(where: { $0.id == id }) {
                notes = try await self.undoFolderIconOrThrow(at: mapping.folderPath)
                await self.clearFolderIconFailure(id)
            }
            try await self.change(id) { config, index in
                let mapping = config.mappings.remove(at: index)
                self.lastFailures[mapping.id] = nil
            }
            var result = await self.applyAfterSave()
            result.messages = notes + result.messages
            return result
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
            let oldPath = await self.config.mappings.first(where: { $0.id == id })?.folderPath
            // A folder that moved and still shows our icon keeps its record (review H2); otherwise the
            // old folder is put back before the mapping moves (FR-014).
            var notes: [String] = []
            var followed = false
            if let oldPath {
                followed = try await self.followFolderIcon(from: oldPath, to: path)
                if !followed { notes = try await self.undoFolderIconOrThrow(at: oldPath) }
            }
            do {
                try await self.change(id) { config, index in
                    config.mappings[index].folderPath = path
                    // A yes to replace one folder's icon is not a yes for another folder (review M1).
                    if !followed {
                        config.mappings[index].folderIcon?.replaceExisting = false
                        config.mappings[index].folderIcon?.confirmedFingerprint = nil
                    }
                }
            } catch {
                // The record goes back to the path the config still names (final review 7).
                if followed, let oldPath { try? await self.folderIcons.unfollow(path, back: oldPath) }
                throw error
            }
            var result = await self.applyAfterSave()
            if let mapping = await self.config.mappings.first(where: { $0.id == id }) {
                notes += await self.applyFolderIcon(for: mapping)
            }
            result.messages = notes + result.messages
            result.rows = await self.rows()
            return result
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

    // MARK: - Folder icons (004 Story 4)

    /// Sets the folder's own Finder icon from `art`, or turns it off with nil (which puts the
    /// folder back, FR-014). A custom icon that isn't ours is replaced only with `confirmReplace`
    /// (FR-013); without it the call throws `folderIconNeedsConfirmation` and changes nothing.
    /// For a mapping that is Off, the art is saved and set when it is turned on.
    public func setFolderIcon(_ art: FolderArt?, for id: UUID, confirmReplace: Bool = false) async throws -> ActionResult {
        try await exclusive { try await self.performSetFolderIcon(art, for: id, confirmReplace: confirmReplace) }
    }

    private func performSetFolderIcon(_ art: FolderArt?, for id: UUID, confirmReplace: Bool) async throws -> ActionResult {
        try requireWritable()
        guard let index = config.mappings.firstIndex(where: { $0.id == id }) else { throw ManagerError.unknownMapping }
        let mapping = config.mappings[index]
        let name = PathStandardizer.abbreviatingHome(mapping.folderPath)

        guard let art else {
            let notes = try undoFolderIconOrThrow(at: mapping.folderPath)
            folderIconFailures[id] = nil
            try change(id) { $0.mappings[$1].folderIcon = nil }
            return ActionResult(rows: await rows(), messages: ["Turned off the folder icon of \(name)."] + notes)
        }

        // 1. The art and the folder are checked before anything is copied.
        do {
            try FolderArtBuilder.checkMaster(art.master)
            for (slot, url) in art.overrides { try FolderArtBuilder.checkOverride(url, name: slot) }
        } catch let error as FolderArtError {
            throw ManagerError.folderArtRefused(error)
        }
        if mapping.enabled, try folderIconsNeedConfirmation(mapping.folderPath), !confirmReplace {
            throw ManagerError.folderIconNeedsConfirmation(existing: true)
        }

        // 2. The art is copied into Icons/, so the icon no longer depends on the originals.
        var imported: [IconAsset] = []
        let discard = { for asset in imported { self.store.deleteFiles(of: asset) } }
        var overrideIDs: [String: UUID] = [:]
        do {
            let master = try copyArt(art.master)
            imported.append(master)
            for (slot, url) in art.overrides {
                let asset = try copyArt(url)
                imported.append(asset)
                overrideIDs[slot] = asset.id
            }
        } catch {
            discard()
            throw Self.managerError(error)
        }
        let wasOurs = (try? folderIcons.entry(for: mapping.folderPath)).flatMap { $0 }.map(folderIcons.isUnchanged) ?? false
        // New art for the same folder keeps an earlier yes to replacing its icon (final review 1):
        // the sheet asks again only for a foreign icon, and On still checks the confirmed icon is
        // the one the folder shows.
        let earlier = mapping.folderIcon.flatMap { $0.replaceExisting ? $0 : nil }
        let setting = FolderIconSetting(enabled: true, artAssetID: imported[0].id, overrideAssetIDs: overrideIDs,
                                        replaceExisting: confirmReplace || earlier != nil,
                                        confirmedFingerprint: confirmReplace
                                            ? (folderIcons.currentFingerprint(of: mapping.folderPath) ?? Self.flagOnlyIcon)
                                            : earlier?.confirmedFingerprint)
        var next = config
        next.mappings[index].folderIcon = setting
        next.assets += imported

        // 3. The icon is set (recorded in the ledger first), then the setting is saved. A failed
        //    save puts the folder back, so the two never disagree.
        if mapping.enabled {
            do {
                try setFolderIcon(setting, assets: next.assets, on: mapping.folderPath, confirmReplace: confirmReplace)
            } catch {
                discard()
                throw Self.managerError(error)
            }
        }
        do {
            config = try store.save(next)
        } catch {
            if mapping.enabled {
                // The folder goes back to what the saved setting says (review M3): our earlier
                // picture if there was one, otherwise its own icon.
                if wasOurs, let previous = mapping.folderIcon {
                    try? setFolderIcon(previous, assets: config.assets, on: mapping.folderPath, confirmReplace: false)
                } else {
                    _ = try? undoFolderIconOrThrow(at: mapping.folderPath)
                }
            }
            discard()
            throw Self.managerError(error)
        }
        folderIconFailures[id] = nil
        let message = mapping.enabled
            ? "Set the folder icon of \(name)."
            : "Saved the folder icon of \(name); it is set when the mapping is turned on."
        return ActionResult(rows: await rows(), messages: [message])
    }

    /// Stands for a confirmed icon that had only the Finder flag and no `Icon\r`, so it never equals
    /// "no fingerprint" and a later flag-only icon needs a new yes (review N3).
    static let flagOnlyIcon = "finder-flag-only"

    /// Read-only, for the opt-in sheet: whether setting a folder icon at `path` would replace a
    /// custom icon that isn't ours, so the sheet shows the replace warning up front.
    public func folderIconNeedsConfirmation(atPath path: String) -> Bool {
        (try? folderIcons.needsConfirmation(folderPath: PathStandardizer.standardize(path))) ?? false
    }

    private func folderIconsNeedConfirmation(_ path: String) throws -> Bool {
        do {
            return try folderIcons.needsConfirmation(folderPath: path)
        } catch {
            throw Self.managerError(error)
        }
    }

    /// Builds the `.icns` in `Build/<id>/` from the stored art and sets it on the folder.
    private func setFolderIcon(_ setting: FolderIconSetting, assets: [IconAsset], on path: String, confirmReplace: Bool) throws {
        try refuseLinkedGlyphFolders()
        let build = container.buildDirectory.appending(path: UUID().uuidString.lowercased(), directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: build) }
        func file(_ id: UUID) throws -> URL {
            guard let asset = assets.first(where: { $0.id == id }),
                  LaunchServicesOverrideProvider.isPlainFileName(asset.fileName) else {
                throw ManagerError.imageUnreadable("the folder art")
            }
            return container.iconsDirectory.appending(path: asset.fileName)
        }
        let icns = build.appending(path: "folder.icns")
        try FileManager.default.createDirectory(at: build, withIntermediateDirectories: true)
        try FolderArtBuilder.build(master: try file(setting.artAssetID),
                                   overrides: try setting.overrideAssetIDs.mapValues(file), to: icns)
        try folderIcons.set(icns, on: path, confirmReplace: confirmReplace)
    }

    /// Copies one art file into `Icons/` as it is (no `.icns` is made from it).
    private func copyArt(_ url: URL) throws -> IconAsset {
        guard !container.iconsDirectoryIsSymbolicLink else {
            throw ManagerError.sidebar(.unexpectedLedgerTarget(container.iconsDirectory.path))
        }
        do {
            return try AssetImporter.importFile(at: url, into: container.iconsDirectory)
        } catch {
            throw ManagerError.imageUnreadable(url.lastPathComponent)
        }
    }

    /// Sets an opted-in mapping's folder icon again (On, Re-point). A custom icon that isn't ours is
    /// replaced only if the owner confirmed that for this mapping (it is backed up and put back on
    /// Off); otherwise the folder is left and the row says so. Problems are reported, not thrown.
    private func applyFolderIcon(for mapping: SidebarMapping) -> [String] {
        guard mapping.enabled, let setting = mapping.folderIcon, setting.enabled else { return [] }
        let name = PathStandardizer.abbreviatingHome(mapping.folderPath)
        do {
            let confirmed = setting.replaceExisting
                && folderIcons.currentFingerprint(of: mapping.folderPath) == setting.confirmedFingerprint
            if !confirmed, try folderIcons.needsConfirmation(folderPath: mapping.folderPath) {
                let message = "\(name) has a custom icon now, so its folder icon wasn't set. Use Folder Icon… to replace it."
                folderIconFailures[mapping.id] = message
                return [message]
            }
            try setFolderIcon(setting, assets: config.assets, on: mapping.folderPath, confirmReplace: confirmed)
            folderIconFailures[mapping.id] = nil
            return []
        } catch {
            let message = Self.managerError(error).message
            folderIconFailures[mapping.id] = message
            return [message]
        }
    }

    /// What to do when the folder of a recorded icon can't be found.
    enum MissingFolder {
        /// Off: keep the entry, so the icon is put back once the folder is there again.
        case keep
        /// Remove, turning the icon off, Reset All: drop the entry and say so.
        case forget
    }

    /// Puts a folder back (Off); problems are reported, not thrown. A confirmed replacement is
    /// remembered as the icon that was put back, so On replaces only that one (review M2).
    private func undoFolderIcon(for mapping: SidebarMapping) -> [String] {
        folderIconFailures[mapping.id] = nil
        var notes: [String] = []
        do {
            let (undoNotes, outcome) = try undoFolderIconReporting(at: mapping.folderPath, missing: .keep)
            notes = undoNotes
            if var setting = mapping.folderIcon, setting.replaceExisting,
               let index = config.mappings.firstIndex(where: { $0.id == mapping.id }) {
                if outcome == .restored {
                    setting.confirmedFingerprint = folderIcons.currentFingerprint(of: mapping.folderPath)
                } else if outcome == .leftChangedElsewhere {
                    setting.replaceExisting = false
                    setting.confirmedFingerprint = nil
                }
                if setting != mapping.folderIcon {
                    var next = config
                    next.mappings[index].folderIcon = setting
                    config = try store.save(next)
                }
            }
            return notes
        } catch {
            return notes + [Self.managerError(error).message]
        }
    }

    private func followFolderIcon(from oldPath: String, to newPath: String) throws -> Bool {
        do {
            return try folderIcons.follow(oldPath, to: newPath)
        } catch {
            throw Self.managerError(error)
        }
    }

    private func clearFolderIconFailure(_ id: UUID) {
        folderIconFailures[id] = nil
    }

    /// Puts the folder back if a folder icon is recorded for it, by the fingerprint rule.
    private func undoFolderIconOrThrow(at path: String, missing: MissingFolder = .forget) throws -> [String] {
        try undoFolderIconReporting(at: path, missing: missing).notes
    }

    private func undoFolderIconReporting(at path: String, missing: MissingFolder) throws -> (notes: [String], outcome: FolderIconUndo?) {
        let name = PathStandardizer.abbreviatingHome(path)
        do {
            guard let entry = try folderIcons.entry(for: path) else { return ([], nil) }
            let outcome = try folderIcons.undo(entry)
            switch outcome {
            case .restored: return (["Put back the earlier icon of \(name)."], outcome)
            case .cleared, .nothingWasSet: return ([], outcome)
            case .leftChangedElsewhere:
                return (["The icon of \(name) was changed by something else, so it was left as it is."], outcome)
            case .folderMissing:
                switch missing {
                case .keep:
                    return (["\(name) can't be found; its folder icon is put back when it's there again."], outcome)
                case .forget:
                    try folderIcons.forget(entry)
                    return (["\(name) can't be found, so its folder icon couldn't be put back. If the folder moved, it still shows that icon; remove it in Get Info."], outcome)
                }
            case .folderUnsafe:
                switch missing {
                case .keep:
                    return (["\(name) isn't a plain folder now, so its folder icon was left as it is."], outcome)
                case .forget:
                    try folderIcons.forget(entry)
                    return (["\(name) isn't a plain folder now, so its folder icon wasn't put back. If a folder there still shows that icon, remove it in Get Info."], outcome)
                }
            }
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
        // Folder icons first (FR-014, FR-017): each folder is put back by the fingerprint rule.
        var folderNotes: [String] = []
        var folderFailures: [String] = []
        var foldersUndone = 0
        let folderEntries: [OutsideChange]
        do {
            folderEntries = try provider.ledgerEntries().filter { $0.kind == .folderIcon }
        } catch {
            throw Self.managerError(error)
        }
        for entry in folderEntries {
            do {
                folderNotes += try undoFolderIconOrThrow(at: entry.target)
                foldersUndone += 1
            } catch {
                folderFailures.append((error as? ManagerError)?.message ?? String(describing: error))
            }
        }

        let report: ResetReport
        do {
            report = try await provider.reset()
        } catch {
            throw Self.managerError(error)
        }
        lastFailures = [:]
        folderIconFailures = [:]
        var messages: [String] = folderNotes

        // Checked again just before anything is deleted (security review M1). A failure is
        // reported with the rest, not thrown, so the folder notes above are kept (re-review 2).
        var containerProblem: String?
        do {
            try requireRealContainer()
        } catch {
            containerProblem = (error as? ManagerError)?.message ?? String(describing: error)
        }
        if report.succeeded && folderFailures.isEmpty && containerProblem == nil {
            messages += provider.removeUnrecordedRegistryFiles()
            // Temp files a crash left while saving the ledger (re-review 5).
            for name in (try? FileManager.default.contentsOfDirectory(atPath: container.root.path)) ?? []
            where name.hasPrefix(".ledger.json.") && name.hasSuffix(".tmp") {
                try? FileManager.default.removeItem(at: container.root.appending(path: name))
            }
            try store.remove()
            if FileManager.default.fileExists(atPath: container.iconsDirectory.path) {
                do {
                    try FileManager.default.removeItem(at: container.iconsDirectory)
                } catch {
                    messages.append("The copied images could not all be deleted: \(error.localizedDescription)")
                }
            }
            for folder in [container.glyphsDirectory, container.buildDirectory, container.folderIconBackupsDirectory]
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
                report.undone.isEmpty && foldersUndone == 0
                    ? "Nothing to reset; your mappings and copied images were removed."
                    : "Removed every custom sidebar icon, mapping and copied image.",
                at: 0
            )
        } else {
            messages += report.failed.map(\.reason.message) + folderFailures + [containerProblem].compactMap { $0 }
            if readOnlyReason == nil {
                // Errors here are added to the messages so the list of failures above is kept.
                do {
                    let entries = try provider.ledgerEntries()
                    let recorded = Set(entries.filter { $0.kind == .sidebarOverride }.compactMap(\.osType))
                    let recordedFolders = Set(entries.filter { $0.kind == .folderIcon }.map(\.target))
                    var next = config
                    next.mappings = config.mappings.filter { recorded.contains($0.osType) || recordedFolders.contains($0.folderPath) }
                    config = try store.save(next)
                } catch {
                    messages.append(Self.managerError(error).message)
                }
            }
            messages.append("Some changes could not be undone and are still recorded. Fix the cause, then click Reset All again.")
        }
        return ActionResult(rows: await rows(), messages: messages,
                            needsRefresh: report.succeeded && folderFailures.isEmpty && !report.undone.isEmpty)
    }

    // MARK: - Helpers

    /// Runs one action at a time; a second action while one is running is refused.
    private func exclusive<T: Sendable>(_ action: () async throws -> T) async throws -> T {
        guard !actionInProgress else { throw ManagerError.busy }
        actionInProgress = true
        defer { actionInProgress = false }
        try requireRealContainer()
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
        // A mapping that is off but whose override is still recorded (its clear failed) keeps its
        // glyph declared, so its Favorite never points at a code the new version lacks (final
        // review 5).
        let recorded = Set(((try? provider.ledgerEntries()) ?? []).filter { $0.kind == .sidebarOverride }.compactMap(\.osType))
        let needed = Set(config.mappings.filter { $0.enabled || recorded.contains($0.osType) }
            .compactMap(\.glyphID).compactMap { config.glyph($0) }
            .map { $0.versionID.uuidString.lowercased() })
        guard !needed.isEmpty, !container.isSymbolicLink(container.glyphsDirectory) else { return nil }
        let all = Set(config.glyphs.map { $0.versionID.uuidString.lowercased() })
        let onDisk = carKeyOnDisk()
        let carExists = FileManager.default.fileExists(atPath: car.path)
        if carExists, onDisk == all { return car }
        if case .available = glyphTool.toolStatus(), let staged = try? stageCar(for: config.glyphs) {
            defer { staged.discard() }
            if (try? installCar(staged)) != nil { return car }
        }
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
        case let error as FolderArtError: .folderArtRefused(error)
        case FolderIconError.needsConfirmation: .folderIconNeedsConfirmation(existing: true)
        case FolderIconError.setFailed(let path): .folderIconFailed(path)
        case FolderIconError.backupFailed(let path): .folderIconBackupFailed(path)
        case FolderIconError.unverified(let path): .folderIconUnverified(path)
        case FolderIconError.unsafeTarget(let path): .folderIconUnsafe(path)
        case FolderIconError.folderMissing(let path): .folderIconMissing(path)
        case OSTypeAllocationError.exhausted: .sidebar(.invalidMapping("no unused type code is left"))
        default: .sidebar(.toolFailed(String(describing: error)))
        }
    }
}
