// swift-tools-version: 6.0

import PackageDescription

let binaryTargetName = "LibtorrentAppleBinary_0_2_12"
let binaryTargetURL = "https://github.com/clOudbb/libtorrent-apple/releases/download/v0.2.12/LibtorrentAppleBinary-0.2.12.zip"
let binaryTargetChecksum = "edda2a90ff0f6413f86103a437e89ca6d32fa7ce87db29a62623b453c5c76b71"

let package = Package(
    name: "libtorrent-apple",
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
    targets: [
        .binaryTarget(
            name: binaryTargetName,
            url: binaryTargetURL,
            checksum: binaryTargetChecksum
        ),
        .target(
            name: "LibtorrentAppleBridge",
            dependencies: [.target(name: binaryTargetName)],
            path: "Sources/LibtorrentAppleBridgeCompat",
            publicHeadersPath: "include"
        ),
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
        ),
        .executableTarget(
            name: "LibtorrentAppleBenchmarkCLI",
            dependencies: ["LibtorrentApple"],
            path: "Sources/LibtorrentAppleBenchmarkCLI"
        ),
        .testTarget(
            name: "LibtorrentAppleTests",
            dependencies: ["LibtorrentApple"],
            path: "Tests/LibtorrentAppleTests"
        ),
    ]
)
