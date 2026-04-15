#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

mode="local-binary"
if [[ $# -gt 0 && "${1}" != --* ]]; then
  mode="$1"
  shift
fi

case "${mode}" in
  source|local-binary|remote-binary)
    ;;
  *)
    echo "Unsupported package mode: ${mode}" >&2
    echo "Usage: $0 [source|local-binary|remote-binary] [benchmark-cli-options...]" >&2
    exit 2
    ;;
esac

export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-/tmp/libtorrent-apple-swift-clang-cache}"
export LIBTORRENT_APPLE_PACKAGE_MODE="${mode}"

case "${mode}" in
  source|local-binary)
    package_path="$("${SCRIPT_DIR}/prepare-dev-package.sh" "${mode}")"
    ;;
  remote-binary)
    package_path="${ROOT_DIR}"
    ;;
esac

swift run --disable-sandbox --package-path "${package_path}" LibtorrentAppleBenchmarkCLI "$@"
