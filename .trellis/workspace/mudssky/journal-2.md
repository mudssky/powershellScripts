# Journal - mudssky (Part 2)

> Continuation from `journal-1.md` (archived at ~2000 lines)
> Started: 2026-09-06

---



## Session 69: WSL 内 browser-debug 互操作：快捷方式生成与调试 Profile 启动

**Date**: 2026-09-06
**Task**: WSL 内 browser-debug 互操作：快捷方式生成与调试 Profile 启动
**Branch**: `master`

### Summary

实现 WSL 交互式 wrapper（shell/shared.d/browser-debug.sh）与 UNC 快捷方式 Bypass 修复，经 Windows pwsh interop 实测 create/start/CDP/stop 全链路；真实 Chrome User Data 克隆为 debug Profile（localhost:9222 从 WSL 直连）。沉淀 repo-ops wsl-windows-interop reference 记录五条直调硬约束（Bypass、pwsh7 硬依赖、UTF-8 编码、-Command 空格分割、pwsh 路径探测）。修复 Resolve-Path 在 WSL UNC 上返回 FileSystem:: 前缀且不折叠 .. 的兼容问题（browser-debug 与 Format-PowerShellCode 两处）。门禁：pnpm qa、qa:bash 107、test:pwsh:qa 235、Windows 侧 BrowserDebug 套件 61/61 全绿；Docker lane 的 scoop shim 失败经 stash 证明为 master 既有问题。

### Git Commits

| Hash | Message |
|------|---------|
| `fbc8dce3` | (see git log) |
| `0b2384d2` | (see git log) |
## Session 69: browser-debug 支持 macOS/Linux 与平台快捷方式

**Date**: 2026-09-06
**Task**: browser-debug 支持 macOS/Linux 与平台快捷方式
**Branch**: `master`

### Summary

browser-debug CLI 扩展为三平台：local 模式全链路（create/start/status/stop/guide/快捷方式）支持 macOS/Linux，lan 与 ssh 保持仅 Windows。新增平台分派层（浏览器发现、User Data 定位、ditto/cp -a 克隆、ps 进程解析 + argv[0] 前缀所有权、.command/.desktop 快捷方式）。macOS 实机验收发现并修复三个问题：Unix detached 启动 SIGHUP 级联关闭浏览器（改 nohup）、Homebrew 裸 apphost 在干净环境双击失败（env -i 探测可用 pwsh）、默认端口与本机常驻 Chromium 冲突（默认统一 21229）。全量 942 测试与 qa 全绿，coverage 61.43%。Linux 分支依赖 CI/WSL 执行 pnpm test:pwsh:all 覆盖。

### Git Commits

| Hash | Message |
|------|---------|
| `c6b3b637` | (see git log) |

### Status

[OK] **Completed**


## Session 71: ser8 新机装机排障与 Linux 安装流水线四项修复

**Date**: 2026-09-09
**Task**: ser8 新机装机排障与 Linux 安装流水线四项修复
**Branch**: `master`

### Summary

在 ser8（Ubuntu 26.04 新机）装机过程中定位并修复 Linux 安装流水线四个缺陷：1) verify 对 JSON 配置调用 ContainsKey 崩溃 + 99verifyInstall.ps1 缺失 -NonInteractive/-Unattended 声明；2) brew shellenv 不落盘 + ProfileTools 依赖继承 PATH，新机 07 误报 fnm/uv Blocked（01 持久化 shellenv + ProfileTools 自解析）；3) pester 容器 /tmp tmpfs 默认 noexec 导致 scoop shim 用例必败（tmpfs 改 :exec）；4) RcloneOps 用例写仓库真实 .runtime 路径，与容器 root lane 属主冲突（改 $TestDrive 隔离）。全部经 trellis-implement/trellis-check 子代理流程，pnpm test:pwsh:all 双 lane 全绿（host 945/0，linux 943/0）。ser8 侧同步：PSGallery 信任、brew shellenv 临时补丁、Docker Engine 装机。

### Git Commits

| Hash | Message |
|------|---------|
| `fc8c7dcb` | (see git log) |
| `849533f2` | (see git log) |
| `6dea7a41` | (see git log) |
| `9f730fb6` | (see git log) |

### Status

[OK] **Completed**
