#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
VERSIONS_FILE="${SCRIPT_DIR}/versions.env"
PACKAGE_GENERATION_SCRIPT="${SCRIPT_DIR}/package-generation.sh"
ARTIFACTS_DIR="${ROOT_DIR}/Artifacts/release"
PACKAGE_SUPPORT_DIR="${ROOT_DIR}/PackageSupport"
LIBTORRENT_SOURCE_DIR="${LIBTORRENT_SOURCE_DIR:-${ROOT_DIR}/Vendor/libtorrent}"
OPENSSL_SOURCE_DIR="${OPENSSL_SOURCE_DIR:-${ROOT_DIR}/Vendor/OpenSSL}"
SOURCE_METADATA_FILE="${LIBTORRENT_SOURCE_DIR}/.bootstrap-source"
OPENSSL_SOURCE_METADATA_FILE="${OPENSSL_SOURCE_DIR}/.bootstrap-source"
VERSION_INPUT="${1:-}"

if [[ -z "${VERSION_INPUT}" ]]; then
    echo "usage: scripts/write-release-metadata.sh <version>" >&2
    exit 1
fi

if [[ -f "${VERSIONS_FILE}" ]]; then
    # shellcheck disable=SC1090
    source "${VERSIONS_FILE}"
fi

VERSION="${VERSION_INPUT#v}"
RELEASE_TAG="v${VERSION}"
# shellcheck disable=SC1090
source "${PACKAGE_GENERATION_SCRIPT}"

FRAMEWORK_BASENAME="${FRAMEWORK_BASENAME:-LibtorrentAppleBinary}"
FRAMEWORK_NAME="${FRAMEWORK_NAME:-$(binary_framework_name_for_version "${VERSION}" "${FRAMEWORK_BASENAME}")}"
ARTIFACT_BASENAME="${ARTIFACT_BASENAME:-$(binary_artifact_basename_for_version "${VERSION}" "${FRAMEWORK_BASENAME}")}"
METADATA_PATH="${ARTIFACTS_DIR}/${ARTIFACT_BASENAME}.env"
BINARY_TARGET_SNIPPET_PATH="${ARTIFACTS_DIR}/${ARTIFACT_BASENAME}.binary-target.swift"
RELEASE_NOTES_PATH="${ARTIFACTS_DIR}/${ARTIFACT_BASENAME}.release-notes.md"
PACKAGE_BINARY_ARTIFACT_CONFIG_PATH="${PACKAGE_SUPPORT_DIR}/BinaryArtifact.env"
PACKAGE_MANIFEST_PATH="${ROOT_DIR}/Package.swift"
BRIDGE_COMPAT_TARGET_PATH="${ROOT_DIR}/Sources/LibtorrentAppleBridgeCompat"

if [[ ! -f "${METADATA_PATH}" ]]; then
    echo "error: metadata file not found at ${METADATA_PATH}" >&2
    exit 1
fi

set -a
source "${METADATA_PATH}"
set +a

# Metadata files may contain absolute paths from the environment that created them.
# Rebind all local output paths to the current repository before generating files.
BINARY_TARGET_SNIPPET_PATH="${ARTIFACTS_DIR}/${ARTIFACT_BASENAME}.binary-target.swift"
RELEASE_NOTES_PATH="${ARTIFACTS_DIR}/${ARTIFACT_BASENAME}.release-notes.md"
PACKAGE_BINARY_ARTIFACT_CONFIG_PATH="${PACKAGE_SUPPORT_DIR}/BinaryArtifact.env"
PACKAGE_MANIFEST_PATH="${ROOT_DIR}/Package.swift"
BRIDGE_COMPAT_TARGET_PATH="${ROOT_DIR}/Sources/LibtorrentAppleBridgeCompat"

if [[ -f "${SOURCE_METADATA_FILE}" ]]; then
    # shellcheck disable=SC1090
    source "${SOURCE_METADATA_FILE}"
fi

if [[ -f "${OPENSSL_SOURCE_METADATA_FILE}" ]]; then
    # shellcheck disable=SC1090
    source "${OPENSSL_SOURCE_METADATA_FILE}"
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

append_bullet() {
    local target_var="$1"
    local text="$2"

    if [[ -z "${text//[[:space:]]/}" ]]; then
        return
    fi

    printf -v "${target_var}" '%s- %s\n' "${!target_var:-}" "${text}"
}

append_section() {
    local target_var="$1"
    local title="$2"
    local content="$3"
    local compact_content

    compact_content="$(printf '%s' "${content}" | tr -d '[:space:]')"
    if [[ -z "${compact_content}" ]]; then
        return
    fi

    printf -v "${target_var}" '%s### %s\n\n%s\n' "${!target_var:-}" "${title}" "${content}"
}

has_any_keyword() {
    local haystack="$1"
    shift

    local keyword
    for keyword in "$@"; do
        if [[ "${haystack}" == *"${keyword}"* ]]; then
            return 0
        fi
    done

    return 1
}

clean_commit_subject() {
    printf '%s\n' "$1" | sed -E 's/^[[:alnum:]_-]+(\([^)]+\))?:[[:space:]]*//'
}

sentence_case() {
    local input="$1"
    if [[ -z "${input}" ]]; then
        return
    fi

    printf '%s%s\n' "$(printf '%s' "${input:0:1}" | tr '[:lower:]' '[:upper:]')" "${input:1}"
}

resolve_previous_release_tag() {
    local tag
    while IFS= read -r tag; do
        [[ -z "${tag}" ]] && continue
        if [[ "${tag}" == "${RELEASE_TAG}" ]]; then
            continue
        fi
        printf '%s\n' "${tag}"
        return
    done < <(git -C "${ROOT_DIR}" tag --sort=-v:refname)
}

build_release_changelog() {
    local previous_tag range commit_subjects changed_files working_tree_files untracked_files diff_text context
    local zh_highlights="" zh_new="" zh_improved="" zh_fixed="" zh_breaking="" zh_notes=""
    local en_highlights="" en_new="" en_improved="" en_fixed="" en_breaking="" en_notes=""
    local zh_summary="" en_summary=""

    previous_tag="$(resolve_previous_release_tag)"
    if [[ -n "${previous_tag}" ]]; then
        range="${previous_tag}..HEAD"
        commit_subjects="$(git -C "${ROOT_DIR}" log --format=%s "${range}" 2>/dev/null || true)"
        changed_files="$(git -C "${ROOT_DIR}" diff --name-only "${range}" 2>/dev/null || true)"
    else
        range="HEAD"
        commit_subjects="$(git -C "${ROOT_DIR}" log --format=%s -n 20 2>/dev/null || true)"
        changed_files="$(git -C "${ROOT_DIR}" diff-tree --no-commit-id --name-only -r HEAD 2>/dev/null || true)"
    fi

    working_tree_files="$(git -C "${ROOT_DIR}" diff --name-only HEAD 2>/dev/null || true)"
    untracked_files="$(git -C "${ROOT_DIR}" ls-files --others --exclude-standard 2>/dev/null || true)"
    if [[ -n "${working_tree_files}" ]]; then
        if [[ -n "${changed_files}" ]]; then
            changed_files="$(printf '%s\n%s\n' "${changed_files}" "${working_tree_files}" | awk 'NF && !seen[$0]++')"
        else
            changed_files="${working_tree_files}"
        fi
    fi

    if [[ -n "${untracked_files}" ]]; then
        if [[ -n "${changed_files}" ]]; then
            changed_files="$(printf '%s\n%s\n' "${changed_files}" "${untracked_files}" | awk 'NF && !seen[$0]++')"
        else
            changed_files="${untracked_files}"
        fi
    fi

    diff_text="$(git -C "${ROOT_DIR}" diff --unified=0 HEAD 2>/dev/null || true)"
    if [[ -n "${untracked_files}" ]]; then
        diff_text="$(printf '%s\n%s\n' "${diff_text}" "${untracked_files}")"
    fi

    context="$(printf '%s\n%s\n%s\n' "${commit_subjects}" "${changed_files}" "${diff_text}" | tr '[:upper:]' '[:lower:]')"

    local has_persistent_restore=0
    local has_recovery_validation=0
    local has_best_effort_restore=0
    local has_move_storage=0
    local has_snapshot_removal=0
    local has_binary_packaging=0
    local has_release_notes=0

    has_any_keyword "${context}" \
        "persistentstate" "savepersistentstate" "restorepersistentstate" "persistent state" \
        "persistentstaterestorereport" "resumedata/" "torrentfiles/" && has_persistent_restore=1

    has_any_keyword "${context}" \
        "validatepersistentrestorecandidates" "restore validation" "before reporting success" \
        "session_torrent_restore_failed" "restore failed" && has_recovery_validation=1

    has_any_keyword "${context}" \
        "besteffort" "best effort" "partial failure" "rehydratetrackedtorrents" && has_best_effort_restore=1

    has_any_keyword "${context}" \
        "movestorage" "storage_moved" "storage move" "downloaddirectory" && has_move_storage=1

    has_any_keyword "${context}" \
        "resumedatasnapshot" "persistresumesnapshot" "restoreresumesnapshot" "restorelatestresumesnapshot" \
        "snapshot restore" "old snapshot" && has_snapshot_removal=1

    has_any_keyword "${context}" \
        "libtorrent_apple_required_alert_mask" "binaryartifact" "xcframework" \
        "local-binary" "remote-binary" "write-release-metadata" "make-xcframework" && has_binary_packaging=1

    has_any_keyword "${context}" \
        "change_log_rules" "release-notes" "release notes" "docs/change_log_rules.md" && has_release_notes=1

    if (( has_persistent_restore )) && (( has_snapshot_removal )); then
        zh_summary="这次更新把下载恢复流程收敛成了一条更可靠的主路径。iOS 和 macOS 下重启后的恢复语义更清晰，旧的 snapshot 恢复链路也已移除。"
        en_summary="This release consolidates restart recovery into a single, more reliable path. Recovery behavior on iOS and macOS is clearer now, and the old snapshot-based restore flow has been removed."
    elif (( has_persistent_restore )); then
        zh_summary="这次更新重点提升了 iOS 和 macOS 下的重启恢复可靠性，让下载状态恢复更接近真实续传。"
        en_summary="This release focuses on more reliable restart recovery on iOS and macOS, with behavior that is closer to true torrent resume."
    elif (( has_binary_packaging )); then
        zh_summary="这次更新重点改进了 binary 打包和集成说明，让发版和接入流程更清晰。"
        en_summary="This release focuses on binary packaging and integration clarity, making the release flow easier to follow."
    else
        zh_summary="这次版本整理了一批重要更新，并保留了后续集成所需的技术信息。"
        en_summary="This release groups together the most important updates while keeping the technical integration details below."
    fi

    if (( has_persistent_restore )); then
        append_bullet zh_highlights "统一使用持久化恢复状态作为主恢复方案，不再依赖旧的 snapshot 恢复链路。"
        append_bullet en_highlights "Moved to persistent restore state as the primary recovery path instead of relying on the old snapshot flow."
        append_bullet zh_new "新增面向 iOS / macOS 重启场景的持久化恢复主链路。"
        append_bullet en_new "Added a durable restore path for iOS and macOS restart recovery."
    fi

    if (( has_recovery_validation )); then
        append_bullet zh_highlights "改进了冷启动恢复语义，恢复结果会在更早阶段暴露，不再先报成功再在启动时失败。"
        append_bullet en_highlights "Improved cold-start restore semantics so failures are surfaced earlier instead of appearing to succeed before startup fails."
        append_bullet zh_improved "改进了恢复校验流程，恢复结果与实际启动行为更加一致。"
        append_bullet en_improved "Improved restore validation so reported results match actual startup behavior more closely."
    fi

    if (( has_best_effort_restore )); then
        append_bullet zh_highlights "优化了冷启动恢复策略，单个任务失败时其余任务仍可继续恢复。"
        append_bullet en_highlights "Changed cold-start recovery to best-effort behavior so one failed torrent no longer blocks the whole session."
        append_bullet zh_improved "改进了多任务恢复表现，健康任务不会再被单个坏任务整批拖垮。"
        append_bullet en_improved "Improved multi-torrent recovery so healthy torrents are not blocked by a single bad restore candidate."
    fi

    if (( has_move_storage )); then
        append_bullet zh_fixed "修复了存储迁移后的路径同步问题，后续文件操作不再容易指向错误目录。"
        append_bullet en_fixed "Fixed a storage-move path sync issue that could make later file operations point at the wrong directory."
    fi

    if (( has_snapshot_removal )); then
        append_bullet zh_breaking "已移除旧的 snapshot 相关恢复 API，后续统一使用 \`savePersistentState()\` 和 \`restorePersistentState()\`。"
        append_bullet en_breaking "Removed the old snapshot-based restore APIs. Use \`savePersistentState()\` and \`restorePersistentState()\` instead."
    fi

    if (( has_binary_packaging )); then
        append_bullet zh_breaking "发版时需要同步发布与当前源码匹配的 XCFramework binary artifact，不能继续复用旧版本工件。"
        append_bullet en_breaking "Releases now need a matching XCFramework binary artifact for the current source state instead of reusing an older packaged artifact."
        append_bullet zh_notes "如果本次版本新增了 bridge 接口或 binary 依赖，请在发布前完成 local-binary / remote-binary 校验。"
        append_bullet en_notes "If this release adds a new bridge API or binary dependency, validate both local-binary and remote-binary modes before publishing."
    fi

    if (( has_release_notes )); then
        append_bullet zh_notes "更新了 release notes 结构，前半部分更适合阅读，后半部分继续保留技术元数据。"
        append_bullet en_notes "Updated the release-notes structure so the changelog is easier to read while the technical metadata remains intact below."
    fi

    if [[ -z "${en_highlights}" ]]; then
        local subject fallback_count=0 cleaned
        while IFS= read -r subject; do
            [[ -z "${subject}" ]] && continue
            cleaned="$(clean_commit_subject "${subject}")"
            cleaned="$(sentence_case "${cleaned}")"
            [[ -z "${cleaned}" ]] && continue
            append_bullet en_highlights "${cleaned}"
            append_bullet zh_highlights "${cleaned}"
            fallback_count=$((fallback_count + 1))
            if (( fallback_count >= 3 )); then
                break
            fi
        done <<< "${commit_subjects}"
    fi

    local zh_body="" en_body=""
    append_section zh_body "What's New" "${zh_summary}"
    append_section zh_body "Highlights" "${zh_highlights}"
    append_section zh_body "New" "${zh_new}"
    append_section zh_body "Improved" "${zh_improved}"
    append_section zh_body "Fixed" "${zh_fixed}"
    append_section zh_body "Breaking / Migration" "${zh_breaking}"
    append_section zh_body "Notes" "${zh_notes}"

    append_section en_body "What's New" "${en_summary}"
    append_section en_body "Highlights" "${en_highlights}"
    append_section en_body "New" "${en_new}"
    append_section en_body "Improved" "${en_improved}"
    append_section en_body "Fixed" "${en_fixed}"
    append_section en_body "Breaking / Migration" "${en_breaking}"
    append_section en_body "Notes" "${en_notes}"

    GENERATED_ZH_CHANGELOG="${zh_body}"
    GENERATED_EN_CHANGELOG="${en_body}"
}

if [[ -n "${BINARY_ARTIFACT_BASE_URL:-}" ]]; then
    DOWNLOAD_URL="${BINARY_ARTIFACT_BASE_URL%/}/releases/download/${RELEASE_TAG}/${ARTIFACT_BASENAME}.zip"
elif [[ -n "${REPOSITORY_SLUG}" ]]; then
    DOWNLOAD_URL="https://github.com/${REPOSITORY_SLUG}/releases/download/${RELEASE_TAG}/${ARTIFACT_BASENAME}.zip"
else
    DOWNLOAD_URL="<replace-with-your-github-release-url>"
fi

build_release_changelog

mkdir -p "${PACKAGE_SUPPORT_DIR}"
write_bridge_compat_target "${BRIDGE_COMPAT_TARGET_PATH}" "${FRAMEWORK_NAME}"
write_release_package_manifest "${PACKAGE_MANIFEST_PATH}" "${FRAMEWORK_NAME}" "${DOWNLOAD_URL}" "${CHECKSUM}"

cat > "${PACKAGE_BINARY_ARTIFACT_CONFIG_PATH}" <<EOF
# Managed by scripts/write-release-metadata.sh.
# Internal release metadata for maintainers.
# The public SwiftPM package is described directly in Package.swift.
# Maintainers can validate internal source/local-binary flows with:
#   ./scripts/validate-dev-package.sh source
#   ./scripts/validate-dev-package.sh local-binary

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
## English

${GENERATED_EN_CHANGELOG}

---

## 中文

${GENERATED_ZH_CHANGELOG}

## Artifact

- XCFramework zip: ${ARTIFACT_BASENAME}.zip
- SwiftPM checksum: \`${CHECKSUM}\`

## Upstream Source

- libtorrent repo: ${LIBTORRENT_REPO_URL:-unknown}
- libtorrent requested ref: ${LIBTORRENT_REF_REQUESTED:-unknown}
- libtorrent resolved ref: ${LIBTORRENT_REF_RESOLVED:-unknown}
- libtorrent commit: ${LIBTORRENT_COMMIT_SHA:-unknown}
- OpenSSL repo: ${OPENSSL_REPO_URL:-unknown}
- OpenSSL requested ref: ${OPENSSL_REF_REQUESTED:-unknown}
- OpenSSL resolved ref: ${OPENSSL_REF_RESOLVED:-unknown}
- OpenSSL commit: ${OPENSSL_COMMIT_SHA:-unknown}

## Consumer Notes

- SwiftPM product exposed to apps: \`LibtorrentApple\`
- Internal binary target used by the package: \`${FRAMEWORK_NAME}\`
- Stable bridge target used by the package: \`LibtorrentAppleBridge\`
- Required Apple system frameworks: ${REQUIRED_SYSTEM_FRAMEWORKS:-CFNetwork,CoreFoundation,Security,SystemConfiguration}
- Required link libraries when integrating the raw framework manually: ${REQUIRED_LINK_LIBRARIES:-libc++}
- Local binary target snippet generated at \`${ARTIFACT_BASENAME}.binary-target.swift\`
- Public package manifest updated at \`Package.swift\`
- Internal release metadata updated at \`PackageSupport/BinaryArtifact.env\`

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
PACKAGE_MANIFEST_PATH=${PACKAGE_MANIFEST_PATH}
BRIDGE_COMPAT_TARGET_PATH=${BRIDGE_COMPAT_TARGET_PATH}
EOF

echo "Wrote ${BINARY_TARGET_SNIPPET_PATH}"
echo "Wrote ${RELEASE_NOTES_PATH}"
echo "Wrote ${PACKAGE_BINARY_ARTIFACT_CONFIG_PATH}"
echo "Wrote ${PACKAGE_MANIFEST_PATH}"
echo "Wrote ${BRIDGE_COMPAT_TARGET_PATH}"
