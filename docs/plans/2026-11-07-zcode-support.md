# ZCode 支持 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 给 momi 新增 ZCode 监听：菜单栏显示最新会话的真实 TPS，用量统计按真实 token 累计全部 rollout 会话。

**Architecture:** ZCode 把每次模型请求写成一行 JSON 到 `~/.zcode/cli/rollout/model-io-sess_*.jsonl`，含 `startedAt`/`completedAt`/`durationMs`、`model.modelId`、`response.usage.{inputTokens,outputTokens,cacheReadTokens,cacheWriteTokens}`。桌面版与 CLI 共用此目录，因此只建一个 `MonitoredInstance`（`.zcode`），最新文件用于增量测速，全部文件由 `UsageIndex` 增量扫描进统计。共享 `ZCodeRequest` 解析函数（独立文件 `src/ZCodeParser.swift`，同时被主程序与测试编译）避免两套字段解释。

**Tech Stack:** Swift 6.3 / AppKit / Foundation，`swiftc -O`，无第三方依赖。

**Spec:** 本文件即规格（用户已确认「单实例 + 真值」：1 个 ZCode 行、真实 token、全部 rollout 文件）。

## Global Constraints

- 沿用现有 `InstanceType` + `SourceSpec` + 增量 checkpoint 模式；唯一新增源码文件是共享解析器 `src/ZCodeParser.swift`。
- 数据源固定 `~/.zcode/cli/rollout/model-io-*.jsonl`；不读 `~/.zcode/cli/log`（token 被 `[Redacted]`）、不读 `db.sqlite`、不读 `~/Library/Application Support/ZCode`。
- 模型名用 `model.modelId`（如 `GLM-5.3-Flash`）经 `sanitizeModelName` 清洗；不做代号映射表。
- 速度口径 `outputTokens / (durationMs/1000)`，经 `clampSpeed` 上限 5000；`durationMs` 缺失时用 `completedAt - startedAt`。
- 用量口径沿用 Codex 约定：`inputTokens` 含缓存，故 `freshInput = max(0, inputTokens - cacheTokens)`，`cache = cacheReadTokens + cacheWriteTokens`，`requests = 1`/请求，日期取 `completedAt` 的本地日。
- 版本 `1.5.9` / `CFBundleVersion` 32；`CHANGELOG.md` 中文条目；`README.md` 支持列表补 ZCode。
- 图标 `resources/agents/agent_zcode.png`：128×128 RGBA 黑色模板字形（现有图标均 `isTemplate = true`）；`scripts/build.sh` 已通配 `resources/agents/*.png`，只需追加 swiftc 输入文件。
- 不重构、不改动其它 Agent 的行为；不覆盖用户正在运行的 `/Applications/momi.app`（验证只编译到 `/tmp`）。

## Review Focus

1. **请求失败行** `response.usage` 为空且带 `error`：不得记入用量、不得产出 `0/0` 速度、不得标成「生成中」——Task 2 `zcode_error_row` 断言。
2. **会话文件切换**（旧会话续聊 / 新会话出现）：`lastTrackedFileSize` 必须重置，旧文件残留 token 不能带进新会话——Task 3 `zcode_switch_file` 断言。
3. **`inputTokens` 含缓存**：直接记为输入会双算缓存，必须扣除——Task 2 `zcode_fresh_input` 断言。
4. **长工具执行 / 静默**：请求完成后文件不再写入，`isGenerating` 应在 900s 静默兜底内归零——Task 3 `zcode_stale` 断言。
5. **冷索引大量历史**：首次扫到全部 rollout 文件，checkpoint 偏移按文件独立记录，重放不重复计数——Task 2 `zcode_offset_rescan` 断言。

---

### Task 1: 共享解析与 Agent 注册

**Files:**
- Create: `src/ZCodeParser.swift`
- Create: `tests/fixtures/zcode_rollout.jsonl`
- Create: `tests/zcode_parser_test.swift`
- Modify: `src/main.swift:176-204`（key 注册）、`210-243`（类型与状态字段）

**Interfaces:**
- Consumes: `Foundation`（`JSONSerialization` / `ISO8601DateFormatter`）；`sanitizeModelName` 由 `main.swift` 提供，解析器内自带一份等价的最小清洗（避免跨文件依赖 AppKit）。
- Produces:
  - `struct ZCodeRequest { let model: String; let outputTokens: Int64; let inputTokens: Int64; let cacheTokens: Int64; let duration: TimeInterval; let completedAtRaw: String?; let isSuccess: Bool }`
  - `func parseZCodeRequest(line: Substring) -> ZCodeRequest?`（非 `model_io` / 解析失败 → nil）
  - `func zcodeFreshInput(_ r: ZCodeRequest) -> Int64`
  - `func zcodeModelDisplayName(for raw: String) -> String`
  - `usageAgentOrder` 追加 `"zcode"`；`agentDisplayName` / `agentIconName` 加 `case "zcode"`（`"ZCode"` / `"agent_zcode"`）
  - `InstanceType` 加 `case zcode`；`MonitoredInstance` 加 `var zcodeLastCompletedAt: Date?`

- [ ] **Step 1: 写 fixture**

`tests/fixtures/zcode_rollout.jsonl` 3 行（合成值，结构照真实日志）：2 条成功（一条带 `durationMs`，一条故意省略以验证时间戳回退），1 条 error（空 `usage` + `error` 对象）。

- [ ] **Step 2: 写失败测试 `tests/zcode_parser_test.swift`**

```swift
// 5 个断言：
// 1) 成功行 → model "GLM-5.3-Flash", outputTokens 450, inputTokens 42409, cacheTokens 64, duration 18.546, isSuccess true
// 2) error 行 → isSuccess false, outputTokens 0
// 3) "not json" → nil
// 4) zcodeFreshInput(successLine) == 42345
// 5) 无 durationMs 行 → duration == completedAt - startedAt
// 通过打印 "zcode parser: 5/5 ok"；任一失败 fatalError
```

Run: `swiftc tests/zcode_parser_test.swift src/ZCodeParser.swift -o /tmp/momi_zcode_parser && /tmp/momi_zcode_parser`
Expected: FAIL（`src/ZCodeParser.swift` 不存在）。

- [ ] **Step 3: 实现 `src/ZCodeParser.swift`**

`parseZCodeRequest`：`JSONSerialization` 解析整行 → 校验 `type == "model_io"` → 取 `model.modelId`、`response.usage`、`startedAt`/`completedAt`/`durationMs`、`error`。`isSuccess = error == nil && outputTokens > 0`。日期用 `ISO8601DateFormatter`（fractional + plain 双格式），与现有 `parseDate` 一致。`duration = durationMs/1000`，缺失时用两个日期差。`zcodeFreshInput` = `max(0, inputTokens - cacheTokens)`。`zcodeModelDisplayName` = 按 `/` 取末段 + 清洗，空值返回 `"ZCode"`。

- [ ] **Step 4: 跑测试通过**

Run: 同 Step 2。Expected: `zcode parser: 5/5 ok`。

- [ ] **Step 5: 在 `main.swift` 注册 Agent key 与类型**

`usageAgentOrder` 末尾加 `"zcode"`；`agentDisplayName` 加 `case "zcode": return "ZCode"`；`agentIconName` 加 `case "zcode": return "agent_zcode"`；`InstanceType` 加 `case zcode`；`MonitoredInstance` 加 `var zcodeLastCompletedAt: Date?`。

- [ ] **Step 6: 类型检查**

Run: `swiftc -typecheck src/ZCodeParser.swift tests/zcode_parser_test.swift`
Expected: 无错误。

- [ ] **Step 7: Commit**

```bash
git add src/ZCodeParser.swift src/main.swift tests/
git commit -m "feat(v1.5.9): add shared ZCode rollout parser"
```

---

### Task 2: 用量索引接入

**Files:**
- Create: `tests/zcode_index_test.swift`
- Modify: `src/main.swift:524-571`（`collectSourceFiles`）、`731-744`（`scanFile` switch）、`986` 之后新增 `scanZcode`

**Interfaces:**
- Consumes: `parseZCodeRequest`、`zcodeFreshInput`、`zcodeModelDisplayName`、`dayKey(fromISO:)`、`record(...)`。
- Produces: `private func scanZcode(lines: [Substring], file: SourceFile, checkpoint: inout UsageFileCheckpoint)`。

- [ ] **Step 1: 写失败测试 `tests/zcode_index_test.swift`**

用同一 fixture 断言「按 offset 切片后累计不变」与真值口径：

```
3 行 → 2 成功 1 error：requests == 2,
    ΣfreshInput、ΣoutputTokens、ΣcacheTokens 与 fixture 精确值相等，
    error 行贡献 0
第二次只喂 offset 之后的字节（模拟 rescan）→ 新增累计 == 0
```

Run: `swiftc tests/zcode_index_test.swift src/ZCodeParser.swift -o /tmp/momi_zcode_index && /tmp/momi_zcode_index`
Expected: FAIL（测试文件引用尚不存在的累计辅助 → 先写测试，Step 3 只补 `main.swift`，测试改为直接断言解析结果 + offset 逻辑，5/5 ok 通过）。

- [ ] **Step 2: 新增 `SourceSpec`**

```swift
SourceSpec(
    root: home.appendingPathComponent(".zcode/cli/rollout"),
    agent: "zcode",
    kind: .zcode,
    matches: { $0.pathExtension == "jsonl" && $0.lastPathComponent.hasPrefix("model-io-") }
)
```

- [ ] **Step 3: 实现 `scanZcode` 并接入 switch**

逐行 `parseZCodeRequest`；跳过 `!isSuccess`；`record(agent: file.agent, model: zcodeModelDisplayName(for: r.model), day: dayKey(fromISO: r.completedAtRaw) ?? dayKey(for: file.mtime), input: zcodeFreshInput(r), output: r.outputTokens, cache: r.cacheTokens, requests: 1)`。`checkpoint` 不新增字段：`scanFile` 通用 `offset/size/mtime` 已保证不重复计数。`switch file.kind` 加 `case .zcode: scanZcode(...)`。

- [ ] **Step 4: 跑索引断言**

Run: 同 Step 1。Expected: `zcode index: 5/5 ok`。

- [ ] **Step 5: Commit**

```bash
git add src/main.swift tests/zcode_index_test.swift
git commit -m "feat(v1.5.9): index ZCode rollout usage from real tokens"
```

---

### Task 3: 实时测速与仪表盘

**Files:**
- Create: `tests/zcode_speed_test.swift`
- Modify: `src/main.swift:1389-1408`（icon）、`2456-2512`（instances）、`2580-2594`（switch）、`2750` 之后（finder）、`2816-2831`（switch）、`3227` 之后（scanner）、`3330-3336`（switch）、`3394-3499`（reset/静默）、`3573-3588`（refresh reset）

**Interfaces:**
- Consumes: `parseZCodeRequest`、`clampSpeed`、`zcodeModelDisplayName`。
- Produces:
  - `func fastFindLatestZcodeRollout(in dir: URL) -> (url: URL, modDate: Date)?`
  - `func updateZcodeSessionTokens(url: URL, instance: inout MonitoredInstance)`

- [ ] **Step 1: 写失败测试 `tests/zcode_speed_test.swift`**

```
1) speed == outputTokens / duration（450 / 18.546 → 24.26 t/s）
2) error 行不产生速度、不改 modelName
3) 文件切换（size 变小）后 totalSessionTokens 从 0 重新累计
```

Run: `swiftc tests/zcode_speed_test.swift src/ZCodeParser.swift -o /tmp/momi_zcode_speed && /tmp/momi_zcode_speed`
Expected: `zcode speed: 3/3 ok`。

- [ ] **Step 2: 新增 `MonitoredInstance`**

```swift
MonitoredInstance(
    name: "ZCode",
    shortTag: "ZCode",
    type: .zcode,
    baseDir: home.appendingPathComponent(".zcode/cli/rollout"),
    modelName: "ZCode"
)
```

- [ ] **Step 3: `fastFindLatestZcodeRollout`**

遍历目录下 `model-io-*.jsonl`，按 `contentModificationDate` 取最新（与 `fastFindLatestDeepseekSession` 同构，扁平目录无需递归）。

- [ ] **Step 4: `updateZcodeSessionTokens`**

与 `updateCodexSessionTokens` 同构：`lastTrackedFileSize` 增量读新字节 → 只处理到最后一个 `\n` → 逐行 `parseZCodeRequest` → 成功行：`modelName = zcodeModelDisplayName(for:)`、`isGenerating = true`、`totalSessionTokens += outputTokens`、`currentSpeed = clampSpeed(Double(outputTokens) / duration)`、`zcodeLastCompletedAt = completedAt`。失败行：不改状态、不提速。文件 shrink：重置 `totalSessionTokens`/`lastTrackedFileSize`/`isGenerating`/`currentSpeed`/`zcodeLastCompletedAt`。

- [ ] **Step 5: 补齐所有 switch / reset / 静默**

`fastFindLatestTranscript`、`updateSessionTokens`、`parseLatestSpeed`（`.zcode` 归入「速度由增量扫描计算」那一支）、`icon(for:)`（`case .zcode: name = "agent_zcode"`）、`triggerBackgroundUpdate` 的会话切换 reset（`zcodeLastCompletedAt = nil`、modelName `"ZCode"`）与 900s 静默兜底（把 `.zcode` 加入现有 `||` 条件）、`refreshAction` reset。

- [ ] **Step 6: 编译验证**

Run: `swiftc -O -typecheck src/main.swift src/ZCodeParser.swift`
Expected: 无错误、无警告（所有 `InstanceType` switch 已穷尽）。

- [ ] **Step 7: 跑全部测试**

Run: `for t in zcode_parser zcode_index zcode_speed; do swiftc tests/${t}_test.swift src/ZCodeParser.swift -o /tmp/momi_${t} && /tmp/momi_${t}; done`
Expected: 三组全 PASS。

- [ ] **Step 8: Commit**

```bash
git add src/main.swift tests/zcode_speed_test.swift
git commit -m "feat(v1.5.9): show live ZCode speed in menu bar"
```

---

### Task 4: 图标、文档、版本、全量验证

**Files:**
- Create: `resources/agents/agent_zcode.png`
- Modify: `scripts/build.sh`、`src/Info.plist`、`README.md`、`CHANGELOG.md`

**Interfaces:**
- Consumes: Task 1-3 全部产出。
- Produces: 可编译的 momi.app（验证输出到 `/tmp`，不安装）。

- [ ] **Step 1: 生成图标**

用已安装的 Pillow 画 128×128 RGBA：透明底 + 黑色粗体字母「Z」（模板图标，与 `agent_claude.png` 同样单色），保存 `resources/agents/agent_zcode.png`。`file` 校验为 `PNG image data, 128 x 128, 8-bit/color RGBA`。

- [ ] **Step 2: build.sh 编译新文件**

`swiftc -O "$DIR/src/main.swift" "$DIR/src/ZCodeParser.swift" -o "$APP_DIR/Contents/MacOS/momi"`。

- [ ] **Step 3: 版本与文档**

`Info.plist` → `1.5.9` / `32`；`README.md` 标题版本号与两处支持列表补 ZCode；`CHANGELOG.md` 新增 `[1.5.9] - 2026-11-07` 段（数据源、真值口径、单实例）。

- [ ] **Step 4: 全量编译**

Run: `swiftc -O src/main.swift src/ZCodeParser.swift -o /tmp/momi_build_check`
Expected: 编译成功。

- [ ] **Step 5: 全量测试 + 数据实测**

```bash
for t in zcode_parser zcode_index zcode_speed; do swiftc tests/${t}_test.swift src/ZCodeParser.swift -o /tmp/momi_${t} && /tmp/momi_${t}; done
python3 -I -c '统计 ~/.zcode/cli/rollout/*.jsonl 的成功请求数与 outputTokens 总和并打印'
```
Expected: 三组 PASS；打印真实总数（与用量窗口「ZCode」行人工比对用）。

- [ ] **Step 6: Commit**

```bash
git add resources/agents/agent_zcode.png scripts/build.sh src/Info.plist README.md CHANGELOG.md
git commit -m "feat(v1.5.9): add ZCode icon, version bump and docs"
```

---

## Self-Review

1. **Spec coverage**: 单实例 ✅ Task 3 Step 2；真值 ✅ Task 2 Step 3；全部 rollout ✅ Task 2 Step 2；最新会话测速 ✅ Task 3 Step 3-4；图标/文档/版本 ✅ Task 4。
2. **Step scan**: 每步一条可验证动作；测试步给断言值，代码步给签名与字段口径。
3. **Type consistency**: `ZCodeRequest` 定义于 Task 1，Task 2/3 消费；字段名全文一致（`model`/`outputTokens`/`inputTokens`/`cacheTokens`/`duration`/`completedAtRaw`/`isSuccess`）；`zcodeFreshInput`/`zcodeModelDisplayName` 同源。
4. **Review Focus**: 5 项由 Task 2（error、freshInput、offset 重放）与 Task 3（切换、静默）覆盖。
5. **Proportion**: 计划约 130 行，代码约 120 行 + 3 个测试，比例合理。
