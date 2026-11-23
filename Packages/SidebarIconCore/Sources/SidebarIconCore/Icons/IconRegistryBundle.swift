import Foundation

/// The Path B icon registration bundle (research R3, `PRIVATE_API.md` PA-04).
///
/// A small application-type bundle with no executable. Its `Info.plist` declares one
/// `UTExportedTypeDeclarations` entry per mapping: the `com.apple.ostype` tag is the code, and
/// `UTTypeIcons` holds the `.icns` plus a symbol name that does not exist.
///
/// Why this shape (macOS 27.2.1, 26B131, research R3 revisions, 2026-11-20):
/// - A document type with only `CFBundleTypeOSTypes` maps the code to a dynamic `dyn.…` type, so
///   no icon resolves. An exported type tagged with the code fixes the lookup.
/// - The Finder sidebar draws a type's *symbol* (`UTTypeIcons` › `UTTypeSymbolName`), not its
///   `.icns`. With no symbol it draws the generic document glyph.
/// - When the named symbol cannot be found, the sidebar falls back to the `.icns` and draws it in
///   full colour. `missingSymbolName` relies on that fallback; a real SF Symbol name in its place
///   gives a monochrome sidebar glyph instead.
/// - The icon is cached per type, so the type identifier includes the asset ID: a new icon gets a
///   new type and is not hidden by the cached one.
///
/// The bundle is `IconRegistry.app` with `CFBundlePackageType` `APPL` and `LSUIElement` set, and
/// is never launched. It stays application-type because that is the shape verified on 26B131
/// (`LSRegisterURL` registers it and its exported types; `lsregister -u` removes both). This file
/// only builds the bundle; registering it is the provider's job.
public enum IconRegistryBundle {
    public static let bundleIdentifier = "com.altmansoftwaredesign.sidebaricons.iconregistry"

    /// The exported type for a code and icon, for example
    /// `com.altmansoftwaredesign.sidebaricons.icon.s001.5b1c0de0-0001-4000-8000-0000000000a1`.
    /// Codes are `S` plus base-36 characters (`OSTypeCode`) and UUIDs are hex and hyphens, so the
    /// result is a valid identifier. The asset ID is part of it because icons are cached per type.
    public static func typeIdentifier(for code: String, assetID: UUID) -> String {
        "com.altmansoftwaredesign.sidebaricons.icon.\(code.lowercased()).\(assetID.uuidString.lowercased())"
    }

    /// A symbol name that is never defined, so the sidebar falls back to the type's `.icns`.
    public static let missingSymbolName = "com.altmansoftwaredesign.sidebaricons.no-symbol"

    /// Bump when the Info.plist layout changes, so the version changes even if the mapping does not.
    /// 2: exported types per code. 3: icons in `UTTypeIcons` with the missing symbol, no document
    /// types, asset ID in the type identifier (2026-11-20).
    static let formatRevision = 3

    /// A version that changes whenever the code-to-icon mapping or the plist format changes, so
    /// Launch Services and the icon cache do not keep serving an earlier bundle's icons. FNV-1a
    /// over the format revision and the sorted entries; deterministic across runs (unlike
    /// `Hasher`). It is not monotonic: a new mapping can get a lower number. Re-registration goes
    /// by path (`LSRegisterURL(url, true)`), so nothing relies on "newer is higher".
    static func bundleVersion(for entries: [Entry]) -> String {
        let key = "format\(formatRevision);" + entries
            .sorted { $0.osType < $1.osType }
            .map { "\($0.osType)=\($0.assetID.uuidString)" }
            .joined(separator: ";")
        var hash: UInt32 = 2_166_136_261
        for byte in key.utf8 {
            hash = (hash ^ UInt32(byte)) &* 16_777_619
        }
        return String(hash)
    }

    public struct Entry: Sendable, Equatable {
        public var osType: String
        public var assetID: UUID
        /// The `.icns` to copy into `Contents/Resources/<assetID>.icns`.
        public var icnsSource: URL

        public init(osType: String, assetID: UUID, icnsSource: URL) {
            self.osType = osType
            self.assetID = assetID
            self.icnsSource = icnsSource
        }

        public var icnsFileName: String { "\(assetID.uuidString).icns" }
    }

    /// The `Info.plist` contents. Deterministic: entries are sorted by code and keys are sorted.
    /// Throws `invalidMapping` for a code outside the project's range or a code used twice, since
    /// either would give an invalid or ambiguous type.
    public static func infoPlist(for entries: [Entry]) throws -> Data {
        let codes = entries.map(\.osType)
        if let bad = codes.first(where: { !OSTypeCode.isValid($0) }) {
            throw SidebarIconError.invalidMapping("type code \(bad) is not in the S000–SZZZ range")
        }
        guard Set(codes).count == codes.count else {
            throw SidebarIconError.invalidMapping("a type code is used more than once")
        }
        let sorted = entries.sorted { $0.osType < $1.osType }
        let exportedTypes: [[String: Any]] = sorted.map { entry in
            [
                "UTTypeIdentifier": typeIdentifier(for: entry.osType, assetID: entry.assetID),
                "UTTypeDescription": "Sidebar Icons \(entry.osType)",
                "UTTypeConformsTo": ["public.data"],
                "UTTypeIcons": [
                    "UTTypeIconFile": entry.icnsFileName,
                    "UTTypeSymbolName": missingSymbolName,
                ],
                "UTTypeTagSpecification": ["com.apple.ostype": [entry.osType]],
            ]
        }
        let plist: [String: Any] = [
            "CFBundleDevelopmentRegion": "en",
            "CFBundleIdentifier": bundleIdentifier,
            "CFBundleInfoDictionaryVersion": "6.0",
            "CFBundleName": "IconRegistry",
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": "1.0",
            "CFBundleVersion": bundleVersion(for: entries),
            "LSMinimumSystemVersion": "27.0",
            "LSUIElement": true,
            "UTExportedTypeDeclarations": exportedTypes,
        ]
        return try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    }

    /// Writes the complete bundle to `bundleURL`, replacing any previous version in one step.
    public static func write(_ entries: [Entry], to bundleURL: URL) throws {
        let fileManager = FileManager.default
        let staging = bundleURL.deletingLastPathComponent()
            .appending(path: ".\(bundleURL.lastPathComponent).staging-\(UUID().uuidString)", directoryHint: .isDirectory)
        let contents = staging.appending(path: "Contents", directoryHint: .isDirectory)
        let resources = contents.appending(path: "Resources", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: resources, withIntermediateDirectories: true)
        do {
            try infoPlist(for: entries).write(to: contents.appending(path: "Info.plist"))
            try Data("APPL????".utf8).write(to: contents.appending(path: "PkgInfo"))
            for entry in entries {
                let target = resources.appending(path: entry.icnsFileName)
                if !fileManager.fileExists(atPath: target.path) {
                    try fileManager.copyItem(at: entry.icnsSource, to: target)
                }
            }
            if fileManager.fileExists(atPath: bundleURL.path) {
                // An atomic swap, not `FileManager.replaceItemAt`: that call also registers an
                // `.app` with Launch Services as a side effect, so every rewrite (and every test
                // that writes twice) would add a registration nobody records. Registration is
                // only ever the explicit `LSRegisterURL` in the adapter, after the ledger entry.
                guard renamex_np(staging.path, bundleURL.path, UInt32(RENAME_SWAP)) == 0 else {
                    throw CocoaError(.fileWriteUnknown, userInfo: [
                        NSFilePathErrorKey: bundleURL.path,
                        NSUnderlyingErrorKey: POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO),
                    ])
                }
                // `staging` now holds the previous version. A failed delete only leaves a staging
                // folder, which Reset All removes.
                try? fileManager.removeItem(at: staging)
            } else {
                try fileManager.moveItem(at: staging, to: bundleURL)
            }
        } catch {
            try? fileManager.removeItem(at: staging)
            throw error
        }
    }
}
