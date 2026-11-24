import Foundation
import Security

/// What a finished (or stopped) process produced.
public struct ProcessOutput: Sendable, Equatable {
    public var exitCode: Int32
    public var standardOutput: Data
    public var standardError: Data
    public var timedOut: Bool

    public init(exitCode: Int32, standardOutput: Data = Data(), standardError: Data = Data(), timedOut: Bool = false) {
        self.exitCode = exitCode
        self.standardOutput = standardOutput
        self.standardError = standardError
        self.timedOut = timedOut
    }
}

/// Runs one program with a fixed argument list and environment, no shell (research D5).
public protocol ProcessRunning: Sendable {
    func run(_ executable: URL, arguments: [String], environment: [String: String], timeout: TimeInterval) throws -> ProcessOutput
}

/// Whether custom glyphs can be built on this Mac.
public enum ToolStatus: Sendable, Equatable {
    case available(URL)
    case unavailable(String)
}

/// Why a glyph build failed. Nothing is changed when one is thrown.
public enum GlyphBuildError: Error, Sendable, Equatable {
    case toolUnavailable(String)
    case compileFailed(String)
    case timedOut
    /// The template has no `Regular-M` glyph, which `actool` requires.
    case missingRequiredGlyph(String)
    case templateUnreadable(String)

    public static let needsXcode = "Custom glyphs need Xcode (the Command Line Tools don't include the asset tool). Install Xcode, or use a system glyph."
    public static let needsLicense = "Open Xcode once and accept its license, then try again."
    public static let needsFirstLaunch = "Open Xcode once to finish installing its components, then try again."

    public var message: String {
        switch self {
        case .toolUnavailable(let reason): reason
        case .compileFailed(let detail): "The asset tool couldn't build the glyph: \(detail)."
        case .timedOut: "The asset tool didn't finish in time; nothing was changed."
        case .missingRequiredGlyph(let name):
            "\(name) has no Regular-Medium (Regular-M) glyph. Make the template with make-symbol-template, or add a Regular-M glyph in the SF Symbols app."
        case .templateUnreadable(let detail): "The template can't be read: \(detail)."
        }
    }
}

/// Finds and runs Xcode's `actool` (004 research D5). Optional: only custom-glyph builds use it.
public struct ActoolRunner: Sendable {
    public static let timeout: TimeInterval = 120
    static let xcrun = URL(fileURLWithPath: "/usr/bin/xcrun")

    let runner: any ProcessRunning
    /// This process's environment; only `HOME` and `TMPDIR` are passed on.
    let inheritedEnvironment: [String: String]
    /// True when the file is an executable signed by Apple (`anchor apple`).
    let isTrustedTool: @Sendable (String) -> Bool
    /// The selected developer directory, read without running anything, or nil if none.
    let developerDirectory: @Sendable () -> String?

    public init(runner: any ProcessRunning = SystemProcessRunner(),
                inheritedEnvironment: [String: String] = ProcessInfo.processInfo.environment,
                isTrustedTool: @escaping @Sendable (String) -> Bool = ActoolRunner.isAppleSignedExecutable,
                developerDirectory: @escaping @Sendable () -> String? = ActoolRunner.selectedDeveloperDirectory) {
        self.runner = runner
        self.inheritedEnvironment = inheritedEnvironment
        self.isTrustedTool = isTrustedTool
        self.developerDirectory = developerDirectory
    }

    /// `PATH=/usr/bin:/bin`, plus `HOME` and `TMPDIR` if set. `DEVELOPER_DIR` is not passed on:
    /// the tool comes from the developer directory chosen with `xcode-select` (review L3).
    var environment: [String: String] {
        var environment = ["PATH": "/usr/bin:/bin"]
        for key in ["HOME", "TMPDIR"] {
            if let value = inheritedEnvironment[key] { environment[key] = value }
        }
        return environment
    }

    /// The developer directory `xcode-select` chose (its link in `/var/db`), or Xcode in
    /// /Applications when none was chosen. Nothing is run, so a Mac without developer tools never
    /// sees the "install the command line developer tools" prompt that `/usr/bin/xcrun` shows.
    public static func selectedDeveloperDirectory() -> String? {
        let fileManager = FileManager.default
        if let link = try? fileManager.destinationOfSymbolicLink(atPath: "/var/db/xcode_select_link") {
            return fileManager.fileExists(atPath: link) ? link : nil
        }
        let xcode = "/Applications/Xcode.app/Contents/Developer"
        return fileManager.fileExists(atPath: xcode) ? xcode : nil
    }

    /// An executable regular file whose code signature is valid and anchored at Apple.
    public static func isAppleSignedExecutable(_ path: String) -> Bool {
        guard FileManager.default.isExecutableFile(atPath: path) else { return false }
        var code: SecStaticCode?
        var requirement: SecRequirement?
        guard SecStaticCodeCreateWithPath(URL(fileURLWithPath: path) as CFURL, [], &code) == errSecSuccess, let code,
              SecRequirementCreateWithString("anchor apple" as CFString, [], &requirement) == errSecSuccess, let requirement
        else { return false }
        return SecStaticCodeCheckValidity(code, [], requirement) == errSecSuccess
    }

    public func toolStatus() -> ToolStatus {
        guard let developer = developerDirectory(), !developer.contains("/CommandLineTools") else {
            return .unavailable(GlyphBuildError.needsXcode)
        }
        let output: ProcessOutput
        do {
            output = try runner.run(Self.xcrun, arguments: ["--find", "actool"], environment: environment, timeout: 30)
        } catch {
            return .unavailable(GlyphBuildError.needsXcode)
        }
        guard output.exitCode == 0, !output.timedOut else {
            return .unavailable(Self.plainReason(output) ?? GlyphBuildError.needsXcode)
        }
        let path = String(decoding: output.standardOutput, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        // The tool must be inside the selected developer directory and signed by Apple.
        let developerPrefix = developer.hasSuffix("/") ? developer : developer + "/"
        guard !path.isEmpty, !path.contains("\n"), path.hasPrefix(developerPrefix), !path.contains("/../"),
              !path.contains("/CommandLineTools/"), isTrustedTool(path) else {
            return .unavailable(GlyphBuildError.needsXcode)
        }
        return .available(URL(fileURLWithPath: path))
    }

    /// Compiles `catalog` into `outputDirectory/Assets.car` and returns its URL.
    public func compile(catalog: URL, outputDirectory: URL, partialInfoPlist: URL) throws -> URL {
        let actool: URL
        switch toolStatus() {
        case .available(let url): actool = url
        case .unavailable(let reason): throw GlyphBuildError.toolUnavailable(reason)
        }
        let arguments = [
            "--compile", outputDirectory.path,
            "--platform", "macosx",
            "--minimum-deployment-target", "27.0",
            "--output-format", "xml1",
            "--errors", "--warnings",
            "--output-partial-info-plist", partialInfoPlist.path,
            catalog.path,
        ]
        let output = try runner.run(actool, arguments: arguments, environment: environment, timeout: Self.timeout)
        if output.timedOut { throw GlyphBuildError.timedOut }
        if output.exitCode != 0, let reason = Self.plainReason(output) { throw GlyphBuildError.toolUnavailable(reason) }
        let errors = Self.errors(in: output.standardOutput)
        let car = outputDirectory.appending(path: "Assets.car")
        guard output.exitCode == 0, errors.isEmpty, FileManager.default.fileExists(atPath: car.path) else {
            let firstStderr = String(decoding: output.standardError, as: UTF8.self)
                .split(separator: "\n").first.map(String.init)
            throw GlyphBuildError.compileFailed(errors.first ?? firstStderr ?? "exit status \(output.exitCode)")
        }
        return car
    }

    /// The license and first-launch failures, in plain language. Only for a failed run, and only
    /// from standard error, so a glyph named like "license-doc" in a warning can't match.
    static func plainReason(_ output: ProcessOutput) -> String? {
        let text = String(decoding: output.standardError, as: UTF8.self).lowercased()
        if text.contains("license") { return GlyphBuildError.needsLicense }
        if text.contains("runfirstlaunch") || text.contains("first launch") { return GlyphBuildError.needsFirstLaunch }
        if text.contains("commandlinetools") || text.contains("unable to find utility") || text.contains("invalid active developer path") {
            return GlyphBuildError.needsXcode
        }
        return nil
    }

    /// Error messages from `actool`'s `xml1` output: document errors first (they name the
    /// symbol set), then general errors.
    static func errors(in plistData: Data) -> [String] {
        guard let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any] else { return [] }
        let document = (plist["com.apple.actool.document.errors"] as? [[String: Any]] ?? []).compactMap { $0["message"] as? String }
        let general = (plist["com.apple.actool.errors"] as? [[String: Any]] ?? []).compactMap { $0["description"] as? String }
        return document + general
    }
}

/// Runs a program with `Process`; stops it after `timeout` seconds. Output goes to temporary
/// files, not pipes, so a helper that inherits them and outlives the program can't keep this
/// waiting (review M1), and nothing is left blocked if the launch fails (L5).
public struct SystemProcessRunner: ProcessRunning {
    public init() {}

    public func run(_ executable: URL, arguments: [String], environment: [String: String], timeout: TimeInterval) throws -> ProcessOutput {
        let fileManager = FileManager.default
        let scratch = fileManager.temporaryDirectory.appending(path: "sidebaricons-run-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: scratch) }
        let outURL = scratch.appending(path: "stdout"), errURL = scratch.appending(path: "stderr")
        for url in [outURL, errURL] {
            guard fileManager.createFile(atPath: url.path, contents: nil) else { throw CocoaError(.fileWriteUnknown) }
        }
        let outHandle = try FileHandle(forWritingTo: outURL)
        let errHandle = try FileHandle(forWritingTo: errURL)
        defer {
            try? outHandle.close()
            try? errHandle.close()
        }

        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = outHandle
        process.standardError = errHandle
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        try process.run()

        var timedOut = false
        if finished.wait(timeout: .now() + timeout) == .timedOut {
            timedOut = true
            process.terminate()
            if finished.wait(timeout: .now() + 5) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                _ = finished.wait(timeout: .now() + 5)
            }
        }
        let limit = 4 * 1024 * 1024
        // Only the first 4 MB are ever read into memory (security review L4).
        func read(_ url: URL) -> Data {
            guard let handle = try? FileHandle(forReadingFrom: url) else { return Data() }
            defer { try? handle.close() }
            return ((try? handle.read(upToCount: limit)) ?? nil) ?? Data()
        }
        return ProcessOutput(exitCode: process.isRunning ? -1 : process.terminationStatus,
                             standardOutput: read(outURL), standardError: read(errURL), timedOut: timedOut)
    }
}
