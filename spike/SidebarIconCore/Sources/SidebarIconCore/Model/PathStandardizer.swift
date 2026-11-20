import Foundation

/// Folder paths are stored absolute, with `~` expanded, symlinks resolved, and no trailing `/`
/// (data-model.md), so a mapping and a Favorite's resolved URL compare equal.
public enum PathStandardizer {
    /// The user's real home directory. Inside the sandboxed extension `NSHomeDirectory()` points
    /// at the extension's container, so `~` is expanded from the password database instead.
    public static var realHomeDirectory: String {
        if let entry = getpwuid(getuid()), let dir = entry.pointee.pw_dir {
            return String(cString: dir)
        }
        return NSHomeDirectory()
    }

    public static func standardize(_ raw: String, home: String = realHomeDirectory) -> String {
        var path = raw
        if path == "~" {
            path = home
        } else if path.hasPrefix("~/") {
            path = home + path.dropFirst(1)
        }
        guard path.hasPrefix("/") else { return path }
        var resolved = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
        while resolved.count > 1 && resolved.hasSuffix("/") {
            resolved.removeLast()
        }
        return resolved
    }
}
