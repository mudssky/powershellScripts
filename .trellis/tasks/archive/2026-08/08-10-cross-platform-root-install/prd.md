# 统一三系统根目录安装入口

## Goal

让已进入仓库根目录、且已具备 PowerShell 7 的用户，通过清晰且一致的根命令在当前 Windows、macOS 或 Linux/WSL 系统上预览或执行 Core/Full 安装，避免记忆底层 `install.ps1` 参数。

## Confirmed Facts

- 根 `install.ps1` 已通过 `Resolve-InstallPlatform` 自动识别当前系统，并统一编排 Windows、macOS、Linux 三个平台的 Stage 1；平台步骤真源为 `config/install/steps.psd1`。
- `Core` 执行 03～07 与 99；`Full` 追加 08～11。三个系统的真实叶子均已接入。
- 新机 Stage 0 仍必须使用各平台入口：`windows/00quickstart.ps1`、`macos/00bootstrap.zsh`、`linux/00quickstart.sh`。Stage 0 负责准备 Git、平台包管理器、仓库和 PowerShell 7，然后移交根 Stage 1。
- 根 `package.json` 目前只有 `pwsh:install` 与 `scripts:install`，两者均为无参数 `install.ps1`，语义是仓库开发工具准备，不是完整系统安装。
- `package.json`/pnpm 入口依赖 Node.js 与 pnpm，因此不能替代新机 Stage 0。
- pnpm 11 会把脚本名后的参数直接传给底层命令；额外写 `--` 会把字面量 `--` 传给 PowerShell。为避免与 pnpm 内置 `install` 命令重名，快捷入口统一采用仓库已有系统配置语义 `provision:*`。
- 真实 smoke 发现 `Write-InstallRunText` 的多参数格式表达式缺少外层括号，Text 模式会抛出格式化异常；JSON 模式已证明 Stage 1 预览执行链本身可完成。

## Requirements

- 保持 `install.ps1` 为安装行为和平台判断的唯一根实现，不在 `package.json` 复制三套平台业务。
- 保持无参数 `install.ps1`、`pnpm pwsh:install` 与 `pnpm scripts:install` 的现有开发环境准备语义。
- 为已完成 Stage 0 的用户提供按安装意图命名的 pnpm Stage 1 快捷入口；Windows、macOS 与 Linux/WSL 使用相同命令，入口直接转交 `install.ps1` 并由其自动识别当前平台。
- 提供步骤列表、Core/Full 预览和 Core/Full 执行入口；执行入口保留向 `install.ps1` 追加参数的能力。
- 修复根安装编排器 Text 汇总的多参数格式化，使默认 preview 命令能输出人类可读结果，并增加行为回归测试。
- 文档必须明确区分“新机 Stage 0”和“仓库根 Stage 1”，使用无 pnpm 内置命令冲突的 `provision:*` 快捷入口，并按 pnpm 11 规则直接追加参数。

## Acceptance Criteria

- [x] `pnpm provision:list` 能列出当前平台的 Stage 1 步骤，且不触发 pnpm 依赖安装流程。
- [x] `pnpm provision:core:preview` 与 `pnpm provision:full:preview` 能以 `WhatIf` 输出 Text 汇总，不产生安装写入或格式化异常。
- [x] `pnpm provision:core` 与 `pnpm provision:full` 分别执行当前平台的 Core/Full；平台继续由 `install.ps1` 自动识别。
- [x] 执行入口可在脚本名后直接追加 `-NetworkMode`、交互模式或步骤过滤参数，不在 package scripts 固化第二套参数逻辑。
- [x] Text 汇总测试覆盖包含多个占位符的运行标题、步骤、source restore 与最终状态输出。
- [x] 旧 `pwsh:install` 与 `scripts:install` 行为不变。
- [x] `docs/INSTALL.md` 明确说明 package scripts 仅适用于 Stage 0 已完成且 Node/pnpm 可用的根 Stage 1。

## Out of Scope

- 使用 package scripts 安装 Node.js、pnpm、PowerShell 7 或平台包管理器。
- 新增第二套安装编排器或平台专属 npm 实现。
- 改变 Core/Full 的软件清单、步骤依赖或平台支持矩阵。
- 新增按 Windows/macOS/Linux 分别命名的重复 package scripts。
