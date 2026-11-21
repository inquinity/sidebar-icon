import SidebarIconCore
import Testing

@Test func versionIsSet() {
    #expect(!SidebarIconCoreInfo.version.isEmpty)
}

@Test func verifiedBuildsIncludeTheSpikeBuild() {
    #expect(SidebarIconCoreInfo.isVerified(build: "26B131"))
    #expect(!SidebarIconCoreInfo.isVerified(build: "26C5"))
    #expect(!SidebarIconCoreInfo.isVerified(build: "unknown"))
}
