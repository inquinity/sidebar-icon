import CryptoKit
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
/// Since 0.3.0 (004 research D2, D3): each mapping's style decides its type's icons (full colour,
/// an SF Symbol, or a custom glyph compiled into the bundle's `Assets.car`), and every distinct
/// content gets its own bundle, `IconRegistry-<hash>.app` with identifier `…iconregistry.<hash>`,
/// because Finder caches a bundle's `Assets.car` per path (004 spike S4b).
///
/// The bundle has `CFBundlePackageType` `APPL` and `LSUIElement` set, and is never launched. It stays application-type because that is the shape verified on 26B131
/// (`LSRegisterURL` registers it and its exported types; `lsregister -u` removes both). This file
/// only builds the bundle; registering it is the provider's job.
public enum IconRegistryBundle {
    /// The identifier of 0.2.0's unversioned bundle; versions append `.<hash>`.
    public static let bundleIdentifier = "com.altmansoftwaredesign.sidebaricons.iconregistry"

    public static func bundleIdentifier(forHash hash: String) -> String { "\(bundleIdentifier).\(hash)" }
    public static func bundleName(forHash hash: String) -> String { "IconRegistry-\(hash).app" }

    /// The exported type for a code and a style key, for example
    /// `com.altmansoftwaredesign.sidebaricons.icon.s001.sf.hammer`. Codes are `S` plus base-36
    /// characters and style keys use lowercase letters, digits, dots and hyphens, so the result is a
    /// valid identifier. The style key is part of it because icons are cached per type.
    public static func typeIdentifier(for code: String, styleKey: String) -> String {
        "com.altmansoftwaredesign.sidebaricons.icon.\(code.lowercased()).\(styleKey)"
    }

    /// A symbol name that is never defined, so the sidebar falls back to the type's `.icns`.
    public static let missingSymbolName = "com.altmansoftwaredesign.sidebaricons.no-symbol"

    /// Bump when the Info.plist layout changes. 3: icons in `UTTypeIcons` with the missing symbol,
    /// asset ID in the type identifier (2026-11-20). 4: styles, versioned bundles (0.3.0).
    static let formatRevision = 4

    public enum EntryStyle: Sendable, Equatable {
        /// The copied image's `.icns`, drawn in full colour (the missing-symbol fallback).
        case fullColour(assetID: UUID, icnsSource: URL)
        /// An SF Symbol by name.
        case systemSymbol(name: String)
        /// A symbol compiled into the bundle's `Assets.car` (`CustomGlyph.symbolName`).
        case customGlyph(symbolName: String, versionID: UUID)
    }

    public struct Entry: Sendable, Equatable {
        public var osType: String
        public var style: EntryStyle

        public init(osType: String, style: EntryStyle) {
            self.osType = osType
            self.style = style
        }

        /// A full-colour entry (the 0.2.0 shape).
        public init(osType: String, assetID: UUID, icnsSource: URL) {
            self.init(osType: osType, style: .fullColour(assetID: assetID, icnsSource: icnsSource))
        }

        /// The part of the type identifier that changes with the icon.
        public var styleKey: String {
            switch style {
            case .fullColour(let assetID, _): assetID.uuidString.lowercased()
            case .systemSymbol(let name): "sf.\(name)"
            case .customGlyph(_, let versionID): "glyph.\(versionID.uuidString.lowercased())"
            }
        }

        /// `<assetID>.icns` for full colour; nothing for the symbol styles.
        public var icnsFileName: String? {
            if case .fullColour(let assetID, _) = style { return "\(assetID.uuidString).icns" }
            return nil
        }

        var icons: [String: String] {
            switch style {
            case .fullColour:
                ["UTTypeIconFile": icnsFileName ?? "", "UTTypeSymbolName": IconRegistryBundle.missingSymbolName]
            case .systemSymbol(let name):
                ["UTTypeSymbolName": name]
            case .customGlyph(let symbolName, _):
                ["UTTypeSymbolName": symbolName]
            }
        }
    }

    /// Eight lowercase hex characters naming one content: the format revision, the sorted entries
    /// and the bytes of `Assets.car`. Same content, same hash, same bundle path, so applying the
    /// same configuration twice writes nothing new.
    public static func contentHash(entries: [Entry], assetsCar: Data?) -> String {
        var hasher = SHA256()
        hasher.update(data: Data("format\(formatRevision);".utf8))
        for entry in entries.sorted(by: { $0.osType < $1.osType }) {
            // Explicit key=value text, so the hash never depends on how Swift prints collections.
            let icons = entry.icons.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ";")
            hasher.update(data: Data("\(entry.osType)|\(entry.styleKey)|\(icons)\n".utf8))
        }
        if let assetsCar { hasher.update(data: assetsCar) }
        return hasher.finalize().prefix(4).map { String(format: "%02x", $0) }.joined()
    }

    /// The `Info.plist` contents. Deterministic: entries are sorted by code and keys are sorted.
    /// Throws `invalidMapping` for a code outside the project's range or a code used twice, since
    /// either would give an invalid or ambiguous type.
    public static func infoPlist(for entries: [Entry], hash: String) throws -> Data {
        let codes = entries.map(\.osType)
        if let bad = codes.first(where: { !OSTypeCode.isValid($0) }) {
            throw SidebarIconError.invalidMapping("type code \(bad) is not in the S000–SZZZ range")
        }
        guard Set(codes).count == codes.count else {
            throw SidebarIconError.invalidMapping("a type code is used more than once")
        }
        let exportedTypes: [[String: Any]] = entries.sorted { $0.osType < $1.osType }.map { entry in
            [
                "UTTypeIdentifier": typeIdentifier(for: entry.osType, styleKey: entry.styleKey),
                "UTTypeDescription": "Sidebar Icons \(entry.osType)",
                "UTTypeConformsTo": ["public.data"],
                "UTTypeIcons": entry.icons,
                "UTTypeTagSpecification": ["com.apple.ostype": [entry.osType]],
            ]
        }
        let plist: [String: Any] = [
            "CFBundleDevelopmentRegion": "en",
            "CFBundleIdentifier": bundleIdentifier(forHash: hash),
            "CFBundleInfoDictionaryVersion": "6.0",
            "CFBundleName": "IconRegistry",
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": "1.0",
            "CFBundleVersion": String(UInt32(hash, radix: 16) ?? 0),
            "LSMinimumSystemVersion": "27.0",
            "LSUIElement": true,
            "UTExportedTypeDeclarations": exportedTypes,
        ]
        return try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    }

    /// Writes the complete bundle to `bundleURL`, replacing any previous content in one step.
    /// `assetsCar`, when given, is copied to `Contents/Resources/Assets.car`.
    public static func write(_ entries: [Entry], assetsCar: URL? = nil, hash: String, to bundleURL: URL) throws {
        try write(entries, assetsCarData: assetsCar.map { try ContainerFile.read($0, limit: ContainerFile.carLimit) }, hash: hash, to: bundleURL)
    }

    /// True when the bundle at `bundleURL` holds exactly this content: the same `Info.plist`, the
    /// same `Assets.car` (or none), and every `.icns` it names. A damaged or planted bundle at a
    /// version's path is rewritten rather than registered as it is.
    public static func isIntact(_ entries: [Entry], assetsCarData: Data?, hash: String, at bundleURL: URL) -> Bool {
        let fileManager = FileManager.default
        let contents = bundleURL.appending(path: "Contents", directoryHint: .isDirectory)
        let resources = contents.appending(path: "Resources", directoryHint: .isDirectory)
        guard let expected = try? infoPlist(for: entries, hash: hash),
              (try? ContainerFile.read(contents.appending(path: "Info.plist"))) == expected,
              fileManager.fileExists(atPath: contents.appending(path: "PkgInfo").path) else { return false }
        for name in entries.compactMap(\.icnsFileName) where !fileManager.fileExists(atPath: resources.appending(path: name).path) {
            return false
        }
        // Nothing else may be in the bundle (security review, info): a planted bundle at a
        // version's path could add plug-ins that Launch Services would register with it.
        var expectedPaths: Set<String> = ["Contents", "Contents/Info.plist", "Contents/PkgInfo", "Contents/Resources"]
        expectedPaths.formUnion(entries.compactMap(\.icnsFileName).map { "Contents/Resources/\($0)" })
        if assetsCarData != nil { expectedPaths.insert("Contents/Resources/Assets.car") }
        guard let found = try? fileManager.subpathsOfDirectory(atPath: bundleURL.path),
              Set(found.filter { ($0 as NSString).lastPathComponent != ".DS_Store" }) == expectedPaths else { return false }
        let car = resources.appending(path: "Assets.car")
        if let assetsCarData {
            return (try? ContainerFile.read(car, limit: ContainerFile.carLimit)) == assetsCarData
        }
        return !fileManager.fileExists(atPath: car.path)
    }

    /// Writes the bundle from the car's bytes, the same bytes the content hash was made from.
    public static func write(_ entries: [Entry], assetsCarData: Data?, hash: String, to bundleURL: URL) throws {
        let fileManager = FileManager.default
        let staging = bundleURL.deletingLastPathComponent()
            .appending(path: ".\(bundleURL.lastPathComponent).staging-\(UUID().uuidString)", directoryHint: .isDirectory)
        let contents = staging.appending(path: "Contents", directoryHint: .isDirectory)
        let resources = contents.appending(path: "Resources", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: resources, withIntermediateDirectories: true)
        do {
            try infoPlist(for: entries, hash: hash).write(to: contents.appending(path: "Info.plist"))
            try Data("APPL????".utf8).write(to: contents.appending(path: "PkgInfo"))
            for entry in entries {
                guard case .fullColour(_, let icnsSource) = entry.style, let name = entry.icnsFileName else { continue }
                let target = resources.appending(path: name)
                if !fileManager.fileExists(atPath: target.path) {
                    try fileManager.copyItem(at: icnsSource, to: target)
                }
            }
            if let assetsCarData {
                try assetsCarData.write(to: resources.appending(path: "Assets.car"))
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
                // `staging` now holds the previous content. A failed delete only leaves a staging
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
