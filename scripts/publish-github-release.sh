#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
VERSION_INPUT="${1:-}"
VERSIONS_FILE="${SCRIPT_DIR}/versions.env"
PACKAGE_GENERATION_SCRIPT="${SCRIPT_DIR}/package-generation.sh"

if [[ -f "${VERSIONS_FILE}" ]]; then
    # shellcheck disable=SC1090
    source "${VERSIONS_FILE}"
fi

# shellcheck disable=SC1090
source "${PACKAGE_GENERATION_SCRIPT}"

if [[ -z "${VERSION_INPUT}" ]]; then
    echo "usage: scripts/publish-github-release.sh <version>" >&2
    exit 1
fi

if [[ ! "${VERSION_INPUT}" =~ ^v?[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]]; then
    echo "error: version must look like 0.1.0 or v0.1.0" >&2
    exit 1
fi

VERSION="${VERSION_INPUT#v}"
RELEASE_TAG="v${VERSION}"
FRAMEWORK_BASENAME="${FRAMEWORK_BASENAME:-LibtorrentAppleBinary}"
FRAMEWORK_NAME="$(binary_framework_name_for_version "${VERSION}" "${FRAMEWORK_BASENAME}")"
ARTIFACT_BASENAME="$(binary_artifact_basename_for_version "${VERSION}" "${FRAMEWORK_BASENAME}")"
METADATA_PATH="${ROOT_DIR}/Artifacts/release/${ARTIFACT_BASENAME}.env"
IS_PRERELEASE=0

if [[ "${VERSION}" == *-* ]]; then
    IS_PRERELEASE=1
fi

if [[ ! -f "${METADATA_PATH}" ]]; then
    echo "error: artifact metadata not found at ${METADATA_PATH}" >&2
    echo "Run scripts/release.sh ${VERSION} first." >&2
    exit 1
fi

if ! command -v gh >/dev/null 2>&1; then
    echo "error: gh CLI is not installed." >&2
    exit 1
fi

if ! gh help release >/dev/null 2>&1; then
    echo "error: gh CLI does not provide the release subcommand." >&2
    exit 1
fi

if [[ -n "${GITHUB_TOKEN:-}" && -z "${GH_TOKEN:-}" ]]; then
    export GH_TOKEN="${GITHUB_TOKEN}"
fi

if [[ -z "${GH_TOKEN:-}" ]]; then
    echo "error: GH_TOKEN or GITHUB_TOKEN is required to publish a GitHub Release." >&2
    exit 1
fi

if ! git rev-parse "${RELEASE_TAG}" >/dev/null 2>&1; then
    echo "error: local tag ${RELEASE_TAG} does not exist." >&2
    echo "Create and push the release tag before publishing." >&2
    exit 1
fi

set -a
source "${METADATA_PATH}"
set +a

PROVENANCE_NOTES_PATH="${ROOT_DIR}/Artifacts/release/${ARTIFACT_BASENAME}.release-notes.md"
GENERATED_NOTES_PATH="${ROOT_DIR}/Artifacts/release/${ARTIFACT_BASENAME}.github-generated-notes.md"
FINAL_RELEASE_NOTES_PATH="${ROOT_DIR}/Artifacts/release/${ARTIFACT_BASENAME}.release-notes.final.md"

if [[ -z "${REPOSITORY_SLUG:-}" || "${REPOSITORY_SLUG}" == "unknown" ]]; then
    echo "error: artifact metadata does not contain a GitHub repository slug." >&2
    exit 1
fi

if [[ ! -f "${PROVENANCE_NOTES_PATH}" ]]; then
    echo "error: release provenance not found at ${PROVENANCE_NOTES_PATH}" >&2
    exit 1
fi

resolve_previous_published_release_tag() {
    local release_tags tag
    release_tags="$(
        gh release list \
            --exclude-drafts \
            --exclude-pre-releases \
            --limit 100 \
            --json tagName \
            --jq '.[].tagName'
    )"

    while IFS= read -r tag; do
        [[ -z "${tag}" ]] && continue
        [[ "${tag}" == "${RELEASE_TAG}" ]] && continue
        printf '%s\n' "${tag}"
        return
    done <<< "${release_tags}"
}

generate_release_notes() {
    local previous_tag target_commitish
    local -a generate_notes_args

    previous_tag="$(resolve_previous_published_release_tag)"
    target_commitish="$(git rev-parse "${RELEASE_TAG}^{commit}")"
    generate_notes_args=(
        -X POST
        "repos/${REPOSITORY_SLUG}/releases/generate-notes"
        -f "tag_name=${RELEASE_TAG}"
        -f "target_commitish=${target_commitish}"
    )

    if [[ -n "${previous_tag}" ]]; then
        generate_notes_args+=(-f "previous_tag_name=${previous_tag}")
    fi

    gh api "${generate_notes_args[@]}" --jq '.body' > "${GENERATED_NOTES_PATH}"

    if [[ ! -s "${GENERATED_NOTES_PATH}" ]]; then
        echo "error: GitHub generated empty release notes for ${RELEASE_TAG}." >&2
        exit 1
    fi

    awk -v provenance_path="${PROVENANCE_NOTES_PATH}" '
        function print_provenance(    line) {
            while ((getline line < provenance_path) > 0) {
                print line
            }
            close(provenance_path)
        }

        /^\*\*Full Changelog\*\*:/ && !inserted {
            print_provenance()
            print ""
            inserted = 1
        }

        { print }

        END {
            if (!inserted) {
                print ""
                print_provenance()
            }
        }
    ' "${GENERATED_NOTES_PATH}" > "${FINAL_RELEASE_NOTES_PATH}"
}

ensure_release_assets_are_new() {
    local release_tag="$1"
    shift
    local asset_name existing_assets

    existing_assets="$(gh release view "${release_tag}" --json assets --jq '.assets[].name' 2>/dev/null || true)"
    [[ -z "${existing_assets}" ]] && return 0

    for asset_name in "$@"; do
        if printf '%s\n' "${existing_assets}" | grep -Fxq "${asset_name}"; then
            echo "error: release asset '${asset_name}' already exists for ${release_tag}. Published assets are immutable." >&2
            exit 1
        fi
    done
}

generate_release_notes

if gh release view "${RELEASE_TAG}" >/dev/null 2>&1; then
    ensure_release_assets_are_new \
        "${RELEASE_TAG}" \
        "$(basename "${ZIP_PATH}")"

    gh release edit "${RELEASE_TAG}" --notes-file "${FINAL_RELEASE_NOTES_PATH}"
    gh release upload \
        "${RELEASE_TAG}" \
        "${ZIP_PATH}"
else
    if [[ "${IS_PRERELEASE}" == "1" ]]; then
        gh release create \
            "${RELEASE_TAG}" \
            "${ZIP_PATH}" \
            --prerelease \
            --title "${RELEASE_TAG}" \
            --notes-file "${FINAL_RELEASE_NOTES_PATH}"
    else
        gh release create \
            "${RELEASE_TAG}" \
            "${ZIP_PATH}" \
            --title "${RELEASE_TAG}" \
            --notes-file "${FINAL_RELEASE_NOTES_PATH}"
    fi
fi

echo "Published ${RELEASE_TAG}"
echo "Artifact: ${ZIP_PATH}"
echo "Checksum: ${CHECKSUM}"
echo "Release notes source: ${FINAL_RELEASE_NOTES_PATH}"
