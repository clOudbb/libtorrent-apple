#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
VERSIONS_FILE="${SCRIPT_DIR}/versions.env"
VERSION_INPUT="${1:-}"

if [[ -f "${VERSIONS_FILE}" ]]; then
    # shellcheck disable=SC1090
    source "${VERSIONS_FILE}"
fi

if [[ -z "${VERSION_INPUT}" ]]; then
    echo "usage: scripts/release.sh <version>" >&2
    exit 1
fi

if [[ ! "${VERSION_INPUT}" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]]; then
    echo "error: version must look like 0.1.0 or v0.1.0" >&2
    exit 1
fi

VERSION="${VERSION_INPUT#v}"
RELEASE_TAG="v${VERSION}"
FRAMEWORK_NAME="${FRAMEWORK_NAME:-LibtorrentAppleBinary}"

"${SCRIPT_DIR}/validate-swift-package.sh" source
"${SCRIPT_DIR}/sync-libtorrent.sh"
"${SCRIPT_DIR}/build-apple-libs.sh"
"${SCRIPT_DIR}/smoke-test-macos-framework.sh"
"${SCRIPT_DIR}/make-xcframework.sh" "${VERSION}"
"${SCRIPT_DIR}/write-release-metadata.sh" "${VERSION}"
"${SCRIPT_DIR}/validate-swift-package.sh" local-binary

METADATA_PATH="${ROOT_DIR}/Artifacts/release/${FRAMEWORK_NAME}-${VERSION}.env"

if [[ ! -f "${METADATA_PATH}" ]]; then
    echo "error: artifact metadata not found at ${METADATA_PATH}" >&2
    exit 1
fi

set -a
source "${METADATA_PATH}"
set +a

if ! command -v gh >/dev/null 2>&1; then
    echo "gh CLI is not installed. Skipping GitHub Release upload."
    echo "Artifact: ${ZIP_PATH}"
    echo "Checksum: ${CHECKSUM}"
    echo "Binary target snippet: ${BINARY_TARGET_SNIPPET_PATH}"
    echo "Upstream libtorrent: ${LIBTORRENT_REF_RESOLVED:-unknown} (${LIBTORRENT_REPO_URL:-unknown})"
    exit 0
fi

if [[ -n "${GITHUB_TOKEN:-}" && -z "${GH_TOKEN:-}" ]]; then
    export GH_TOKEN="${GITHUB_TOKEN}"
fi

if [[ -z "${GH_TOKEN:-}" ]]; then
    echo "GH_TOKEN or GITHUB_TOKEN is not set. Skipping GitHub Release upload."
    echo "Artifact: ${ZIP_PATH}"
    echo "Checksum: ${CHECKSUM}"
    echo "Binary target snippet: ${BINARY_TARGET_SNIPPET_PATH}"
    echo "Upstream libtorrent: ${LIBTORRENT_REF_RESOLVED:-unknown} (${LIBTORRENT_REPO_URL:-unknown})"
    exit 0
fi

if gh release view "${RELEASE_TAG}" >/dev/null 2>&1; then
    gh release edit "${RELEASE_TAG}" --notes-file "${RELEASE_NOTES_PATH}"
    gh release upload \
        "${RELEASE_TAG}" \
        "${ZIP_PATH}" \
        "${METADATA_PATH}" \
        "${BINARY_TARGET_SNIPPET_PATH}" \
        "${RELEASE_NOTES_PATH}" \
        --clobber
else
    gh release create \
        "${RELEASE_TAG}" \
        "${ZIP_PATH}" \
        "${METADATA_PATH}" \
        "${BINARY_TARGET_SNIPPET_PATH}" \
        "${RELEASE_NOTES_PATH}" \
        --title "${RELEASE_TAG}" \
        --notes-file "${RELEASE_NOTES_PATH}"
fi

echo "Published ${RELEASE_TAG}"
echo "Artifact: ${ZIP_PATH}"
echo "Checksum: ${CHECKSUM}"
echo "Binary target snippet: ${BINARY_TARGET_SNIPPET_PATH}"
echo "Upstream libtorrent: ${LIBTORRENT_REF_RESOLVED:-unknown} (${LIBTORRENT_REPO_URL:-unknown})"
