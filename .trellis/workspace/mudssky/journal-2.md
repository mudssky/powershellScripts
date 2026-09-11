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


## Session 72: shell 层接管登录 profile：受管块替代 01 直写

**Date**: 2026-09-09
**Task**: shell 层接管登录 profile：受管块替代 01 直写
**Branch**: `master`

### Summary

评审发现 849533f2 让 01 直写 .profile 越界且追加位置在 .bashrc source 之后：非交互登录 shell（bash -lc/ssh/cron）的 .bashrc 早退导致 fnm env 不加载，node/pnpm 不可见（ser8 实测）。按用户设计意见改为 shell 层统一接管：shell/deploy.sh 新增 marker 受管块（先 brew prefix 探测去重、后 fnm env，幂等原位替换、时间戳 .bak、dry-run、bash/zprofile 分派），01 撤销直写，交互 shared.d 片段零改动，spec 三层职责校准。trellis-implement/trellis-check 子代理流程，check 8 组边界实测通过；pnpm test:pwsh:all 双 lane 全绿（host 945/0，linux 943/0）；ser8 回归清理手工痕迹后仅受管块即三命令全可见、幂等复跑无重复。

### Git Commits

| Hash | Message |
|------|---------|
| `fde35788` | (see git log) |

### Status

[OK] **Completed**


## Session 73: Windows WSL 自启接入流水线与 SSHCopyID 安装

**Date**: 2026-09-09
**Task**: Windows WSL 自启接入流水线与 SSHCopyID 安装
**Branch**: `master`

### Summary

brainstorm 勘察确认 WSL 自启机制层已存在（windows/wsl AtStartup+S4U 计划任务、portproxy 2222→sshd 2223、relay keepalive、mirrored 网络），缺口是未接入流水线与缺 SSHCopyID。激活 steps.psd1 windows 10 login-items → 新叶子 10deployWslAutostart.ps1（薄封装、幂等、前置不足 Blocked/10、WhatIf 零落盘）；apps-config winget 段新增 axeprpr.SSHCopyID 并实机确认 portable 作用域后补齐 08 Full winget 消费方（Invoke-WindowsWingetCatalogInstall，镜像 scoop 包装）；99 新增 login-items 只读检查。trellis-implement/check 子代理流程含两轮顺序回归修复（WhatIf 契约、Blocked 优先于参数错误，附静态顺序守卫）。pnpm test:pwsh:all 双 lane 全绿（host 956/0，linux 954/0）。RustDesk Windows 单独任务待开。

### Git Commits

| Hash | Message |
|------|---------|
| `5a996894` | (see git log) |

### Status

[OK] **Completed**


## Session 74: browser-debug LAN 指南自动探测 Tailscale 地址

**Date**: 2026-09-10
**Task**: browser-debug LAN 指南自动探测 Tailscale 地址
**Branch**: `master`

### Summary

为 browser-debug LAN 启动指南增加 Tailscale 地址自动探测：新增 Resolve-BrowserDebugTailscaleAddress 只读解析 tailscale status --json（3s 超时，全失败静默回退），Tailnet endpoint/探测/attach/Agent Prompt 改用真实 100.64/10 IPv4 并渲染主机名与 MagicDNS 别名可复制字段；未检测到时保持占位符加提示。同步 spec 合同、docs 索引与 6 个新 Pester 用例；pnpm test:pwsh:all 双车道全绿，qa 格式化步骤因本机缺 cargo 未跑（需 CI/WSL 补跑 format:pwsh）。

### Git Commits

| Hash | Message |
|------|---------|
| `40138881` | (see git log) |

### Status

[OK] **Completed**


## Session 75: Git 身份规则化：gitconfig 脚本按本地配置驱动

**Date**: 2026-09-11
**Task**: Git 身份规则化：gitconfig 脚本按本地配置驱动
**Branch**: `feat/git-identity-rules`

### Summary

把 gitconfig_personal.ps1 从逐仓写入身份改为 profile 配置驱动：身份数据移到不提交的 config/git/gitconfig.local.json，带 hosts 的 profile 渲染成 includeIf 规则由 Git 按 remote 自动选身份。新增 -InstallRules/-ShowCurrent/-Recurse/-ClearLocal/-ProfileName，移除无参数即写全局个人身份的旧行为，删除根目录 gitconfig_company.ps1。固化两个踩到的坑：includeIf 的 ** 紧跟冒号时不跨 / 会让 scp 简写漏匹配，每个 host 必须渲染 :* 与 :*/** 四条模式；判断身份健康必须读 --show-origin 来源文件，否则仓库级硬编码覆盖会被误判成健康。新增 35 个 Pester 用例与 infra spec，WSL 与 Windows 两侧已实测安装并验证八种 remote 形态。

### Git Commits

| Hash | Message |
|------|---------|
| `5b45c671` | (see git log) |
| `bb8eae45` | (see git log) |
| `576f9960` | (see git log) |

### Status

[OK] **Completed**
