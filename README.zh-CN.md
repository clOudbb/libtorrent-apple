<p align="center">
  <img src="Resources/LibtorrentAppleBanner.png" alt="libtorrent-apple" width="560">
</p>

<p align="center">
  <a href="https://swift.org"><img src="https://img.shields.io/badge/Swift-6.0-orange?style=flat-square" alt="Swift 6.0"></a>
  <a href="Package.swift"><img src="https://img.shields.io/badge/Platforms-iOS%2015%2B%20%7C%20macOS%2013%2B-yellowgreen?style=flat-square" alt="Platforms: iOS 15+ and macOS 13+"></a>
  <a href="Package.swift"><img src="https://img.shields.io/badge/SwiftPM-0.2.10-orange?style=flat-square" alt="SwiftPM 0.2.10"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-blue?style=flat-square" alt="MIT License"></a>
  <a href="https://github.com/arvidn/libtorrent"><img src="https://img.shields.io/badge/libtorrent-v2.0.12-informational?style=flat-square" alt="libtorrent v2.0.12"></a>
  <a href="https://github.com/krzyzanowskim/OpenSSL"><img src="https://img.shields.io/badge/OpenSSL-3.6.2000-lightgrey?style=flat-square" alt="OpenSSL 3.6.2000"></a>
</p>

[English](README.md)

`libtorrent-apple` 是一个基于 `libtorrent` 的 Apple 平台 Swift SDK。
它提供真实可分发的 `XCFramework`、Swift 优先的 API，以及完整的 GitHub Release + SwiftPM 二进制分发链路。

## 这个仓库能给你什么

- 一个对外的 SwiftPM 产品：`LibtorrentApple`
- 一个稳定桥接 target，底层使用版本化内部二进制 target，当前为 `LibtorrentAppleBinary_0_2_10`
- `iOS 真机`、`iOS 模拟器`、`macOS` 三套产物
- 一套可以产出 GitHub Release 二进制包的自动化脚本
- 一套已经覆盖 `iTorrent`、`anitorrent` 这类项目 BT 核心能力的 Swift API

## 快速接入

添加包依赖：

```swift
.package(url: "https://github.com/clOudbb/libtorrent-apple.git", from: "0.2.10")
```

导入模块：

```swift
import LibtorrentApple
```

## 主要类型

- `TorrentDownloader`：更高层的入口，负责目录管理、元数据获取、持久化恢复
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

### 5. 可选运行时调优与 peer 过滤

```swift
var configuration = SessionConfiguration(downloadDirectory: downloader.defaultSaveDirectory())
configuration.shareRatioLimit = 200

let runtimeDownloader = TorrentDownloader(configuration: configuration)
try await runtimeDownloader.start()
try await runtimeDownloader.setPeerFilters(
    blockedCIDRs: ["10.0.0.0/8"],
    allowedCIDRs: []
)
```

多数 App 直接配置 `SessionConfiguration` 并保留默认值即可。`applyProfile` 只是基于同一套公开配置 API 的便捷入口；使用后仍可覆盖任意已暴露字段。高频运行时控制应使用下面的窄粒度 setter。

### 6. 运行时 Speed 与 BitTorrent 设置

上传/下载限速和核心 BT 控制已经拆成 sparse runtime patch，下游不需要为了一个滑条变化反复提交完整 `SessionConfiguration`。

```swift
guard LibtorrentApple.backendSupportsSessionRuntimeSettings else {
    // 使用 v0.2.10+ binary artifact，或回退到低频 applyConfiguration。
    return
}

// 立即限速更新。
try await runtimeDownloader.setRateLimits(
    uploadBytesPerSecond: 256 * 1024,
    downloadBytesPerSecond: 4 * 1024 * 1024
)

// 给 UI slider 使用的 throttle/coalesce 更新：第一笔尽快生效，短窗口内只保留最后一笔。
await runtimeDownloader.scheduleRateLimits(
    uploadBytesPerSecond: 512 * 1024,
    downloadBytesPerSecond: 8 * 1024 * 1024,
    throttleInterval: 0.2
)

// 可运行时调整的 BitTorrent 设置，不会重放完整配置。
try await runtimeDownloader.setConnectionLimits(
    globalConnections: 500,
    connectionSpeed: 40,
    torrentConnectBoost: 80
)
try await runtimeDownloader.setActiveLimits(downloads: -1, seeds: -1, torrents: -1)
try await runtimeDownloader.setRateLimitOptions(includeIPOverhead: true)
```

这些 API 中 `nil` 表示“不改”，`0` 保持 libtorrent 的不限速语义。`applyConfiguration` 仍用于初始化、持久化恢复和低频完整配置；运行时 speed、queue、connection、transport 控制应优先使用窄 API，避免夹带 DHT、UPnP、监听端口等无关设置。

### 7. 延迟应用与恢复 Reannounce Hooks

```swift
let session = await runtimeDownloader.session()
var tuned = await session.configuration
tuned.connectionSpeed = 45
tuned.peerTurnover = 4
tuned.announceToAllTiers = true

await session.scheduleConfigurationApply(
    tuned,
    debounceInterval: 0.2
)

// 下游 App 可以在网络路径变化或系统唤醒回调中触发。
_ = try await session.handleNetworkPathChanged()
_ = try await session.handleSystemWakeupDetected()
```

`handleNetworkPathChanged()` 和 `handleSystemWakeupDetected()` 会在 native bridge 支持时先重开 libtorrent network sockets，再批量 reannounce。iOS 下游 App 应从 `NWPathMonitor` 更新和系统唤醒回调中主动调用它们。当前默认 `SessionConfiguration.listenInterfaces` 已改为显式双栈绑定：`0.0.0.0:0,[::]:0`。

### 8. 运行时传输行为控制（uTP/TCP）

```swift
// 立即生效
try await runtimeDownloader.setTransportBehavior(.tcpOnly)

// debounce 后生效，适合高频开关
await runtimeDownloader.scheduleTransportBehaviorApply(.preferTCP, debounceInterval: 0.2)
_ = await runtimeDownloader.flushDeferredRuntimePatch()
```

行为映射：

- `.balanced`：启用 TCP + uTP，`mixedModeAlgorithm = .peerProportional`
- `.preferTCP`：启用 TCP + uTP，`mixedModeAlgorithm = .preferTCP`
- `.tcpOnly`：启用 TCP，禁用 uTP
- `.utpOnly`：禁用 TCP，启用 uTP

### 9. Throughput Optimizer（P0-1/P0-2）

```swift
await runtimeDownloader.startThroughputOptimizer(
    policy: .default
)

// 可选：检查状态
let enabled = await runtimeDownloader.isThroughputOptimizerEnabled()
print("optimizer enabled:", enabled)

// 停止并恢复 baseline 配置
await runtimeDownloader.stopThroughputOptimizer(restoreBaseline: true)
```

它会处理：

- 低速/零速窗口检测
- 对停滞下载做批量 reannounce
- 临时吞吐 boost（`connectionSpeed`、`torrentConnectBoost`、request queue、peer turnover）
- 在稳定恢复窗口后自动还原 baseline

### 10. 文件优先级、tracker 和 torrent 控制

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

### 11. 保存和恢复

适用于 iOS / macOS 重启后的持久化恢复：

```swift
let persistentStateURL = try await downloader.savePersistentState()
print(persistentStateURL.path)

let report = try await downloader.restorePersistentState()
print(report.restoredCount, report.degradedCount, report.failedCount)
```

这条路径用于持久化重启恢复：

- SDK 会保存 session manifest 和每个 torrent 的恢复产物
- 恢复时优先使用 native resume data，缺失时回退到持久化的 `.torrent` 元数据，再回退到仍然可用的原始 source
- 下游 App 应在启动、进入后台、以及定时 debounce 时触发保存

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
- swarm 计数能力（`peerCount/seedCount` + `peerTotalCount/seedTotalCount`）
- session 配置延迟应用和批量 reannounce 恢复 hooks
- 稀疏运行时补丁：限速、连接数、队列、rate-limit option 和 uTP/TCP 传输控制

## HTTPS Tracker 与 TLS Backend

- `libtorrent-apple` 现在只支持 `OpenSSL` 这一条 HTTPS tracker backend。
- 运行时可通过 `LibtorrentApple.backendInfo.supportsHTTPSTrackers` 确认能力位。
- 回归测试已覆盖 `https://.../announce` tracker URL 不再落入 `unsupported_url_protocol`。
- release 构建默认会同步并固定 `https://github.com/krzyzanowskim/OpenSSL.git` 的 `OpenSSL-Universal` 产物。
- 本地 release 构建仍支持显式传入 `OPENSSL_*` 路径；若未显式传入，也会继续尝试本地 `OpenSSL-Universal` checkout 或 SwiftPM cache。

## 本地构建与验证

### 公开包与维护者验证路径

对下游 App 来说，公开 SwiftPM 包现在只保留 `remote-binary` 一条消费路径。

当前公开包信息：

- 仓库：`https://github.com/clOudbb/libtorrent-apple.git`
- 最新公开包版本：`0.2.10`
- 当前二进制产物：`https://github.com/clOudbb/libtorrent-apple/releases/download/v0.2.10/LibtorrentAppleBinary-0.2.10.zip`
- 当前 binary module 身份：`LibtorrentAppleBinary_0_2_10`

- 每个 release tag 都会提交一份自包含的 `Package.swift`，其中直接写死 binary target 名、URL 和 checksum。
- 公开包始终通过稳定名字的 `LibtorrentAppleBridge` 内部桥接层访问底层二进制，而每个 release 都拥有独立的版本化 binary module 身份，例如 `LibtorrentAppleBinary_0_2_10`。
- `PackageSupport/BinaryArtifact.env` 只保留给维护者脚本使用，不再参与下游 SwiftPM 解析。

仅供维护者使用的验证路径：

- `source`：编译仓库内 bootstrap bridge target（`Sources/LibtorrentAppleBridge`），适合 API 开发和快速迭代。
- `local-binary`：加载 `Artifacts/release/` 下的版本化 XCFramework，并通过生成的 `Sources/LibtorrentAppleBridgeCompat` 兼容桥接层做与生产等价的行为验证。

验证 source dev package：

```bash
./scripts/validate-dev-package.sh source
```

构建 Apple 平台产物：

```bash
./scripts/sync-libtorrent.sh
./scripts/sync-openssl.sh
./scripts/build-apple-libs.sh
./scripts/smoke-test-macos-framework.sh
./scripts/make-xcframework.sh 0.2.10
```

验证 local-binary dev package：

```bash
./scripts/validate-dev-package.sh local-binary
```

验证公开 remote-binary 包：

```bash
./scripts/validate-swift-package.sh remote-binary
```

验证两个 tag 在同一缓存目录里来回切换：

```bash
./scripts/validate-version-switch.sh \
  --repo-url https://github.com/clOudbb/libtorrent-apple.git \
  --version-a 0.2.9 \
  --version-b 0.2.10
```

用当前工作区做一次完整的本地自验：

```bash
./scripts/self-verify-version-switch.sh \
  --version-a 0.2.10 \
  --version-b 0.2.11-alpha.1
```

本地自验会把临时验证 tag 改写成 `binaryTarget(path:)`。
原因是 SwiftPM 对 URL 形式的 binary target 只接受 `https`，所以本地回归仍然验证同一套版本化 XCFramework 身份，只是不再伪造 HTTP 下载地址。

运行本地 benchmark demo：

```bash
cp PackageSupport/BENCHMARK_SOURCES_TEMPLATE.txt /tmp/benchmark-sources.txt
# 编辑 /tmp/benchmark-sources.txt，替换成你的磁力链接/.torrent 输入

./scripts/run-benchmark-demo.sh local-binary \
  --sources-file /tmp/benchmark-sources.txt \
  --duration 300 \
  --interval 1
```

demo 会输出：

- `session_samples.csv`
- `torrent_samples.csv`
- `summary.json`
- `samples.json`

### 发布路径

- 手动发布：先执行 `./scripts/release.sh <version>`，提交 `Package.swift`、`Sources/LibtorrentAppleBridgeCompat`、`PackageSupport/BinaryArtifact.env`，创建并推送 tag，再手动上传生成的 zip，或者执行 `./scripts/publish-github-release.sh <version>` 自动创建 GitHub Release。
- GitHub 自动发布：`Release` workflow 会执行同一套 prepare 流程，提交 `Package.swift`、`Sources/LibtorrentAppleBridgeCompat`、`PackageSupport/BinaryArtifact.env`，创建并推送 tag、发布 GitHub Release，并在最后执行 remote-binary 验证；如果提供 baseline 版本，还会额外执行 tag 切换验证。

## 指定其他 upstream 版本构建

默认会使用 `scripts/versions.env` 里固定的 upstream 版本，这样构建更可复现。

如果你想直接追 upstream 最新 release tag：

```bash
LIBTORRENT_REF=latest ./scripts/sync-libtorrent.sh
OPENSSL_REF=latest ./scripts/sync-openssl.sh
```

如果你想临时指定某个版本：

```bash
LIBTORRENT_REF=v2.0.12 ./scripts/release.sh 0.2.11-alpha.1
OPENSSL_REF=3.6.2000 ./scripts/release.sh 0.2.11-alpha.1
```

如果你想在一次 release 构建里同时追两者最新版本：

```bash
LIBTORRENT_REF=latest OPENSSL_REF=latest ./scripts/release.sh 0.2.11-alpha.1
```

## Release 与 SwiftPM 的关系

SwiftPM 真正依赖的是 GitHub Release 上的二进制 zip。

对 SwiftPM 来说，真正必须的是：

- 仓库里的 `Package.swift`
- 仓库里的 `Sources/LibtorrentAppleBridgeCompat`
- GitHub Release 上的 `LibtorrentAppleBinary-<version>.zip`

这个 zip 里已经包含完整的版本化 `.xcframework`。  
所以给 SwiftPM 发版时，不需要单独上传 `.framework` 目录。

对当前和后续 release tag：

- 每个 release 都拥有独立的内部 binary module/framework 名
- 根 `Package.swift` 对下游消费完全自包含
- release 资产不可覆盖，发现问题只能发新 tag
- 下游稳定性通过 `旧版本 -> 新版本 -> 旧版本` 共用缓存回归验证

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
ValidationFixtures/
  SPMVersionSwitchConsumer/
Sources/
  LibtorrentApple/
    Models/
    Errors/
    Session/
  LibtorrentAppleBridge/
    include/
  LibtorrentAppleBridgeCompat/
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
