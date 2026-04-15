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

"${SCRIPT_DIR}/validate-dev-package.sh" source
"${SCRIPT_DIR}/sync-libtorrent.sh"
"${SCRIPT_DIR}/sync-openssl.sh"
"${SCRIPT_DIR}/build-apple-libs.sh"
"${SCRIPT_DIR}/smoke-test-macos-framework.sh"
"${SCRIPT_DIR}/make-xcframework.sh" "${VERSION}"
"${SCRIPT_DIR}/write-release-metadata.sh" "${VERSION}"
"${SCRIPT_DIR}/validate-dev-package.sh" local-binary

METADATA_PATH="${ROOT_DIR}/Artifacts/release/${FRAMEWORK_NAME}-${VERSION}.env"

if [[ ! -f "${METADATA_PATH}" ]]; then
    echo "error: artifact metadata not found at ${METADATA_PATH}" >&2
    exit 1
fi

set -a
source "${METADATA_PATH}"
set +a

echo "Prepared ${RELEASE_TAG}"
echo "Artifact: ${ZIP_PATH}"
echo "Checksum: ${CHECKSUM}"
echo "Binary target snippet: ${BINARY_TARGET_SNIPPET_PATH}"
echo "Upstream libtorrent: ${LIBTORRENT_REF_RESOLVED:-unknown} (${LIBTORRENT_REPO_URL:-unknown})"
echo "Upstream OpenSSL: ${OPENSSL_REF_RESOLVED:-unknown} (${OPENSSL_REPO_URL:-unknown})"
echo "Next: commit PackageSupport/BinaryArtifact.env, create/push ${RELEASE_TAG}, then publish assets manually or via scripts/publish-github-release.sh ${VERSION}."
