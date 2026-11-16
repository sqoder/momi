# momi 菜单栏标题极简化 (方案 A) 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 优化 momi 菜单栏文案为极致轻量纯文字（方案 A），消除刘海屏下的溢出裁剪问题。

**Architecture:** 
1. 修改 `src/main.swift` 中的初始标题和 `updateDashboardState()` 状态机输出，移除 `· 生成中`、`· 双路并发`、`tok/s` 等冗余字符；
2. 生成态输出 `%.1f t/s`（~45 pt），空闲态无速度时输出 `--`（~15 pt）；
3. 使用 `momi-menubar-fixture-verify` 管线验证标题格式与无污染，最后编译重装并在实机运行。

**Tech Stack:** Swift, AppKit, NSStatusItem

---

## Global Constraints
- 绝不污染 `~/Library/Application Support/momi/usage.json`。
- 绝不改动 `src/main.swift` 以外无关的逻辑（符合 Karpathy Surgical Changes 原则）。
- 使用 `verify-menubar.sh` 进行端到端验证后方可提交与更新 `/Applications/momi.app`。

---

## Task 1: 精简 `src/main.swift` 中的状态栏标题

**Files:**
- Modify: `src/main.swift:2214-2217`, `src/main.swift:3175-3195`

- [x] **Step 1: 修改初始启动标题**
  将 `statusItem.button?.title = "-- tok/s"` 改为 `statusItem.button?.title = "--"`。

- [x] **Step 2: 修改 `updateDashboardState()` 文案格式**
  - 并发态：`displaySpeed > 0 ? String(format: "%.1f t/s", displaySpeed) : "生成中"`
  - 单 Agent 态：`gen.currentSpeed > 0 ? String(format: "%.1f t/s", gen.currentSpeed) : "生成中"`
  - 空闲态：`speed > 0 ? String(format: "%.1f t/s", speed) : "--"`

- [x] **Step 3: 验证菜单栏标题格式与长度**
  确认菜单栏在生成态输出 `%.1f t/s`、空闲态输出 `--`，窄刘海屏下不被系统裁剪。

- [x] **Step 4: 运行单元测试**
  运行 `./scripts/test.sh`，确认核心格式化与测速解析检查全部通过。

- [x] **Step 5: 编译并重新部署 `/Applications/momi.app`**
  运行 `./scripts/build.sh`，启动新版应用并确认在 macOS 菜单栏正常居留与显示。
