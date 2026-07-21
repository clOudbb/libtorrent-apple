#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
VERSIONS_FILE="${SCRIPT_DIR}/versions.env"
PACKAGE_GENERATION_SCRIPT="${SCRIPT_DIR}/package-generation.sh"
ARTIFACTS_DIR="${ROOT_DIR}/Artifacts/release"
PACKAGE_SUPPORT_DIR="${ROOT_DIR}/PackageSupport"
LIBTORRENT_SOURCE_DIR="${LIBTORRENT_SOURCE_DIR:-${ROOT_DIR}/Vendor/libtorrent}"
OPENSSL_SOURCE_DIR="${OPENSSL_SOURCE_DIR:-${ROOT_DIR}/Vendor/OpenSSL}"
SOURCE_METADATA_FILE="${LIBTORRENT_SOURCE_DIR}/.bootstrap-source"
OPENSSL_SOURCE_METADATA_FILE="${OPENSSL_SOURCE_DIR}/.bootstrap-source"
VERSION_INPUT="${1:-}"

if [[ -z "${VERSION_INPUT}" ]]; then
    echo "usage: scripts/write-release-metadata.sh <version>" >&2
    exit 1
fi

if [[ -f "${VERSIONS_FILE}" ]]; then
    # shellcheck disable=SC1090
    source "${VERSIONS_FILE}"
fi

VERSION="${VERSION_INPUT#v}"
RELEASE_TAG="v${VERSION}"

# shellcheck disable=SC1090
source "${PACKAGE_GENERATION_SCRIPT}"

FRAMEWORK_BASENAME="${FRAMEWORK_BASENAME:-LibtorrentAppleBinary}"
FRAMEWORK_NAME="${FRAMEWORK_NAME:-$(binary_framework_name_for_version "${VERSION}" "${FRAMEWORK_BASENAME}")}"
ARTIFACT_BASENAME="${ARTIFACT_BASENAME:-$(binary_artifact_basename_for_version "${VERSION}" "${FRAMEWORK_BASENAME}")}"
METADATA_PATH="${ARTIFACTS_DIR}/${ARTIFACT_BASENAME}.env"
BINARY_TARGET_SNIPPET_PATH="${ARTIFACTS_DIR}/${ARTIFACT_BASENAME}.binary-target.swift"
RELEASE_NOTES_PATH="${ARTIFACTS_DIR}/${ARTIFACT_BASENAME}.release-notes.md"
PACKAGE_BINARY_ARTIFACT_CONFIG_PATH="${PACKAGE_SUPPORT_DIR}/BinaryArtifact.env"
PACKAGE_MANIFEST_PATH="${ROOT_DIR}/Package.swift"
BRIDGE_COMPAT_TARGET_PATH="${ROOT_DIR}/Sources/LibtorrentAppleBridgeCompat"

if [[ ! -f "${METADATA_PATH}" ]]; then
    echo "error: metadata file not found at ${METADATA_PATH}" >&2
    exit 1
fi

set -a
source "${METADATA_PATH}"
set +a

# Metadata files may contain absolute paths from the environment that created them.
# Rebind all local output paths to the current repository before generating files.
BINARY_TARGET_SNIPPET_PATH="${ARTIFACTS_DIR}/${ARTIFACT_BASENAME}.binary-target.swift"
RELEASE_NOTES_PATH="${ARTIFACTS_DIR}/${ARTIFACT_BASENAME}.release-notes.md"
PACKAGE_BINARY_ARTIFACT_CONFIG_PATH="${PACKAGE_SUPPORT_DIR}/BinaryArtifact.env"
PACKAGE_MANIFEST_PATH="${ROOT_DIR}/Package.swift"
BRIDGE_COMPAT_TARGET_PATH="${ROOT_DIR}/Sources/LibtorrentAppleBridgeCompat"

if [[ -f "${SOURCE_METADATA_FILE}" ]]; then
    # shellcheck disable=SC1090
    source "${SOURCE_METADATA_FILE}"
fi

if [[ -f "${OPENSSL_SOURCE_METADATA_FILE}" ]]; then
    # shellcheck disable=SC1090
    source "${OPENSSL_SOURCE_METADATA_FILE}"
fi

resolve_repo_slug() {
    if [[ -n "${GITHUB_REPOSITORY:-}" ]]; then
        printf '%s\n' "${GITHUB_REPOSITORY}"
        return
    fi

    local origin_url
    origin_url="$(git -C "${ROOT_DIR}" config --get remote.origin.url 2>/dev/null || true)"

    if [[ "${origin_url}" =~ github\.com[:/]([^/]+/[^/.]+)(\.git)?$ ]]; then
        printf '%s\n' "${BASH_REMATCH[1]}"
        return
    fi

    printf '%s\n' ""
}

REPOSITORY_SLUG="$(resolve_repo_slug)"
LIBTORRENT_WEB_URL="${LIBTORRENT_REPO_URL%.git}"
OPENSSL_WEB_URL="${OPENSSL_REPO_URL%.git}"

if [[ -n "${BINARY_ARTIFACT_BASE_URL:-}" ]]; then
    DOWNLOAD_URL="${BINARY_ARTIFACT_BASE_URL%/}/releases/download/${RELEASE_TAG}/${ARTIFACT_BASENAME}.zip"
elif [[ -n "${REPOSITORY_SLUG}" ]]; then
    DOWNLOAD_URL="https://github.com/${REPOSITORY_SLUG}/releases/download/${RELEASE_TAG}/${ARTIFACT_BASENAME}.zip"
else
    DOWNLOAD_URL="<replace-with-your-github-release-url>"
fi

mkdir -p "${PACKAGE_SUPPORT_DIR}"
write_bridge_compat_target "${BRIDGE_COMPAT_TARGET_PATH}" "${FRAMEWORK_NAME}"
write_release_package_manifest "${PACKAGE_MANIFEST_PATH}" "${FRAMEWORK_NAME}" "${DOWNLOAD_URL}" "${CHECKSUM}"

cat > "${PACKAGE_BINARY_ARTIFACT_CONFIG_PATH}" <<EOF
# Managed by scripts/write-release-metadata.sh.
# Internal release metadata for maintainers.
# The public SwiftPM package is described directly in Package.swift.
# Maintainers can validate internal source/local-binary flows with:
#   ./scripts/validate-dev-package.sh source
#   ./scripts/validate-dev-package.sh local-binary

BINARY_FRAMEWORK_NAME=${FRAMEWORK_NAME}
BINARY_ARTIFACT_VERSION=${VERSION}
BINARY_ARTIFACT_URL=${DOWNLOAD_URL}
BINARY_ARTIFACT_CHECKSUM=${CHECKSUM}
EOF

cat > "${BINARY_TARGET_SNIPPET_PATH}" <<EOF
.binaryTarget(
    name: "${FRAMEWORK_NAME}",
    url: "${DOWNLOAD_URL}",
    checksum: "${CHECKSUM}"
)
EOF

cat > "${RELEASE_NOTES_PATH}" <<EOF
## Build Provenance

- libtorrent: [${LIBTORRENT_REF_RESOLVED}](${LIBTORRENT_WEB_URL}/tree/${LIBTORRENT_REF_RESOLVED}) ([\`${LIBTORRENT_COMMIT_SHA:0:7}\`](${LIBTORRENT_WEB_URL}/commit/${LIBTORRENT_COMMIT_SHA})), WebTorrent disabled
- OpenSSL: [${OPENSSL_REF_RESOLVED}](${OPENSSL_WEB_URL}/tree/${OPENSSL_REF_RESOLVED}) ([\`${OPENSSL_COMMIT_SHA:0:7}\`](${OPENSSL_WEB_URL}/commit/${OPENSSL_COMMIT_SHA}))
- Boost headers: [${BOOST_VERSION}](${BOOST_SOURCE_URL})
EOF

cat >> "${METADATA_PATH}" <<EOF
REPOSITORY_SLUG=${REPOSITORY_SLUG:-unknown}
DOWNLOAD_URL=${DOWNLOAD_URL}
BINARY_TARGET_SNIPPET_PATH=${BINARY_TARGET_SNIPPET_PATH}
RELEASE_NOTES_PATH=${RELEASE_NOTES_PATH}
PACKAGE_BINARY_ARTIFACT_CONFIG_PATH=${PACKAGE_BINARY_ARTIFACT_CONFIG_PATH}
PACKAGE_MANIFEST_PATH=${PACKAGE_MANIFEST_PATH}
BRIDGE_COMPAT_TARGET_PATH=${BRIDGE_COMPAT_TARGET_PATH}
EOF

echo "Wrote ${BINARY_TARGET_SNIPPET_PATH}"
echo "Wrote ${RELEASE_NOTES_PATH}"
echo "Wrote ${PACKAGE_BINARY_ARTIFACT_CONFIG_PATH}"
echo "Wrote ${PACKAGE_MANIFEST_PATH}"
echo "Wrote ${BRIDGE_COMPAT_TARGET_PATH}"
