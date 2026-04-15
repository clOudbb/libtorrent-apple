#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
MODE="${1:-}"
DEV_ROOT="${ROOT_DIR}/.build/dev-package"
TEMPLATE_PATH="${ROOT_DIR}/PackageSupport/Package.dev-template.swift"
CONFIG_PATH="${ROOT_DIR}/PackageSupport/BinaryArtifact.env"
VERSIONS_FILE="${SCRIPT_DIR}/versions.env"

if [[ -f "${VERSIONS_FILE}" ]]; then
    # shellcheck disable=SC1090
    source "${VERSIONS_FILE}"
fi

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

FRAMEWORK_NAME="${FRAMEWORK_NAME:-LibtorrentAppleBinary}"
if [[ -f "${CONFIG_PATH}" ]]; then
    while IFS='=' read -r raw_key raw_value; do
        key="$(echo "${raw_key}" | tr -d '[:space:]')"
        value="$(echo "${raw_value}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
        if [[ "${key}" == "BINARY_FRAMEWORK_NAME" && -n "${value}" ]]; then
            FRAMEWORK_NAME="${value}"
            break
        fi
    done < "${CONFIG_PATH}"
fi

PACKAGE_DIR="${DEV_ROOT}/${MODE}"
mkdir -p "${PACKAGE_DIR}"

ln -sfn "${ROOT_DIR}/Sources" "${PACKAGE_DIR}/Sources"
ln -sfn "${ROOT_DIR}/Tests" "${PACKAGE_DIR}/Tests"
ln -sfn "${ROOT_DIR}/Artifacts" "${PACKAGE_DIR}/Artifacts"
ln -sfn "${ROOT_DIR}/PackageSupport" "${PACKAGE_DIR}/PackageSupport"

sed \
    -e "s/__PACKAGE_MODE__/${MODE}/g" \
    -e "s/__FRAMEWORK_NAME__/${FRAMEWORK_NAME}/g" \
    "${TEMPLATE_PATH}" > "${PACKAGE_DIR}/Package.swift"

echo "${PACKAGE_DIR}"
