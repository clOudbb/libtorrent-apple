# libtorrent 2.1.0 Upgrade Design

## Context

The repository currently pins libtorrent `v2.0.13`. The latest stable upstream release is `v2.1.0`. libtorrent 2.1 requires C++17 and introduces WebTorrent support, enabled by default. WebTorrent adds WebRTC-related dependencies and a larger network attack surface.

## Chosen Approach

Upgrade the pinned dependency to stable libtorrent `v2.1.0` while preserving the SDK's current product scope:

- Compile libtorrent and the native bridge as C++17.
- Pass `-Dwebtorrent=OFF` explicitly to the libtorrent CMake build.
- Keep the existing Swift and C bridge APIs unchanged unless compilation against 2.1.0 requires a compatibility adjustment.
- Do not change the public `libtorrent-apple` package version or published binary artifact metadata as part of this dependency-source update.

This avoids silently adding WebRTC behavior and dependencies. Standard BitTorrent operation—including TCP, uTP, DHT, PEX, LSD, magnet links, torrent files, and HTTP/HTTPS/UDP trackers—remains enabled.

## Files and Responsibilities

- `scripts/versions.env`: pin the reproducible libtorrent source ref to `v2.1.0`.
- `scripts/build-apple-libs.sh`: select C++17 for libtorrent and the native bridge, and explicitly disable WebTorrent.
- `NativeBridge/src/libtorrent_apple_bridge.cpp`: receive only compatibility changes proven necessary by a 2.1.0 build.
- `README.md`: update all libtorrent version references and document the WebTorrent build policy in English.
- `README.zh-CN.md`: mirror the version and WebTorrent policy in Chinese.

## Build and Data Flow

`scripts/sync-libtorrent.sh` resolves the pinned `v2.1.0` tag and writes the resolved tag and commit SHA into the ignored vendor checkout. `scripts/build-apple-libs.sh` then configures each Apple SDK build with C++17 and `webtorrent=OFF`, compiles the C++ bridge with the same language standard, and packages the resulting static libraries into Apple frameworks.

No runtime configuration or public API is added for WebTorrent because the feature is not compiled into the binary.

## Failure Handling

Existing fail-fast shell behavior remains in place. Source synchronization fails when `v2.1.0` cannot be resolved, CMake configuration fails when the toolchain or dependency set is incompatible, and compilation exposes any native bridge API changes that must be addressed explicitly.

## Verification

Verification will cover:

1. The default source sync resolves exactly to `v2.1.0`.
2. The Apple native build accepts C++17 and `webtorrent=OFF`.
3. The native bridge compiles against libtorrent 2.1.0.
4. The macOS framework smoke test passes.
5. Repository searches show no stale `v2.0.13` documentation or default dependency references.
6. The English and Chinese README files state that WebTorrent is disabled and distinguish it from standard BitTorrent and tracker support.

## Out of Scope

- Exposing WebTorrent, WebRTC, STUN, or WebSocket tracker configuration.
- Publishing a new `libtorrent-apple` release or replacing its binary artifact.
- Changing OpenSSL or Boost versions unless the libtorrent 2.1.0 build proves that a change is required.
