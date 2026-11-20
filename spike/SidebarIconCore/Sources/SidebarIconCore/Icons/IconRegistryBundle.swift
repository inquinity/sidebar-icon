import Foundation

/// The Path B icon registration bundle (research R3, `PRIVATE_API.md` PA-04).
///
/// A small application-type bundle with no executable whose `Info.plist` declares one
/// `CFBundleDocumentTypes` entry per mapping: one `CFBundleTypeOSTypes` code and one
/// `CFBundleTypeIconFile`. Launch Services binds document-type claims to applications, so the
/// bundle is `IconRegistry.app` with `CFBundlePackageType` `APPL` and `LSUIElement` set; it is
/// never launched. This file only builds the bundle; registering it is the provider's job.
public enum IconRegistryBundle {
    public static let bundleIdentifier = "com.altmansoftwaredesign.SidebarIcons.IconRegistry"

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
    public static func infoPlist(for entries: [Entry]) throws -> Data {
        let documentTypes: [[String: Any]] = entries
            .sorted { $0.osType < $1.osType }
            .map { entry in
                [
                    "CFBundleTypeName": "Sidebar Icons \(entry.osType)",
                    "CFBundleTypeOSTypes": [entry.osType],
                    "CFBundleTypeIconFile": entry.icnsFileName,
                    "CFBundleTypeRole": "None",
                ]
            }
        let plist: [String: Any] = [
            "CFBundleDevelopmentRegion": "en",
            "CFBundleDocumentTypes": documentTypes,
            "CFBundleIdentifier": bundleIdentifier,
            "CFBundleInfoDictionaryVersion": "6.0",
            "CFBundleName": "IconRegistry",
            "CFBundlePackageType": "APPL",
            "CFBundleShortVersionString": "1.0",
            "CFBundleVersion": "1",
            "LSMinimumSystemVersion": "27.0",
            "LSUIElement": true,
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
                _ = try fileManager.replaceItemAt(bundleURL, withItemAt: staging)
            } else {
                try fileManager.moveItem(at: staging, to: bundleURL)
            }
        } catch {
            try? fileManager.removeItem(at: staging)
            throw error
        }
    }
}
