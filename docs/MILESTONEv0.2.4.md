# MILESTONE v0.2.4

Status: In Progress  
Date: 2026-04-02  
Owner: libtorrent-apple maintainers

## 1. 背景与问题总结

当前 iOS 真机 BT 异常在下游表现为“任务可添加，但长时间无吞吐/无 peers/无节点增长”。结合仓库现状，核心问题分三类：

1. 可观测性不足：`allTorrentStatuses()` 读取 native status 失败时静默回退缓存，错误不外显，导致误判。
2. 能力不透明：下游无法直接获知当前 binary 是否支持 `https tracker`。
3. 构建策略风险：`build-apple-libs.sh` 曾默认禁用 OpenSSL/GnuTLS，易导致 `https tracker unsupported URL protocol`。

## 2. 目标

1. 让 status 读取失败可被感知与追踪，不再“静默吞错”。
2. 在 bridge/API 暴露 HTTPS tracker 能力标记，便于下游启动期策略分流。
3. 将 TLS 后端策略改为可配置，避免默认强制禁用。
4. 在不走 release 的前提下完成本地开发与自验收，等待人工确认后再进入发布流程。

## 3. 范围

### In Scope

1. `TorrentSession` 状态轮询失败告警与失败计数。
2. Native bridge 新增 `supports_https_trackers` 能力接口（source + binary header + Swift 暴露）。
3. 构建脚本 TLS 后端策略参数化与元数据输出。
4. 文档化 v0.2.4 问题定义、执行项、验收项。

### Out of Scope

1. 直接发布新二进制产物与打 tag。
2. 下游 App 的 Info.plist、本地网络权限和 UI 行为修改。
3. 真机网络环境差异（运营商、路由、NAT 类型）本身的外部变量消除。

## 4. TODO（执行清单）

- [x] 新建 `MILESTONEv0.2.4` 文档并固化问题口径。
- [x] `TorrentSession.allTorrentStatuses()` 增加 status 读取失败告警，不再静默吞错。
- [x] 增加 status 失败计数与节流上报（首次 + 固定间隔）机制。
- [x] 调整状态融合策略：`running/idle` 优先采用 native state，降低“伪稳定”显示。
- [x] 新增 bridge 能力接口：`libtorrent_apple_bridge_supports_https_trackers()`。
- [x] Swift 暴露能力位：`LibtorrentApple.backendSupportsHTTPSTrackers`。
- [x] `TorrentBackendInfo` 增补 `supportsHTTPSTrackers`（含兼容解码）。
- [x] 构建脚本增加 `HTTPS_TRACKER_BACKEND=auto|openssl|gnutls|disabled`。
- [x] 构建元数据记录 TLS 后端策略，便于产物追踪。
- [ ] 在下游 iPhone 真机进行长窗口回归验证（由人工联调执行）。
- [ ] 用户确认后再进入 release 流程。

## 5. 自验收标准

- [x] `./scripts/validate-swift-package.sh source` 通过。
- [x] 关键改动文件编译通过，无新增 API 断裂。
- [x] 代码审查确认：status 失败路径会产生 `nativeEvent` 告警。
- [x] 代码审查确认：下游可读取 HTTPS tracker 支持能力位。

## 6. 风险与备注

1. 即使完成本里程碑，若网络环境本身不可达，DHT 仍可能低节点或无节点。
2. `remote-binary` 与新源码字段若未同步发布，仍会存在模式漂移，不在本里程碑内完成发布收口。
3. 发布动作延后，待用户确认代码后再执行。
