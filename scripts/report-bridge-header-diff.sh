#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
HEADER_PATH_DEFAULT="NativeBridge/include/libtorrent_apple_bridge.h"

usage() {
    cat >&2 <<'EOF'
usage: scripts/report-bridge-header-diff.sh [options]

options:
  --base <ref-or-path>        Base git ref or local file path (default: HEAD^)
  --head <ref-or-path>        Head git ref or local file path (default: working tree header)
  --header-path <path>        Repository-relative header path (default: NativeBridge/include/libtorrent_apple_bridge.h)
  --fail-on-removals          Exit non-zero when public identifiers are removed
EOF
    exit 1
}

BASE_SPEC="HEAD^"
HEAD_SPEC=""
HEADER_PATH="${HEADER_PATH_DEFAULT}"
FAIL_ON_REMOVALS=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --base)
            BASE_SPEC="${2:-}"
            shift 2
            ;;
        --head)
            HEAD_SPEC="${2:-}"
            shift 2
            ;;
        --header-path)
            HEADER_PATH="${2:-}"
            shift 2
            ;;
        --fail-on-removals)
            FAIL_ON_REMOVALS=1
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "error: unknown argument '$1'" >&2
            usage
            ;;
    esac
done

TMP_DIR="$(mktemp -d "/tmp/libtorrent-apple-bridge-diff.XXXXXX")"
BASE_FILE="${TMP_DIR}/base.h"
HEAD_FILE="${TMP_DIR}/head.h"
BASE_SYMBOLS="${TMP_DIR}/base-symbols.txt"
HEAD_SYMBOLS="${TMP_DIR}/head-symbols.txt"
REMOVED_SYMBOLS="${TMP_DIR}/removed-symbols.txt"
ADDED_SYMBOLS="${TMP_DIR}/added-symbols.txt"

cleanup() {
    rm -rf "${TMP_DIR}"
}

trap cleanup EXIT

materialize_spec() {
    local spec="$1"
    local output_file="$2"

    if [[ -z "${spec}" ]]; then
        cat "${ROOT_DIR}/${HEADER_PATH}" > "${output_file}"
        return
    fi

    if [[ -f "${spec}" ]]; then
        cat "${spec}" > "${output_file}"
        return
    fi

    git -C "${ROOT_DIR}" show "${spec}:${HEADER_PATH}" > "${output_file}"
}

extract_symbols() {
    local input_file="$1"
    local output_file="$2"

    grep -Eo 'libtorrent_apple_[A-Za-z0-9_]+' "${input_file}" | sort -u > "${output_file}" || true
}

materialize_spec "${BASE_SPEC}" "${BASE_FILE}"
materialize_spec "${HEAD_SPEC}" "${HEAD_FILE}"

extract_symbols "${BASE_FILE}" "${BASE_SYMBOLS}"
extract_symbols "${HEAD_FILE}" "${HEAD_SYMBOLS}"

comm -23 "${BASE_SYMBOLS}" "${HEAD_SYMBOLS}" > "${REMOVED_SYMBOLS}"
comm -13 "${BASE_SYMBOLS}" "${HEAD_SYMBOLS}" > "${ADDED_SYMBOLS}"

echo "Bridge header diff for ${HEADER_PATH}:"
diff -u "${BASE_FILE}" "${HEAD_FILE}" || true

echo
echo "Removed public identifiers:"
if [[ -s "${REMOVED_SYMBOLS}" ]]; then
    cat "${REMOVED_SYMBOLS}"
else
    echo "(none)"
fi

echo
echo "Added public identifiers:"
if [[ -s "${ADDED_SYMBOLS}" ]]; then
    cat "${ADDED_SYMBOLS}"
else
    echo "(none)"
fi

if [[ "${FAIL_ON_REMOVALS}" == "1" && -s "${REMOVED_SYMBOLS}" ]]; then
    echo "error: removed public bridge identifiers detected" >&2
    exit 1
fi
