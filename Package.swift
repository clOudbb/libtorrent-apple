// swift-tools-version: 6.0

import Foundation
import PackageDescription

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

guard let binaryArtifactConfiguration = loadBinaryArtifactConfiguration() else {
    fatalError(
        """
        PackageSupport/BinaryArtifact.env is missing or incomplete.
        The public SwiftPM package is remote-binary-only.
        Maintainers should use scripts/validate-dev-package.sh for source/local-binary validation.
        """
    )
}

var targets: [Target] = []
let bridgeDependencyName = binaryArtifactConfiguration.frameworkName

targets.append(
    .binaryTarget(
        name: binaryArtifactConfiguration.frameworkName,
        url: binaryArtifactConfiguration.downloadURL,
        checksum: binaryArtifactConfiguration.checksum
    )
)

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
    targets: targets
)
