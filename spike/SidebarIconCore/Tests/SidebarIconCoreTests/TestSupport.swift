import Foundation

/// A fresh directory under the system temporary directory, removed when the value is released.
final class TemporaryDirectory {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appending(path: "SidebarIconCoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}

struct TestError: Error, Equatable {}
