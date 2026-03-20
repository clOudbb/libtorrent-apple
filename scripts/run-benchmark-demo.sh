#!/usr/bin/env bash
set -euo pipefail

mode="source"
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

export LIBTORRENT_APPLE_PACKAGE_MODE="${mode}"
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-/tmp/libtorrent-apple-swift-clang-cache}"
swift run --disable-sandbox LibtorrentAppleBenchmarkCLI "$@"
