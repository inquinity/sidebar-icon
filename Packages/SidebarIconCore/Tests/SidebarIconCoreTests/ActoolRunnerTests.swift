import Foundation
import Testing
@testable import SidebarIconCore

/// 004 T024: research D5 and contracts/glyph-builder.md, errors → messages.
@Suite struct ActoolRunnerTests {
    private func compile(_ fake: FakeActool, in dir: TemporaryDirectory) throws -> URL {
        let out = dir.url.appending(path: "out")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let catalog = dir.url.appending(path: "G.xcassets")
        try FileManager.default.createDirectory(at: catalog, withIntermediateDirectories: true)
        return try fake.runner().compile(catalog: catalog, outputDirectory: out, partialInfoPlist: dir.url.appending(path: "p.plist"))
    }

    @Test func usesTheFixedArgumentsAndAMinimalEnvironment() throws {
        let dir = try TemporaryDirectory()
        let fake = FakeActool()
        let car = try compile(fake, in: dir)
        #expect(car.lastPathComponent == "Assets.car")
        let calls = fake.state.withLock { $0.calls }
        #expect(calls.map(\.executable) == ["/usr/bin/xcrun", FakeActool.actoolPath])
        #expect(calls[0].arguments == ["--find", "actool"])
        let out = dir.url.appending(path: "out").path
        #expect(calls[1].arguments == [
            "--compile", out, "--platform", "macosx", "--minimum-deployment-target", "27.0",
            "--output-format", "xml1", "--errors", "--warnings",
            "--output-partial-info-plist", dir.url.appending(path: "p.plist").path, dir.url.appending(path: "G.xcassets").path,
        ])
        #expect(calls[1].environment == ["PATH": "/usr/bin:/bin", "HOME": "/Users/x", "TMPDIR": "/tmp/x/"])
        #expect(calls[1].timeout == 120)
    }

    @Test func passesDeveloperDirWhenSet() {
        let runner = ActoolRunner(runner: FakeActool(), inheritedEnvironment: ["DEVELOPER_DIR": "/Applications/Xcode-beta.app/Contents/Developer"])
        #expect(runner.environment == ["PATH": "/usr/bin:/bin", "DEVELOPER_DIR": "/Applications/Xcode-beta.app/Contents/Developer"])
    }

    @Test func timeoutMapsToTimedOut() throws {
        let dir = try TemporaryDirectory()
        let fake = FakeActool()
        fake.state.withLock { $0.timesOut = true }
        #expect(throws: GlyphBuildError.timedOut) { try compile(fake, in: dir) }
        #expect(GlyphBuildError.timedOut.message.contains("nothing was changed"))
    }

    @Test func xmlErrorMapsToTheFirstError() throws {
        let dir = try TemporaryDirectory()
        let fake = FakeActool()
        fake.state.withLock { $0.compileError = try? Data(contentsOf: try fixture("actool-err.plist")) }
        do {
            _ = try compile(fake, in: dir)
            Issue.record("expected compileFailed")
        } catch let GlyphBuildError.compileFailed(detail) {
            #expect(detail.contains("must have a glyph for Regular weight Medium size"))
            #expect(detail.hasPrefix("The SVG file provided for the symbol image set"))
        }
        #expect(ActoolRunner.errors(in: try Data(contentsOf: try fixture("actool-ok.plist"))).isEmpty)
    }

    @Test func toolStatusCases() {
        func status(_ output: ProcessOutput, executable: Bool = true) -> ToolStatus {
            let fake = FakeActool()
            fake.state.withLock { $0.findOutput = output }
            return ActoolRunner(runner: fake, inheritedEnvironment: [:], isExecutable: { _ in executable }).toolStatus()
        }
        let found = ProcessOutput(exitCode: 0, standardOutput: Data((FakeActool.actoolPath + "\n").utf8))
        #expect(status(found) == .available(URL(fileURLWithPath: FakeActool.actoolPath)))
        #expect(status(found, executable: false) == .unavailable(GlyphBuildError.needsXcode))
        #expect(status(ProcessOutput(exitCode: 72, standardError: Data("xcrun: error: unable to find utility \"actool\", not a developer tool or in PATH".utf8)))
            == .unavailable(GlyphBuildError.needsXcode))
        #expect(status(ProcessOutput(exitCode: 0, standardOutput: Data("/Library/Developer/CommandLineTools/usr/bin/actool\n".utf8)))
            == .unavailable(GlyphBuildError.needsXcode))
        #expect(status(ProcessOutput(exitCode: 0, standardOutput: Data())) == .unavailable(GlyphBuildError.needsXcode))
        #expect(status(ProcessOutput(exitCode: 69, standardError: Data("You have not agreed to the Xcode license agreements.".utf8)))
            == .unavailable(GlyphBuildError.needsLicense))
        #expect(status(ProcessOutput(exitCode: 1, standardError: Data("Run xcodebuild -runFirstLaunch to install components".utf8)))
            == .unavailable(GlyphBuildError.needsFirstLaunch))
    }

    @Test func realRunnerCapturesOutputAndStopsAtTheTimeout() throws {
        let runner = SystemProcessRunner()
        let echo = try runner.run(URL(fileURLWithPath: "/bin/echo"), arguments: ["hi"], environment: [:], timeout: 10)
        #expect(echo.exitCode == 0)
        #expect(String(decoding: echo.standardOutput, as: UTF8.self) == "hi\n")
        let start = Date()
        let sleep = try runner.run(URL(fileURLWithPath: "/bin/sleep"), arguments: ["30"], environment: [:], timeout: 0.5)
        #expect(sleep.timedOut)
        #expect(Date().timeIntervalSince(start) < 10)
    }
}
