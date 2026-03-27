---
module: PsUtils
date: 2026-03-14
problem_type: developer_experience
component: tooling
symptoms:
  - "`pnpm benchmark` 在缺少 Name 参数时直接报错，用户必须先执行 `--list` 再复制 benchmark 名称"
  - "交互选择逻辑分散在 benchmark 与 Docker 清理脚本中，后续脚本很容易重复实现 `fzf` 与文本降级"
  - "如果直接用 `Get-Command` 探测 `fzf`，会重新引入仓库已知的命令发现性能风险"
root_cause: missing_tooling
resolution_type: tooling_addition
severity: medium
tags: [powershell, psutils, benchmark, fzf, interactive-selection, fallback]
---

# Troubleshooting: 为 benchmark 和脚本工具沉淀可复用的交互选择模块

## Problem

仓库中的 benchmark 调度脚本在缺少 `Name` 参数时只会报错，要求用户先手动执行 `--list` 再复制名称，交互体验较差。与此同时，`fzf` 选择与文本降级逻辑已经分别散落在不同脚本中，如果继续做局部补丁，后续脚本会持续复制同一套实现。

这不是单一脚本的小修，而是一个工具链层面的缺口：仓库缺少统一的“候选项交互选择”基础设施，导致 CLI 体验和代码复用都不稳定。

## Environment

- Module: PsUtils / benchmark tooling
- Affected Component: `psutils/modules/selection.psm1`、`scripts/pwsh/devops/Invoke-Benchmark.ps1`
- Platform: PowerShell 脚本工具链，跨平台
- PowerShell: 7.5.x
- Key files:
  - `psutils/modules/selection.psm1`
  - `psutils/psutils.psd1`
  - `scripts/pwsh/devops/Invoke-Benchmark.ps1`
  - `psutils/tests/selection.Tests.ps1`
  - `tests/Invoke-Benchmark.Tests.ps1`
- Date: 2026-03-14

## Symptoms

- 用户运行 `pnpm benchmark` 时，会收到“缺少 benchmark 名称”的错误，而不是直接进入选择流程。
- 仓库里已经有 `fzf` 相关能力，但一个在 `functions.psm1`，一个在 `Clean-DockerImages.ps1`，没有形成统一 API。
- 如果在新模块里直接用 `Get-Command` 检测 `fzf`，会触发仓库已经踩过的命令发现成本问题，拖慢测试与交互路径。

## What Didn't Work

**Attempted Solution 1:** 继续在 `Invoke-Benchmark.ps1` 内局部添加 `fzf` 与文本编号选择逻辑。  

- **Why it failed:** 这只能修 benchmark 的单点体验，无法解决仓库里交互选择能力分散的问题；下一个脚本出现类似需求时，仍会继续复制实现。

**Attempted Solution 2:** 沿用 PowerShell 最直接的命令探测方式，用 `Get-Command` 判断 `fzf` 是否存在。  

- **Why it failed:** 仓库已有性能回归经验表明，`Get-Command` 在缺失命令场景下会触发高成本命令发现链路。对一个本应很轻的交互选择模块来说，这个代价不必要，也会放大测试时延。

**Attempted Solution 3:** 只做 `fzf` happy path，把文本编号选择当作附带兜底。  

- **Why it failed:** 这会让没有 `fzf` 的环境继续退回到糟糕的 CLI 体验，等于没有真正解决“脚本能引导用户完成选择”这个目标。

## Solution

修复最终分为三部分：

1. 在 `psutils/modules/selection.psm1` 新增统一 API：`Select-InteractiveItem`
2. 将新模块接入 `psutils/psutils.psd1`，让它成为标准可导出的公共能力
3. 改造 `Invoke-Benchmark.ps1`，在缺少 `Name` 时使用该模块完成选择，并显式处理取消返回值

### Code changes

```powershell
# Before (broken):
if ([string]::IsNullOrWhiteSpace($Name)) {
    Write-Error "缺少 benchmark 名称。先运行: pnpm benchmark -- --list"
    exit 1
}
```

```powershell
# After (fixed):
if ([string]::IsNullOrWhiteSpace($Name)) {
    $selected = Select-BenchmarkCatalogItem -Catalog $catalog -RepoRoot $repoRoot
    if ($null -eq $selected) {
        Write-Warning '已取消 benchmark 选择，本次不执行任何 benchmark。'
        return
    }
}
```

```powershell
# New shared API:
Select-InteractiveItem `
    -Items $Catalog `
    -DisplayScriptBlock { "{0} ({1})" -f $_.Name, $_.File } `
    -Prompt 'Benchmark > ' `
    -Header '请选择要运行的 benchmark'
```

```powershell
# Lightweight fzf detection:
function Test-InteractiveSelectionFzfAvailable {
    if (Test-Path Function:\fzf) { return $true }
    if (Test-Path Alias:\fzf) { return $true }
    return (-not [string]::IsNullOrWhiteSpace((Find-InteractiveSelectionExecutablePath -Name 'fzf')))
}
```

### Verification commands

```bash
# 模块行为测试
pwsh -NoProfile -Command "Invoke-Pester -Path './psutils/tests/selection.Tests.ps1' -Output Detailed"

# benchmark 集成测试
pwsh -NoProfile -Command "Invoke-Pester -Path './tests/Invoke-Benchmark.Tests.ps1' -Output Detailed"

# 仓库级验证
pnpm qa
```

### Verified result

- `Select-InteractiveItem` 支持字符串输入、对象输入、单选、多选、取消返回与 `fzf`/文本降级两条路径。
- `pnpm benchmark` 在未传名称时可直接进入交互选择，不再要求用户先手工复制 benchmark 名称。
- `pnpm qa` 通过，新增测试已纳入 QA 路径。

## Why This Works

根因不是 benchmark 脚本本身“少一个 if”，而是仓库缺少统一的交互选择基础设施。只在业务脚本里继续堆逻辑，会让 `fzf` 探测、文本降级、对象显示映射和多选解析持续散落在各处。

`Select-InteractiveItem` 的价值在于把这些横切关注点统一下沉：

1. **统一交互能力**：调用方只负责提供候选项和显示逻辑，不再各自实现 `fzf`/文本降级。
2. **保持边界清晰**：对象输入必须显式指定 `DisplayProperty` 或 `DisplayScriptBlock`，避免公共模块累积隐式字段猜测。
3. **避免性能回归**：`fzf` 探测不使用 `Get-Command`，而是走轻量 PATH/别名/函数检查，规避仓库里已知的命令发现高成本问题。
4. **兼顾自动化与交互式**：显式传入 `Name` 时，benchmark 仍保持原有非交互执行路径，不破坏参数透传与自动化调用。

## Prevention

- **以后只要有“从候选项里选一个或多个”的场景，优先复用 `Select-InteractiveItem`。** 不要再在脚本里单独复制 `fzf` 与文本降级逻辑。
- **对象候选项一律显式提供显示逻辑。** 不要在公共模块里猜 `Name`、`Title` 或 `DisplayName`。
- **不要在轻量探测路径里使用 `Get-Command` 检查外部工具。** 仓库已经证明它会放大命令发现成本，尤其是缺失命令场景。
- **交互式脚本必须显式处理取消返回值。** 单选取消返回 `$null`，多选取消返回空数组；调用方应自行决定退出、提示或重试。
- **为交互基础设施同时补模块级测试和集成测试。** 模块测试验证 API 语义，脚本集成测试验证真实 CLI 调用链。

## Related Issues

- See also: [command-discovery-regression-profile-20260314.md](../performance-issues/command-discovery-regression-profile-20260314.md)
