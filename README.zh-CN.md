# libtorrent-apple

[English](README.md)

`libtorrent-apple` 是一个基于 `libtorrent` 的 Apple 平台 Swift SDK。
它提供真实可分发的 `XCFramework`、Swift 优先的 API，以及完整的 GitHub Release + SwiftPM 二进制分发链路。

## 这个仓库能给你什么

- 一个对外的 SwiftPM 产品：`LibtorrentApple`
- 一个内部二进制 target：`LibtorrentAppleBinary`
- `iOS 真机`、`iOS 模拟器`、`macOS` 三套产物
- 一套可以产出 GitHub Release 二进制包的自动化脚本
- 一套已经覆盖 `iTorrent`、`anitorrent` 这类项目 BT 核心能力的 Swift API

## 快速接入

添加包依赖：

```swift
.package(url: "https://github.com/clOudbb/libtorrent-apple.git", from: "0.2.1")
```

导入模块：

```swift
import LibtorrentApple
```

## 主要类型

- `TorrentDownloader`：更高层的入口，负责目录管理、元数据获取、resume 快照
- `TorrentSession`：更底层的 session actor，直接控制 torrent 生命周期
- `TorrentHandle`：单个 torrent 的控制对象
- `TorrentFileHandle`：单个文件的控制对象
- `TorrentDownloadController`：面向边下边播的流式下载控制接口
- `SessionConfiguration`：session 配置，包含端口、限速、代理、加密、网络行为等

## 主要 API 用法

### 1. 启动 downloader 并添加 magnet

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

### 2. 添加本地 `.torrent` 文件

```swift
let torrentURL = URL(fileURLWithPath: "/path/to/file.torrent")

let handle = try await downloader.addTorrent(
    from: .torrentFile(torrentURL, displayName: "Episode 01")
)

let files = try await handle.files()
print(files.map(\.path))
```

### 3. 监听 alerts 和总统计

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
        print("运行中的 torrent 数:", stats.runningTorrentCount)
        print("下载速度:", stats.aggregateDownloadRateBytesPerSecond)
    }
}
```

### 4. 做边下边播相关控制

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
        print("已完成 piece 数:", nextSnapshot.completedPieceCount)
    }
}
```

### 5. 应用 animeko 对齐策略与 peer 过滤

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

### 5. 文件优先级、tracker 和 torrent 控制

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

### 6. 保存和恢复

仓库级 JSON 快照恢复：

```swift
let snapshotURL = try await downloader.persistResumeSnapshot(named: "default")
print(snapshotURL.path)

try await downloader.restoreLatestResumeSnapshot()
```

单个 torrent 的 native resume data：

```swift
let nativeResumeData = try await handle.exportResumeData()

let restoredHandle = try await downloader.addTorrent(
    fromNativeResumeData: nativeResumeData,
    options: AddTorrentOptions(displayName: "Restored Torrent")
)

print(try await restoredHandle.status().name)
```

## 这版 API 已经覆盖的能力

当前版本已经包含：

- magnet 和 `.torrent` 添加
- HTTP(S) `.torrent` 元数据抓取
- torrent 的添加、暂停、恢复、删除、recheck、reannounce
- 文件列表、文件优先级、包含或排除、删除本地文件数据
- tracker 查询、替换、追加
- peer 和 piece 查询
- 顺序下载、piece 优先级、piece deadline
- native alert 轮询和高频 typed alert 映射
- native resume data 导出和导入
- downloader 级 stats stream 和 piece update stream
- 代理、加密、队列、缓存、send buffer 等 session 配置
- qB 风格 swarm 计数能力（`peerCount/seedCount` + `peerTotalCount/seedTotalCount`）

## 本地构建与验证

### Package Mode 与推荐顺序

下游 App 依赖时，推荐优先级如下：

1. `remote-binary`（最推荐）
2. `local-binary`
3. `source`（不推荐用于生产）

各模式说明：

- `remote-binary`（推荐）：SwiftPM 直接下载 `PackageSupport/BinaryArtifact.env` 指向的 GitHub Release XCFramework。
  这是最接近真实下游集成的路径，不需要本地 C/C++ 构建，CI 成本最低。
- `local-binary`：加载本仓库脚本产出的 `Artifacts/release/LibtorrentAppleBinary.xcframework`。
  适合发版前在本地先做“与生产等价”的行为验证，再上传 Release 产物。
- `source`（不推荐用于生产）：编译仓库内 bootstrap bridge target（`Sources/LibtorrentAppleBridge`），适合 API 开发和快速迭代。
  当前问题是：这条链路与最终发布的 binary 产物不是同一套打包/链接路径，source 模式结果不能作为下游最终吞吐验收依据。
  一个已发生过的漂移案例：早期版本里 binary 模式的 Swift 包装层曾直接禁掉 `applyConfiguration`，而 native bridge 实际已支持运行时限速更新；该问题已在 `0.2.1` 修复，但也说明 source/binary 一致性必须在 binary 模式下验收。

验证 source mode：

```bash
./scripts/validate-swift-package.sh source
```

构建 Apple 平台产物：

```bash
./scripts/sync-libtorrent.sh
./scripts/build-apple-libs.sh
./scripts/smoke-test-macos-framework.sh
./scripts/make-xcframework.sh 0.2.1
```

验证 local-binary mode：

```bash
./scripts/validate-swift-package.sh local-binary
```

验证 remote-binary mode：

```bash
./scripts/validate-swift-package.sh remote-binary
```

运行本地 benchmark demo（v0.2.1 P0-0）：

```bash
cp PackageSupport/BENCHMARK_SOURCES_TEMPLATE.txt /tmp/benchmark-sources.txt
# 编辑 /tmp/benchmark-sources.txt，替换成你的磁力链接/.torrent 输入

./scripts/run-benchmark-demo.sh local-binary \
  --profile animeko-parity \
  --sources-file /tmp/benchmark-sources.txt \
  --duration 300 \
  --interval 1
```

demo 会输出：

- `session_samples.csv`
- `torrent_samples.csv`
- `summary.json`
- `samples.json`

## 指定其他 libtorrent 版本构建

默认会使用 `scripts/versions.env` 里固定的 upstream 版本，这样构建更可复现。

如果你想直接追 upstream 最新 release tag：

```bash
LIBTORRENT_REF=latest ./scripts/sync-libtorrent.sh
```

如果你想临时指定某个版本：

```bash
LIBTORRENT_REF=v2.0.12 ./scripts/release.sh 0.2.1
```

## Release 与 SwiftPM 的关系

SwiftPM 真正依赖的是 GitHub Release 上的二进制 zip。

对 SwiftPM 来说，真正必须的是：

- 仓库里的 `Package.swift`
- 仓库里的 `PackageSupport/BinaryArtifact.env`
- GitHub Release 上的 `LibtorrentAppleBinary-<version>.zip`

这个 zip 里已经包含完整的 `LibtorrentAppleBinary.xcframework`。  
所以给 SwiftPM 发版时，不需要单独上传 `.framework` 目录。

## 环境要求

- Xcode 16+ command line tools
- `cmake`
- `git`
- `curl`

如果缺少 `cmake`：

```bash
brew install cmake
```

## 仓库结构

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

## 说明

- App 侧应该依赖 `LibtorrentApple`，不要直接依赖 `LibtorrentAppleBinary`
- 如果你不用 SwiftPM，而是手动接原始 framework，还需要额外链接：
  - `CFNetwork`
  - `CoreFoundation`
  - `Security`
  - `SystemConfiguration`
  - `libc++`
