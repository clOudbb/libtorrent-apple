#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
MODE="${1:-source}"
CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-/tmp/libtorrent-apple-swift-clang-cache}"

case "${MODE}" in
    source|local-binary|remote-binary)
        ;;
    *)
        echo "usage: scripts/validate-swift-package.sh [source|local-binary|remote-binary]" >&2
        exit 1
        ;;
esac

export LIBTORRENT_APPLE_PACKAGE_MODE="${MODE}"
export CLANG_MODULE_CACHE_PATH

swift build --package-path "${ROOT_DIR}"
swift test --package-path "${ROOT_DIR}" --disable-xctest

echo "Swift package validation passed in ${MODE} mode."
