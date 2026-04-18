// swift-tools-version: 6.0

import PackageDescription

let packageMode = "__PACKAGE_MODE__"
let frameworkName = "__FRAMEWORK_NAME__"

var targets: [Target] = []

switch packageMode {
case "source":
    targets.append(
        .target(
            name: "LibtorrentAppleBridge",
            path: "Sources/LibtorrentAppleBridge",
            publicHeadersPath: "include"
        )
    )
case "local-binary":
    targets.append(
        .binaryTarget(
            name: frameworkName,
            path: "Artifacts/release/\(frameworkName).xcframework"
        )
    )
    targets.append(
        .target(
            name: "LibtorrentAppleBridge",
            dependencies: [.target(name: frameworkName)],
            path: "Sources/LibtorrentAppleBridgeCompat",
            publicHeadersPath: "include"
        )
    )
default:
    fatalError("Unsupported dev package mode: \(packageMode)")
}

targets.append(
    .target(
        name: "LibtorrentApple",
        dependencies: ["LibtorrentAppleBridge"],
        path: "Sources/LibtorrentApple",
        linkerSettings: [
            .linkedFramework("CFNetwork"),
            .linkedFramework("CoreFoundation"),
            .linkedFramework("Security"),
            .linkedFramework("SystemConfiguration"),
            .linkedLibrary("c++"),
        ]
    )
)

targets.append(
    .executableTarget(
        name: "LibtorrentAppleBenchmarkCLI",
        dependencies: ["LibtorrentApple"],
        path: "Sources/LibtorrentAppleBenchmarkCLI"
    )
)

targets.append(
    .testTarget(
        name: "LibtorrentAppleTests",
        dependencies: ["LibtorrentApple"],
        path: "Tests/LibtorrentAppleTests"
    )
)

let package = Package(
    name: "libtorrent-apple-dev",
    platforms: [
        .iOS(.v15),
        .macOS(.v13),
    ],
    products: [
        .library(
            name: "LibtorrentApple",
            targets: ["LibtorrentApple"]
        ),
        .executable(
            name: "LibtorrentAppleBenchmarkCLI",
            targets: ["LibtorrentAppleBenchmarkCLI"]
        ),
    ],
    targets: targets
)
