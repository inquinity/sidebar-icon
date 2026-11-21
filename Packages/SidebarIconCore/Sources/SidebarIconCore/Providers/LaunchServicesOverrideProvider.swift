@preconcurrency import CoreServices
import Foundation

// Path B: the Launch Services sidebar icon override (research R2, R3, R7, R8).
//
// THIS IS THE ONLY FILE THAT TOUCHES PRIVATE, UNDOCUMENTED, OR DEPRECATED BEHAVIOR
// (Constitution II). Every such use is listed in PRIVATE_API.md; any change here must update that
// register in the same commit (Constitution VI). Uses by register ID:
//   PA-01  LSSharedFileListCreate, kLSSharedFileListFavoriteItems, LSSharedFileListCopySnapshot,
//          LSSharedFileListItemCopyResolvedURL, LSSharedFileListItemCopyDisplayName
//   PA-02  LSSharedFileListItemCopyProperty, LSSharedFileListItemSetProperty
//   PA-03  property key com.apple.LSSharedFileList.OverrideIcon.OSType
//   PA-04  LSRegisterURL on IconRegistry.app, relied on for sidebar icon lookup
//   PA-05  lsregister -dump (read-only) and lsregister -u
//
// The provider logic (ledger ordering, skips, reset order) is separate from the system calls
// (`SystemLaunchServices`) so it can be tested with a fake.

/// One Finder sidebar Favorite as read through `LSSharedFileList` (experiment B1).
public struct FavoriteItem: Sendable, Equatable {
    public var displayName: String
    /// Standardized path of the resolved URL; nil for items that are not files (AirDrop, Recents).
    public var path: String?
    /// The current `OverrideIcon.OSType` value, if any.
    public var overrideIcon: String?

    public init(displayName: String, path: String?, overrideIcon: String?) {
        self.displayName = displayName
        self.path = path
        self.overrideIcon = overrideIcon
    }
}

/// A registered bundle that claims one of the type codes, from `lsregister -dump`.
public struct LSClaimOwner: Sendable, Equatable, CustomStringConvertible {
    public var name: String
    public var identifier: String?
    public var path: String?

    public var description: String {
        [name, identifier, path].compactMap { $0 }.joined(separator: " — ")
    }
}

/// The system calls Path B needs. `SystemLaunchServices` is the real implementation.
public protocol LaunchServicesSystem: Sendable {
    /// Throws `favoritesUnavailable` when the list cannot be created.
    func listFavorites() throws -> [FavoriteItem]
    /// Sets the override on the one Favorite that resolves to `path`.
    func setOverrideIcon(_ code: String, forFavoriteAt path: String) throws
    /// Clears the override on every Favorite whose current value is `code`, wherever its folder now
    /// lives. Favorites carrying any other value are left alone. Returns how many were cleared.
    /// Throws `propertyRejected` if a write fails and `overrideNotCleared` if the code is still
    /// there when read back.
    func clearOverrideIcon(_ code: String) throws -> Int
    func register(bundleAt url: URL) throws
    func unregister(bundleAt url: URL) throws
    /// Owners of each code among registered bundles; codes with no claim are absent.
    func claims(on codes: Set<String>) throws -> [String: [LSClaimOwner]]
    /// Whether Launch Services still lists a bundle at `url`.
    func isRegistered(bundleAt url: URL) throws -> Bool
}

public struct LaunchServicesOverrideProvider: SidebarIconProvider {
    public let mechanism = "ls-override"

    let container: ContainerLocator
    let ledger: LedgerStore
    let system: any LaunchServicesSystem

    public init(container: ContainerLocator, system: any LaunchServicesSystem = SystemLaunchServices()) {
        self.container = container
        self.ledger = LedgerStore(url: container.ledgerURL)
        self.system = system
    }

    /// Experiment B1, read-only.
    public func listFavorites() throws -> [FavoriteItem] {
        try system.listFavorites()
    }

    public func ledgerEntries() throws -> [OutsideChange] {
        try ledger.entries()
    }

    public func status(for mappings: [SidebarMapping]) async throws -> [MappingStatus] {
        let favorites = try system.listFavorites()
        return mappings.map { mapping in
            let matches = favorites.filter { $0.path == mapping.folderPath }
            return MappingStatus(
                mappingID: mapping.id,
                folderPath: mapping.folderPath,
                folderExists: FileManager.default.fileExists(atPath: mapping.folderPath),
                favoriteCount: matches.count,
                activeOverride: matches.count == 1 ? matches[0].overrideIcon : nil
            )
        }
    }

    public func apply(_ mappings: [SidebarMapping], assets: [IconAsset]) async throws -> ApplyReport {
        var report = ApplyReport()
        if let problem = SidebarMapping.validate(mappings).first {
            throw SidebarIconError.invalidMapping(String(describing: problem))
        }
        let favorites = try system.listFavorites()
        let assetsByID = Dictionary(assets.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let recordedOverrides = try ledger.entries().filter { $0.kind == .sidebarOverride }
        let ownCodes = Set(recordedOverrides.compactMap(\.osType))

        func registryEntry(for mapping: SidebarMapping) -> IconRegistryBundle.Entry? {
            guard let asset = assetsByID[mapping.iconAssetID], let icns = try? icnsFile(for: asset) else { return nil }
            return .init(osType: mapping.osType, assetID: asset.id, icnsSource: icns)
        }

        // 1. Decide which enabled mappings can be applied; report the rest (spec edge cases).
        var eligible: [(mapping: SidebarMapping, entry: IconRegistryBundle.Entry)] = []
        for mapping in mappings where mapping.enabled {
            let skip = { (reason: SidebarIconError) in
                report.skipped.append(.init(mappingID: mapping.id, reason: reason))
            }
            guard FileManager.default.fileExists(atPath: mapping.folderPath) else {
                skip(.folderMissing(mapping.folderPath)); continue
            }
            let matches = favorites.filter { $0.path == mapping.folderPath }
            switch matches.count {
            case 0: skip(.folderNotInFavorites(mapping.folderPath)); continue
            case 1: break
            default: skip(.folderInFavoritesMoreThanOnce(mapping.folderPath)); continue
            }
            // Never overwrite an override this utility did not set (another tool's, or the user's).
            if let current = matches[0].overrideIcon, current != mapping.osType, !ownCodes.contains(current) {
                skip(.foreignOverride(path: mapping.folderPath, code: current)); continue
            }
            guard let entry = registryEntry(for: mapping) else {
                skip(.assetConversionFailed(mapping.iconAssetID)); continue
            }
            eligible.append((mapping, entry))
        }

        // 2. Clear overrides whose mapping is disabled, gone, or moved to another folder
        // (data-model.md, `enabled`). This runs before registration, so a failure there can't stop
        // Off or Remove from clearing, and before any override is set: overrides are cleared
        // by code, so clearing after a moved mapping's code was set on its new Favorite would
        // remove the new one, and skipping the clear would leave the old Favorite carrying an
        // override that no ledger entry records. A failure keeps that ledger entry, is noted, and
        // does not stop the other entries or lose the report.
        let enabledPaths = Set(mappings.filter(\.enabled).map(\.folderPath))
        for entry in try ledger.entries() where entry.kind == .sidebarOverride && !enabledPaths.contains(entry.target) {
            do {
                try ledger.undo(entry) {
                    guard let code = entry.osType else { return }
                    _ = try system.clearOverrideIcon(code)
                }
                report.cleared.append(entry.target)
            } catch {
                report.notes.append("Could not clear \(entry.osType ?? "?") on \(entry.target): \(Self.sidebarError(error).message)")
            }
        }

        // 3. Register the icons (research R3 part 1), after checking no one else claims the codes (R7).
        // The bundle keeps every code an override in the ledger still points at (after the clears
        // above), so a Favorite that was skipped, or whose clear failed, is not left pointing at an
        // unregistered code.
        let bundleURL = container.registryBundleURL
        var bundleEntries: [IconRegistryBundle.Entry] = []
        if !eligible.isEmpty {
            bundleEntries = eligible.map(\.entry)
            let eligibleIDs = Set(eligible.map(\.mapping.id))
            let stillRecorded = Set(try ledger.entries().filter { $0.kind == .sidebarOverride }.compactMap(\.osType))
            for mapping in mappings where !eligibleIDs.contains(mapping.id) && stillRecorded.contains(mapping.osType) {
                if let entry = registryEntry(for: mapping) { bundleEntries.append(entry) }
            }
            // A code another bundle claims is left out, and only its mapping is skipped; the
            // others are still applied.
            let codes = Set(bundleEntries.map(\.osType))
            var claimed: [String: [String]] = [:]
            for (code, owners) in try system.claims(on: codes) {
                let others = Self.foreignOwners(owners, ownBundle: bundleURL)
                if !others.isEmpty { claimed[code] = others.map(\.description) }
            }
            if !claimed.isEmpty {
                eligible.removeAll { item in
                    guard let owners = claimed[item.mapping.osType] else { return false }
                    report.skipped.append(.init(
                        mappingID: item.mapping.id, reason: .codeClaimedElsewhere(code: item.mapping.osType, owners: owners)
                    ))
                    return true
                }
                bundleEntries.removeAll { claimed[$0.osType] != nil }
            }
            report.notes.append("R7: no other registered bundle claims \(Set(bundleEntries.map(\.osType)).sorted().joined(separator: ", ")).")
        }
        if !eligible.isEmpty {
            try Self.refuseSymbolicLink(bundleURL)
            try IconRegistryBundle.write(bundleEntries, to: bundleURL)
            do {
                try ledger.record(OutsideChange(kind: .iconRegistration, target: bundleURL.path)) {
                    try system.register(bundleAt: bundleURL)
                }
            } catch {
                // The ledger entry was rolled back, so nothing would ever remove the bundle: undo
                // a possible partial registration and delete it now.
                try? system.unregister(bundleAt: bundleURL)
                try? FileManager.default.removeItem(at: bundleURL)
                throw error
            }
        }

        // 4. Point each Favorite at its code (research R3 part 2).
        for (mapping, _) in eligible {
            let change = OutsideChange(kind: .sidebarOverride, target: mapping.folderPath, osType: mapping.osType)
            do {
                try ledger.record(change) {
                    try system.setOverrideIcon(mapping.osType, forFavoriteAt: mapping.folderPath)
                }
                report.applied.append(mapping.id)
                // A different code set earlier on the same Favorite has just been replaced.
                for stale in try ledger.entries() where stale.kind == .sidebarOverride
                    && stale.target == mapping.folderPath && stale.osType != mapping.osType {
                    try ledger.undo(stale) {}
                }
            } catch {
                report.skipped.append(.init(mappingID: mapping.id, reason: Self.sidebarError(error)))
            }
        }

        // 5. With no enabled mapping left and no override still recorded, the registry bundle is
        // no longer needed: unregister and delete it, the same way Reset does (Story 2, PA-04).
        let entriesNow = try ledger.entries()
        if !mappings.contains(where: \.enabled), !entriesNow.contains(where: { $0.kind == .sidebarOverride }) {
            for entry in entriesNow where entry.kind == .iconRegistration {
                do {
                    try undoRegistration(entry)
                    report.cleared.append(entry.target)
                } catch {
                    report.notes.append("Could not remove the icon registration: \(Self.sidebarError(error).message)")
                }
            }
        }
        return report
    }

    /// Clears every override first, then unregisters and deletes the registration bundle. If any
    /// override cannot be cleared, the registration is kept so the ledger stays consistent; run
    /// reset again after fixing the cause.
    ///
    /// Overrides are cleared by code, not by path, so a Favorite whose folder was moved or renamed
    /// is still found, and a Favorite whose value was since changed by someone else is left alone.
    public func reset() async throws -> ResetReport {
        var report = ResetReport()
        let entries = try ledger.entries()

        for entry in entries where entry.kind == .sidebarOverride {
            do {
                guard let code = entry.osType, OSTypeCode.isValid(code) else {
                    throw SidebarIconError.unexpectedLedgerTarget("override entry for \(entry.target) has no valid code")
                }
                try ledger.undo(entry) {
                    if try system.clearOverrideIcon(code) == 0 {
                        report.notes.append("No Favorite still carries \(code) (\(entry.target)); nothing to clear.")
                    }
                }
                report.undone.append(entry)
            } catch {
                report.failed.append(.init(change: entry, reason: Self.sidebarError(error)))
            }
        }

        let registrations = entries.filter { $0.kind == .iconRegistration }
        guard report.failed.isEmpty else {
            if !registrations.isEmpty {
                report.notes.append("The icon registration was kept because some overrides could not be cleared.")
            }
            return report
        }
        for entry in registrations {
            do {
                try undoRegistration(entry)
                report.undone.append(entry)
            } catch {
                report.failed.append(.init(change: entry, reason: Self.sidebarError(error)))
            }
        }
        return report
    }

    /// Unregisters (PA-05) and deletes the registry bundle for a registration ledger entry, then
    /// removes the entry. Only ever acts on this utility's own bundle path, never a symbolic link,
    /// whatever the ledger says.
    func undoRegistration(_ entry: OutsideChange) throws {
        let ownBundle = container.registryBundleURL
        guard PathStandardizer.standardize(entry.target) == PathStandardizer.standardize(ownBundle.path) else {
            throw SidebarIconError.unexpectedLedgerTarget(entry.target)
        }
        try Self.refuseSymbolicLink(ownBundle)
        try ledger.undo(entry) {
            do {
                try system.unregister(bundleAt: ownBundle)
            } catch {
                // `lsregister -u` may fail for a bundle that was already deleted; that is fine only
                // if Launch Services no longer lists it.
                guard !FileManager.default.fileExists(atPath: ownBundle.path),
                      try !system.isRegistered(bundleAt: ownBundle)
                else { throw error }
            }
            if FileManager.default.fileExists(atPath: ownBundle.path) {
                try FileManager.default.removeItem(at: ownBundle)
            }
        }
    }

    /// The codes among `codes` that another registered bundle or type claims (R7, PA-05 read-only).
    /// Claims by this utility's own registry bundle don't count.
    public func codesClaimedElsewhere(among codes: Set<String>) throws -> Set<String> {
        let bundleURL = container.registryBundleURL
        return Set(try system.claims(on: codes).compactMap { code, owners in
            Self.foreignOwners(owners, ownBundle: bundleURL).isEmpty ? nil : code
        })
    }

    /// After a successful reset, removes what the ledger can't know about: registry staging folders
    /// left by a crash, and a registry bundle written but never recorded, which is unregistered
    /// first (PA-05) in case it was registered. A symbolic link is removed as a link, never followed
    /// or unregistered. Returns a message for each item that could not be removed.
    public func removeUnrecordedRegistryFiles() -> [String] {
        let fileManager = FileManager.default
        let root = container.root
        let bundleName = container.registryBundleURL.lastPathComponent
        var messages: [String] = []
        for name in (try? fileManager.contentsOfDirectory(atPath: root.path)) ?? []
        where name == bundleName || name.hasPrefix(".\(bundleName).staging-") {
            let url = root.appending(path: name)
            let isLink = (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true
            if name == bundleName, !isLink {
                try? system.unregister(bundleAt: url)
            }
            do {
                try fileManager.removeItem(at: url)
            } catch {
                messages.append("\(name) could not be deleted: \(error.localizedDescription)")
            }
        }
        return messages
    }

    /// Experiment B6: whether `lsregister -dump` still lists the registration bundle.
    public func registrationStillListed() throws -> Bool {
        try system.isRegistered(bundleAt: container.registryBundleURL)
    }

    /// The `.icns` for `asset` in `Icons/`, converted on first use. A missing or unusable `.icns`
    /// (empty, truncated) is rebuilt from the copied source (research D5).
    func icnsFile(for asset: IconAsset) throws -> URL {
        // File names come from stored data; only plain names inside a real `Icons/` directory are
        // accepted.
        guard Self.isPlainFileName(asset.fileName), asset.icnsFileName.map(Self.isPlainFileName) ?? true,
              !container.iconsDirectoryIsSymbolicLink else {
            throw SidebarIconError.assetConversionFailed(asset.id)
        }
        let source = container.iconsDirectory.appending(path: asset.fileName)
        if asset.sourceFormat == .icns { return source }
        let icns = container.iconsDirectory.appending(path: asset.icnsFileName ?? "\(asset.id.uuidString).icns")
        if !ICNSConverter.isUsableICNS(at: icns) {
            try ICNSConverter.convert(source, to: icns)
        }
        return icns
    }

    /// A single path component: no `/`, not `.` or `..`, not hidden, not empty.
    static func isPlainFileName(_ name: String) -> Bool {
        !name.isEmpty && !name.contains("/") && !name.hasPrefix(".") && name != ".."
    }

    /// The registry bundle must be a real directory in the container. A symbolic link there (for
    /// example planted in the shared App Group container) could make `LSRegisterURL` or
    /// `lsregister -u` act on another app, so it is refused.
    static func refuseSymbolicLink(_ url: URL) throws {
        let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey])
        if values?.isSymbolicLink == true {
            throw SidebarIconError.unexpectedLedgerTarget(url.path)
        }
    }

    /// The owners of a code claim that are not this utility's own registry bundle. Only the bundle
    /// at our path is ours; a stale copy elsewhere is a conflict. A claim whose bundle path could
    /// not be read counts as ours only if it has our identifier.
    static func foreignOwners(_ owners: [LSClaimOwner], ownBundle: URL) -> [LSClaimOwner] {
        owners.filter { owner in
            if let path = owner.path { return !samePath(path, ownBundle.path) }
            return owner.identifier != IconRegistryBundle.bundleIdentifier
        }
    }

    /// Compares paths the way `lsregister -dump` and Foundation may spell them differently:
    /// standardized, symlinks resolved, and without the `/System/Volumes/Data` firmlink prefix.
    static func samePath(_ a: String, _ b: String) -> Bool {
        func normalize(_ path: String) -> String {
            var standardized = PathStandardizer.standardize(path)
            let firmlink = "/System/Volumes/Data"
            if standardized.hasPrefix(firmlink + "/") {
                standardized.removeFirst(firmlink.count)
            }
            return standardized
        }
        return normalize(a) == normalize(b)
    }

    static func sidebarError(_ error: any Error) -> SidebarIconError {
        (error as? SidebarIconError) ?? .toolFailed(String(describing: error))
    }
}

// MARK: - System calls (private and deprecated API)

/// The real `LaunchServicesSystem`. Each member names its `PRIVATE_API.md` entry.
public struct SystemLaunchServices: LaunchServicesSystem {
    /// PA-03. Undocumented key; the value is written as a four-character `CFString`.
    static let overrideIconKeyName = "com.apple.LSSharedFileList.OverrideIcon.OSType"
    static var overrideIconKey: CFString { overrideIconKeyName as CFString }

    /// PA-05. Undocumented tool.
    static let lsregisterPath =
        "/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"

    public init() {}

    /// PA-01.
    private func favoritesSnapshot() throws -> [LSSharedFileListItem] {
        guard let list = LSSharedFileListCreate(nil, kLSSharedFileListFavoriteItems.takeUnretainedValue(), nil)?
            .takeRetainedValue()
        else {
            throw SidebarIconError.favoritesUnavailable
        }
        var seed: UInt32 = 0
        guard let snapshot = LSSharedFileListCopySnapshot(list, &seed)?.takeRetainedValue() else {
            throw SidebarIconError.favoritesUnavailable
        }
        return (snapshot as NSArray).map { $0 as! LSSharedFileListItem }
    }

    /// PA-01.
    private func resolvedPath(of item: LSSharedFileListItem) -> String? {
        let flags = LSSharedFileListResolutionFlags(kLSSharedFileListNoUserInteraction | kLSSharedFileListDoNotMountVolumes)
        guard let url = LSSharedFileListItemCopyResolvedURL(item, flags, nil)?.takeRetainedValue() as URL?,
              url.isFileURL
        else { return nil }
        return PathStandardizer.standardize(url.path)
    }

    /// PA-02 (read) with the PA-03 key.
    private func overrideIcon(of item: LSSharedFileListItem) -> String? {
        guard let value = LSSharedFileListItemCopyProperty(item, Self.overrideIconKey)?.takeRetainedValue() else {
            return nil
        }
        // A property stored as `kCFNull` (rather than removed) means no override.
        if CFGetTypeID(value) == CFNullGetTypeID() { return nil }
        switch value {
        case let string as String:
            return string
        case let number as NSNumber:
            return Self.fourCharacterCode(number.uint32Value)
        case let data as Data where data.count == 4:
            return String(data: data, encoding: .macOSRoman)
        default:
            return String(describing: value)
        }
    }

    public func listFavorites() throws -> [FavoriteItem] {
        try favoritesSnapshot().map { item in
            FavoriteItem(
                displayName: LSSharedFileListItemCopyDisplayName(item).takeRetainedValue() as String,
                path: resolvedPath(of: item),
                overrideIcon: overrideIcon(of: item)
            )
        }
    }

    /// PA-02 (write) with the PA-03 key.
    public func setOverrideIcon(_ code: String, forFavoriteAt path: String) throws {
        let matches = try favoritesSnapshot().filter { resolvedPath(of: $0) == path }
        guard !matches.isEmpty else { throw SidebarIconError.folderNotInFavorites(path) }
        guard matches.count == 1 else { throw SidebarIconError.folderInFavoritesMoreThanOnce(path) }
        let status = LSSharedFileListItemSetProperty(matches[0], Self.overrideIconKey, code as CFString)
        guard status == noErr else { throw SidebarIconError.propertyRejected(path, status) }
    }

    /// PA-02 (read, then write `kCFNull`) with the PA-03 key.
    ///
    /// Writing `kCFNull` removes the property. Writing `NULL` returns `noErr` but leaves the
    /// property in place (experiment B6, 26B131), so the result is read back from a fresh snapshot
    /// and a Favorite that still carries the code is reported as `overrideNotCleared`.
    public func clearOverrideIcon(_ code: String) throws -> Int {
        var cleared = 0
        for item in try favoritesSnapshot() where overrideIcon(of: item) == code {
            let status = LSSharedFileListItemSetProperty(item, Self.overrideIconKey, kCFNull)
            guard status == noErr else {
                throw SidebarIconError.propertyRejected(resolvedPath(of: item) ?? code, status)
            }
            cleared += 1
        }
        if cleared > 0, let remaining = try favoritesSnapshot().first(where: { overrideIcon(of: $0) == code }) {
            throw SidebarIconError.overrideNotCleared(path: resolvedPath(of: remaining) ?? "?", code: code)
        }
        return cleared
    }

    /// PA-04. `LSRegisterURL` itself is public; Finder using the registration for sidebar icons is not.
    public func register(bundleAt url: URL) throws {
        let status = LSRegisterURL(url as CFURL, true)
        guard status == noErr else { throw SidebarIconError.registrationFailed(status) }
    }

    /// PA-05. There is no public unregister call.
    public func unregister(bundleAt url: URL) throws {
        _ = try runLSRegister(["-u", url.path])
    }

    /// PA-05, read-only.
    public func claims(on codes: Set<String>) throws -> [String: [LSClaimOwner]] {
        LSRegisterDumpParser.claims(on: codes, in: try runLSRegister(["-dump"]))
    }

    /// PA-05, read-only.
    public func isRegistered(bundleAt url: URL) throws -> Bool {
        LSRegisterDumpParser.registeredPaths(in: try runLSRegister(["-dump"]))
            .contains { LaunchServicesOverrideProvider.samePath($0, url.path) }
    }

    private func runLSRegister(_ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: Self.lsregisterPath)
        process.arguments = arguments
        process.environment = [:]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            throw SidebarIconError.toolFailed("lsregister could not be started: \(error.localizedDescription)")
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw SidebarIconError.toolFailed("lsregister \(arguments.first ?? "") exited with \(process.terminationStatus)")
        }
        return String(decoding: data, as: UTF8.self)
    }

    static func fourCharacterCode(_ value: UInt32) -> String {
        let bytes = [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: value >> $0) }
        return String(bytes: bytes, encoding: .macOSRoman) ?? String(value)
    }
}

/// Reads the parts of `lsregister -dump` output this project needs. The format is not stable
/// (PA-05), so only three record shapes are used:
///
///     bundle id:   Name (0x2244)        claim id:   20784 (0x5130)
///     path:        /Applications/…      bundle:     Name (0x2244)
///     identifier:  com.example.app      bindings:   .*, 'fold', 'S001'
///
///     type id:     com.example.type (0x7000)
///     bundle:      Name (0x2244)
///     tags:        .ext, 'S001', application/x-example
///
/// Records are separated by lines of dashes.
enum LSRegisterDumpParser {
    private struct Record {
        var fields: [(key: String, value: String)] = []
        func first(_ key: String) -> String? { fields.first { $0.key == key }?.value }
    }

    private static func records(in dump: String) -> [Record] {
        var records: [Record] = []
        var current = Record()
        for line in dump.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("----------") {
                if !current.fields.isEmpty { records.append(current) }
                current = Record()
                continue
            }
            guard let first = line.first else { continue }
            if first.isWhitespace {
                // A wrapped `bindings:` or `tags:` list continues on indented lines.
                if let last = current.fields.last, last.key == "bindings" || last.key == "tags" {
                    current.fields[current.fields.count - 1].value += " " + line.trimmingCharacters(in: .whitespaces)
                }
                continue
            }
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<colon])
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            current.fields.append((key, value))
        }
        if !current.fields.isEmpty { records.append(current) }
        return records
    }

    /// `Name (0x2244)` → (`Name`, `0x2244`).
    private static func splitReference(_ value: String) -> (name: String, ref: String?) {
        guard value.hasSuffix(")"), let open = value.range(of: " (0x", options: .backwards) else { return (value, nil) }
        let ref = String(value[value.index(open.lowerBound, offsetBy: 2)..<value.index(before: value.endIndex)])
        return (String(value[..<open.lowerBound]), ref)
    }

    static func claims(on codes: Set<String>, in dump: String) -> [String: [LSClaimOwner]] {
        let all = records(in: dump)
        var bundles: [String: LSClaimOwner] = [:]
        for record in all {
            guard let bundleID = record.first("bundle id") else { continue }
            let (name, ref) = splitReference(bundleID)
            guard let ref else { continue }
            bundles[ref] = LSClaimOwner(
                name: name,
                identifier: record.first("identifier"),
                path: record.first("path").map { splitReference($0).name }
            )
        }
        var result: [String: [LSClaimOwner]] = [:]
        // A code is taken by a document-type claim that binds it (`claim id` … `bindings:`) or by a
        // type declaration that tags it (`type id` … `tags:`); either can win the icon lookup.
        for record in all {
            let listKey: String
            if record.first("claim id") != nil {
                listKey = "bindings"
            } else if record.first("type id") != nil {
                listKey = "tags"
            } else {
                continue
            }
            let list = record.fields.filter { $0.key == listKey }.map(\.value).joined(separator: ", ")
            let claimed = codes.filter { list.contains("'\($0)'") }
            guard !claimed.isEmpty else { continue }
            let (name, ref) = splitReference(record.first("bundle") ?? "unknown")
            let owner = ref.flatMap { bundles[$0] } ?? LSClaimOwner(name: name)
            // A bundle that both declares and claims a code is listed once.
            for code in claimed where !(result[code]?.contains(owner) ?? false) {
                result[code, default: []].append(owner)
            }
        }
        return result
    }

    static func registeredPaths(in dump: String) -> Set<String> {
        Set(records(in: dump).compactMap { record in
            record.first("bundle id") == nil ? nil : record.first("path").map { splitReference($0).name }
        })
    }
}

extension LSClaimOwner {
    init(name: String) {
        self.init(name: name, identifier: nil, path: nil)
    }
}
