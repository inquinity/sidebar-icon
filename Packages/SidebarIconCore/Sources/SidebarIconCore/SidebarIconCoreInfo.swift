/// Package identity and the macOS builds the sidebar mechanism has been verified on.
public enum SidebarIconCoreInfo {
    public static let version = "0.2.0"

    /// macOS builds on which Path B was verified end to end (research D8). Finder's rendering
    /// can't be detected automatically, so other builds get a non-blocking warning.
    public static let verifiedBuilds: Set<String> = ["26B131"]

    public static func isVerified(build: String) -> Bool {
        verifiedBuilds.contains(build)
    }
}
