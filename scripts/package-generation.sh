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

binary_artifact_basename_for_version() {
    local version_input="${1:-}"
    local base_name="${2:-LibtorrentAppleBinary}"

    printf '%s-%s\n' "${base_name}" "${version_input#v}"
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

#ifndef LIBTORRENT_APPLE_HAS_SESSION_RUNTIME_SETTINGS
#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    bool has_upload_rate_limit;
    int32_t upload_rate_limit;
    bool has_download_rate_limit;
    int32_t download_rate_limit;
    bool has_connections_limit;
    int32_t connections_limit;
    bool has_active_downloads_limit;
    int32_t active_downloads_limit;
    bool has_active_seeds_limit;
    int32_t active_seeds_limit;
    bool has_active_checking_limit;
    int32_t active_checking_limit;
    bool has_active_dht_limit;
    int32_t active_dht_limit;
    bool has_active_tracker_limit;
    int32_t active_tracker_limit;
    bool has_active_lsd_limit;
    int32_t active_lsd_limit;
    bool has_active_limit;
    int32_t active_limit;
    bool has_connection_speed;
    int32_t connection_speed;
    bool has_torrent_connect_boost;
    int32_t torrent_connect_boost;
    bool has_mixed_mode_algorithm;
    int32_t mixed_mode_algorithm;
    bool has_rate_limit_ip_overhead;
    bool rate_limit_ip_overhead;
    bool has_allow_multiple_connections_per_ip;
    bool allow_multiple_connections_per_ip;
    bool has_enable_outgoing_tcp;
    bool enable_outgoing_tcp;
    bool has_enable_incoming_tcp;
    bool enable_incoming_tcp;
    bool has_enable_outgoing_utp;
    bool enable_outgoing_utp;
    bool has_enable_incoming_utp;
    bool enable_incoming_utp;
    bool has_auto_sequential;
    bool auto_sequential;
} libtorrent_apple_bridge_session_runtime_settings_t;

bool libtorrent_apple_bridge_session_apply_runtime_settings(
    libtorrent_apple_session_t *session,
    const libtorrent_apple_bridge_session_runtime_settings_t *settings,
    libtorrent_apple_error_t *error_out
);

bool libtorrent_apple_bridge_supports_session_runtime_settings(void);

#ifdef __cplusplus
}
#endif
#endif

#endif
EOF

    cat > "${output_dir}/bridge_compat.c" <<'EOF'
#include "LibtorrentAppleBridge.h"

#include <dlfcn.h>
#include <stdio.h>

#ifndef LIBTORRENT_APPLE_HAS_SESSION_RUNTIME_SETTINGS
typedef bool (*libtorrent_apple_session_apply_runtime_settings_fn)(
    libtorrent_apple_session_t *session,
    const libtorrent_apple_bridge_session_runtime_settings_t *settings,
    libtorrent_apple_error_t *error_out
);

static void *bridge_compat_runtime_settings_symbol(void) {
    return dlsym(RTLD_DEFAULT, "libtorrent_apple_session_apply_runtime_settings");
}

static void bridge_compat_set_error(
    libtorrent_apple_error_t *error_out,
    int32_t code,
    const char *message
) {
    if (error_out == NULL) {
        return;
    }

    error_out->code = code;
    snprintf(error_out->message, sizeof(error_out->message), "%s", message);
}

bool libtorrent_apple_bridge_session_apply_runtime_settings(
    libtorrent_apple_session_t *session,
    const libtorrent_apple_bridge_session_runtime_settings_t *settings,
    libtorrent_apple_error_t *error_out
) {
    void *symbol = bridge_compat_runtime_settings_symbol();
    if (symbol != NULL) {
        libtorrent_apple_session_apply_runtime_settings_fn apply_runtime_settings =
            (libtorrent_apple_session_apply_runtime_settings_fn)symbol;
        return apply_runtime_settings(session, settings, error_out);
    }

    bridge_compat_set_error(
        error_out,
        -3,
        "runtime settings require a binary artifact that exports libtorrent_apple_session_apply_runtime_settings"
    );
    return false;
}

bool libtorrent_apple_bridge_supports_session_runtime_settings(void) {
    return bridge_compat_runtime_settings_symbol() != NULL;
}
#endif
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
