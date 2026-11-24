import Foundation

/// Reads files from the utility's own container: regular files only, never through a symbolic
/// link, and never more than `limit` bytes (security review L5). A FIFO, device or link planted
/// there can't hang the app or make it read something else.
public enum ContainerFile {
    /// `config.json`, `ledger.json`, `Info.plist`, glyph templates and keys.
    public static let smallLimit = 16 * 1024 * 1024
    /// A combined `Assets.car`.
    public static let carLimit = 64 * 1024 * 1024

    /// Throws `CocoaError(.fileReadNoSuchFile)` for a missing file, as `Data(contentsOf:)` does.
    public static func read(_ url: URL, limit: Int = smallLimit) throws -> Data {
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard fd >= 0 else {
            if errno == ENOENT { throw CocoaError(.fileReadNoSuchFile, userInfo: [NSFilePathErrorKey: url.path]) }
            throw CocoaError(.fileReadUnknown, userInfo: [NSFilePathErrorKey: url.path,
                                                          NSUnderlyingErrorKey: POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)])
        }
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: true)
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_mode & S_IFMT == S_IFREG else {
            throw CocoaError(.fileReadUnknown, userInfo: [NSFilePathErrorKey: url.path])
        }
        guard info.st_size <= limit, let data = try handle.read(upToCount: limit + 1), data.count <= limit else {
            if info.st_size == 0 { return Data() }
            throw CocoaError(.fileReadTooLarge, userInfo: [NSFilePathErrorKey: url.path])
        }
        return data
    }
}
