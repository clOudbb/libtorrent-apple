# libtorrent-apple Bootstrap

## Project Goal

Build an independent open-source Apple-platform libtorrent package, initially supporting:
- iOS Device
- iOS Simulator
- macOS

This repository is not a torrent app. It is a reusable Apple platform package/framework that exposes libtorrent capabilities through a stable Swift-friendly API.

App Store distribution is not a goal. iOS usage is expected to be mainly self-signed / open-source distribution.

## Prior Analysis Summary

### Repositories evaluated

1. `drip-torrent/LibTorrent-swift`
- Useful as a reference.
- It already uses SwiftPM structure and MIT licensing.
- It is not a production-ready Apple distribution package yet.
- It behaves more like a source wrapper that expects local system dependencies such as `libtorrent-rasterbar`, `boost`, and `openssl`.
- It is not enough as the mainline dependency for this repo.

2. `XITRIX/LibTorrent-Swift`
- Useful as an Apple/libtorrent integration reference.
- It is closer to app-internal engineering assets.
- It is based on Xcode project + ObjC++/C++ integration.
- It is not a clean SwiftPM-first distributable package.
- It should not be used directly as the production base unless license position is made explicit.

3. `open-ani/anitorrent`
- Do not use as a base.
- It is Kotlin/JVM oriented.
- Its README states that iOS support is only planned.
- It is GPL-3.0 and does not fit the intended Swift/Apple package direction.

## Final Technical Direction

### Product positioning

This project is not just a Swift wrapper.
It should become a distributable Apple torrent runtime package.

The value is:
- end users do not need to compile libtorrent themselves
- end users do not need to manage boost/openssl Apple builds themselves
- Apple multi-architecture packaging is handled here
- SwiftPM consumption should be straightforward

### Distribution strategy

Use:
- `XCFramework`
- SwiftPM `binaryTarget`
- GitHub Releases to host binary artifacts

### Release strategy

Use:
- automated build steps
- manually triggered release flow
- GitHub Actions + `GITHUB_TOKEN`
- no GitHub account password in scripts

### Platform scope for phase 1

Support only:
- iOS Device
- iOS Simulator
- macOS

Do not expand to Catalyst/tvOS/watchOS in the first phase.

### Engineering constraints

- Swift 6
- strict concurrency mindset
- no Combine
- keep API actor-friendly and Sendable-friendly
- do not over-engineer early with plugin systems
- establish stable boundaries first
- start by making build/release infrastructure real, then deepen API coverage

## First Phase Functional Scope

Implement or prepare API surface for:
- session start / stop
- add torrent from magnet link
- add torrent from `.torrent` file
- pause torrent
- resume torrent
- remove torrent
- query torrent status
- alert stream
- resume data export / restore
- stable models and error types

This phase is not about a full-featured download app.
It is about repository skeleton, packaging strategy, release automation, and native bridge boundaries.

## Proposed Repository Structure

Create and maintain an initial structure similar to:

```text
libtorrent-apple/
├── Package.swift
├── README.md
├── LICENSE
├── .gitignore
├── Sources/
│   ├── LibtorrentApple/
│   │   ├── Models/
│   │   ├── Errors/
│   │   ├── Session/
│   │   └── LibtorrentApple.swift
│   └── LibtorrentAppleBridge/
│       ├── include/
│       └── placeholder bridge files
├── scripts/
│   ├── sync-libtorrent.sh
│   ├── build-apple-libs.sh
│   ├── make-xcframework.sh
│   └── release.sh
└── .github/
    └── workflows/
        └── release.yml
```

The exact file layout may be adjusted, but the repo should clearly separate:
- public Swift API
- native bridge boundary
- packaging/build scripts
- release automation

## Packaging Approach

### Core idea

The repository should eventually provide a binary distribution path via `XCFramework` and SwiftPM `binaryTarget`.

However, if there is no binary artifact yet in the first commit, it is acceptable to start with a normal target skeleton as long as the design cleanly transitions later to:

```swift
.binaryTarget(name: "LibtorrentApple", url: "...", checksum: "...")
```

### Why this differs from existing "LibTorrent-Swift" style repos

The main distinction is not API naming. It is delivery responsibility.

Those repos are closer to:
- wrapper around libtorrent source/build assumptions

This repo should become:
- a distributable Apple platform package with stable runtime delivery

That means this repo owns:
- architecture builds
- Apple slices
- packaging into xcframework
- release assets
- checksum generation
- SwiftPM binary consumption path

## Automation Plan

This repo should automate the repetitive release chain so day-to-day work can focus on native bridge and Swift API logic.

### Script responsibilities

1. `scripts/sync-libtorrent.sh`
- fetch or pin libtorrent source/version
- pin dependency versions if applicable

2. `scripts/build-apple-libs.sh`
- build native artifacts for:
  - iphoneos
  - iphonesimulator
  - macosx
- use consistent build configuration

3. `scripts/make-xcframework.sh`
- assemble per-platform outputs into `.xcframework`
- zip artifact
- compute SwiftPM checksum

4. `scripts/release.sh`
- validate version input
- run the packaging pipeline
- update package metadata if needed
- create/update GitHub Release
- upload zip asset

### GitHub Actions expectations

`.github/workflows/release.yml` should support:
- manual trigger
- macOS runner
- build xcframework
- zip artifact
- compute checksum
- publish or update GitHub Release
- use `GITHUB_TOKEN`

### Security conclusion

Do not use GitHub account passwords.
Prefer:
- local `gh auth login` for manual local publishing, or
- GitHub Actions with built-in `GITHUB_TOKEN`

For this project, preferred release mode is:
- manually triggered workflow
- automated release steps

## Suggested Public API Direction

Keep the first public API compact and stable.
Prefer a shape like:
- `SessionConfiguration`
- `TorrentSource`
- `TorrentState`
- `TorrentStatus`
- `TorrentMetrics`
- `TorrentAlert`
- `LibtorrentAppleError`
- `TorrentSession`

Use actors where that naturally improves safety and clarity.

Avoid exposing raw C++ details directly to Swift consumers.
Bridge should stay internal or behind narrow boundaries.

## What the next Codex session should do

The next Codex session in this repository should execute, not just plan.

### Immediate task order

1. Inspect current repository contents.
2. If mostly empty, create the initial repository skeleton.
3. Create:
- `Package.swift`
- `README.md`
- `LICENSE`
- `.gitignore`
4. Create source skeleton under:
- `Sources/LibtorrentApple`
- `Sources/LibtorrentAppleBridge`
5. Create initial API placeholders for:
- configuration
- source
- state
- metrics/status
- alerts
- errors
- session facade
6. Create automation script templates under `scripts/`.
7. Create `.github/workflows/release.yml`.
8. Keep everything concise and clean.
9. After scaffolding, summarize what was created and recommend the next concrete implementation step.

### Important execution style

- Do not spend the whole turn only analyzing.
- Start creating the repository structure immediately.
- Favor small, clean initial files.
- Keep comments short and useful.
- Preserve future migration path toward binary distribution.

## Additional context from the original app integration discussion

This repository should remain generic and reusable.
It should not include OpenBangumi-specific business models.

However, the long-term consumer is expected to be an app architecture that can adapt a stable torrent backend interface onto its own domain layer.
That downstream integration is not the concern of this repository right now.

## One-line mission

Build a clean, Apple-focused, distributable libtorrent package with automated packaging and release flow, so future work can focus on native bridge and API logic instead of repetitive build/distribution steps.
