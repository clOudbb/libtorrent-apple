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
HTTPS_TRACKER_BACKEND="${HTTPS_TRACKER_BACKEND:-openssl}"
IPHONEOS_ARCHS="${IPHONEOS_ARCHS:-arm64}"
IPHONESIMULATOR_ARCHS="${IPHONESIMULATOR_ARCHS:-arm64 x86_64}"
MACOSX_ARCHS="${MACOSX_ARCHS:-arm64 x86_64}"

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

resolve_absolute_path() {
    local input_path="$1"

    if [[ -d "${input_path}" ]]; then
        (
            cd "${input_path}"
            pwd
        )
        return
    fi

    if [[ -e "${input_path}" ]]; then
        (
            cd "$(dirname "${input_path}")"
            printf '%s/%s\n' "$(pwd)" "$(basename "${input_path}")"
        )
        return
    fi

    echo "error: path does not exist: ${input_path}" >&2
    exit 1
}

prepare_boost_headers() {
    if [[ -n "${BOOST_INCLUDE_DIR:-}" ]]; then
        if [[ ! -f "${BOOST_INCLUDE_DIR}/boost/config.hpp" ]]; then
            echo "error: BOOST_INCLUDE_DIR does not contain boost/config.hpp: ${BOOST_INCLUDE_DIR}" >&2
            exit 1
        fi

        resolve_absolute_path "${BOOST_INCLUDE_DIR}"
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

    resolve_absolute_path "${boost_source_root}"
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

sdk_env_suffix() {
    printf '%s\n' "$1" | tr '[:lower:]-' '[:upper:]_'
}

resolve_sdk_env_value() {
    local base_name="$1"
    local sdk="$2"
    local sdk_suffix
    local sdk_key

    sdk_suffix="$(sdk_env_suffix "${sdk}")"
    sdk_key="${base_name}_${sdk_suffix}"

    if [[ -n "${!sdk_key:-}" ]]; then
        printf '%s\n' "${!sdk_key}"
        return
    fi

    printf '%s\n' "${!base_name:-}"
}

first_existing_path() {
    local path
    for path in "$@"; do
        if [[ -e "${path}" ]]; then
            printf '%s\n' "${path}"
            return 0
        fi
    done

    return 1
}

CURRENT_OPENSSL_INCLUDE_DIR=""
CURRENT_OPENSSL_SSL_LIBRARY=""
CURRENT_OPENSSL_CRYPTO_LIBRARY=""
CURRENT_EXTRA_ARCHIVES=()
CURRENT_FRAMEWORK_ARCHS=()
OPENSSL_SUPPORT_ROOT=""
OPENSSL_SUPPORT_PREPARED=0

prepare_local_openssl_support() {
    local candidate
    local repo_head
    local extraction_root

    if [[ "${HTTPS_TRACKER_BACKEND}" != "openssl" ]]; then
        return
    fi

    if [[ "${OPENSSL_SUPPORT_PREPARED}" == "1" ]]; then
        return
    fi

    OPENSSL_SUPPORT_PREPARED=1

    if [[ -n "${OPENSSL_UNIVERSAL_DIR:-}" ]]; then
        if [[ ! -d "${OPENSSL_UNIVERSAL_DIR}" ]]; then
            echo "error: OPENSSL_UNIVERSAL_DIR does not exist: ${OPENSSL_UNIVERSAL_DIR}" >&2
            exit 1
        fi

        if [[ -f "${OPENSSL_UNIVERSAL_DIR}/macosx/lib/libssl.a" ]]; then
            OPENSSL_SUPPORT_ROOT="$(resolve_absolute_path "${OPENSSL_UNIVERSAL_DIR}")"
            return
        fi

        echo "error: OPENSSL_UNIVERSAL_DIR must point to an OpenSSL-Universal checkout containing <sdk>/lib/libssl.a." >&2
        exit 1
    fi

    for candidate in \
        "${ROOT_DIR}/Vendor/OpenSSL" \
        "${ROOT_DIR}/Vendor/OpenSSL-Universal" \
        "${HOME}/Library/Caches/org.swift.swiftpm/repositories"/OpenSSL-*; do
        [[ -e "${candidate}" ]] || continue

        if [[ -f "${candidate}/macosx/lib/libssl.a" ]]; then
            OPENSSL_SUPPORT_ROOT="$(resolve_absolute_path "${candidate}")"
            return
        fi

        if ! git --git-dir="${candidate}" cat-file -e HEAD:macosx/lib/libssl.a >/dev/null 2>&1; then
            continue
        fi

        repo_head="$(git --git-dir="${candidate}" rev-parse HEAD)"
        extraction_root="${BUILD_DIR}/vendor/openssl-universal/${repo_head}"

        if [[ ! -f "${extraction_root}/.source-head" ]] || [[ "$(cat "${extraction_root}/.source-head")" != "${repo_head}" ]]; then
            rm -rf "${extraction_root}"
            mkdir -p "${extraction_root}"
            git --git-dir="${candidate}" archive HEAD \
                iphoneos/include \
                iphoneos/lib \
                iphonesimulator/include \
                iphonesimulator/lib \
                macosx/include \
                macosx/lib | tar -xf - -C "${extraction_root}"
            printf '%s\n' "${repo_head}" > "${extraction_root}/.source-head"
        fi

        OPENSSL_SUPPORT_ROOT="$(resolve_absolute_path "${extraction_root}")"
        return
    done
}

configure_crypto_backend_for_sdk() {
    local sdk="$1"
    local sdk_suffix
    local openssl_sdk_dir=""

    CURRENT_OPENSSL_INCLUDE_DIR=""
    CURRENT_OPENSSL_SSL_LIBRARY=""
    CURRENT_OPENSSL_CRYPTO_LIBRARY=""
    CURRENT_EXTRA_ARCHIVES=()

    if [[ "${HTTPS_TRACKER_BACKEND}" != "openssl" ]]; then
        return
    fi

    sdk_suffix="$(sdk_env_suffix "${sdk}")"

    CURRENT_OPENSSL_INCLUDE_DIR="$(resolve_sdk_env_value OPENSSL_INCLUDE_DIR "${sdk}")"
    CURRENT_OPENSSL_SSL_LIBRARY="$(resolve_sdk_env_value OPENSSL_SSL_LIBRARY "${sdk}")"
    CURRENT_OPENSSL_CRYPTO_LIBRARY="$(resolve_sdk_env_value OPENSSL_CRYPTO_LIBRARY "${sdk}")"

    if [[ -z "${CURRENT_OPENSSL_INCLUDE_DIR}" || -z "${CURRENT_OPENSSL_SSL_LIBRARY}" || -z "${CURRENT_OPENSSL_CRYPTO_LIBRARY}" ]]; then
        prepare_local_openssl_support

        if [[ -n "${OPENSSL_SUPPORT_ROOT}" ]]; then
            openssl_sdk_dir="${OPENSSL_SUPPORT_ROOT}/${sdk}"
            if [[ -z "${CURRENT_OPENSSL_INCLUDE_DIR}" && -d "${openssl_sdk_dir}/include" ]]; then
                CURRENT_OPENSSL_INCLUDE_DIR="${openssl_sdk_dir}/include"
            fi
            if [[ -z "${CURRENT_OPENSSL_SSL_LIBRARY}" && -f "${openssl_sdk_dir}/lib/libssl.a" ]]; then
                CURRENT_OPENSSL_SSL_LIBRARY="${openssl_sdk_dir}/lib/libssl.a"
            fi
            if [[ -z "${CURRENT_OPENSSL_CRYPTO_LIBRARY}" && -f "${openssl_sdk_dir}/lib/libcrypto.a" ]]; then
                CURRENT_OPENSSL_CRYPTO_LIBRARY="${openssl_sdk_dir}/lib/libcrypto.a"
            fi
        fi
    fi

    if [[ "${sdk}" == macosx ]]; then
        if [[ -z "${CURRENT_OPENSSL_INCLUDE_DIR}" ]]; then
            CURRENT_OPENSSL_INCLUDE_DIR="$(
                first_existing_path \
                    /opt/homebrew/opt/openssl@3/include \
                    /usr/local/opt/openssl@3/include \
                    /opt/homebrew/opt/openssl/include \
                    /usr/local/opt/openssl/include \
                    /usr/local/Cellar/openssl@3/*/include \
                || true
            )"
        fi

        if [[ -z "${CURRENT_OPENSSL_SSL_LIBRARY}" ]]; then
            CURRENT_OPENSSL_SSL_LIBRARY="$(
                first_existing_path \
                    /opt/homebrew/opt/openssl@3/lib/libssl.a \
                    /usr/local/opt/openssl@3/lib/libssl.a \
                    /opt/homebrew/opt/openssl/lib/libssl.a \
                    /usr/local/opt/openssl/lib/libssl.a \
                    /usr/local/Cellar/openssl@3/*/lib/libssl.a \
                || true
            )"
        fi

        if [[ -z "${CURRENT_OPENSSL_CRYPTO_LIBRARY}" ]]; then
            CURRENT_OPENSSL_CRYPTO_LIBRARY="$(
                first_existing_path \
                    /opt/homebrew/opt/openssl@3/lib/libcrypto.a \
                    /usr/local/opt/openssl@3/lib/libcrypto.a \
                    /opt/homebrew/opt/openssl/lib/libcrypto.a \
                    /usr/local/opt/openssl/lib/libcrypto.a \
                    /usr/local/Cellar/openssl@3/*/lib/libcrypto.a \
                || true
            )"
        fi
    fi

    if [[ -z "${CURRENT_OPENSSL_INCLUDE_DIR}" || -z "${CURRENT_OPENSSL_SSL_LIBRARY}" || -z "${CURRENT_OPENSSL_CRYPTO_LIBRARY}" ]]; then
        echo "error: HTTPS_TRACKER_BACKEND=openssl requires Apple-platform OpenSSL paths for ${sdk}." >&2
        echo "Set OPENSSL_INCLUDE_DIR_${sdk_suffix}, OPENSSL_SSL_LIBRARY_${sdk_suffix}, and OPENSSL_CRYPTO_LIBRARY_${sdk_suffix} (or generic OPENSSL_*)." >&2
        echo "You can also point OPENSSL_UNIVERSAL_DIR at a local OpenSSL-Universal checkout." >&2
        exit 1
    fi

    CURRENT_EXTRA_ARCHIVES=("${CURRENT_OPENSSL_SSL_LIBRARY}" "${CURRENT_OPENSSL_CRYPTO_LIBRARY}")
}

thin_archive_to_current_archs() {
    local input_archive="$1"
    local output_archive="$2"
    local output_dir
    local base_name
    local arch
    local available_archs
    local arch_count
    local thinned_archives=()

    output_dir="$(dirname "${output_archive}")"
    base_name="$(basename "${output_archive}" .a)"

    mkdir -p "${output_dir}"
    rm -f "${output_archive}"
    available_archs="$(xcrun lipo -archs "${input_archive}")"
    arch_count="$(printf '%s\n' "${available_archs}" | wc -w | tr -d ' ')"

    if [[ "${#CURRENT_FRAMEWORK_ARCHS[@]}" -eq 0 ]]; then
        cp "${input_archive}" "${output_archive}"
        return
    fi

    if [[ "${#CURRENT_FRAMEWORK_ARCHS[@]}" -eq 1 ]]; then
        if ! printf '%s\n' "${available_archs}" | tr ' ' '\n' | grep -qx "${CURRENT_FRAMEWORK_ARCHS[0]}"; then
            echo "error: archive ${input_archive} does not contain architecture ${CURRENT_FRAMEWORK_ARCHS[0]}" >&2
            exit 1
        fi

        if [[ "${arch_count}" == "1" ]]; then
            cp "${input_archive}" "${output_archive}"
        else
            lipo -thin "${CURRENT_FRAMEWORK_ARCHS[0]}" "${input_archive}" -output "${output_archive}"
        fi
        return
    fi

    for arch in "${CURRENT_FRAMEWORK_ARCHS[@]}"; do
        local arch_archive="${output_dir}/${base_name}-${arch}.a"

        if ! printf '%s\n' "${available_archs}" | tr ' ' '\n' | grep -qx "${arch}"; then
            echo "error: archive ${input_archive} does not contain architecture ${arch}" >&2
            exit 1
        fi

        if [[ "${arch_count}" == "1" ]]; then
            cp "${input_archive}" "${arch_archive}"
        else
            lipo -thin "${arch}" "${input_archive}" -output "${arch_archive}"
        fi
        thinned_archives+=("${arch_archive}")
    done

    lipo -create "${thinned_archives[@]}" -output "${output_archive}"
    rm -f "${thinned_archives[@]}"
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
    )

    if [[ "${HTTPS_TRACKER_BACKEND}" == "openssl" ]]; then
        cmake_args+=(
            -DOPENSSL_USE_STATIC_LIBS=TRUE
            -DOPENSSL_INCLUDE_DIR="${CURRENT_OPENSSL_INCLUDE_DIR}"
            -DOPENSSL_SSL_LIBRARY="${CURRENT_OPENSSL_SSL_LIBRARY}"
            -DOPENSSL_CRYPTO_LIBRARY="${CURRENT_OPENSSL_CRYPTO_LIBRARY}"
        )
    fi

    case "${HTTPS_TRACKER_BACKEND}" in
        auto)
            ;;
        openssl)
            cmake_args+=(-Dgnutls=OFF)
            ;;
        gnutls)
            cmake_args+=(-Dgnutls=ON)
            ;;
        disabled)
            cmake_args+=(
                -DCMAKE_DISABLE_FIND_PACKAGE_OpenSSL=TRUE
                -DCMAKE_DISABLE_FIND_PACKAGE_GnuTLS=TRUE
                -DCMAKE_DISABLE_FIND_PACKAGE_LibGcrypt=TRUE
            )
            ;;
        *)
            echo "error: HTTPS_TRACKER_BACKEND must be one of: auto|openssl|gnutls|disabled" >&2
            exit 1
            ;;
    esac

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
    local bridge_cflags=()
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

    case "${HTTPS_TRACKER_BACKEND}" in
        openssl)
            bridge_cflags+=(-DTORRENT_USE_SSL=1 -DTORRENT_USE_OPENSSL=1)
            if [[ -n "${CURRENT_OPENSSL_INCLUDE_DIR}" ]]; then
                bridge_cflags+=(-I"${CURRENT_OPENSSL_INCLUDE_DIR}")
            fi
            ;;
        gnutls)
            bridge_cflags+=(-DTORRENT_USE_SSL=1 -DTORRENT_USE_GNUTLS=1)
            ;;
        auto)
            if [[ -n "${CURRENT_OPENSSL_INCLUDE_DIR}" && -n "${CURRENT_OPENSSL_SSL_LIBRARY}" && -n "${CURRENT_OPENSSL_CRYPTO_LIBRARY}" ]]; then
                bridge_cflags+=(-DTORRENT_USE_SSL=1 -DTORRENT_USE_OPENSSL=1 -I"${CURRENT_OPENSSL_INCLUDE_DIR}")
            fi
            ;;
        disabled)
            bridge_cflags+=(-DTORRENT_USE_SSL=0)
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
            -I"${boost_include_dir}" \
            "${bridge_cflags[@]}"

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
    shift 4
    local extra_archives=("$@")
    local thinned_extra_archives=()
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

    if [[ "${#extra_archives[@]}" -gt 0 ]]; then
        local extra_archives_dir="${BUILD_DIR}/${sdk}/thinned-extra-archives"
        local extra_archive_index=0
        local extra_archive

        rm -rf "${extra_archives_dir}"
        mkdir -p "${extra_archives_dir}"

        for extra_archive in "${extra_archives[@]}"; do
            local thinned_archive_path="${extra_archives_dir}/$(basename "${extra_archive}" .a)-${extra_archive_index}.a"
            thin_archive_to_current_archs "${extra_archive}" "${thinned_archive_path}"
            thinned_extra_archives+=("${thinned_archive_path}")
            ((extra_archive_index += 1))
        done
    fi

    libtool -static -o "${binary_path}" "${bridge_archive}" "${libtorrent_archive}" "${thinned_extra_archives[@]}"

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
HTTPS_TRACKER_BACKEND=${HTTPS_TRACKER_BACKEND}
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
            read -r -a archs <<< "${IPHONEOS_ARCHS}"
            ;;
        iphonesimulator)
            deployment_target="${IOS_DEPLOYMENT_TARGET}"
            read -r -a archs <<< "${IPHONESIMULATOR_ARCHS}"
            ;;
        macosx)
            deployment_target="${MACOS_DEPLOYMENT_TARGET}"
            read -r -a archs <<< "${MACOSX_ARCHS}"
            ;;
        *)
            echo "error: unsupported sdk ${sdk}" >&2
            exit 1
            ;;
    esac

    mkdir -p "${BUILD_DIR}/${sdk}"
    CURRENT_FRAMEWORK_ARCHS=("${archs[@]}")
    configure_crypto_backend_for_sdk "${sdk}"

    libtorrent_archive="$(build_libtorrent_for_sdk "${sdk}" "${deployment_target}" "${BOOST_INCLUDE_DIR_USED}" "${archs[@]}")"
    build_bridge_archive_for_sdk "${sdk}" "${deployment_target}" "${BOOST_INCLUDE_DIR_USED}" "${archs[@]}"
    bridge_archive="$(bridge_archive_for_sdk "${sdk}")"
    write_framework_bundle "${sdk}" "${deployment_target}" "${libtorrent_archive}" "${bridge_archive}" "${CURRENT_EXTRA_ARCHIVES[@]}"

    echo "Built ${FRAMEWORK_NAME}.framework for ${sdk}"
done

echo "Built native frameworks for libtorrent ${LIBTORRENT_REF_RESOLVED:-unknown}."
