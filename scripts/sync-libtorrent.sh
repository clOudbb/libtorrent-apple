#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
VENDOR_DIR="${ROOT_DIR}/Vendor"
SOURCE_DIR="${VENDOR_DIR}/libtorrent"
VERSIONS_FILE="${SCRIPT_DIR}/versions.env"

if [[ -f "${VERSIONS_FILE}" ]]; then
    # shellcheck disable=SC1090
    source "${VERSIONS_FILE}"
fi

resolve_libtorrent_ref() {
    local requested_ref="$1"

    if [[ "${requested_ref}" != "latest" ]]; then
        printf '%s\n' "${requested_ref}"
        return
    fi

    git ls-remote --tags --refs "${LIBTORRENT_REPO_URL}" \
        | awk -F'/' '{print $NF}' \
        | grep -E '^v?[0-9]+\.[0-9]+\.[0-9]+$' \
        | sort -V \
        | tail -n 1
}

RESOLVED_LIBTORRENT_REF="$(resolve_libtorrent_ref "${LIBTORRENT_REF}")"

if [[ -z "${RESOLVED_LIBTORRENT_REF}" ]]; then
    echo "error: failed to resolve libtorrent ref from ${LIBTORRENT_REPO_URL} for request '${LIBTORRENT_REF}'" >&2
    exit 1
fi

mkdir -p "${VENDOR_DIR}"

update_submodules() {
    local repository_dir="$1"

    git -C "${repository_dir}" submodule sync --recursive

    if git -C "${repository_dir}" submodule update --init --recursive --depth 1; then
        return
    fi

    echo "warning: shallow submodule update failed, retrying with full history" >&2
    git -C "${repository_dir}" submodule update --init --recursive
}

if [[ ! -d "${SOURCE_DIR}/.git" ]]; then
    git clone \
        --depth 1 \
        --branch "${RESOLVED_LIBTORRENT_REF}" \
        --recurse-submodules \
        --shallow-submodules \
        "${LIBTORRENT_REPO_URL}" \
        "${SOURCE_DIR}"
    update_submodules "${SOURCE_DIR}"
else
    git -C "${SOURCE_DIR}" remote set-url origin "${LIBTORRENT_REPO_URL}"
    git -C "${SOURCE_DIR}" fetch --tags --force origin "${RESOLVED_LIBTORRENT_REF}"
    git -C "${SOURCE_DIR}" checkout --force FETCH_HEAD
    update_submodules "${SOURCE_DIR}"
fi

LIBTORRENT_COMMIT_SHA="$(git -C "${SOURCE_DIR}" rev-parse HEAD)"

printf 'LIBTORRENT_REPO_URL=%s\nLIBTORRENT_REF_REQUESTED=%s\nLIBTORRENT_REF_RESOLVED=%s\nLIBTORRENT_COMMIT_SHA=%s\n' \
    "${LIBTORRENT_REPO_URL}" \
    "${LIBTORRENT_REF}" \
    "${RESOLVED_LIBTORRENT_REF}" \
    "${LIBTORRENT_COMMIT_SHA}" > "${SOURCE_DIR}/.bootstrap-source"

echo "Synced libtorrent source to ${SOURCE_DIR} at ${RESOLVED_LIBTORRENT_REF} (${LIBTORRENT_COMMIT_SHA})"
