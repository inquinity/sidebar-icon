// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SidebarIconCore",
    platforms: [.macOS("27.0")],
    products: [
        .library(name: "SidebarIconCore", targets: ["SidebarIconCore"]),
        .executable(name: "make-symbol-template", targets: ["make-symbol-template"]),
    ],
    targets: [
        .target(name: "SidebarIconCore"),
        // The manual process's helper (004 research D4b): SVG in, symbol template out.
        .executableTarget(name: "make-symbol-template", dependencies: ["SidebarIconCore"]),
        .testTarget(
            name: "SidebarIconCoreTests",
            dependencies: ["SidebarIconCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
