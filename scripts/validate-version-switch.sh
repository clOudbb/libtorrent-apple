#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
FIXTURE_ROOT_DEFAULT="${ROOT_DIR}/ValidationFixtures/SPMVersionSwitchConsumer"
PRODUCT_NAME="SPMVersionSwitchConsumer"

usage() {
    cat >&2 <<'EOF'
usage: scripts/validate-version-switch.sh --repo-url <git-url> --version-a <version> --version-b <version> [options]

options:
  --fixture-root <path>   Consumer fixture root (default: ValidationFixtures/SPMVersionSwitchConsumer)
  --work-root <path>      Persistent working directory (default: temporary directory)
  --cache-root <path>     Shared cache/build root (default: <work-root>/cache)
  --build-system <name>   SwiftPM build system: native|swiftbuild|xcode (default: xcode)
  --package-identity <id> Override the SwiftPM package identity derived from the repo URL
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

REPO_URL=""
VERSION_A=""
VERSION_B=""
FIXTURE_ROOT="${FIXTURE_ROOT_DEFAULT}"
WORK_ROOT=""
CACHE_ROOT=""
BUILD_SYSTEM="${BUILD_SYSTEM:-xcode}"
PACKAGE_IDENTITY=""
KEEP_WORKDIR=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --repo-url)
            REPO_URL="${2:-}"
            shift 2
            ;;
        --version-a)
            VERSION_A="${2:-}"
            shift 2
            ;;
        --version-b)
            VERSION_B="${2:-}"
            shift 2
            ;;
        --fixture-root)
            FIXTURE_ROOT="${2:-}"
            shift 2
            ;;
        --work-root)
            WORK_ROOT="${2:-}"
            shift 2
            ;;
        --cache-root)
            CACHE_ROOT="${2:-}"
            shift 2
            ;;
        --build-system)
            BUILD_SYSTEM="${2:-}"
            shift 2
            ;;
        --package-identity)
            PACKAGE_IDENTITY="${2:-}"
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

if [[ -z "${REPO_URL}" || -z "${VERSION_A}" || -z "${VERSION_B}" ]]; then
    usage
fi

if [[ ! -d "${FIXTURE_ROOT}" ]]; then
    echo "error: fixture root not found at ${FIXTURE_ROOT}" >&2
    exit 1
fi

require_command rsync
require_command swift
require_command python3

CLEANUP_WORK_ROOT=0
if [[ -z "${WORK_ROOT}" ]]; then
    WORK_ROOT="$(mktemp -d "/tmp/libtorrent-apple-version-switch.XXXXXX")"
    CLEANUP_WORK_ROOT=1
fi

if [[ -z "${CACHE_ROOT}" ]]; then
    CACHE_ROOT="${WORK_ROOT}/cache"
fi

CONSUMER_DIR="${WORK_ROOT}/consumer"
SCRATCH_PATH="${CACHE_ROOT}/scratch"
SHARED_CACHE_PATH="${CACHE_ROOT}/shared-cache"
CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-${CACHE_ROOT}/clang-module-cache}"

cleanup() {
    if [[ "${KEEP_WORKDIR}" == "1" || "${CLEANUP_WORK_ROOT}" != "1" ]]; then
        echo "Version-switch validation workdir preserved at ${WORK_ROOT}"
        return
    fi

    rm -rf "${WORK_ROOT}"
}

trap cleanup EXIT

mkdir -p "${WORK_ROOT}" "${CACHE_ROOT}"
rm -rf "${CONSUMER_DIR}"
rsync -a --delete --exclude '.build' "${FIXTURE_ROOT}/" "${CONSUMER_DIR}/"

if [[ -z "${PACKAGE_IDENTITY}" ]]; then
    PACKAGE_IDENTITY="$(basename "${REPO_URL}")"
    PACKAGE_IDENTITY="${PACKAGE_IDENTITY%.git}"
fi

render_manifest() {
    local version="$1"
    python3 - \
        "${FIXTURE_ROOT}/Package.swift.template" \
        "${CONSUMER_DIR}/Package.swift" \
        "${REPO_URL}" \
        "${version}" \
        "${PACKAGE_IDENTITY}" <<'PY'
from pathlib import Path
import sys

template_path, output_path, repo_url, version, package_identity = sys.argv[1:]
contents = Path(template_path).read_text()
contents = contents.replace("__REPO_URL__", repo_url)
contents = contents.replace("__PACKAGE_VERSION__", version)
contents = contents.replace("__PACKAGE_IDENTITY__", package_identity)
Path(output_path).write_text(contents)
PY
}

assert_resolved_version() {
    local expected_version="$1"

    python3 - "${CONSUMER_DIR}/Package.resolved" "${PACKAGE_IDENTITY}" "${expected_version}" <<'PY'
from pathlib import Path
import json
import sys

resolved_path = Path(sys.argv[1])
package_identity = sys.argv[2]
expected_version = sys.argv[3]

data = json.loads(resolved_path.read_text())
pins = data.get("pins")
if pins is None:
    pins = data.get("object", {}).get("pins", [])

matching_pin = None
for pin in pins:
    identity = pin.get("identity") or pin.get("package")
    location = pin.get("location") or pin.get("repositoryURL") or ""
    if identity == package_identity or location.rstrip("/").endswith(f"/{package_identity}.git") or location.rstrip("/").endswith(f"/{package_identity}"):
        matching_pin = pin
        break

if matching_pin is None:
    print(f"error: could not find package identity '{package_identity}' in Package.resolved", file=sys.stderr)
    sys.exit(1)

resolved_version = (matching_pin.get("state") or {}).get("version")
if resolved_version != expected_version:
    print(
        f"error: Package.resolved pinned '{package_identity}' at '{resolved_version}', expected '{expected_version}'",
        file=sys.stderr,
    )
    sys.exit(1)
PY
}

resolve_checkout_dir() {
    local candidate="${SCRATCH_PATH}/checkouts/${PACKAGE_IDENTITY}"
    local remote_url

    if [[ -d "${candidate}" ]]; then
        printf '%s\n' "${candidate}"
        return
    fi

    for candidate in "${SCRATCH_PATH}/checkouts"/*; do
        [[ -d "${candidate}" ]] || continue
        remote_url="$(git -C "${candidate}" config --get remote.origin.url 2>/dev/null || true)"
        if [[ "${remote_url}" == "${REPO_URL}" ]]; then
            printf '%s\n' "${candidate}"
            return
        fi
    done

    echo "error: failed to locate checkout directory for ${PACKAGE_IDENTITY}" >&2
    exit 1
}

resolve_expected_binary_target_name() {
    local checkout_dir="$1"
    local config_path="${checkout_dir}/PackageSupport/BinaryArtifact.env"

    if [[ -f "${config_path}" ]]; then
        while IFS='=' read -r raw_key raw_value; do
            key="$(echo "${raw_key}" | tr -d '[:space:]')"
            value="$(echo "${raw_value}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
            if [[ "${key}" == "BINARY_FRAMEWORK_NAME" && -n "${value}" ]]; then
                printf '%s\n' "${value}"
                return
            fi
        done < "${config_path}"
    fi

    python3 - "${checkout_dir}/Package.swift" <<'PY'
from pathlib import Path
import re
import sys

contents = Path(sys.argv[1]).read_text()
patterns = (
    r'let\s+binaryTargetName\s*=\s*"([^"]+)"',
    r'\.binaryTarget\(\s*name:\s*"([^"]+)"',
)
for pattern in patterns:
    match = re.search(pattern, contents)
    if match:
        print(match.group(1))
        sys.exit(0)

print("error: failed to resolve expected binary target name from Package.swift", file=sys.stderr)
sys.exit(1)
PY
}

assert_build_loaded_expected_target() {
    local expected_binary_target_name="$1"
    local build_output="$2"
    local built_framework_path

    if [[ "${build_output}" != *"${expected_binary_target_name}"* ]]; then
        echo "error: build output did not reference expected binary target ${expected_binary_target_name}" >&2
        exit 1
    fi

    case "${BUILD_SYSTEM}" in
        native)
            built_framework_path="$(find "${SCRATCH_PATH}" -path "*/debug/${expected_binary_target_name}.framework" -print -quit 2>/dev/null || true)"
            ;;
        *)
            built_framework_path="$(find "${SCRATCH_PATH}" -path "*/Products/*/${expected_binary_target_name}.framework" -print -quit 2>/dev/null || true)"
            ;;
    esac

    if [[ -z "${built_framework_path}" ]]; then
        echo "error: built products did not contain ${expected_binary_target_name}.framework" >&2
        exit 1
    fi
}

run_stage() {
    local label="$1"
    local version="$2"
    local checkout_dir
    local expected_binary_target_name
    local build_output
    local run_output

    echo "==> [${label}] validating version ${version}"
    render_manifest "${version}"
    rm -f "${CONSUMER_DIR}/Package.resolved"

    swift package resolve \
        --package-path "${CONSUMER_DIR}" \
        --cache-path "${SHARED_CACHE_PATH}" \
        --scratch-path "${SCRATCH_PATH}" \
        --manifest-cache shared

    assert_resolved_version "${version}"
    checkout_dir="$(resolve_checkout_dir)"
    expected_binary_target_name="$(resolve_expected_binary_target_name "${checkout_dir}")"

    build_output="$(
        swift build \
        --package-path "${CONSUMER_DIR}" \
        --cache-path "${SHARED_CACHE_PATH}" \
        --scratch-path "${SCRATCH_PATH}" \
        --manifest-cache shared \
        --build-system "${BUILD_SYSTEM}" \
        --product "${PRODUCT_NAME}"
    )"
    printf '%s\n' "${build_output}"
    assert_build_loaded_expected_target "${expected_binary_target_name}" "${build_output}"

    run_output="$(
        swift run \
        --package-path "${CONSUMER_DIR}" \
        --cache-path "${SHARED_CACHE_PATH}" \
        --scratch-path "${SCRATCH_PATH}" \
        --manifest-cache shared \
        --build-system "${BUILD_SYSTEM}" \
        --skip-build \
        "${PRODUCT_NAME}"
    )"
    printf '%s\n' "${run_output}"
}

export CLANG_MODULE_CACHE_PATH

run_stage "A" "${VERSION_A}"
run_stage "B" "${VERSION_B}"
run_stage "A-again" "${VERSION_A}"

echo "Version-switch validation passed for ${VERSION_A} -> ${VERSION_B} -> ${VERSION_A}."
