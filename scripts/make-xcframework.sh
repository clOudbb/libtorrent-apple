#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
BUILD_DIR="${ROOT_DIR}/Build/apple"
ARTIFACTS_DIR="${ROOT_DIR}/Artifacts/release"
VERSION="${1:-dev}"
SOURCE_METADATA_FILE="${ROOT_DIR}/Vendor/libtorrent/.bootstrap-source"
VERSIONS_FILE="${SCRIPT_DIR}/versions.env"

if [[ -f "${VERSIONS_FILE}" ]]; then
    # shellcheck disable=SC1090
    source "${VERSIONS_FILE}"
fi

FRAMEWORK_NAME="${FRAMEWORK_NAME:-LibtorrentApple}"

DEVICE_FRAMEWORK="${BUILD_DIR}/iphoneos/${FRAMEWORK_NAME}.framework"
SIMULATOR_FRAMEWORK="${BUILD_DIR}/iphonesimulator/${FRAMEWORK_NAME}.framework"
MACOS_FRAMEWORK="${BUILD_DIR}/macosx/${FRAMEWORK_NAME}.framework"
XCFRAMEWORK_PATH="${ARTIFACTS_DIR}/${FRAMEWORK_NAME}.xcframework"
ZIP_PATH="${ARTIFACTS_DIR}/${FRAMEWORK_NAME}-${VERSION}.zip"
METADATA_PATH="${ARTIFACTS_DIR}/${FRAMEWORK_NAME}-${VERSION}.env"

for framework in "${DEVICE_FRAMEWORK}" "${SIMULATOR_FRAMEWORK}" "${MACOS_FRAMEWORK}"; do
    if [[ ! -d "${framework}" ]]; then
        echo "error: missing framework slice ${framework}" >&2
        echo "Run scripts/build-apple-libs.sh after wiring the actual native framework build outputs." >&2
        exit 1
    fi
done

mkdir -p "${ARTIFACTS_DIR}"
rm -rf "${XCFRAMEWORK_PATH}" "${ZIP_PATH}" "${METADATA_PATH}"

xcodebuild -create-xcframework \
    -framework "${DEVICE_FRAMEWORK}" \
    -framework "${SIMULATOR_FRAMEWORK}" \
    -framework "${MACOS_FRAMEWORK}" \
    -output "${XCFRAMEWORK_PATH}"

(
    cd "${ARTIFACTS_DIR}"
    zip -qry "$(basename "${ZIP_PATH}")" "$(basename "${XCFRAMEWORK_PATH}")"
)

CHECKSUM="$(swift package compute-checksum "${ZIP_PATH}")"

if [[ -f "${SOURCE_METADATA_FILE}" ]]; then
    # shellcheck disable=SC1090
    source "${SOURCE_METADATA_FILE}"
fi

cat > "${METADATA_PATH}" <<EOF
FRAMEWORK_NAME=${FRAMEWORK_NAME}
VERSION=${VERSION}
XCFRAMEWORK_PATH=${XCFRAMEWORK_PATH}
ZIP_PATH=${ZIP_PATH}
CHECKSUM=${CHECKSUM}
LIBTORRENT_REPO_URL=${LIBTORRENT_REPO_URL:-unknown}
LIBTORRENT_REF_REQUESTED=${LIBTORRENT_REF_REQUESTED:-unknown}
LIBTORRENT_REF_RESOLVED=${LIBTORRENT_REF_RESOLVED:-unknown}
LIBTORRENT_COMMIT_SHA=${LIBTORRENT_COMMIT_SHA:-unknown}
REQUIRED_SYSTEM_FRAMEWORKS=CFNetwork,CoreFoundation,Security,SystemConfiguration
REQUIRED_LINK_LIBRARIES=libc++
EOF

echo "Created ${ZIP_PATH}"
echo "SwiftPM checksum: ${CHECKSUM}"
