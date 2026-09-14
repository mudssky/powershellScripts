# Fix Linux verify ContainsKey crash and orchestrator NonInteractive forwarding

## Goal

修复 Linux 安装流水线在 99 verify 步骤上必然失败的缺陷，使 `install.ps1 -Preset Core -NonInteractive` 与 `99verifyInstall.ps1` 在新机（Ubuntu 26.04）上可用。问题在 ser8 新机安装时发现，本地 WSL（pwsh 7.5.2）同样复现，属 master 通用缺陷。

## Root Causes

1. `linux/pwsh/Test-InstallState.ps1` 的 `sources` 检查对 `Resolve-ConfigSources` 返回的 JSON 配置（PSCustomObject）调用 `.ContainsKey`，该方法只存在于 Hashtable，导致 verify 必然抛
   "PSCustomObject does not contain a method named 'ContainsKey'" 并退出 1。
2. `linux/99verifyInstall.ps1` 未声明 `-Unattended` / `-NonInteractive`。根编排器会把这两个公共交互开关无条件转发给所有叶子，pwsh wrapper 按叶子真实参数校验后抛
   "叶子脚本不支持参数: -NonInteractive"。同类的 macos `99verifyInstall.zsh`、`windows/99verifyInstall.ps1`、`03configureSources.sh`、`04deployShellConfig.sh` 均已接受这两个参数，唯独 Linux verify 遗漏。

## Requirements

- 修复 1：按 `.trellis/spec/psutils/package/shared-config-resolver.md` 契约，用 `ConvertTo-ConfigHashtable` 转换 `targets` 后再做键查找；不改变 `psutils/src/config` 的全局反序列化行为。
- 修复 2：为 `linux/99verifyInstall.ps1` 补声明 `[switch]$Unattended` / `[switch]$NonInteractive`（只读脚本，接受但无行为），与同目录 `07installProfileTools.ps1` 风格一致。
- 不改动编排器与 wrapper 的参数校验机制（它是防 typo 的安全设计）。

## Acceptance Criteria

- [x] `pwsh linux/99verifyInstall.ps1 -Preset Core` 不再抛 ContainsKey 异常，按实际环境输出 Pass/Blocked/Skipped。
- [x] `pwsh ./install.ps1 -Preset Core -Step verify -NetworkMode Direct -NonInteractive` 通过 wrapper 参数校验并正常完成。
- [x] `pwsh ./install.ps1 -Preset Core -WhatIf` 不再在 verify 步骤报错。
- [x] `pnpm qa`（158/0）与 `pnpm test:pwsh:all` 通过（938/1；唯一失败为 master 既有的 docker 套件 scoop 测试，干净 master stash 复跑同样失败，与本修复无关）。
- [x] 修复同步到 ser8 后，`-Preset Core -Step verify` 在真实新机环境可执行（不再崩溃；剩余 Fail 为 docker 未装等真实待办）。

## Notes

- ser8 安装现场另有两个非缺陷项：05 core-cli 未完成导致 07 node/pnpm 连锁 Blocked（重跑 core-cli 即可）；Pester 经 `Install-PSResource` 报 `repository ''` 疑似 ser8 到 PowerShell Gallery 的网络问题（待现场确认）。
