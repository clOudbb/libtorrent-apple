#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
VERSIONS_FILE="${SCRIPT_DIR}/versions.env"
SOURCE_DIR="${LIBTORRENT_SOURCE_DIR:-${ROOT_DIR}/Vendor/libtorrent}"
BOOST_VENDOR_DIR="${BOOST_VENDOR_DIR:-${ROOT_DIR}/Vendor/boost}"
BUILD_DIR="${ROOT_DIR}/Build/apple"
CONFIGURATION="${CONFIGURATION:-Release}"
SOURCE_METADATA_FILE="${SOURCE_DIR}/.bootstrap-source"
NATIVE_BRIDGE_DIR="${ROOT_DIR}/NativeBridge"
SDKS=(iphoneos iphonesimulator macosx)

if [[ -f "${VERSIONS_FILE}" ]]; then
    # shellcheck disable=SC1090
    source "${VERSIONS_FILE}"
fi

FRAMEWORK_NAME="${FRAMEWORK_NAME:-LibtorrentApple}"
IOS_DEPLOYMENT_TARGET="${IOS_DEPLOYMENT_TARGET:-15.0}"
MACOS_DEPLOYMENT_TARGET="${MACOS_DEPLOYMENT_TARGET:-13.0}"
BOOST_VERSION="${BOOST_VERSION:-1.76.0}"
BOOST_SOURCE_URL="${BOOST_SOURCE_URL:-https://archives.boost.io/release/${BOOST_VERSION}/source/boost_${BOOST_VERSION//./_}.tar.bz2}"
BUILD_JOBS="${BUILD_JOBS:-$(sysctl -n hw.ncpu 2>/dev/null || printf '4\n')}"
CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-/tmp/libtorrent-apple-clang-cache}"

if [[ ! -d "${SOURCE_DIR}" ]]; then
    echo "error: libtorrent source not found at ${SOURCE_DIR}. Run scripts/sync-libtorrent.sh first." >&2
    exit 1
fi

if [[ ! -d "${NATIVE_BRIDGE_DIR}" ]]; then
    echo "error: native bridge sources not found at ${NATIVE_BRIDGE_DIR}" >&2
    exit 1
fi

if [[ -f "${SOURCE_METADATA_FILE}" ]]; then
    # shellcheck disable=SC1090
    source "${SOURCE_METADATA_FILE}"
fi

require_command() {
    local command_name="$1"
    if ! command -v "${command_name}" >/dev/null 2>&1; then
        echo "error: required command '${command_name}' was not found" >&2
        exit 1
    fi
}

prepare_boost_headers() {
    if [[ -n "${BOOST_INCLUDE_DIR:-}" ]]; then
        if [[ ! -f "${BOOST_INCLUDE_DIR}/boost/config.hpp" ]]; then
            echo "error: BOOST_INCLUDE_DIR does not contain boost/config.hpp: ${BOOST_INCLUDE_DIR}" >&2
            exit 1
        fi

        printf '%s\n' "${BOOST_INCLUDE_DIR}"
        return
    fi

    local boost_version_underscored="${BOOST_VERSION//./_}"
    local boost_source_root="${BOOST_SOURCE_ROOT:-${BOOST_VENDOR_DIR}/boost_${boost_version_underscored}}"
    local archive_name="${BOOST_SOURCE_URL##*/}"
    local archive_path="${BOOST_VENDOR_DIR}/${archive_name}"

    mkdir -p "${BOOST_VENDOR_DIR}"

    if [[ ! -d "${boost_source_root}" ]]; then
        if [[ ! -f "${archive_path}" ]]; then
            curl -L --fail --retry 3 "${BOOST_SOURCE_URL}" -o "${archive_path}"
        fi
        tar -xf "${archive_path}" -C "${BOOST_VENDOR_DIR}"
    fi

    if [[ ! -f "${boost_source_root}/boost/config.hpp" ]]; then
        echo "error: boost headers not found under ${boost_source_root}" >&2
        exit 1
    fi

    printf '%s\n' "${boost_source_root}"
}

cmake_build_dir_for_sdk() {
    printf '%s\n' "${BUILD_DIR}/$1/cmake"
}

framework_dir_for_sdk() {
    printf '%s\n' "${BUILD_DIR}/$1/${FRAMEWORK_NAME}.framework"
}

bridge_archive_for_sdk() {
    printf '%s\n' "${BUILD_DIR}/$1/bridge/${FRAMEWORK_NAME}_bridge.a"
}

build_libtorrent_for_sdk() {
    local sdk="$1"
    local deployment_target="$2"
    local boost_include_dir="$3"
    shift 3
    local archs=("$@")
    local archs_string
    local build_dir
    local c_compiler
    local cxx_compiler
    local libtorrent_archive

    archs_string="$(IFS=';'; printf '%s' "${archs[*]}")"
    build_dir="$(cmake_build_dir_for_sdk "${sdk}")"
    c_compiler="$(xcrun --sdk "${sdk}" --find clang)"
    cxx_compiler="$(xcrun --sdk "${sdk}" --find clang++)"

    rm -rf "${build_dir}"
    mkdir -p "${build_dir}"

    local cmake_args=(
        -S "${SOURCE_DIR}"
        -B "${build_dir}"
        -G "Unix Makefiles"
        -DCMAKE_C_COMPILER="${c_compiler}"
        -DCMAKE_CXX_COMPILER="${cxx_compiler}"
        -DCMAKE_BUILD_TYPE="${CONFIGURATION}"
        -DCMAKE_CXX_STANDARD=14
        -DCMAKE_OSX_SYSROOT="${sdk}"
        -DCMAKE_OSX_ARCHITECTURES="${archs_string}"
        -DCMAKE_OSX_DEPLOYMENT_TARGET="${deployment_target}"
        -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY
        -DBUILD_SHARED_LIBS=OFF
        -Dbuild_examples=OFF
        -Dbuild_tests=OFF
        -Dbuild_tools=OFF
        -Ddeprecated-functions=ON
        -Ddht=ON
        -Dencryption=ON
        -DBOOST_ROOT="${boost_include_dir}"
        -DBOOST_INCLUDEDIR="${boost_include_dir}"
        -DBoost_INCLUDE_DIR="${boost_include_dir}"
        -DBoost_NO_BOOST_CMAKE=ON
        -DCMAKE_DISABLE_FIND_PACKAGE_OpenSSL=TRUE
        -DCMAKE_DISABLE_FIND_PACKAGE_GnuTLS=TRUE
        -DCMAKE_DISABLE_FIND_PACKAGE_LibGcrypt=TRUE
    )

    if [[ "${sdk}" == iphoneos || "${sdk}" == iphonesimulator ]]; then
        cmake_args+=(-DCMAKE_SYSTEM_NAME=iOS)
    fi

    cmake "${cmake_args[@]}" >&2
    cmake --build "${build_dir}" --config "${CONFIGURATION}" -j "${BUILD_JOBS}" >&2

    libtorrent_archive="$(find "${build_dir}" -name 'libtorrent-rasterbar.a' -print -quit)"
    if [[ -z "${libtorrent_archive}" ]]; then
        echo "error: failed to locate libtorrent-rasterbar.a for ${sdk}" >&2
        exit 1
    fi

    printf '%s\n' "${libtorrent_archive}"
}

build_bridge_archive_for_sdk() {
    local sdk="$1"
    local deployment_target="$2"
    local boost_include_dir="$3"
    shift 3
    local archs=("$@")
    local bridge_dir="${BUILD_DIR}/${sdk}/bridge"
    local sdk_path
    local cxx_compiler
    local deployment_flag
    local bridge_archives=()
    local arch

    rm -rf "${bridge_dir}"
    mkdir -p "${bridge_dir}"

    sdk_path="$(xcrun --sdk "${sdk}" --show-sdk-path)"
    cxx_compiler="$(xcrun --sdk "${sdk}" --find clang++)"

    case "${sdk}" in
        iphoneos)
            deployment_flag="-miphoneos-version-min=${deployment_target}"
            ;;
        iphonesimulator)
            deployment_flag="-mios-simulator-version-min=${deployment_target}"
            ;;
        macosx)
            deployment_flag="-mmacosx-version-min=${deployment_target}"
            ;;
        *)
            echo "error: unsupported sdk ${sdk}" >&2
            exit 1
            ;;
    esac

    for arch in "${archs[@]}"; do
        local object_path="${bridge_dir}/${FRAMEWORK_NAME}_${arch}.o"
        local archive_path="${bridge_dir}/${FRAMEWORK_NAME}_${arch}.a"

        "${cxx_compiler}" \
            -std=c++14 \
            -c "${NATIVE_BRIDGE_DIR}/src/libtorrent_apple_bridge.cpp" \
            -o "${object_path}" \
            -arch "${arch}" \
            -isysroot "${sdk_path}" \
            "${deployment_flag}" \
            -I"${NATIVE_BRIDGE_DIR}/include" \
            -I"${SOURCE_DIR}/include" \
            -I"${boost_include_dir}"

        libtool -static -o "${archive_path}" "${object_path}"
        bridge_archives+=("${archive_path}")
    done

    if [[ "${#bridge_archives[@]}" -eq 1 ]]; then
        cp "${bridge_archives[0]}" "$(bridge_archive_for_sdk "${sdk}")"
    else
        lipo -create "${bridge_archives[@]}" -output "$(bridge_archive_for_sdk "${sdk}")"
    fi
}

write_framework_bundle() {
    local sdk="$1"
    local deployment_target="$2"
    local libtorrent_archive="$3"
    local bridge_archive="$4"
    local framework_dir
    local headers_dir
    local modules_dir
    local resources_dir
    local binary_path
    local minimum_os_key="MinimumOSVersion"

    framework_dir="$(framework_dir_for_sdk "${sdk}")"

    rm -rf "${framework_dir}"
    if [[ "${sdk}" == macosx ]]; then
        local versions_dir="${framework_dir}/Versions"
        local version_dir="${versions_dir}/A"

        headers_dir="${version_dir}/Headers"
        modules_dir="${version_dir}/Modules"
        resources_dir="${version_dir}/Resources"
        binary_path="${version_dir}/${FRAMEWORK_NAME}"
        minimum_os_key="LSMinimumSystemVersion"

        mkdir -p "${headers_dir}" "${modules_dir}" "${resources_dir}"
        mkdir -p "${versions_dir}"
        ln -sfn "A" "${versions_dir}/Current"
        ln -sfn "Versions/Current/Headers" "${framework_dir}/Headers"
        ln -sfn "Versions/Current/Modules" "${framework_dir}/Modules"
        ln -sfn "Versions/Current/Resources" "${framework_dir}/Resources"
        ln -sfn "Versions/Current/${FRAMEWORK_NAME}" "${framework_dir}/${FRAMEWORK_NAME}"
    else
        headers_dir="${framework_dir}/Headers"
        modules_dir="${framework_dir}/Modules"
        resources_dir="${framework_dir}"
        binary_path="${framework_dir}/${FRAMEWORK_NAME}"

        mkdir -p "${headers_dir}" "${modules_dir}"
    fi

    libtool -static -o "${binary_path}" "${bridge_archive}" "${libtorrent_archive}"

    cp "${NATIVE_BRIDGE_DIR}/include/LibtorrentAppleBinary.h" "${headers_dir}/LibtorrentAppleBinary.h"
    cp "${NATIVE_BRIDGE_DIR}/include/libtorrent_apple_bridge.h" "${headers_dir}/libtorrent_apple_bridge.h"

    cat > "${modules_dir}/module.modulemap" <<EOF
framework module ${FRAMEWORK_NAME} {
    umbrella header "LibtorrentAppleBinary.h"

    export *
    module * { export * }
}
EOF

    cat > "${resources_dir}/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>${FRAMEWORK_NAME}</string>
    <key>CFBundleIdentifier</key>
    <string>io.github.zhangzhenghong.${FRAMEWORK_NAME}.${sdk}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${FRAMEWORK_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>FMWK</string>
    <key>CFBundleShortVersionString</key>
    <string>${LIBTORRENT_REF_RESOLVED:-dev}</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>${minimum_os_key}</key>
    <string>${deployment_target}</string>
</dict>
</plist>
EOF

    cat > "${BUILD_DIR}/${sdk}/BUILD_METADATA.env" <<EOF
SDK=${sdk}
CONFIGURATION=${CONFIGURATION}
FRAMEWORK_NAME=${FRAMEWORK_NAME}
FRAMEWORK_PATH=${framework_dir}
LIBTORRENT_ARCHIVE=${libtorrent_archive}
BRIDGE_ARCHIVE=${bridge_archive}
LIBTORRENT_REPO_URL=${LIBTORRENT_REPO_URL:-unknown}
LIBTORRENT_REF_REQUESTED=${LIBTORRENT_REF_REQUESTED:-unknown}
LIBTORRENT_REF_RESOLVED=${LIBTORRENT_REF_RESOLVED:-unknown}
LIBTORRENT_COMMIT_SHA=${LIBTORRENT_COMMIT_SHA:-unknown}
BOOST_VERSION=${BOOST_VERSION}
BOOST_SOURCE_URL=${BOOST_SOURCE_URL}
BOOST_INCLUDE_DIR=${BOOST_INCLUDE_DIR_USED}
REQUIRED_SYSTEM_FRAMEWORKS=CFNetwork,CoreFoundation,Security,SystemConfiguration
REQUIRED_LINK_LIBRARIES=libc++
EOF
}

require_command cmake
require_command curl
require_command git
require_command libtool
require_command lipo
require_command tar
require_command xcodebuild
require_command xcrun

mkdir -p "${BUILD_DIR}"
mkdir -p "${CLANG_MODULE_CACHE_PATH}"

export CLANG_MODULE_CACHE_PATH

BOOST_INCLUDE_DIR_USED="$(prepare_boost_headers)"

for sdk in "${SDKS[@]}"; do
    case "${sdk}" in
        iphoneos)
            deployment_target="${IOS_DEPLOYMENT_TARGET}"
            archs=(arm64)
            ;;
        iphonesimulator)
            deployment_target="${IOS_DEPLOYMENT_TARGET}"
            archs=(arm64 x86_64)
            ;;
        macosx)
            deployment_target="${MACOS_DEPLOYMENT_TARGET}"
            archs=(arm64 x86_64)
            ;;
        *)
            echo "error: unsupported sdk ${sdk}" >&2
            exit 1
            ;;
    esac

    mkdir -p "${BUILD_DIR}/${sdk}"

    libtorrent_archive="$(build_libtorrent_for_sdk "${sdk}" "${deployment_target}" "${BOOST_INCLUDE_DIR_USED}" "${archs[@]}")"
    build_bridge_archive_for_sdk "${sdk}" "${deployment_target}" "${BOOST_INCLUDE_DIR_USED}" "${archs[@]}"
    bridge_archive="$(bridge_archive_for_sdk "${sdk}")"
    write_framework_bundle "${sdk}" "${deployment_target}" "${libtorrent_archive}" "${bridge_archive}"

    echo "Built ${FRAMEWORK_NAME}.framework for ${sdk}"
done

echo "Built native frameworks for libtorrent ${LIBTORRENT_REF_RESOLVED:-unknown}."
