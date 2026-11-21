import Foundation

public enum SystemInfo {
    /// The macOS build, for example `26B131`, recorded in ledger entries and findings.
    public static var macOSBuild: String {
        var size = 0
        guard sysctlbyname("kern.osversion", nil, &size, nil, 0) == 0, size > 0 else { return "unknown" }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("kern.osversion", &buffer, &size, nil, 0) == 0 else { return "unknown" }
        return String(cString: buffer)
    }

    /// For example `macOS 27.2.1 (26B131)`.
    public static var macOSDescription: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let patch = version.patchVersion > 0 ? ".\(version.patchVersion)" : ""
        return "macOS \(version.majorVersion).\(version.minorVersion)\(patch) (\(macOSBuild))"
    }
}
