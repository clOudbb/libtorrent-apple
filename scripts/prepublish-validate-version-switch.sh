#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
PACKAGE_GENERATION_SCRIPT="${SCRIPT_DIR}/package-generation.sh"

usage() {
    cat >&2 <<'EOF'
usage: scripts/prepublish-validate-version-switch.sh --version-a <version> --version-b <version> [options]

options:
  --source-repo <path>    Source repository to validate (default: current repo)
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

rewrite_legacy_release_manifest() {
    local package_path="$1"
    local config_path="$2"
    local binary_target_name=""
    local binary_target_url=""
    local binary_target_checksum=""

    while IFS='=' read -r raw_key raw_value; do
        key="$(echo "${raw_key}" | tr -d '[:space:]')"
        value="$(echo "${raw_value}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

        case "${key}" in
            BINARY_FRAMEWORK_NAME)
                binary_target_name="${value}"
                ;;
            BINARY_ARTIFACT_URL)
                binary_target_url="${value}"
                ;;
            BINARY_ARTIFACT_CHECKSUM)
                binary_target_checksum="${value}"
                ;;
        esac
    done < "${config_path}"

    if [[ -z "${binary_target_name}" || -z "${binary_target_url}" || -z "${binary_target_checksum}" ]]; then
        echo "error: failed to derive legacy release metadata from ${config_path}" >&2
        exit 1
    fi

    cat > "${package_path}" <<EOF
// swift-tools-version: 6.0

import PackageDescription

let binaryTargetName = "${binary_target_name}"
let binaryTargetURL = "${binary_target_url}"
let binaryTargetChecksum = "${binary_target_checksum}"

let package = Package(
    name: "libtorrent-apple",
    platforms: [
        .iOS(.v15),
        .macOS(.v13),
    ],
    products: [
        .library(
            name: "LibtorrentApple",
            targets: ["LibtorrentApple"]
        ),
        .executable(
            name: "LibtorrentAppleBenchmarkCLI",
            targets: ["LibtorrentAppleBenchmarkCLI"]
        ),
    ],
    targets: [
        .binaryTarget(
            name: binaryTargetName,
            url: binaryTargetURL,
            checksum: binaryTargetChecksum
        ),
        .target(
            name: "LibtorrentApple",
            dependencies: [.target(name: binaryTargetName)],
            path: "Sources/LibtorrentApple",
            linkerSettings: [
                .linkedFramework("CFNetwork"),
                .linkedFramework("CoreFoundation"),
                .linkedFramework("Security"),
                .linkedFramework("SystemConfiguration"),
                .linkedLibrary("c++"),
            ]
        ),
        .executableTarget(
            name: "LibtorrentAppleBenchmarkCLI",
            dependencies: ["LibtorrentApple"],
            path: "Sources/LibtorrentAppleBenchmarkCLI"
        ),
        .testTarget(
            name: "LibtorrentAppleTests",
            dependencies: ["LibtorrentApple"],
            path: "Tests/LibtorrentAppleTests"
        ),
    ]
)
EOF
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
require_command rsync
require_command python3

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

if [[ -n "${CURRENT_PREPARED_VERSION}" && "${CURRENT_PREPARED_VERSION}" != "${VERSION_B}" ]]; then
    echo "error: prepublish validation expects the prepared source-repo version to match --version-b (${CURRENT_PREPARED_VERSION})." >&2
    exit 1
fi

# shellcheck disable=SC1090
source "${PACKAGE_GENERATION_SCRIPT}"
FRAMEWORK_NAME_B="$(binary_framework_name_for_version "${VERSION_B}")"
FRAMEWORK_PATH_B="${SOURCE_REPO}/Artifacts/release/${FRAMEWORK_NAME_B}.xcframework"

if [[ ! -d "${FRAMEWORK_PATH_B}" ]]; then
    echo "error: prepared XCFramework not found at ${FRAMEWORK_PATH_B}" >&2
    exit 1
fi

if ! git -C "${SOURCE_REPO}" rev-parse "v${VERSION_A}" >/dev/null 2>&1; then
    echo "error: baseline tag v${VERSION_A} was not found in ${SOURCE_REPO}" >&2
    exit 1
fi

CLEANUP_WORK_ROOT=0
if [[ -z "${WORK_ROOT}" ]]; then
    WORK_ROOT="$(mktemp -d "/tmp/libtorrent-apple-prepublish-switch.XXXXXX")"
    CLEANUP_WORK_ROOT=1
fi

VALIDATION_REPO="${WORK_ROOT}/validation-repo"
REMOTE_REPO="${WORK_ROOT}/validation-remote.git"

cleanup() {
    if [[ "${KEEP_WORKDIR}" == "1" || "${CLEANUP_WORK_ROOT}" != "1" ]]; then
        echo "Prepublish version-switch workdir preserved at ${WORK_ROOT}"
        return
    fi

    rm -rf "${WORK_ROOT}"
}

trap cleanup EXIT

rm -rf "${VALIDATION_REPO}" "${REMOTE_REPO}"
mkdir -p "${VALIDATION_REPO}"

git -C "${SOURCE_REPO}" archive "v${VERSION_A}" | tar -x -C "${VALIDATION_REPO}"

if grep -q "PackageSupport/BinaryArtifact.env" "${VALIDATION_REPO}/Package.swift" && [[ -f "${VALIDATION_REPO}/PackageSupport/BinaryArtifact.env" ]]; then
    rewrite_legacy_release_manifest "${VALIDATION_REPO}/Package.swift" "${VALIDATION_REPO}/PackageSupport/BinaryArtifact.env"
fi

pushd "${VALIDATION_REPO}" >/dev/null

git init
git config user.name "Codex"
git config user.email "codex@example.com"
git add -A
git commit -m "chore(validation): import ${VERSION_A}"
git tag -a "v${VERSION_A}" -m "v${VERSION_A}"

rsync -a \
    --delete \
    --exclude '.git' \
    --exclude '.build' \
    --exclude 'Build' \
    --exclude 'Artifacts/release' \
    --exclude 'Vendor/libtorrent' \
    --exclude 'Vendor/OpenSSL' \
    "${SOURCE_REPO}/" "${VALIDATION_REPO}/"

mkdir -p "Artifacts/release"
rsync -a "${FRAMEWORK_PATH_B}/" "Artifacts/release/${FRAMEWORK_NAME_B}.xcframework/"

# shellcheck disable=SC1090
source "${VALIDATION_REPO}/scripts/package-generation.sh"
write_local_validation_package_manifest \
    "Package.swift" \
    "${FRAMEWORK_NAME_B}" \
    "Artifacts/release/${FRAMEWORK_NAME_B}.xcframework"

git add -A
git add -f "Artifacts/release/${FRAMEWORK_NAME_B}.xcframework"
git commit -m "chore(validation): prepare ${VERSION_B}"
git tag -a "v${VERSION_B}" -m "v${VERSION_B}"

git init --bare "${REMOTE_REPO}"
git remote add origin "${REMOTE_REPO}"
git branch -M main
git push origin main --tags

popd >/dev/null

"${SCRIPT_DIR}/validate-version-switch.sh" \
    --repo-url "file://${REMOTE_REPO}" \
    --version-a "${VERSION_A}" \
    --version-b "${VERSION_B}" \
    --work-root "${WORK_ROOT}/consumer-validation" \
    --keep-workdir

echo "Prepublish version-switch validation passed for ${VERSION_A} -> ${VERSION_B} -> ${VERSION_A}."
