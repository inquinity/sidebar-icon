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
        #expect(calls[0].environment == calls[1].environment)
        #expect(calls[1].timeout == 120)
    }

    @Test func neverPassesDeveloperDir() {
        let runner = ActoolRunner(runner: FakeActool(), inheritedEnvironment: ["DEVELOPER_DIR": "/Applications/Xcode-beta.app/Contents/Developer"])
        #expect(runner.environment == ["PATH": "/usr/bin:/bin"])
    }

    @Test func noDeveloperDirectoryMeansNoXcrun() {
        let fake = FakeActool()
        for developer in [nil, "/Library/Developer/CommandLineTools"] as [String?] {
            let runner = ActoolRunner(runner: fake, inheritedEnvironment: [:], isTrustedTool: { _ in true }, developerDirectory: { developer })
            #expect(runner.toolStatus() == .unavailable(GlyphBuildError.needsXcode))
        }
        // The xcrun shim, which can show an install prompt, never ran.
        #expect(fake.state.withLock { $0.calls.isEmpty })
    }

    @Test func toolOutsideTheDeveloperDirectoryIsRefused() {
        let fake = FakeActool()
        fake.state.withLock { $0.findOutput = ProcessOutput(exitCode: 0, standardOutput: Data("/tmp/Developer/usr/bin/actool\n".utf8)) }
        let runner = ActoolRunner(runner: fake, inheritedEnvironment: [:], isTrustedTool: { _ in true },
                                  developerDirectory: { "/Applications/Xcode.app/Contents/Developer" })
        #expect(runner.toolStatus() == .unavailable(GlyphBuildError.needsXcode))
    }

    @Test func realXcodeActoolIsAppleSigned() throws {
        let path = "/Applications/Xcode.app/Contents/Developer/usr/bin/actool"
        try #require(FileManager.default.fileExists(atPath: path), "Xcode not installed here")
        #expect(ActoolRunner.isAppleSignedExecutable(path))
        let unsigned = try TemporaryDirectory()
        let script = unsigned.url.appending(path: "actool")
        try Data("#!/bin/sh\n".utf8).write(to: script)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        #expect(!ActoolRunner.isAppleSignedExecutable(script.path))
    }

    @Test func licenseWordInASuccessfulRunIsNotAnError() throws {
        let output = ProcessOutput(exitCode: 0, standardOutput: Data("glyph license-doc".utf8), standardError: Data("warning: license-doc".utf8))
        #expect(ActoolRunner.plainReason(ProcessOutput(exitCode: 1, standardError: Data("Xcode license".utf8))) == GlyphBuildError.needsLicense)
        #expect(ActoolRunner.plainReason(ProcessOutput(exitCode: 1, standardOutput: Data("license".utf8))) == nil)
        _ = output
        let dir = try TemporaryDirectory()
        let fake = LicenseWarningActool()
        let out = dir.url.appending(path: "out")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let runner = ActoolRunner(runner: fake, inheritedEnvironment: [:], isTrustedTool: { _ in true },
                                  developerDirectory: { "/Applications/Xcode.app/Contents/Developer" })
        #expect(try runner.compile(catalog: dir.url, outputDirectory: out, partialInfoPlist: dir.url.appending(path: "p")).lastPathComponent == "Assets.car")
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
            return ActoolRunner(runner: fake, inheritedEnvironment: [:], isTrustedTool: { _ in executable },
                                developerDirectory: { "/Applications/Xcode.app/Contents/Developer" }).toolStatus()
        }
        let found = ProcessOutput(exitCode: 0, standardOutput: Data((FakeActool.actoolPath + "\n").utf8))
        #expect(status(found) == .available(URL(fileURLWithPath: FakeActool.actoolPath)))
        #expect(status(found, executable: false) == .unavailable(GlyphBuildError.needsXcode))
        #expect(status(ProcessOutput(exitCode: 0, standardOutput: Data("/Applications/Xcode.app/Contents/Developer/../../../tmp/actool\n".utf8)))
            == .unavailable(GlyphBuildError.needsXcode))
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

    @Test func childThatKeepsTheOutputOpenDoesntBlock() throws {
        let start = Date()
        let output = try SystemProcessRunner().run(URL(fileURLWithPath: "/bin/sh"), arguments: ["-c", "sleep 20 & echo hi"],
                                                   environment: ["PATH": "/usr/bin:/bin"], timeout: 10)
        #expect(String(decoding: output.standardOutput, as: UTF8.self) == "hi\n")
        #expect(Date().timeIntervalSince(start) < 5)
    }

    @Test func launchFailureThrowsWithoutHanging() {
        #expect(throws: (any Error).self) {
            try SystemProcessRunner().run(URL(fileURLWithPath: "/nonexistent/tool"), arguments: [], environment: [:], timeout: 5)
        }
    }
}

/// An actool that succeeds but prints "license" in a warning.
final class LicenseWarningActool: ProcessRunning {
    func run(_ executable: URL, arguments: [String], environment: [String: String], timeout: TimeInterval) throws -> ProcessOutput {
        if executable.path == "/usr/bin/xcrun" {
            return ProcessOutput(exitCode: 0, standardOutput: Data((FakeActool.actoolPath + "\n").utf8))
        }
        let output = URL(fileURLWithPath: arguments[arguments.firstIndex(of: "--compile")! + 1])
        try Data("car".utf8).write(to: output.appending(path: "Assets.car"))
        return ProcessOutput(exitCode: 0, standardOutput: try Data(contentsOf: try fixture("actool-ok.plist")),
                             standardError: Data("warning: symbol license-doc is large".utf8))
    }
}
