#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

usage() {
    cat >&2 <<'EOF'
usage: scripts/self-verify-version-switch.sh --version-a <version> --version-b <version> [options]

options:
  --source-repo <path>    Source repository to copy for validation (default: current repo)
  --work-root <path>      Persistent working directory (default: temporary directory)
  --keep-workdir          Keep the generated working directory on success
EOF
    exit 1
}

require_command() {
    local command_name="$1"
    if ! command -v "${command_name}" >/dev/null 2>&1; then
        echo "error: required command '${command_name}' was not found" >&2
        exit 1
    fi
}

find_free_port() {
    python3 - <<'PY'
import socket

with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
    sock.bind(("127.0.0.1", 0))
    print(sock.getsockname()[1])
PY
}

VERSION_A=""
VERSION_B=""
SOURCE_REPO="${ROOT_DIR}"
WORK_ROOT=""
KEEP_WORKDIR=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version-a)
            VERSION_A="${2:-}"
            shift 2
            ;;
        --version-b)
            VERSION_B="${2:-}"
            shift 2
            ;;
        --source-repo)
            SOURCE_REPO="${2:-}"
            shift 2
            ;;
        --work-root)
            WORK_ROOT="${2:-}"
            shift 2
            ;;
        --keep-workdir)
            KEEP_WORKDIR=1
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "error: unknown argument '$1'" >&2
            usage
            ;;
    esac
done

if [[ -z "${VERSION_A}" || -z "${VERSION_B}" ]]; then
    usage
fi

require_command git
require_command python3
require_command rsync
require_command ditto

CURRENT_PREPARED_VERSION=""
if [[ -f "${SOURCE_REPO}/PackageSupport/BinaryArtifact.env" ]]; then
    while IFS='=' read -r raw_key raw_value; do
        key="$(echo "${raw_key}" | tr -d '[:space:]')"
        value="$(echo "${raw_value}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
        if [[ "${key}" == "BINARY_ARTIFACT_VERSION" ]]; then
            CURRENT_PREPARED_VERSION="${value}"
            break
        fi
    done < "${SOURCE_REPO}/PackageSupport/BinaryArtifact.env"
fi

if [[ -n "${CURRENT_PREPARED_VERSION}" && "${CURRENT_PREPARED_VERSION}" != "${VERSION_A}" ]]; then
    echo "error: self-verification expects --version-a to match the prepared source-repo version (${CURRENT_PREPARED_VERSION})." >&2
    echo "Use scripts/validate-version-switch.sh for already-published historical tags." >&2
    exit 1
fi

CLEANUP_WORK_ROOT=0
if [[ -z "${WORK_ROOT}" ]]; then
    WORK_ROOT="$(mktemp -d "/tmp/libtorrent-apple-self-verify.XXXXXX")"
    CLEANUP_WORK_ROOT=1
fi

VALIDATION_REPO="${WORK_ROOT}/validation-repo"
REMOTE_REPO="${WORK_ROOT}/validation-remote.git"
SERVER_ROOT="${WORK_ROOT}/artifact-server"
SERVER_LOG="${WORK_ROOT}/artifact-server.log"
PORT="$(find_free_port)"
SERVER_PID=""

cleanup() {
    if [[ "${KEEP_WORKDIR}" == "1" || "${CLEANUP_WORK_ROOT}" != "1" ]]; then
        echo "Self-verification workdir preserved at ${WORK_ROOT}"
        return
    fi

    rm -rf "${WORK_ROOT}"
}

trap cleanup EXIT

mkdir -p "${SERVER_ROOT}" "${VALIDATION_REPO}"

rsync -a \
    --delete \
    --exclude '.git' \
    --exclude '.build' \
    --exclude 'Build' \
    --exclude 'Artifacts/release' \
    "${SOURCE_REPO}/" "${VALIDATION_REPO}/"

rm -rf \
    "${VALIDATION_REPO}/Vendor/libtorrent" \
    "${VALIDATION_REPO}/Vendor/OpenSSL"

source "${VALIDATION_REPO}/scripts/package-generation.sh"
FRAMEWORK_NAME_A="$(binary_framework_name_for_version "${VERSION_A}")"
mkdir -p "${VALIDATION_REPO}/Artifacts/release"
cp \
    "${SOURCE_REPO}/Artifacts/release/${FRAMEWORK_NAME_A}-${VERSION_A}.zip" \
    "${VALIDATION_REPO}/Artifacts/release/${FRAMEWORK_NAME_A}-${VERSION_A}.zip"
cp \
    "${SOURCE_REPO}/Artifacts/release/${FRAMEWORK_NAME_A}-${VERSION_A}.env" \
    "${VALIDATION_REPO}/Artifacts/release/${FRAMEWORK_NAME_A}-${VERSION_A}.env"

pushd "${VALIDATION_REPO}" >/dev/null

git init
git config user.name "Codex"
git config user.email "codex@example.com"

export BINARY_ARTIFACT_BASE_URL="http://127.0.0.1:${PORT}"

./scripts/write-release-metadata.sh "${VERSION_A}"
rm -rf "Artifacts/release/${FRAMEWORK_NAME_A}.xcframework"
ditto -x -k \
    "Artifacts/release/${FRAMEWORK_NAME_A}-${VERSION_A}.zip" \
    "Artifacts/release"
write_local_validation_package_manifest \
    "Package.swift" \
    "${FRAMEWORK_NAME_A}" \
    "Artifacts/release/${FRAMEWORK_NAME_A}.xcframework"

git add -A
git add -f "Artifacts/release/${FRAMEWORK_NAME_A}.xcframework"
git commit -m "chore(release): prepare ${VERSION_A}"
git tag -a "v${VERSION_A}" -m "v${VERSION_A}"

./scripts/release.sh "${VERSION_B}"

FRAMEWORK_NAME_B="$(binary_framework_name_for_version "${VERSION_B}")"
write_local_validation_package_manifest \
    "Package.swift" \
    "${FRAMEWORK_NAME_B}" \
    "Artifacts/release/${FRAMEWORK_NAME_B}.xcframework"

git add -A
git add -f "Artifacts/release/${FRAMEWORK_NAME_B}.xcframework"
git commit -m "chore(release): prepare ${VERSION_B}"
git tag -a "v${VERSION_B}" -m "v${VERSION_B}"

git init --bare "${REMOTE_REPO}"
git remote add origin "${REMOTE_REPO}"
git branch -M main
git push origin main --tags

popd >/dev/null

REPO_URL="file://${REMOTE_REPO}"
"${SCRIPT_DIR}/validate-version-switch.sh" \
    --repo-url "${REPO_URL}" \
    --version-a "${VERSION_A}" \
    --version-b "${VERSION_B}" \
    --work-root "${WORK_ROOT}/consumer-validation" \
    --keep-workdir

echo "Local self-verification passed for ${VERSION_A} -> ${VERSION_B} -> ${VERSION_A}."
