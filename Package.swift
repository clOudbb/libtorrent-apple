// swift-tools-version: 6.0

import Foundation
import PackageDescription

enum PackageMode: String {
    case source
    case localBinary = "local-binary"
    case remoteBinary = "remote-binary"
}

struct BinaryArtifactConfiguration {
    let frameworkName: String
    let downloadURL: String
    let checksum: String
}

func loadBinaryArtifactConfiguration() -> BinaryArtifactConfiguration? {
    let configPath = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("PackageSupport/BinaryArtifact.env")

    guard let contents = try? String(contentsOf: configPath, encoding: .utf8) else {
        return nil
    }

    var values: [String: String] = [:]
    for rawLine in contents.split(whereSeparator: \.isNewline) {
        let line = rawLine.trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty, !line.hasPrefix("#"), let separator = line.firstIndex(of: "=") else {
            continue
        }

        let key = String(line[..<separator]).trimmingCharacters(in: .whitespaces)
        let value = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
        values[key] = value
    }

    let frameworkName = values["BINARY_FRAMEWORK_NAME"] ?? "LibtorrentAppleBinary"

    guard let downloadURL = values["BINARY_ARTIFACT_URL"],
          !downloadURL.isEmpty,
          !downloadURL.contains("<replace"),
          let checksum = values["BINARY_ARTIFACT_CHECKSUM"],
          !checksum.isEmpty
    else {
        return nil
    }

    return BinaryArtifactConfiguration(
        frameworkName: frameworkName,
        downloadURL: downloadURL,
        checksum: checksum
    )
}

let environment = ProcessInfo.processInfo.environment
let requestedMode = PackageMode(rawValue: environment["LIBTORRENT_APPLE_PACKAGE_MODE"] ?? "")
let binaryArtifactConfiguration = loadBinaryArtifactConfiguration()

let packageMode: PackageMode = {
    switch requestedMode {
    case .source:
        return .source
    case .localBinary:
        return .localBinary
    case .remoteBinary:
        return binaryArtifactConfiguration == nil ? .source : .remoteBinary
    case nil:
        return binaryArtifactConfiguration == nil ? .source : .remoteBinary
    }
}()

var targets: [Target] = []
let bridgeDependencyName: String

switch packageMode {
case .source:
    bridgeDependencyName = "LibtorrentAppleBridge"
    targets.append(
        .target(
            name: bridgeDependencyName,
            path: "Sources/LibtorrentAppleBridge",
            publicHeadersPath: "include"
        )
    )
case .localBinary:
    let frameworkName = binaryArtifactConfiguration?.frameworkName ?? "LibtorrentAppleBinary"
    bridgeDependencyName = frameworkName
    targets.append(
        .binaryTarget(
            name: frameworkName,
            path: "Artifacts/release/\(frameworkName).xcframework"
        )
    )
case .remoteBinary:
    let config = binaryArtifactConfiguration!
    bridgeDependencyName = config.frameworkName
    targets.append(
        .binaryTarget(
            name: config.frameworkName,
            url: config.downloadURL,
            checksum: config.checksum
        )
    )
}

targets.append(
    .target(
        name: "LibtorrentApple",
        dependencies: [.target(name: bridgeDependencyName)],
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
    .testTarget(
        name: "LibtorrentAppleTests",
        dependencies: ["LibtorrentApple"],
        path: "Tests/LibtorrentAppleTests"
    )
)

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
    ],
    targets: targets
)
