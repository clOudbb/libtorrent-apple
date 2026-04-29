# MILESTONE v0.2.9

Status: Planned
Date: 2026-03-27
Owner: libtorrent-apple maintainers

## 1. 目标

1. 新增 `qBittorrentParity.v1` 策略，尽可能对齐 qBittorrent 的吞吐相关策略与能力面。
2. 将 anime parity 升级为“严格对齐 animeko/anitorrent”的策略实现（计划命名 `animekoParity.v2`）。
3. 新增 `transmissionParity.v1` 策略，对齐 Transmission 风格的均衡连接、队列和 uTP/TCP 策略。
4. 完整暴露 `SessionConfiguration` 可调参数给下游，profile 仅作为参考 preset 与便捷入口。
5. 保持兼容：默认策略不变，不替换 `SessionConfiguration.default` 现有行为。

## 2. 范围与约束

### In Scope

1. 补齐吞吐关键 `settings_pack` 映射能力（Swift -> C -> Native -> binary/source 一致）。
2. 修正 runtime apply 语义，支持 libtorrent 常用特殊值语义（含 `-1` 场景）。
3. 交付 3 套正式 throughput reference profile：`animekoParity.v2`、`qBittorrentParity.v1`、`transmissionParity.v1`。
4. 构建基准对比与验收报告（baseline / anime / qb / transmission）。

### Out of Scope

1. 下游 App UI 设计与交互实现。
2. 非 BT 链路能力（搜索、播放等）。
3. 默认策略切换（本里程碑明确不改默认）。

## 3. 执行计划（待批准后实施）

### 阶段 A: 能力补齐（P0，阻塞项）

1. 扩展 `SessionConfiguration` 与 `libtorrent_apple_session_configuration_t` 字段，覆盖 qB/anitorrent 吞吐关键项。
2. NativeBridge 扩展映射并补齐 source/binary 一致性。
3. runtime apply 语义修复：
   - 区分“仅允许非负”的字段与“允许 `-1`”的字段。
   - 移除当前统一 `max(value, 0)` 的过度钳制策略。
4. 任务级参数能力补齐（例如 per-torrent 连接/上传槽等关键限制项）。

### 阶段 B: 策略档落地（P0）

1. `qBittorrentParity.v1`
   - 对齐 qB 的吞吐关键默认策略（连接并发、请求队列、磁盘队列、uTP/TCP、choking、announce 等核心项）。
   - 作为新增 profile，不替换默认策略。
2. `animekoParity.v2`
   - 严格对齐 anitorrent 当前策略值。
   - 修复现有 profile 行为差距（例如 tracker preset 仅常量存在但未自动注入的问题）。
3. `transmissionParity.v1`
   - 对齐 Transmission 风格的较低全局 peer 压力、下载队列、request queue 与 uTP/TCP 公平策略。
   - 作为新增 profile，不替换默认策略。

### 阶段 C: 验收基线与对比（P1）

1. Benchmark CLI 扩展，支持四组对比：
   - `baseline`
   - `animekoParity.v2`
   - `qBittorrentParity.v1`
   - `transmissionParity.v1`
2. 统一指标输出：
   - 平均下载速率（30s/60s/全窗口）
   - 峰值下载速率
   - 上传速率、上传量、下载量、ratio
   - connected peers/seeds 与 total peers/seeds
   - 会话连接数、告警与失败统计
3. 阈值（已确认）：
   - qB 对齐验收：同条件 5 分钟窗口平均下载速率差距 `<= 15%`。
   - anime 对齐验收：同条件贴近 anitorrent（目标 `<= 10%`，如受平台限制需附偏差归因）。

### 阶段 D: 文档与发布（P1）

1. README 增补 profile 使用说明与适用场景：
   - `baseline`（默认）
   - `animekoParity.v2`
   - `qBittorrentParity.v1`
   - `transmissionParity.v1`
2. 明确兼容策略：
   - 默认不变
   - 新增 profile 仅显式启用时生效
   - 下游可直接使用完整 `SessionConfiguration` 参数，也可先应用 profile 后覆盖具体字段
3. 形成里程碑收尾报告（完成项、风险、未达标项与后续动作）。

## 4. P0 TODO List（统一口径，执行清单）

说明：本节与 `8.5` 保持一一对应，作为实际执行与打勾清单。未全部完成前，不宣称“已对齐 qBittorrent 吞吐优化策略”。

1. [x] `SessionConfiguration` 补齐 qB 吞吐关键字段全集：`announce_to_all_trackers`、`announce_to_all_tiers`、`peer_turnover`、`peer_turnover_cutoff`、`peer_turnover_interval`、`mixed_mode_algorithm`、`choking_algorithm`、`seed_choking_algorithm`、`piece_extent_affinity`、`suggest_mode`、`max_concurrent_http_announces`、`stop_tracker_timeout`、`rate_limit_ip_overhead`、`allow_multiple_connections_per_ip`、`validate_https_trackers`、`ssrf_mitigation` 等。
2. [x] C Header 与 NativeBridge 同步扩展并完整映射上述字段到 `settings_pack`（禁止字段遗漏或默认值漂移）。
3. [x] `runtime apply` 语义精确对齐：可动态修改字段/必须重建字段严格区分，`-1` 语义按字段执行并有明确错误提示。
4. [x] `qBittorrentParity.v1` 升级为完整策略档：按 qB 吞吐相关默认策略逐项赋值，不再是参数子集。
5. [x] 增加 `deferred apply` 行为层：高频配置变更合并应用，避免频繁 apply 导致吞吐抖动。
6. [x] 增加会话事件策略：网络切换/系统唤醒后批量 `reannounce`，并记录恢复指标。
7. [x] 增加 peer class / uTP-TCP 行为控制接口（不仅静态参数）。
8. [x] 发现源策略标准化：Benchmark/Demo 强制同一 magnet、同一 tracker 集合、同一时间窗口进行公平 A/B。
9. [x] 指标补齐并固化输出：`Seeds/Peers connected(total)`、`Downloaded/Uploaded`、`Ratio`、连接稳定性、首次有效下载时间。
10. [x] 建立强制验收门禁：同条件 5 分钟窗口 `qB parity` 平均下载速率差距 `<= 15%`，并输出归因报告。
11. [ ] 完成 `source` / `local-binary` / `remote-binary` 三模式一致性校验（编译、功能、运行时行为）。
12. [ ] 发布流程强制化：先构建二进制产物并校验，再打 tag，再验证下游 SPM 拉取，杜绝 header/xcframework 版本错配。

### 4.2 v0.2.9 执行结果（本轮）

1. 新增会话级高级字段并贯通 `Swift -> C Header -> NativeBridge -> settings_pack`，补齐 qB 吞吐关键参数全集。
2. 新增运行时传输行为控制接口：`SessionTransportBehavior` + `setTransportBehavior/scheduleTransportBehaviorApply`，支持 uTP/TCP 动态策略切换。
3. Benchmark CLI 指标升级：补齐 `connected(total)`（peer/seed）、`Downloaded/Uploaded`、`Ratio`、连接稳定性（std-dev）、首次有效下载时间。
4. 新增公平 A/B 门禁脚本：`scripts/benchmark-parity-gate.sh`，强制同源/同 tracker/同窗口并输出 `gate_report.json`。
5. 新增一次性同条件测速对比脚本：`scripts/benchmark-once-compare.sh`（按参考组输出单次差异报告，无强门禁）。
6. 新增三模式一键校验入口：`scripts/validate-swift-package.sh all`，统一触发 `source/local-binary/remote-binary` 验证（其中 remote-binary 需等待本轮二进制产物发布后再验收）。
7. 构建与测试：`source` 模式已完成编译与测试通过（含新增 transport behavior + throughput optimizer 测试）；当前 `remote-binary` 因产物版本仍为 `v0.2.3`，与新 header/API 存在预期错配，待发布阶段完成项 11/12 收口。

### 4.3 本轮审查修正（qB/Transmission 吞吐对齐补强）

1. 修正 `qBittorrentParity.v1` 中仍偏离 qB/libtorrent 公开默认值的吞吐参数：
   - `maxAllowedIncomingRequestQueueSize = 2000`
   - `wholePiecesThreshold = 20`
   - `aioThreads = 10`
   - `checkingMemoryUsage = 32`
   - `filePoolSize = 5000`
   - `stopTrackerTimeout = 5`
   - `sendBufferLowWatermarkBytes = 10 KiB`
   - `sendBufferWatermarkBytes = 500 KiB`
   - `sendBufferWatermarkFactorPercent = 50`
2. 新增 `transmissionParity.v1`，覆盖 Transmission 风格的连接上限、下载队列、request queue、I/O 与 uTP/TCP 公平策略。
3. 修复 runtime apply 的“默认 0 值误写入”风险：运行中仅对发生变更的 integer settings 写入 `settings_pack`，避免 peer filter、tracker、proxy 等小配置变更把 libtorrent 启动默认值意外压成 0。
4. Benchmark 配置快照补齐 I/O 与 send-buffer 关键字段，避免验收报告只覆盖连接层参数。
5. 本轮未新增 C ABI 字段，避免在 `remote-binary` 产物重发前扩大 source/binary 错配面；per-torrent 连接数、上传槽、单任务限速仍应作为下一轮 ABI 版本化发布项。

### 4.4 策略目标调整

1. 正式目标 profile 收敛为三套：
   - `animekoParity.v2`：anime/anitorrent 取向，保留 anime tracker preset，采用更快 peer churn、更高请求队列与更高 I/O buffer。
   - `qBittorrentParity.v1`：qB/libtorrent 默认吞吐取向，偏 TCP、qB 默认 announce/request queue/send buffer/AIO/file pool。
   - `transmissionParity.v1`：Transmission 均衡取向，较低全局 peer 压力、下载队列限制、`reqq=2000` 等 request queue 对齐、uTP/TCP 公平策略。
2. 取消非 parity 的极限实验策略：
   - 原因：高并发/大队列不是某个成熟客户端的可复现策略，容易把瓶颈转移到移动端发热、内存、磁盘和 NAT/路由器压力。
   - public API、Benchmark CLI、README 与验收标准均只保留三套正式参考 profile。
3. API 定位调整：
   - 完整参数面通过 `SessionConfiguration` 暴露给下游。
   - profile 是 versioned convenience/reference preset，下游可以直接自定义，也可以先应用 preset 后覆盖字段。

## 4.1 历史进度（阶段 1，已完成）

说明：以下为前序阶段完成项，用于记录背景；不等价于“已完成 qB 完整吞吐对齐”。

1. [x] 扩展会话配置字段：新增连接/请求队列/I/O 线程等吞吐关键字段并完成 Swift->C 映射。
2. [x] 修复 runtime apply 字段语义：连接与 active limit 支持 `-1`，其余字段保持非负约束。
3. [x] 新增并落地 `qBittorrentParity.v1`（参数子集版本）。
4. [x] 升级并落地 `animekoParity.v2`（保留 `animekoParity.v1` 兼容）。
5. [x] 新增 `transmissionParity.v1`。
6. [x] 修复 tracker preset 自动注入能力缺口（`addTorrent` 自动应用 `trackerPresetURLs`）。
7. [x] Benchmark CLI 支持策略配置快照与 profile 选择（`animeko-parity-v2` / `qbittorrent-parity-v1` / `transmission-parity-v1`）。

## 5. 验收标准（Definition of Done）

1. 默认策略保持现状，不发生行为回归。
2. `animekoParity.v2`、`qBittorrentParity.v1`、`transmissionParity.v1` 可显式启用并输出完整配置快照。
3. source/binary 两种模式行为一致，不存在“某模式禁用能力”的分歧。
4. runtime apply 在支持字段上可稳定生效，错误字段有明确报错。
5. qB 对齐实验满足已确认阈值：平均下载速率差距 `<= 15%`（同机型/同网络/同资源/同窗口）。
6. 产出完整 benchmark 日志与总结文档，可复现。
7. `animekoParity.v2` 相对 `animekoParity.v1` 必须“非退化”：
   - 同条件下核心吞吐指标不得劣于 `v1`（平均下载速率、峰值下载速率、连接稳定性）。
   - 若 `v2 < v1`，必须先进行自检修复并重新验证；若仍无法稳定达到 `v1`，则回退 `animekoParity.v1` 作为默认 anime parity 策略实现。
8. `4. P0 TODO List（统一口径，执行清单）` 12 项全部完成并打勾。

## 6. 风险与预案

1. 风险：移动端平台约束导致无法完全达到桌面 qB 峰值。
   - 预案：严格同环境对比并给出“策略等价/平台差异”分离结论。
2. 风险：激进参数引发不稳定（高 CPU/高发热/网络抖动）。
   - 预案：正式 profile 只保留可对齐成熟客户端的参数组合；下游如需更激进配置，可基于公开 `SessionConfiguration` 自行覆盖。
3. 风险：字段扩展引发 source/binary 版本错配。
   - 预案：按发布流程先构建二进制、再更新 checksum/tag，发布前做跨模式编译校验。
4. 风险：`animekoParity.v2` 优化后出现吞吐回归（不如 `v1`）。
   - 预案：设置 `v2 vs v1` 强制门禁；回归时先自检修复，若仍不达标则回退到 `v1`。

## 7. 备注（本次已确认决策）

1. 同意按阶段执行（A -> B -> C -> D）。
2. 接受 qB 对齐验收阈值 `<= 15%`。
3. 默认策略保持不变，仅新增/保留三套正式参考 profile：`animekoParity.v2`、`qBittorrentParity.v1`、`transmissionParity.v1`。
4. anime parity 升级约束：`v2` 必须优于或至少不劣于 `v1`；若优化失败则回退 `v1`。

## 8. 后续优化计划（待确认后执行）

说明：本节为“继续优化开发”的执行草案。未确认前，仅保留文档计划，不推进代码实现。

### 8.1 优化目标（v0.2.9 补充）

1. 将 `qBittorrentParity.v1` 从“参数子集对齐”升级为“吞吐关键能力对齐（参数 + 行为）”。
2. 保持 `baseline`/`animekoParity.v1`/`animekoParity.v2`/`qBittorrentParity.v1`/`transmissionParity.v1` 兼容，默认策略不变。
3. 所有新增能力保证 `source` / `local-binary` / `remote-binary` 三模式一致。

### 8.2 优先级与工作分解

#### P0-A：补齐 qB 吞吐关键 settings 映射（参数层）

1. 新增并贯通以下字段（Swift -> C Header -> NativeBridge -> README）：
   - tracker/announce 相关：`announce_to_all_trackers`、`announce_to_all_tiers`、`max_concurrent_http_announces`、`stop_tracker_timeout`
   - 连接调度相关：`peer_turnover`、`peer_turnover_cutoff`、`peer_turnover_interval`
   - 传输策略相关：`mixed_mode_algorithm`、`choking_algorithm`、`seed_choking_algorithm`
   - 吞吐细项相关：`piece_extent_affinity`、`suggest_mode`、`rate_limit_ip_overhead`
2. 默认值策略：
   - 默认配置保持不变（新增字段默认“关闭或 libtorrent 默认行为”）。
   - 仅在 `qBittorrentParity.v1` 中显式赋值。

预估提升（同网络/同资源，单项非叠加）：`+3% ~ +25%`（连接质量较差场景可更高）。

#### P0-B：补齐 qB 行为层能力（非纯参数）

1. 增加“会话延迟重配（deferred apply）”机制，合并高频配置变更，减少 apply 抖动。
2. 增加“批量 reannounce”触发机制（用于网络切换/唤醒后恢复）。
3. 增加 uTP/TCP 策略行为控制接口，避免仅靠静态参数。

预估提升：`+0% ~ +15%`（主要提升稳定性与长窗口平均速率）。

#### P0-C：发现源能力强化（吞吐上限关键项）

1. 明确 `qBittorrentParity.v1` 的 tracker 策略（不默认注入 anime tracker；允许调用方显式注入）。
2. 在 demo/benchmark 中强制公平注入同一 tracker 集合，避免“策略差异被源差异掩盖”。
3. 输出“连接成功率/平均 peers/seeds/有效连接时间占比”指标用于归因。

预估提升：`+0% ~ +300%`（源不足场景最显著）。

#### P1：I/O 与平台相关吞吐细项（择机）

1. 评估是否补充：`send/recv socket buffer`、`listen_queue_size`、`hashing_threads`（LT2）等。
2. 仅在有明确瓶颈证据时纳入 profile，避免过度参数化。

预估提升：`+0% ~ +20%`（设备与网络依赖强）。

### 8.3 量化验收与门禁

1. 核心验收仍使用同机型/同网络/同资源/同窗口 A/B：
   - 5 分钟平均下载速率差距（目标：`qB parity <= 15%`）。
2. 新增门禁指标：
   - peers/seeds 连接稳定性（连接数 30s 滚动标准差）
   - 冷启动 120s 内首次有效下载时间
   - tracker 可用率与 reannounce 成功率
3. 判定原则：
   - 若吞吐未提升但“源质量指标”显著下降，判定为测试条件问题，不直接否定策略实现。
   - 若吞吐与连接稳定性均无改善，回滚该项并记录。

### 8.4 风险控制

1. 新增字段默认不生效，仅 profile 显式启用，避免影响现有策略。
2. 每次扩展 C Header 字段后，必须先重打 binary 再发 tag，防止源码/二进制接口错配。
3. 若 `animekoParity.v2` 相比 `v1` 退化，按既定规则先修复，不可修复则回退 `v1`。

### 8.5 完整对齐 qB 吞吐策略 TODO（必须全部完成）

说明：执行清单以 `4. P0 TODO List（统一口径，执行清单）` 为唯一真源，`8.5` 不再维护重复条目，避免清单漂移。
