// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SidebarIconCore",
    platforms: [.macOS("27.0")],
    products: [
        .library(name: "SidebarIconCore", targets: ["SidebarIconCore"]),
    ],
    targets: [
        .target(name: "SidebarIconCore"),
        .testTarget(name: "SidebarIconCoreTests", dependencies: ["SidebarIconCore"]),
    ]
)
