# Milestones

This file is the working roadmap for `libtorrent-apple`.
It exists to keep the public Swift API stable while the native bridge and release pipeline continue to evolve.

## Product Goal

Build a release-ready Apple SDK with:
- a stable SwiftPM product: `LibtorrentApple`
- an internal binary target: `LibtorrentAppleBinary`
- a Swift-first API layer that covers the core libtorrent workflows without forcing app code to speak C or C++
- enough native escape hatches to avoid blocking advanced users on long-tail libtorrent capabilities

## Reference Direction

This roadmap is guided by two public references:
- `iTorrent`: stable user-facing capabilities such as background download, sequential download, file selection, magnet and `.torrent` intake, and tracker-related stability work
- `open-ani/anitorrent`: low-level but intentionally split APIs around session, downloader, files, peers, and pieces

The intent is not to clone either project.
The intent is to ship a stable Swift SDK that covers the core operational surface those projects rely on.

## Reference Baseline Snapshot

Snapshot date: 2026-03-13

This section exists so future implementation work does not need to re-discover the same baseline from upstream projects every turn.

### iTorrent Baseline

Nature:
- app-level feature baseline, not a reusable SDK API surface
- useful for deciding which end-user torrent workflows must already be supported by our Swift SDK

Publicly visible current capability baseline:
- background downloading
- sequential download for playback while data is still arriving
- add torrent files from Share menu
- add magnet links directly
- download torrent by link
- magnet and `.torrent` based intake
- store files in Files app
- file sharing from the app
- file selection for download
- WebDAV server support
- RSS feed support
- notification and live progress widgets

Recent public stability emphasis:
- background download crash fixes and performance improvements
- tracker list crash fixes
- tracker reannounce support
- default port setting fixes
- core performance refactoring
- libtorrent version upgrades

Implication for `libtorrent-apple` v1:
- our Swift API must already support the torrent-engine capabilities behind the above workflows
- app-shell features such as WebDAV, Share Extension, RSS UI, notifications, and Files app integration are not SDK-v1 requirements by themselves
- the engine-level capabilities behind them are SDK-v1 requirements:
  - background-safe restore and persistence
  - magnet and `.torrent` intake
  - sequential download
  - file selection and file priority
  - tracker management and reannounce
  - stable port and session settings

### Anitorrent Baseline

Nature:
- public low-level API baseline
- direct parity target for our Swift API surface

Public surface snapshot:
- `TorrentDownloader`
  - backend or vendor info
  - total stats across tasks
  - magnet and HTTP `.torrent` fetch
  - start download from encoded torrent info
  - save-directory lookup
  - save enumeration
- `TorrentSession`
  - session stats flow
  - name retrieval
  - file listing
  - peer listing
  - close and conditional close
- files API
  - `TorrentFileEntry`
  - `TorrentFileHandle`
  - `FilePriority`
  - per-file pause, resume, close, delete semantics
- peer API
  - peer information model
  - peer filtering primitives
- pieces and streaming control API
  - `Piece`
  - `PieceList`
  - piece subscription primitives
  - `TorrentDownloadController`
  - explicit streaming-oriented piece priority logic

Implication for `libtorrent-apple` v1:
- public Swift API capability must be at least equivalent to this surface
- naming may differ, but object roles and control surface cannot be weaker
- piece-aware and streaming-aware control is not optional

### Combined v1 Reference Floor

The first stable Swift version must satisfy both:
- API capability parity with the public `anitorrent` surface
- engine capability parity with the core torrent workflows visible in `iTorrent`

Concretely, v1 must include:
- downloader-level API
- session-level API
- torrent-handle API
- file entry and file-handle API
- file priorities
- peer listing
- piece-aware control
- sequential download and streaming-oriented priorities
- magnet, `.torrent`, and HTTP `.torrent` intake
- save discovery and resume restore
- tracker control and reannounce
- stable session configuration for ports, limits, and network behavior

## Current Baseline

Already implemented:
- SwiftPM wrapper product plus binary target packaging
- real Apple framework and XCFramework build pipeline
- source-mode and local-binary validation
- downloader-level Swift surface via `TorrentDownloader`
- backend or vendor metadata surface via `TorrentBackendInfo`
- downloader aggregate stats via `TorrentDownloaderStats`
- encoded torrent intake via `EncodedTorrentInfo`
- snapshot persistence helpers and managed torrent file storage
- session start and stop
- add torrent from magnet or `.torrent` file
- add torrent from encoded `.torrent` data
- pause, resume, remove, and status query
- public `TorrentHandle` API for status, pause, resume, remove, and export operations
- public `TorrentHandle` control for file enumeration, file priorities, sequential download, recheck, reannounce, move storage, piece priorities, and piece deadlines
- public `TorrentFile` and `TorrentFileHandle` surfaces for file-scoped enumeration, include or exclude, pause or resume-by-priority control, and local file-data deletion
- public `TorrentTracker`, `TorrentPeer`, and `TorrentPiece` model surfaces for tracker, peer, and piece inspection
- public tracker update APIs for tracker replacement and tracker addition
- public `TorrentDownloadController` surface for piece snapshots, piece update streams, sequential mode, playback-oriented prefetching, and file or piece prioritization
- torrent metadata export for completed `.torrent` info
- fetch torrent metadata from file URLs, HTTP(S), and magnet links
- save-directory lookup plus persisted snapshot enumeration
- native alert polling wired into `alerts()`
- strongly typed high-frequency alert coverage plus raw alert passthrough
- native per-torrent resume data export and import
- session stats updates and piece-progress update streams
- `SessionConfiguration` coverage for proxy, encryption, queue, cache, and streaming-oriented defaults

## v1 Status

The repository has reached its planned v1 baseline.

That means:
- the public Swift surface now covers the downloader/session/file/peer/piece/tracker/controller roles recorded in the `anitorrent` baseline
- the engine workflows visible in `iTorrent` are implemented at the SDK layer
- source-mode and local-binary mode both validate against the same high-level API set
- release-ready binary artifacts are generated from the same implementation that backs the Swift wrapper

The remaining work after this point is post-v1 improvement work, not v1 completion work.

## v1 Principles

1. Public Swift models must stabilize before long-tail libtorrent coverage.
2. High-frequency workflows get typed Swift APIs first.
3. Long-tail libtorrent features can be exposed via a raw/native escape hatch.
4. Source mode and binary mode must keep behavioral parity.
5. Persistence, restore, and alert semantics are part of the stable API surface, not implementation details.

## Parity Floor with Anitorrent

The first public Swift version must provide API capability at least on par with the public surface exposed by `open-ani/anitorrent`.
This is a capability floor, not a naming requirement.

That means v1 must cover the practical roles currently represented there by:
- `TorrentDownloader`
- `TorrentSession`
- `TorrentFileEntry`
- `TorrentFileHandle`
- `FilePriority`
- `PeerInfo`
- `PieceList`
- `TorrentDownloadController`

At minimum, our public Swift API must expose equivalent capability for:
- downloader-level total stats
- backend and vendor information
- fetching torrent metadata from magnet links and HTTP `.torrent` URLs
- starting downloads from encoded torrent data
- save-directory discovery and saved-session enumeration
- session stats
- file listing and per-file control
- peer listing
- piece-aware and streaming-aware download control

## Milestone 1: Stable Core API

Priority: highest

Deliverables:
- freeze the public core type set:
  - `TorrentDownloader`
  - `TorrentSession`
  - `TorrentHandle`
  - `AddTorrentOptions`
  - `TorrentStatus`
  - `TorrentFile`
  - `TorrentFileHandle`
  - `TorrentPeer`
  - `TorrentTracker`
  - `TorrentAlert`
  - `ResumeData`
  - `SessionConfiguration`
- add downloader-level API parity:
  - total stats across active torrents
  - backend or vendor info
  - magnet and HTTP `.torrent` metadata fetch
  - start download from encoded torrent data
  - save-directory lookup
  - saved-session enumeration
- expand `SessionConfiguration` to cover the high-frequency session knobs:
  - ports
  - DHT, LSD, UPnP, NAT-PMP
  - upload and download limits
  - connection limits
  - proxy and encryption
  - queue and cache related basics
- add a real `TorrentHandle` control surface:
  - pause
  - resume
  - remove
  - recheck
  - move storage
  - force reannounce
  - sequential download
  - file priorities
  - piece priorities
  - piece deadlines
- complete torrent intake:
  - magnet
  - `.torrent` file
  - in-memory torrent data
  - native resume data
  - optional URL-based `.torrent` loading

Exit criteria:
- no public API rename is expected for the core type set
- a sample client can add, inspect, control, and restore torrents without touching C ABI symbols

## Milestone 2: Streaming and File Control

Priority: highest

Deliverables:
- file enumeration and file progress
- first-class `TorrentFileHandle` semantics for file-scoped pause, resume, close, and delete
- file inclusion and exclusion
- file priorities
- piece list or equivalent piece mapping
- sequential download
- piece deadlines
- streaming controller semantics equivalent to anitorrent's download controller role
- metadata-ready state handling
- sensible streaming-oriented defaults that app code can override

Exit criteria:
- a client can start playback-oriented downloads using only Swift APIs
- file-level selection and prioritization do not require raw bridge calls

## Milestone 3: Persistence and Alerts

Priority: highest

Deliverables:
- native resume data import and restore
- session-level save and restore strategy
- shutdown-time flush semantics
- strongly typed alert coverage for the high-frequency alert set:
  - torrent added
  - torrent removed
  - metadata received
  - state changed
  - torrent finished
  - tracker warning
  - tracker error
  - resume data saved
  - resume data failed
  - performance warning
- raw alert passthrough for unsupported alert kinds

Exit criteria:
- app restart and restore is reliable enough for production use
- alert handling no longer depends on parsing generic strings for common cases

## Milestone 4: Observability APIs

Priority: medium

Deliverables:
- trackers query and update APIs
- peers query APIs
- files query APIs
- pieces or piece-progress APIs
- session stats and torrent stats snapshots
- clearer state and progress semantics for metadata-only and partial states

Exit criteria:
- typical torrent-client UIs can be built without reaching into native internals

## Milestone 5: Stabilization and Release Hardening

Priority: highest before `1.0.0`

Deliverables:
- layered Swift error taxonomy instead of relying mainly on `nativeOperationFailed`
- scenario-driven tests covering:
  - magnet flow
  - `.torrent` flow
  - single-file and multi-file torrents
  - pause and resume
  - remove and restore
  - sequential download
  - file priorities
  - resume-data roundtrip
  - tracker error handling
  - metadata-incomplete behavior
  - source-mode and binary-mode parity
- docs that define:
  - actor and concurrency model
  - lifecycle requirements
  - persistence contract
  - recommended integration patterns
- release process clarity for binary checksum and tag consistency

Exit criteria:
- the package can be treated as a stable dependency by another app team
- `1.0.0` can be tagged without expecting immediate public API churn

## Deferred Until After v1

These are useful, but they are not SDK-v1 blockers:
- RSS
- WebDAV
- Share Extension support
- notification products such as Live Activity
- Files app integration details
- app-layer download manager UI concerns

## Post-v1 Improvement Areas

These are the main areas to improve after the v1 release is cut:
1. Broaden typed alert coverage beyond the current high-frequency set.
2. Add more long-tail `settings_pack` and per-torrent configuration coverage where real client demand justifies it.
3. Expand streaming helpers from polling-based piece updates into more specialized playback heuristics if app teams need them.
4. Add richer tracker and peer mutation APIs if future consumers need more than query, add, replace, and reannounce.
5. Continue scenario coverage around larger multi-file torrents and more recovery edge cases.

## Working Rule

Any new feature work should map back to one of the milestones above.
If a change does not help API completeness, restore reliability, streaming control, observability, or release stability, it should not preempt these milestones.
