#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
MODE="${1:-}"
DEV_ROOT="${ROOT_DIR}/.build/dev-package"
TEMPLATE_PATH="${ROOT_DIR}/PackageSupport/Package.dev-template.swift"
CONFIG_PATH="${ROOT_DIR}/PackageSupport/BinaryArtifact.env"
VERSIONS_FILE="${SCRIPT_DIR}/versions.env"
PACKAGE_GENERATION_SCRIPT="${SCRIPT_DIR}/package-generation.sh"

if [[ -f "${VERSIONS_FILE}" ]]; then
    # shellcheck disable=SC1090
    source "${VERSIONS_FILE}"
fi

# shellcheck disable=SC1090
source "${PACKAGE_GENERATION_SCRIPT}"

usage() {
    echo "usage: scripts/prepare-dev-package.sh <source|local-binary>" >&2
    exit 1
}

case "${MODE}" in
    source|local-binary)
        ;;
    *)
        usage
        ;;
esac

if [[ ! -f "${TEMPLATE_PATH}" ]]; then
    echo "error: missing dev package template at ${TEMPLATE_PATH}" >&2
    exit 1
fi

PREPARED_FRAMEWORK_NAME=""
if [[ -f "${CONFIG_PATH}" ]]; then
    while IFS='=' read -r raw_key raw_value; do
        key="$(echo "${raw_key}" | tr -d '[:space:]')"
        value="$(echo "${raw_value}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

        case "${key}" in
            BINARY_FRAMEWORK_NAME)
                PREPARED_FRAMEWORK_NAME="${value}"
                ;;
        esac
    done < "${CONFIG_PATH}"
fi

EXPLICIT_FRAMEWORK_NAME="${FRAMEWORK_NAME:-}"
DEFAULT_FRAMEWORK_NAME="${FRAMEWORK_BASENAME:-LibtorrentAppleBinary}"
PREPARED_FRAMEWORK_PATH="${ROOT_DIR}/Artifacts/release/${PREPARED_FRAMEWORK_NAME}.xcframework"
DEFAULT_FRAMEWORK_PATH="${ROOT_DIR}/Artifacts/release/${DEFAULT_FRAMEWORK_NAME}.xcframework"

if [[ -n "${EXPLICIT_FRAMEWORK_NAME}" ]]; then
    FRAMEWORK_NAME="${EXPLICIT_FRAMEWORK_NAME}"
elif [[ -n "${PREPARED_FRAMEWORK_NAME}" && -d "${PREPARED_FRAMEWORK_PATH}" ]]; then
    FRAMEWORK_NAME="${PREPARED_FRAMEWORK_NAME}"
elif [[ -d "${DEFAULT_FRAMEWORK_PATH}" ]]; then
    FRAMEWORK_NAME="${DEFAULT_FRAMEWORK_NAME}"
else
    FRAMEWORK_NAME="${DEFAULT_FRAMEWORK_NAME}"
fi

PACKAGE_DIR="${DEV_ROOT}/${MODE}"
rm -rf "${PACKAGE_DIR}"
mkdir -p "${PACKAGE_DIR}/Sources"

ln -sfn "${ROOT_DIR}/Sources/LibtorrentApple" "${PACKAGE_DIR}/Sources/LibtorrentApple"
ln -sfn "${ROOT_DIR}/Sources/LibtorrentAppleBenchmarkCLI" "${PACKAGE_DIR}/Sources/LibtorrentAppleBenchmarkCLI"
ln -sfn "${ROOT_DIR}/Tests" "${PACKAGE_DIR}/Tests"
ln -sfn "${ROOT_DIR}/Artifacts" "${PACKAGE_DIR}/Artifacts"
ln -sfn "${ROOT_DIR}/PackageSupport" "${PACKAGE_DIR}/PackageSupport"

case "${MODE}" in
    source)
        ln -sfn "${ROOT_DIR}/Sources/LibtorrentAppleBridge" "${PACKAGE_DIR}/Sources/LibtorrentAppleBridge"
        ;;
    local-binary)
        write_bridge_compat_target "${PACKAGE_DIR}/Sources/LibtorrentAppleBridgeCompat" "${FRAMEWORK_NAME}"
        ;;
esac

sed \
    -e "s/__PACKAGE_MODE__/${MODE}/g" \
    -e "s/__FRAMEWORK_NAME__/${FRAMEWORK_NAME}/g" \
    "${TEMPLATE_PATH}" > "${PACKAGE_DIR}/Package.swift"

echo "${PACKAGE_DIR}"
