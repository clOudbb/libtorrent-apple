#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
MODE="${1:-remote-binary}"
CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-/tmp/libtorrent-apple-swift-clang-cache}"

if [[ "${MODE}" != "remote-binary" ]]; then
    echo "usage: scripts/validate-swift-package.sh [remote-binary]" >&2
    echo "For internal source/local-binary validation use scripts/validate-dev-package.sh." >&2
    exit 1
fi

export CLANG_MODULE_CACHE_PATH
export LIBTORRENT_APPLE_PACKAGE_MODE="remote-binary"

swift build --package-path "${ROOT_DIR}"
swift test --package-path "${ROOT_DIR}" --disable-xctest
echo "Swift package validation passed in remote-binary mode."
