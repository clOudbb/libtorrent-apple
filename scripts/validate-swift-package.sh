#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
MODE="${1:-source}"
CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-/tmp/libtorrent-apple-swift-clang-cache}"

run_mode() {
    local mode="$1"
    export LIBTORRENT_APPLE_PACKAGE_MODE="${mode}"
    export CLANG_MODULE_CACHE_PATH

    swift build --package-path "${ROOT_DIR}"
    swift test --package-path "${ROOT_DIR}" --disable-xctest
    echo "Swift package validation passed in ${mode} mode."
}

case "${MODE}" in
    source|local-binary|remote-binary)
        run_mode "${MODE}"
        ;;
    all)
        run_mode source
        run_mode local-binary
        run_mode remote-binary
        ;;
    all-local)
        run_mode source
        run_mode local-binary
        ;;
    *)
        echo "usage: scripts/validate-swift-package.sh [source|local-binary|remote-binary|all|all-local]" >&2
        exit 1
        ;;
esac
