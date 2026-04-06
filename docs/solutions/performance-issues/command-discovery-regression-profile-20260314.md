---
module: Profile
date: 2026-03-14
problem_type: performance_issue
component: tooling
symptoms:
  - "PowerShell Profile 加载耗时从约 1000ms 回归到 52368ms"
  - "全新 pwsh -NoProfile 进程中命令探测阶段单独耗时超过 60 秒"
  - "Windows 上缺失 choco、brew、apt 时，每个命令探测都可能卡住约 20 秒"
root_cause: wrong_api
resolution_type: code_fix
severity: high
tags: [profile, powershell, command-discovery, startup-performance, get-command]
---

# Troubleshooting: Profile 命令探测导致启动性能回归

## Problem

Profile 安装提示聚合改动后，PowerShell 启动时间从约 1 秒级回归到 50 秒级。问题只在真实冷启动路径中稳定复现，表现为 `Profile 加载耗时: 52368 毫秒`，严重影响日常 shell 使用。

根因不在 `starship`、`zoxide` 或代理检测本身，而是在同步启动阶段对缺失包管理器命令使用了错误的探测 API，触发了 PowerShell 命令发现的高成本回退链路。

## Environment

- Module: Profile
- Affected Component: PowerShell 启动期命令探测 / 安装提示聚合逻辑
- Platform: Windows 10.0.26200
- PowerShell: 7.5.4
- Key files:
  - `profile/features/environment.ps1`
  - `profile/Debug-ProfilePerformance.ps1`
  - `profile/core/loadModule.ps1`
  - `psutils/modules/commandDiscovery.psm1`
- Date: 2026-03-14

## Symptoms

- 用户实际看到 `Profile 加载耗时: 52368 毫秒`，原本基线约为 1000ms 左右。
- 全新 `pwsh -NoProfile` 子进程中，`Get-Command -Name @('starship','zoxide','sccache','fnm','scoop','winget','choco','brew','apt') -CommandType Application` 可达到 64770ms。
- 单独测量缺失命令时，`choco`、`brew`、`apt` 各自都可能消耗约 18-22 秒。
- `where.exe` 对同样的缺失命令几乎瞬时返回，说明问题不是简单的 PATH 文件系统扫描，而是 PowerShell 的命令发现回退逻辑。

## What Didn't Work

**Attempted Solution 1:** 继续依赖 `Get-Command -CommandType Application`，只是把工具和包管理器改成一次批量探测。

- **Why it failed:** 缺失命令会触发 PowerShell 命令发现回退，包含额外的 `get-*` 推断与更重的搜索路径，批量调用并不会规避这个成本，反而把多个高延迟探测叠加到了同步启动路径里。

**Attempted Solution 2:** 先假设问题只是 PATH 太长或某些目录过慢，使用 `where.exe` 做对照验证。

- **Why it failed:** `where.exe` 结果很快，说明根因不是“纯 PATH 遍历过多”，而是 `Get-Command` 语义过重；它帮助定位了问题，但本身不是修复方案。

**Attempted Solution 3:** 直接相信旧版 `Debug-ProfilePerformance.ps1` 结果。

- **Why it failed:** 旧诊断脚本当时只测工具探测，没有把新增的包管理器集合纳入 Phase 4.06，因此无法准确复现真实回归路径，必须先让诊断脚本跟真实启动路径保持一致。

## Solution

修复分成三步：

1. 为 `psutils` 新增统一的轻量命令探测 API：`Find-ExecutableCommand`
2. 将该模块纳入 Profile 同步核心加载路径，避免因为调用新 API 又触发 psutils 全量自动导入
3. 在 Profile 启动期只探测“当前平台真正需要”的工具和包管理器，避免 Windows 冷启动再去碰 `brew`、`apt` 之类无关命令

**Code changes**:

```powershell
# Before (broken):
$toolNames = @('starship', 'zoxide', 'sccache', 'fnm')
$packageManagerNames = @('scoop', 'winget', 'choco', 'brew', 'apt')
$trackedCommandNames = @($toolNames + $packageManagerNames)
$foundCommands = Get-Command -Name $trackedCommandNames -CommandType Application -ErrorAction SilentlyContinue

# After (fixed):
$toolNames = @('starship', 'zoxide', 'sccache', 'fnm')
$trackedToolNames = if ($runtimePlatform -eq 'windows') {
    @('starship', 'zoxide', 'sccache')
} else {
    $toolNames
}
$packageManagerNames = switch ($runtimePlatform) {
    'windows' { @('scoop', 'winget', 'choco') }
    'macos' { @('brew') }
    default { @('brew', 'apt') }
}
$trackedCommandNames = @($trackedToolNames + $packageManagerNames)
$commandDiscoveryResults = Find-ExecutableCommand -Name $trackedCommandNames -CacheMisses
```

```powershell
# New shared API:
Find-ExecutableCommand -Name @('starship', 'zoxide', 'scoop') -CacheMisses
```

**Verification commands**:

```powershell
# 1. 详细性能诊断
pwsh -NoProfile -NoLogo -File ./profile/Debug-ProfilePerformance.ps1

# 2. 冷启动 benchmark
pnpm benchmark -- command-discovery -Iterations 2

# 3. 质量验证
pnpm qa
```

**Observed result after fix**:

- `Debug-ProfilePerformance.ps1` 总耗时约 `1083ms`
- 其中 `4.06-command-discovery` 约 `220ms`
- benchmark 中：
  - `Find-ExecutableCommand` 平均 `321.37ms`
  - `Get-Command -CommandType Application` 平均 `17406.726ms`
  - 冷启动命令探测速率约提升 `54.164x`

## Why This Works

根因是 **在性能敏感的同步启动路径里，用了语义过重的通用命令发现 API**。

`Get-Command -CommandType Application` 看起来像“查可执行文件是否存在”，但在命令不存在时，PowerShell 仍会走一套昂贵的命令发现流程，包括额外的回退搜索和 `get-*` 推断。这在交互式一般命令发现里可以接受，但放进 Profile 启动同步路径就会把多个未命中成本直接叠加。

`Find-ExecutableCommand` 的修复关键在于两点：

1. **缩窄语义**：它只做“按当前 shell 可执行语义查外部命令”，不处理函数、别名、模块自动导入，也不复刻 `Get-Command` 的完整搜索行为。
2. **缩窄范围**：Windows 启动时只探测 Windows 真正需要的工具和包管理器，不再无意义地扫描 `brew` / `apt`。

这样既保住了聚合安装提示的功能，又把命令探测重新收回到可控成本范围内。

## Prevention

- **不要在 Profile 同步启动路径里直接用 `Get-Command -CommandType Application` 做缺失命令探测。** 如果只是判断外部命令是否存在，优先使用 `Find-ExecutableCommand`。
- **Profile 启动期的命令探测必须做平台裁剪。** 不要在 Windows 上探测 Linux/macOS 包管理器，反之亦然。
- **新增同步路径能力时，同时更新诊断脚本。** 否则 `Debug-ProfilePerformance.ps1` 会和真实启动路径脱节，导致回归被漏检。
- **任何启动期修改都要跑两类验证**：
  - `pwsh -NoProfile -NoLogo -File ./profile/Debug-ProfilePerformance.ps1`
  - `pnpm benchmark -- command-discovery`
- **如果启动期要调用新的 psutils 函数，必须先确认它位于核心同步模块集合中。** 否则会通过 `PSModulePath` 误触发 psutils 全量自动导入，直接抵消性能优化。

## Related Issues

No related issues documented yet.
