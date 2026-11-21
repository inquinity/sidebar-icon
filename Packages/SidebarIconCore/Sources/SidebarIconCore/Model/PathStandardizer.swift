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

    /// Whether `path` has the stored shape: absolute, no `~`, no trailing `/`, no empty, `.` or
    /// `..` components. Unlike `standardize`, it never looks at the filesystem, so a folder that was
    /// renamed or replaced by a link later does not make the stored mappings invalid.
    public static func isStoredForm(_ path: String) -> Bool {
        guard path.hasPrefix("/") else { return false }
        if path == "/" { return true }
        let components = path.dropFirst().split(separator: "/", omittingEmptySubsequences: false)
        return !components.contains { $0.isEmpty || $0 == "." || $0 == ".." }
    }

    /// `~/dev` for a path inside the home directory, for display only.
    public static func abbreviatingHome(_ path: String, home: String = realHomeDirectory) -> String {
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }
}
