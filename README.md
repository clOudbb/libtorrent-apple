# libtorrent-apple

[中文说明](README.zh-CN.md)

`libtorrent-apple` is a SwiftPM-friendly Apple SDK built on top of `libtorrent`.
It packages a real multi-platform `XCFramework`, exposes a Swift-first API, and keeps the C or C++ boundary hidden behind the package.

## What This Repo Gives You

- A public SwiftPM product: `LibtorrentApple`
- An internal binary target: `LibtorrentAppleBinary`
- Apple builds for `iOS device`, `iOS simulator`, and `macOS`
- A release pipeline that produces a GitHub Release-hosted `XCFramework` zip for SwiftPM
- A Swift API that already covers the core BitTorrent engine workflows used by projects like `iTorrent` and `anitorrent`

## Quick Start

Add the package:

```swift
.package(url: "https://github.com/clOudbb/libtorrent-apple.git", from: "0.1.4")
```

Then import:

```swift
import LibtorrentApple
```

## Main Types

- `TorrentDownloader`: higher-level entry point with managed directories, metadata fetch, and resume snapshots
- `TorrentSession`: lower-level session actor for direct torrent lifecycle control
- `TorrentHandle`: torrent-scoped control surface
- `TorrentFileHandle`: file-scoped control surface
- `TorrentDownloadController`: streaming-oriented piece and file prioritization API
- `SessionConfiguration`: session settings for ports, limits, proxy, encryption, and network behavior

## Basic Usage

### 1. Start a downloader and add a magnet link

```swift
import Foundation
import LibtorrentApple

let downloader = TorrentDownloader(
    configuration: SessionConfiguration(
        downloadDirectory: FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
    )
)

try await downloader.start()

let handle = try await downloader.addTorrent(
    from: .magnetLink(
        URL(string: "magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567")!,
        displayName: "Ubuntu ISO"
    )
)

let status = try await handle.status()
print(status.name)
print(status.metrics.progress)
```

### 2. Add a local `.torrent` file

```swift
let torrentURL = URL(fileURLWithPath: "/path/to/file.torrent")

let handle = try await downloader.addTorrent(
    from: .torrentFile(torrentURL, displayName: "Episode 01")
)

let files = try await handle.files()
print(files.map(\.path))
```

### 3. Observe alerts and aggregate stats

```swift
Task {
    let alerts = await downloader.alerts()
    for await alert in alerts {
        print("[\(alert.kind.rawValue)] \(alert.message)")
    }
}

Task {
    let statsStream = await downloader.statsUpdates(pollInterval: 1)
    for await stats in statsStream {
        print("running torrents:", stats.runningTorrentCount)
        print("download rate:", stats.aggregateDownloadRateBytesPerSecond)
    }
}
```

### 4. Streaming-oriented control

```swift
let controller = try await handle.downloadController()

let snapshot = try await controller.prepareForStreaming(
    fileIndex: 0,
    leadPieceCount: 8,
    deadlineMilliseconds: 1_500,
    includeOnlySelectedFile: true
)

print(snapshot.progress)

Task {
    let pieceUpdates = controller.updates(pollInterval: 1)
    for try await nextSnapshot in pieceUpdates {
        print("completed pieces:", nextSnapshot.completedPieceCount)
    }
}
```

### 5. Apply animeko parity strategy and peer filters

```swift
var configuration = SessionConfiguration(downloadDirectory: downloader.defaultSaveDirectory())
configuration.shareRatioLimit = 200
configuration.applyProfile(.animekoParityV1)

let parityDownloader = TorrentDownloader(configuration: configuration)
try await parityDownloader.start()
try await parityDownloader.applyProfile(.animekoParityV1)
try await parityDownloader.setPeerFilters(
    blockedCIDRs: ["10.0.0.0/8"],
    allowedCIDRs: []
)
```

### 5. File priorities, trackers, and torrent control

```swift
_ = try await handle.setFilePriority(.high, at: 0)
try await handle.setSequentialDownload(true)
try await handle.forceReannounce(after: 0, ignoreMinimumInterval: true)

_ = try await handle.replaceTrackers([
    TorrentTrackerUpdate(url: "https://tracker-1.example/announce", tier: 0),
    TorrentTrackerUpdate(url: "https://tracker-2.example/announce", tier: 1),
])

let trackers = try await handle.trackers()
let peers = try await handle.peers()
let pieces = try await handle.pieces()

print(trackers.count, peers.count, pieces.count)
```

### 6. Save and restore

Repository-level JSON snapshot:

```swift
let snapshotURL = try await downloader.persistResumeSnapshot(named: "default")
print(snapshotURL.path)

try await downloader.restoreLatestResumeSnapshot()
```

Native per-torrent resume data:

```swift
let nativeResumeData = try await handle.exportResumeData()

let restoredHandle = try await downloader.addTorrent(
    fromNativeResumeData: nativeResumeData,
    options: AddTorrentOptions(displayName: "Restored Torrent")
)

print(try await restoredHandle.status().name)
```

## API Coverage

This version already includes:

- magnet and `.torrent` intake
- HTTP(S) `.torrent` metadata fetch
- torrent add, pause, resume, remove, recheck, and reannounce
- file listing, file priorities, include or exclude, and file-local data deletion
- tracker query, replacement, and addition
- peer and piece inspection
- sequential download, piece priorities, and piece deadlines
- native alert polling plus typed high-frequency alert mapping
- native resume data export and import
- downloader-level stats streams and piece update streams
- proxy, encryption, queue, cache, and send-buffer session settings
- qB-style swarm counters via torrent metrics (`peerCount/seedCount` + `peerTotalCount/seedTotalCount`)

## Build and Validate Locally

### Package Modes

- `source`: uses the in-repo bootstrap bridge target (`Sources/LibtorrentAppleBridge`) for API development and fast validation; not the production throughput path.
- `local-binary`: uses a locally built XCFramework at `Artifacts/release/LibtorrentAppleBinary.xcframework`.
- `remote-binary`: uses the GitHub Release binary artifact configured in `PackageSupport/BinaryArtifact.env` (default when config is present).

For production behavior parity and BT throughput validation, use `local-binary` or `remote-binary`.

Validate source mode:

```bash
./scripts/validate-swift-package.sh source
```

Build the Apple frameworks:

```bash
./scripts/sync-libtorrent.sh
./scripts/build-apple-libs.sh
./scripts/smoke-test-macos-framework.sh
./scripts/make-xcframework.sh 0.1.4
```

Validate local binary mode:

```bash
./scripts/validate-swift-package.sh local-binary
```

Run the local benchmark demo (v0.2.0 P0-0):

```bash
cp PackageSupport/BENCHMARK_SOURCES_TEMPLATE.txt /tmp/benchmark-sources.txt
# edit /tmp/benchmark-sources.txt and replace with your magnet/.torrent sources

./scripts/run-benchmark-demo.sh source \
  --profile animeko-parity \
  --sources-file /tmp/benchmark-sources.txt \
  --duration 300 \
  --interval 1
```

The demo writes:

- `session_samples.csv`
- `torrent_samples.csv`
- `summary.json`
- `samples.json`

## Build Against a Different libtorrent Version

By default the repo builds from the pinned version in `scripts/versions.env`.
That keeps builds reproducible.

Use the latest upstream release tag:

```bash
LIBTORRENT_REF=latest ./scripts/sync-libtorrent.sh
```

Use a specific upstream tag for one build:

```bash
LIBTORRENT_REF=v2.0.12 ./scripts/release.sh 0.1.4
```

## Release Model

The public SwiftPM package depends on a GitHub Release-hosted binary artifact.

What SwiftPM actually needs:

- the committed `Package.swift`
- the committed `PackageSupport/BinaryArtifact.env`
- the GitHub Release asset `LibtorrentAppleBinary-<version>.zip`

The zip already contains the full `LibtorrentAppleBinary.xcframework`.
You do not upload standalone `.framework` directories for SwiftPM consumption.

## Tooling Requirements

- Xcode 16+ command line tools
- `cmake`
- `git`
- `curl`

If `cmake` is missing:

```bash
brew install cmake
```

## Repository Layout

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
NativeBridge/
scripts/
.github/workflows/
```

## Notes

- Apps should depend on `LibtorrentApple`, not `LibtorrentAppleBinary`
- If you manually link the raw framework instead of the package, also link:
  - `CFNetwork`
  - `CoreFoundation`
  - `Security`
  - `SystemConfiguration`
  - `libc++`
