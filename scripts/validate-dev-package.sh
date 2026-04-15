#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
MODE="${1:-source}"
CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-/tmp/libtorrent-apple-swift-clang-cache}"

run_mode() {
    local mode="$1"
    local package_dir
    package_dir="$("${SCRIPT_DIR}/prepare-dev-package.sh" "${mode}")"

    export CLANG_MODULE_CACHE_PATH
    export LIBTORRENT_APPLE_PACKAGE_MODE="${mode}"

    swift build --package-path "${package_dir}"
    swift test --package-path "${package_dir}" --disable-xctest
    echo "Swift dev package validation passed in ${mode} mode."
}

case "${MODE}" in
    source|local-binary)
        run_mode "${MODE}"
        ;;
    all-local)
        run_mode source
        run_mode local-binary
        ;;
    *)
        echo "usage: scripts/validate-dev-package.sh [source|local-binary|all-local]" >&2
        exit 1
        ;;
esac
