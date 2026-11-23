import Foundation
import Synchronization

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
    /// This process's environment; only a few variables are passed on.
    let inheritedEnvironment: [String: String]
    let isExecutable: @Sendable (String) -> Bool

    public init(runner: any ProcessRunning = SystemProcessRunner(),
                inheritedEnvironment: [String: String] = ProcessInfo.processInfo.environment,
                isExecutable: @escaping @Sendable (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }) {
        self.runner = runner
        self.inheritedEnvironment = inheritedEnvironment
        self.isExecutable = isExecutable
    }

    /// `PATH=/usr/bin:/bin`, plus `HOME`, `TMPDIR` and `DEVELOPER_DIR` if set.
    var environment: [String: String] {
        var environment = ["PATH": "/usr/bin:/bin"]
        for key in ["HOME", "TMPDIR", "DEVELOPER_DIR"] {
            if let value = inheritedEnvironment[key] { environment[key] = value }
        }
        return environment
    }

    public func toolStatus() -> ToolStatus {
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
        guard !path.isEmpty, !path.contains("\n"), path.hasPrefix("/"),
              !path.contains("/CommandLineTools/"), path.contains("/Developer/"), isExecutable(path) else {
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
        if let reason = Self.plainReason(output) { throw GlyphBuildError.toolUnavailable(reason) }
        let errors = Self.errors(in: output.standardOutput)
        let car = outputDirectory.appending(path: "Assets.car")
        guard output.exitCode == 0, errors.isEmpty, FileManager.default.fileExists(atPath: car.path) else {
            let firstStderr = String(decoding: output.standardError, as: UTF8.self)
                .split(separator: "\n").first.map(String.init)
            throw GlyphBuildError.compileFailed(errors.first ?? firstStderr ?? "exit status \(output.exitCode)")
        }
        return car
    }

    /// The license and first-launch failures, in plain language.
    static func plainReason(_ output: ProcessOutput) -> String? {
        let text = (String(decoding: output.standardError, as: UTF8.self) + String(decoding: output.standardOutput, as: UTF8.self)).lowercased()
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

/// Runs a program with `Process`; stops it after `timeout` seconds.
public struct SystemProcessRunner: ProcessRunning {
    public init() {}

    public func run(_ executable: URL, arguments: [String], environment: [String: String], timeout: TimeInterval) throws -> ProcessOutput {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        process.standardInput = FileHandle.nullDevice
        let stdout = Pipe(), stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        // Read both pipes while the process runs, so a full pipe can't block it.
        let collected = Mutex<(out: Data, err: Data)>((Data(), Data()))
        let readers = DispatchGroup()
        for (pipe, isOut) in [(stdout, true), (stderr, false)] {
            readers.enter()
            DispatchQueue.global().async {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                collected.withLock { if isOut { $0.out = data } else { $0.err = data } }
                readers.leave()
            }
        }
        try process.run()
        var timedOut = false
        if finished.wait(timeout: .now() + timeout) == .timedOut {
            timedOut = true
            process.terminate()
            if finished.wait(timeout: .now() + 5) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                finished.wait()
            }
        }
        readers.wait()
        let (out, err) = collected.withLock { ($0.out, $0.err) }
        return ProcessOutput(exitCode: process.terminationStatus, standardOutput: out, standardError: err, timedOut: timedOut)
    }
}
