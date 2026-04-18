#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
VERSIONS_FILE="${SCRIPT_DIR}/versions.env"

if [[ -f "${VERSIONS_FILE}" ]]; then
    # shellcheck disable=SC1090
    source "${VERSIONS_FILE}"
fi

FRAMEWORK_NAME="${FRAMEWORK_NAME:-${FRAMEWORK_BASENAME:-LibtorrentAppleBinary}}"
FRAMEWORK_DIR="${FRAMEWORK_DIR:-${ROOT_DIR}/Build/apple/macosx/${FRAMEWORK_NAME}.framework}"
FRAMEWORK_BINARY_PATH="${FRAMEWORK_DIR}/${FRAMEWORK_NAME}"

if [[ ! -d "${FRAMEWORK_DIR}" ]]; then
    echo "error: framework not found at ${FRAMEWORK_DIR}. Run scripts/build-apple-libs.sh first." >&2
    exit 1
fi

if [[ ! -f "${FRAMEWORK_BINARY_PATH}" ]]; then
    echo "error: framework binary not found at ${FRAMEWORK_BINARY_PATH}" >&2
    exit 1
fi

FRAMEWORK_ARCHS="$(xcrun lipo -archs "${FRAMEWORK_BINARY_PATH}")"
HOST_ARCH="$(uname -m)"
TEST_ARCH="${HOST_ARCH}"

if ! printf '%s\n' "${FRAMEWORK_ARCHS}" | tr ' ' '\n' | grep -qx "${HOST_ARCH}"; then
    TEST_ARCH="${FRAMEWORK_ARCHS%% *}"
fi

tmpdir="$(mktemp -d /tmp/libtorrent-apple-smoke.XXXXXX)"
trap 'rm -rf "${tmpdir}"' EXIT

cat > "${tmpdir}/smoke.cpp" <<EOF
#include <${FRAMEWORK_NAME}/LibtorrentAppleBinary.h>
#include <stdio.h>

int main(void) {
    libtorrent_apple_session_configuration_t configuration = libtorrent_apple_session_configuration_default();
    configuration.enable_dht = false;
    configuration.enable_lsd = false;
    configuration.enable_upnp = false;
    configuration.enable_natpmp = false;

    if (!libtorrent_apple_bridge_is_available()) {
        fprintf(stderr, "bridge unavailable\n");
        return 1;
    }

    libtorrent_apple_session_t *session = NULL;
    libtorrent_apple_error_t error = {0};
    if (!libtorrent_apple_session_create(&configuration, &session, &error)) {
        fprintf(stderr, "session create failed: %d %s\n", error.code, error.message);
        return 2;
    }

    printf("libtorrent version: %s\n", libtorrent_apple_bridge_version());
    libtorrent_apple_session_destroy(session);
    return 0;
}
EOF

clang++ \
    -arch "${TEST_ARCH}" \
    "${tmpdir}/smoke.cpp" \
    -o "${tmpdir}/smoke" \
    -F"$(dirname "${FRAMEWORK_DIR}")" \
    -framework "${FRAMEWORK_NAME}" \
    -framework CFNetwork \
    -framework CoreFoundation \
    -framework Security \
    -framework SystemConfiguration \
    -I"${FRAMEWORK_DIR}/Headers"

if [[ "${TEST_ARCH}" == "${HOST_ARCH}" ]]; then
    "${tmpdir}/smoke"
else
    arch "-${TEST_ARCH}" "${tmpdir}/smoke"
fi

echo "macOS framework smoke test passed for ${FRAMEWORK_DIR}"
