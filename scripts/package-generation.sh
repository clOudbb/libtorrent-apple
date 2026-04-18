#!/usr/bin/env bash

set -euo pipefail

sanitize_version_identifier() {
    local version_input="${1:-}"
    local sanitized

    sanitized="${version_input#v}"
    sanitized="$(printf '%s' "${sanitized}" | sed -E 's/[^0-9A-Za-z]+/_/g; s/^_+//; s/_+$//g')"

    if [[ -z "${sanitized}" ]]; then
        echo "error: failed to sanitize version identifier from '${version_input}'" >&2
        exit 1
    fi

    printf '%s\n' "${sanitized}"
}

binary_framework_name_for_version() {
    local version_input="${1:-}"
    local base_name="${2:-LibtorrentAppleBinary}"
    local sanitized_version

    sanitized_version="$(sanitize_version_identifier "${version_input}")"
    printf '%s_%s\n' "${base_name}" "${sanitized_version}"
}

write_bridge_compat_target() {
    local output_dir="${1:-}"
    local framework_name="${2:-}"

    if [[ -z "${output_dir}" || -z "${framework_name}" ]]; then
        echo "error: write_bridge_compat_target requires <output_dir> <framework_name>" >&2
        exit 1
    fi

    mkdir -p "${output_dir}/include"

    cat > "${output_dir}/include/LibtorrentAppleBridge.h" <<EOF
#ifndef LIBTORRENT_APPLE_BRIDGE_COMPAT_H
#define LIBTORRENT_APPLE_BRIDGE_COMPAT_H

#include <${framework_name}/LibtorrentAppleBinary.h>

#endif
EOF

    cat > "${output_dir}/bridge_compat.c" <<'EOF'
#include "LibtorrentAppleBridge.h"
EOF
}

write_release_package_manifest() {
    local output_path="${1:-}"
    local binary_target_name="${2:-}"
    local binary_target_url="${3:-}"
    local binary_target_checksum="${4:-}"

    if [[ -z "${output_path}" || -z "${binary_target_name}" || -z "${binary_target_url}" || -z "${binary_target_checksum}" ]]; then
        echo "error: write_release_package_manifest requires <output_path> <binary_target_name> <url> <checksum>" >&2
        exit 1
    fi

    cat > "${output_path}" <<EOF
// swift-tools-version: 6.0

import PackageDescription

let binaryTargetName = "${binary_target_name}"
let binaryTargetURL = "${binary_target_url}"
let binaryTargetChecksum = "${binary_target_checksum}"

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
EOF
}

write_local_validation_package_manifest() {
    local output_path="${1:-}"
    local binary_target_name="${2:-}"
    local binary_target_path="${3:-}"

    if [[ -z "${output_path}" || -z "${binary_target_name}" || -z "${binary_target_path}" ]]; then
        echo "error: write_local_validation_package_manifest requires <output_path> <binary_target_name> <path>" >&2
        exit 1
    fi

    cat > "${output_path}" <<EOF
// swift-tools-version: 6.0

import PackageDescription

let binaryTargetName = "${binary_target_name}"
let binaryTargetPath = "${binary_target_path}"

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
            path: binaryTargetPath
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
EOF
}
