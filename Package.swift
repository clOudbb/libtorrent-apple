// swift-tools-version: 6.0

import PackageDescription

let binaryTargetName = "LibtorrentAppleBinary_0_3_1"
let binaryTargetURL = "https://github.com/clOudbb/libtorrent-apple/releases/download/v0.3.1/LibtorrentAppleBinary-0.3.1.zip"
let binaryTargetChecksum = "d887e4e3b5c58a4a28e68ffe04fe443e084201787e4a1558e278d90ea85ccb08"

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
