# libtorrent-apple

Apple-focused libtorrent packaging repo for iOS and macOS.

## Status

This repository now provides:
- a SwiftPM-ready wrapper product exposed as `LibtorrentApple`
- an internal binary framework target packaged as `LibtorrentAppleBinary.xcframework`
- a real Apple native build pipeline for `libtorrent`
- a native C bridge packaged into `LibtorrentAppleBinary.framework`
- release automation that assembles an `XCFramework`

The end state is:
- apps depend on the Swift package product `LibtorrentApple`
- that Swift target internally depends on the binary target `LibtorrentAppleBinary`
- the binary target resolves to a GitHub Release-hosted `LibtorrentAppleBinary.xcframework.zip`

The execution roadmap for API stabilization and milestone tracking lives in [MILESTONES.md](MILESTONES.md).
The current v1 floor is explicit there: the Swift API must reach at least capability parity with `open-ani/anitorrent`.
That roadmap also records a fixed reference snapshot for both `iTorrent` and `anitorrent`, so future work can follow the same baseline without re-checking those projects every time.

Current state:
- the v1 Swift API floor has been implemented and validated in both source-mode and local-binary mode
- the repository is release-ready for a GitHub Release upload of the generated `LibtorrentAppleBinary.xcframework.zip`

## Current Swift API

- `TorrentSession` is backed by the native bridge for start, stop, add magnet, add `.torrent`, pause, resume, remove, and status queries
- `TorrentHandle` now provides Swift control for status, pause, resume, remove, save-directory lookup, native resume export, `.torrent` metadata export, file listing, trackers, tracker replacement and addition, peers, pieces, file-priority changes, sequential download, recheck, reannounce, storage move, piece priorities, and piece deadlines
- `TorrentFile` and `TorrentFileHandle` now provide a first-class Swift file surface for file enumeration plus file-scoped priority, pause, resume, include or exclude, and local data deletion semantics
- `TorrentTracker`, `TorrentPeer`, and `TorrentPiece` now provide public Swift models for tracker state, peer state, and piece-aware inspection
- `TorrentDownloadController` now provides streaming-oriented control with piece snapshots, piece update streams, sequential mode, file prioritization, piece prioritization, piece deadlines, and playback-oriented prefetch preparation
- `TorrentDownloader` now provides downloader-level vendor info, aggregate stats, stats update streams, encoded torrent intake, managed torrent-file storage, snapshot persistence, and torrent metadata fetch from `file://`, `http(s)://`, and magnet links
- `alerts()` now streams both high-level wrapper events and strongly typed high-frequency native libtorrent alerts exposed through the bridge
- native resume data import and export are both implemented through the Swift API
- `exportResumeData()` and `restoreResumeData()` still provide the repository's JSON snapshot layer for whole-session restore
- `SessionConfiguration` now covers listen interfaces, DHT/LSD/UPnP/NAT-PMP, alert mask, user agent, handshake version, upload/download limits, connection limits, queue limits, cache and send-buffer policy, auto-sequential mode, proxy settings, and protocol-encryption policy

## v1 Status

The repository has reached its intended v1 API floor:
- downloader/session/handle/file/piece/tracker/peer surfaces are all public
- the API is at least capability-parity with the reference `anitorrent` roles recorded in `MILESTONES.md`
- the engine-level workflows visible in `iTorrent` are covered at the SDK level:
  - magnet and `.torrent` intake
  - HTTP(S) `.torrent` metadata fetch
  - file selection and file priority
  - sequential download and playback-oriented piece control
  - tracker query, replacement, addition, and reannounce
  - resume export and restore
  - session stats and piece-progress streams

Post-v1 improvements remain possible, but they are no longer blockers for `1.0.0`.

## Package Architecture

- Public SwiftPM product: `LibtorrentApple`
- Internal binary target: `LibtorrentAppleBinary`
- Local development modes:
  - `LIBTORRENT_APPLE_PACKAGE_MODE=source`
  - `LIBTORRENT_APPLE_PACKAGE_MODE=local-binary`
- Release/default mode:
  - `PackageSupport/BinaryArtifact.env` drives the remote `binaryTarget` URL + checksum

Consumer shape after the release asset is uploaded:

```swift
.package(url: "https://github.com/clOudbb/libtorrent-apple.git", from: "0.1.2")
```

```swift
import LibtorrentApple
```

## Layout

```text
PackageSupport/
  BinaryArtifact.env
Sources/
  LibtorrentApple/
    Models/
    Errors/
    Session/
  LibtorrentAppleBridge/
    include/
scripts/
.github/workflows/
```

## Local Validation

Validate the source bridge mode:

```bash
./scripts/validate-swift-package.sh source
```

Validate the local binary package mode after generating the XCFramework:

```bash
./scripts/validate-swift-package.sh local-binary
```

The binary packaging pipeline is real:

```bash
./scripts/sync-libtorrent.sh
./scripts/build-apple-libs.sh
./scripts/smoke-test-macos-framework.sh
./scripts/make-xcframework.sh 0.1.2
```

Outputs:
- `Build/apple/iphoneos/LibtorrentAppleBinary.framework`
- `Build/apple/iphonesimulator/LibtorrentAppleBinary.framework`
- `Build/apple/macosx/LibtorrentAppleBinary.framework`
- `Artifacts/release/LibtorrentAppleBinary.xcframework`
- `Artifacts/release/LibtorrentAppleBinary-<version>.zip`
- `Artifacts/release/LibtorrentAppleBinary-<version>.binary-target.swift`
- `Artifacts/release/LibtorrentAppleBinary-<version>.release-notes.md`

## Upstream Version Strategy

The default behavior is to build from a pinned libtorrent ref declared in `scripts/versions.env`.
That keeps local builds and CI reproducible, while still allowing anyone to self-package a newer upstream version on demand.

If you explicitly want the newest upstream release tag, run:

```bash
LIBTORRENT_REF=latest ./scripts/sync-libtorrent.sh
```

If you want a specific upstream version for one release:

```bash
LIBTORRENT_REF=v2.0.11 ./scripts/release.sh 0.1.0
```

The chosen upstream repo/ref is threaded through:
- `scripts/sync-libtorrent.sh`
- `scripts/build-apple-libs.sh`
- `scripts/make-xcframework.sh`
- `scripts/release.sh`

That metadata is written into local build outputs and release metadata so the final framework can always be traced back to the exact libtorrent source version it was built from.

## Dependency Strategy

The repository does not require locally prebuilt `libtorrent`, `boost`, or `openssl` artifacts.

- `libtorrent` is synced from the configured upstream repo/ref using `git clone --recurse-submodules`
- Boost is used in header-only mode for the current CMake path and is downloaded automatically unless `BOOST_INCLUDE_DIR` is provided
- Apple builds use the platform crypto stack instead of OpenSSL by default, which keeps the self-build path much simpler

You can override the defaults inline:

```bash
LIBTORRENT_REF=latest ./scripts/release.sh 0.1.0
```

```bash
BOOST_INCLUDE_DIR=/absolute/path/to/boost_1_76_0 ./scripts/build-apple-libs.sh
```

If you do not provide `BOOST_INCLUDE_DIR`, the build script will fetch the pinned Boost source tarball declared in `scripts/versions.env` and use its headers automatically.

## Tooling Requirements

- Xcode 16+ command line tools
- `cmake`
- `git`
- `curl`

If `cmake` is missing, install it first:

```bash
brew install cmake
```

## Release Pipeline

The repository includes template automation for:
- syncing libtorrent source
- building Apple platform artifacts
- smoke-testing the macOS framework slice
- assembling an `XCFramework`
- zipping and computing a SwiftPM checksum
- updating `PackageSupport/BinaryArtifact.env`
- generating a ready-to-paste `binaryTarget` snippet
- creating or updating a GitHub Release with `gh` + `GITHUB_TOKEN`

GitHub Actions can now run the pipeline in two ways:
- manual `workflow_dispatch`
- automatic `push` on tags matching `v*`

Practical caveat:
- the tag-triggered workflow can compile and upload release assets automatically
- SwiftPM remote binary releases still need the tagged commit to contain the matching `PackageSupport/BinaryArtifact.env`
- because the checksum is only known after packaging, the fully reproducible release flow is still best handled as a staged process: build assets first, commit the updated binary metadata, then create the final tag

The current binary framework exposes a small native C bridge in `NativeBridge/`, and the Swift wrapper in `Sources/LibtorrentApple/` now sits on top of that bridge for both source-mode and binary-mode validation.

If you integrate the raw framework manually instead of using a package wrapper, also link:
- `CFNetwork`
- `CoreFoundation`
- `Security`
- `SystemConfiguration`
- `libc++`
