import Foundation
import Synchronization
@testable import SidebarIconCore

/// A fake `ProcessRunning` for `xcrun --find actool` and `actool` itself. A compile writes an
/// `Assets.car` listing the catalog's symbol sets, so different glyph sets give different cars.
final class FakeActool: ProcessRunning {
    static let actoolPath = "/Applications/Xcode.app/Contents/Developer/usr/bin/actool"

    struct State {
        var calls: [(executable: String, arguments: [String], environment: [String: String], timeout: TimeInterval)] = []
        var findOutput = ProcessOutput(exitCode: 0, standardOutput: Data((FakeActool.actoolPath + "\n").utf8))
        var compileError: Data?
        var timesOut = false
    }

    let state = Mutex(State())

    var compileCount: Int { state.withLock { $0.calls.filter { $0.executable == Self.actoolPath }.count } }

    func run(_ executable: URL, arguments: [String], environment: [String: String], timeout: TimeInterval) throws -> ProcessOutput {
        let current = state.withLock { state in
            state.calls.append((executable.path, arguments, environment, timeout))
            return state
        }
        if executable.path == "/usr/bin/xcrun" { return current.findOutput }
        if current.timesOut { return ProcessOutput(exitCode: 15, timedOut: true) }
        if let error = current.compileError { return ProcessOutput(exitCode: 1, standardOutput: error) }
        let output = URL(fileURLWithPath: arguments[arguments.firstIndex(of: "--compile")! + 1])
        let catalog = URL(fileURLWithPath: arguments.last!)
        let sets = try FileManager.default.contentsOfDirectory(atPath: catalog.path).filter { $0.hasSuffix(".symbolset") }.sorted()
        try Data(("car:" + sets.joined(separator: ",")).utf8).write(to: output.appending(path: "Assets.car"))
        return ProcessOutput(exitCode: 0, standardOutput: try Data(contentsOf: try fixture("actool-ok.plist")))
    }

    func runner() -> ActoolRunner {
        ActoolRunner(runner: self, inheritedEnvironment: ["HOME": "/Users/x", "TMPDIR": "/tmp/x/", "SECRET": "nope"],
                     isExecutable: { $0 == FakeActool.actoolPath })
    }
}
