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
.package(url: "https://github.com/clOudbb/libtorrent-apple.git", from: "0.2.5")
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

### 5. Apply Throughput Profiles and Peer Filters

```swift
var configuration = SessionConfiguration(downloadDirectory: downloader.defaultSaveDirectory())
configuration.shareRatioLimit = 200
configuration.applyProfile(.animekoParityV2)

let parityDownloader = TorrentDownloader(configuration: configuration)
try await parityDownloader.start()
try await parityDownloader.applyProfile(.qBittorrentParityV1)
try await parityDownloader.setPeerFilters(
    blockedCIDRs: ["10.0.0.0/8"],
    allowedCIDRs: []
)
```

Available profiles:

- `.baseline`: keep default behavior
- `.animekoParityV1`: legacy animeko parity profile
- `.animekoParityV2`: upgraded animeko/anitorrent parity profile
- `.qBittorrentParityV1`: qBittorrent-style throughput profile
- `.beastV1`: aggressive extreme-throughput profile (higher CPU/network/battery cost)

### 6. Deferred Apply and Recovery Reannounce Hooks

```swift
let session = await parityDownloader.session()
var tuned = await session.configuration
tuned.connectionSpeed = 45
tuned.peerTurnover = 4
tuned.announceToAllTiers = true

await session.scheduleConfigurationApply(
    tuned,
    debounceInterval: 0.2
)

// Triggered by downstream app callbacks when network path changes or system wakes.
_ = try await session.handleNetworkPathChanged()
_ = try await session.handleSystemWakeupDetected()
```

`handleNetworkPathChanged()` and `handleSystemWakeupDetected()` reopen libtorrent network sockets before reannounce whenever the native bridge supports it. On iOS, downstream apps should call these from `NWPathMonitor` updates and wake callbacks. The default `SessionConfiguration` listen interfaces are now explicit dual-stack bindings: `0.0.0.0:0,[::]:0`.

### 7. Runtime Transport Behavior Controls (uTP/TCP)

```swift
// Immediate apply
try await parityDownloader.setTransportBehavior(.tcpOnly)

// Debounced apply (for high-frequency toggles)
await parityDownloader.scheduleTransportBehaviorApply(.preferTCP, debounceInterval: 0.2)
_ = await parityDownloader.flushDeferredConfigurationApply()
```

Behavior mapping:

- `.balanced`: enable TCP + uTP, `mixedModeAlgorithm = .peerProportional`
- `.preferTCP`: enable TCP + uTP, `mixedModeAlgorithm = .preferTCP`
- `.tcpOnly`: enable TCP, disable uTP
- `.utpOnly`: disable TCP, enable uTP

### 8. Throughput Optimizer (P0-1/P0-2)

```swift
await parityDownloader.startThroughputOptimizer(
    policy: .default
)

// Optional: check status
let enabled = await parityDownloader.isThroughputOptimizerEnabled()
print("optimizer enabled:", enabled)

// Stop and restore baseline configuration
await parityDownloader.stopThroughputOptimizer(restoreBaseline: true)
```

What it does:

- low-speed/zero-speed window detection
- batch reannounce for stalled downloads
- temporary throughput boost (`connectionSpeed`, `torrentConnectBoost`, request queues, peer turnover)
- auto-restore baseline after stable recovery windows

### 9. File priorities, trackers, and torrent control

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

### 10. Save and restore

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
- deferred session configuration apply and batch reannounce recovery hooks
- runtime uTP/TCP transport behavior control hooks

## HTTPS Trackers and TLS Backend

- `libtorrent-apple` supports only the `OpenSSL` HTTPS tracker backend.
- Check `LibtorrentApple.backendInfo.supportsHTTPSTrackers` to confirm capability at runtime.
- Regression tests cover the `unsupported_url_protocol` failure mode for `https://.../announce` tracker URLs.
- Release builds sync and pin `OpenSSL-Universal` from `https://github.com/krzyzanowskim/OpenSSL.git` by default.
- Local release builds still support explicit `OPENSSL_*` paths and fall back to a local `OpenSSL-Universal` checkout or SwiftPM cache when needed.

## Build and Validate Locally

### Package Modes and Recommendation

Recommended dependency mode for downstream apps (highest priority first):

1. `remote-binary` (recommended)
2. `local-binary`
3. `source` (not recommended for production)

Mode details:

- `remote-binary` (recommended): SwiftPM downloads the Release XCFramework declared by `PackageSupport/BinaryArtifact.env`.
  This is the closest path to real downstream integration, with no local C/C++ toolchain cost and minimal CI time.
- `local-binary`: loads `Artifacts/release/LibtorrentAppleBinary.xcframework` built by this repo's scripts.
  Use this for pre-release verification when you need production-equivalent behavior before uploading Release assets.
- `source` (not recommended for production): compiles the in-repo bootstrap bridge target (`Sources/LibtorrentAppleBridge`) for API development and fast iteration.
  Current caveat: this path is a different packaging/linking route from shipped binary artifacts, so source-mode results cannot be used as final throughput acceptance for downstream apps.
  A concrete drift example from earlier versions: binary-mode `applyConfiguration` was gated off in Swift wrapper even though the native bridge already supported runtime rate-limit apply; this is already fixed and included in `0.2.4`, but it shows why source and binary parity must be validated on binary mode.

Validate source mode:

```bash
./scripts/validate-swift-package.sh source
```

Validate all package modes in one command:

```bash
./scripts/validate-swift-package.sh all
```

Note: `remote-binary` mode requires the published XCFramework to match current source headers/API.

Build the Apple frameworks:

```bash
./scripts/sync-libtorrent.sh
./scripts/sync-openssl.sh
./scripts/build-apple-libs.sh
./scripts/smoke-test-macos-framework.sh
./scripts/make-xcframework.sh 0.2.5
```

Validate local binary mode:

```bash
./scripts/validate-swift-package.sh local-binary
```

Validate remote binary mode:

```bash
./scripts/validate-swift-package.sh remote-binary
```

Run the local benchmark demo (v0.2.5 P0-0):

```bash
cp PackageSupport/BENCHMARK_SOURCES_TEMPLATE.txt /tmp/benchmark-sources.txt
# edit /tmp/benchmark-sources.txt and replace with your magnet/.torrent sources

./scripts/run-benchmark-demo.sh local-binary \
  --profile animeko-parity-v2 \
  --sources-file /tmp/benchmark-sources.txt \
  --duration 300 \
  --interval 1
```

The demo writes:

- `session_samples.csv`
- `torrent_samples.csv`
- `summary.json`
- `samples.json`

Run a fair A/B parity gate with enforced same sources, same trackers, and same time window:

```bash
./scripts/benchmark-parity-gate.sh \
  --mode local-binary \
  --reference-profile animeko-parity-v2 \
  --candidate-profile qbittorrent-parity-v1 \
  --threshold-percent 15 \
  --duration 300 \
  --interval 1 \
  -- \
  --sources-file /tmp/benchmark-sources.txt \
  --tracker-file /tmp/benchmark-trackers.txt
```

Gate outputs:

- `reference-*/summary.json`
- `candidate-*/summary.json`
- `gate_report.json` (pass/fail + throughput gap + attribution hints)

Run a simplified one-shot same-condition comparison (reference only, no gate threshold):

```bash
./scripts/benchmark-once-compare.sh \
  --mode local-binary \
  --reference-profile animeko-parity-v2 \
  --candidate-profile qbittorrent-parity-v1 \
  --duration 120 \
  --interval 1 \
  -- \
  --sources-file /tmp/benchmark-sources.txt \
  --tracker-file /tmp/benchmark-trackers.txt
```

## Build Against Different Upstream Versions

By default the repo builds from the pinned upstream versions in `scripts/versions.env`.
That keeps builds reproducible.

Use the latest upstream release tag:

```bash
LIBTORRENT_REF=latest ./scripts/sync-libtorrent.sh
OPENSSL_REF=latest ./scripts/sync-openssl.sh
```

Use a specific upstream tag for one build:

```bash
LIBTORRENT_REF=v2.0.12 ./scripts/release.sh 0.2.5
OPENSSL_REF=3.6.0001 ./scripts/release.sh 0.2.5
```

Override both dependencies in one release build:

```bash
LIBTORRENT_REF=latest OPENSSL_REF=latest ./scripts/release.sh 0.2.5
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
