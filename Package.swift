// swift-tools-version: 6.0

import PackageDescription

let binaryTargetName = "LibtorrentAppleBinary_0_2_8_alpha_3"
let binaryTargetURL = "https://github.com/clOudbb/libtorrent-apple/releases/download/v0.2.8-alpha.3/LibtorrentAppleBinary-0.2.8-alpha.3.zip"
let binaryTargetChecksum = "8b06d5bfc83846b0c77c97b48a8b745efea98d9c8c6fb7013653437e0de9be70"

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
