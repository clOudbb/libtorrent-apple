#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
VENDOR_DIR="${VENDOR_DIR:-${ROOT_DIR}/Vendor}"
SOURCE_DIR="${OPENSSL_SOURCE_DIR:-${VENDOR_DIR}/OpenSSL}"
VERSIONS_FILE="${SCRIPT_DIR}/versions.env"

if [[ -f "${VERSIONS_FILE}" ]]; then
    # shellcheck disable=SC1090
    source "${VERSIONS_FILE}"
fi

resolve_openssl_ref() {
    local requested_ref="$1"

    if [[ "${requested_ref}" != "latest" ]]; then
        printf '%s\n' "${requested_ref}"
        return
    fi

    git ls-remote --tags --refs "${OPENSSL_REPO_URL}" \
        | awk -F'/' '{print $NF}' \
        | grep -E '^v?[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$' \
        | sort -V \
        | tail -n 1
}

RESOLVED_OPENSSL_REF="$(resolve_openssl_ref "${OPENSSL_REF}")"

if [[ -z "${RESOLVED_OPENSSL_REF}" ]]; then
    echo "error: failed to resolve OpenSSL ref from ${OPENSSL_REPO_URL} for request '${OPENSSL_REF}'" >&2
    exit 1
fi

mkdir -p "${VENDOR_DIR}"

if [[ ! -d "${SOURCE_DIR}/.git" ]]; then
    git clone \
        --depth 1 \
        --branch "${RESOLVED_OPENSSL_REF}" \
        "${OPENSSL_REPO_URL}" \
        "${SOURCE_DIR}"
else
    git -C "${SOURCE_DIR}" remote set-url origin "${OPENSSL_REPO_URL}"
    git -C "${SOURCE_DIR}" fetch --tags --force origin "${RESOLVED_OPENSSL_REF}"
    git -C "${SOURCE_DIR}" checkout --force FETCH_HEAD
fi

OPENSSL_COMMIT_SHA="$(git -C "${SOURCE_DIR}" rev-parse HEAD)"

printf 'OPENSSL_REPO_URL=%s\nOPENSSL_REF_REQUESTED=%s\nOPENSSL_REF_RESOLVED=%s\nOPENSSL_COMMIT_SHA=%s\n' \
    "${OPENSSL_REPO_URL}" \
    "${OPENSSL_REF}" \
    "${RESOLVED_OPENSSL_REF}" \
    "${OPENSSL_COMMIT_SHA}" > "${SOURCE_DIR}/.bootstrap-source"

echo "Synced OpenSSL source to ${SOURCE_DIR} at ${RESOLVED_OPENSSL_REF} (${OPENSSL_COMMIT_SHA})"
