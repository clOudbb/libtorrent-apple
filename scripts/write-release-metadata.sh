#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
VERSIONS_FILE="${SCRIPT_DIR}/versions.env"
ARTIFACTS_DIR="${ROOT_DIR}/Artifacts/release"
PACKAGE_SUPPORT_DIR="${ROOT_DIR}/PackageSupport"
SOURCE_METADATA_FILE="${ROOT_DIR}/Vendor/libtorrent/.bootstrap-source"
VERSION_INPUT="${1:-}"

if [[ -z "${VERSION_INPUT}" ]]; then
    echo "usage: scripts/write-release-metadata.sh <version>" >&2
    exit 1
fi

if [[ -f "${VERSIONS_FILE}" ]]; then
    # shellcheck disable=SC1090
    source "${VERSIONS_FILE}"
fi

FRAMEWORK_NAME="${FRAMEWORK_NAME:-LibtorrentApple}"
VERSION="${VERSION_INPUT#v}"
RELEASE_TAG="v${VERSION}"
METADATA_PATH="${ARTIFACTS_DIR}/${FRAMEWORK_NAME}-${VERSION}.env"
BINARY_TARGET_SNIPPET_PATH="${ARTIFACTS_DIR}/${FRAMEWORK_NAME}-${VERSION}.binary-target.swift"
RELEASE_NOTES_PATH="${ARTIFACTS_DIR}/${FRAMEWORK_NAME}-${VERSION}.release-notes.md"
PACKAGE_BINARY_ARTIFACT_CONFIG_PATH="${PACKAGE_SUPPORT_DIR}/BinaryArtifact.env"

if [[ ! -f "${METADATA_PATH}" ]]; then
    echo "error: metadata file not found at ${METADATA_PATH}" >&2
    exit 1
fi

set -a
source "${METADATA_PATH}"
set +a

if [[ -f "${SOURCE_METADATA_FILE}" ]]; then
    # shellcheck disable=SC1090
    source "${SOURCE_METADATA_FILE}"
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

if [[ -n "${REPOSITORY_SLUG}" ]]; then
    DOWNLOAD_URL="https://github.com/${REPOSITORY_SLUG}/releases/download/${RELEASE_TAG}/${FRAMEWORK_NAME}-${VERSION}.zip"
else
    DOWNLOAD_URL="<replace-with-your-github-release-url>"
fi

mkdir -p "${PACKAGE_SUPPORT_DIR}"

cat > "${PACKAGE_BINARY_ARTIFACT_CONFIG_PATH}" <<EOF
# Managed by scripts/write-release-metadata.sh.
# For local development:
#   LIBTORRENT_APPLE_PACKAGE_MODE=source swift build
#   LIBTORRENT_APPLE_PACKAGE_MODE=local-binary swift build

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
# ${RELEASE_TAG}

## Artifact

- XCFramework zip: ${FRAMEWORK_NAME}-${VERSION}.zip
- SwiftPM checksum: \`${CHECKSUM}\`

## Upstream Source

- libtorrent repo: ${LIBTORRENT_REPO_URL:-unknown}
- requested ref: ${LIBTORRENT_REF_REQUESTED:-unknown}
- resolved ref: ${LIBTORRENT_REF_RESOLVED:-unknown}
- commit: ${LIBTORRENT_COMMIT_SHA:-unknown}

## Consumer Notes

- SwiftPM product exposed to apps: \`LibtorrentApple\`
- Internal binary target used by the package: \`${FRAMEWORK_NAME}\`
- Required Apple system frameworks: ${REQUIRED_SYSTEM_FRAMEWORKS:-CFNetwork,CoreFoundation,Security,SystemConfiguration}
- Required link libraries when integrating the raw framework manually: ${REQUIRED_LINK_LIBRARIES:-libc++}
- Binary target snippet is attached as \`${FRAMEWORK_NAME}-${VERSION}.binary-target.swift\`
- Package binary config updated at \`PackageSupport/BinaryArtifact.env\`

## SwiftPM Snippet

\`\`\`swift
$(cat "${BINARY_TARGET_SNIPPET_PATH}")
\`\`\`
EOF

cat >> "${METADATA_PATH}" <<EOF
REPOSITORY_SLUG=${REPOSITORY_SLUG:-unknown}
DOWNLOAD_URL=${DOWNLOAD_URL}
BINARY_TARGET_SNIPPET_PATH=${BINARY_TARGET_SNIPPET_PATH}
RELEASE_NOTES_PATH=${RELEASE_NOTES_PATH}
PACKAGE_BINARY_ARTIFACT_CONFIG_PATH=${PACKAGE_BINARY_ARTIFACT_CONFIG_PATH}
EOF

echo "Wrote ${BINARY_TARGET_SNIPPET_PATH}"
echo "Wrote ${RELEASE_NOTES_PATH}"
echo "Wrote ${PACKAGE_BINARY_ARTIFACT_CONFIG_PATH}"
