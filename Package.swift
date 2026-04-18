// swift-tools-version: 6.0

import PackageDescription

let binaryTargetName = "LibtorrentAppleBinary_0_2_8_alpha_4"
let binaryTargetURL = "https://github.com/clOudbb/libtorrent-apple/releases/download/v0.2.8-alpha.4/LibtorrentAppleBinary-0.2.8-alpha.4.zip"
let binaryTargetChecksum = "526932a1f4dff9f536fca6061ec3ef97314d69f293e1bd4f385e75dd4df820e6"

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
