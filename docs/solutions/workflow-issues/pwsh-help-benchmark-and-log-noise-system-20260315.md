---
module: System
date: 2026-03-15
problem_type: workflow_issue
component: testing_framework
symptoms:
  - "`pnpm qa` 与 `pnpm test:pwsh:all` 的墙钟时间被少数 Pester 热点文件主导"
  - "`psutils/tests/help.Tests.ps1` 反复扫描真实 `psutils` 目录，Linux 开销尤为明显"
  - "`tests/Invoke-Benchmark.Tests.ps1` 为验证 CLI 包装层重复启动外层 `pwsh`"
  - "`tests/Sync-PathFromBash.Tests.ps1` 为 `WhatIf` 断言重复进行多次子进程采样"
root_cause: test_isolation
resolution_type: code_fix
severity: high
tags: [powershell, pester, benchmark, performance, console-output, pre-commit, test-isolation, qa, cross-platform]
---

# Troubleshooting: 继续收敛 Pester 热点测试的夹具、进程与日志开销

## Problem

在把 `help` 的性能比较迁出默认 full 门禁、并收口一轮 `WhatIf` / fallback 日志噪音之后，`pnpm qa` 和 `pnpm test:pwsh:all` 里仍有几类共享热点持续主导墙钟时间：

1. `psutils/tests/help.Tests.ps1` 还在为真实帮助搜索反复扫描整个 `psutils` 目录。
2. `tests/Invoke-Benchmark.Tests.ps1` 几乎每个 `It` 都要重新启动一次外层 `pwsh -NoProfile -File`。
3. `tests/Sync-PathFromBash.Tests.ps1` 为 append / prepend / login 三条 `WhatIf` 分支分别拉起子进程。

这类问题的共同点不是“业务逻辑慢”，而是测试没有把功能断言与高成本外部路径隔离开，导致目录扫描、模块导入、PowerShell 启动和主机输出处理成本被重复支付。

## Environment

- Module: System
- Affected Component:
  - `psutils/tests/help.Tests.ps1`
  - `tests/Invoke-Benchmark.Tests.ps1`
  - `tests/Sync-PathFromBash.Tests.ps1`
  - `scripts/pwsh/devops/Invoke-Benchmark.ps1`
- Related but unchanged context:
  - `tests/benchmarks/HelpSearch.Benchmark.ps1`
  - `PesterConfiguration.ps1`
- Platform: Windows host + Linux Docker container
- PowerShell: 7.5.4
- Pester: 5.7.1
- Date: 2026-03-15

## Symptoms

- 用户给出的慢文件列表里：
  - `psutils/tests/help.Tests.ps1`
    - host `3.95s`
    - linux `16.86s`
  - `tests/Invoke-Benchmark.Tests.ps1`
    - host `12.24s`
    - linux `8.26s`
  - `tests/Sync-PathFromBash.Tests.ps1`
    - host `4.08s`
    - linux `2.41s`
- `help.Tests.ps1` 的真实仓库扫描在 Linux 上尤其明显，说明问题不只是断言数量，而是输入集过大。
- `Invoke-Benchmark.Tests.ps1` 的主要成本不是 benchmark 本身，而是 CLI 包装层重复启动外层 `pwsh`。
- `Sync-PathFromBash.Tests.ps1` 的 `WhatIf` 验证虽然语义简单，但每条分支都要额外支付一次 shell 启动和模块导入成本。

## Solution

这次修复是在前一轮“迁出 help 性能比较、收口日志噪音”的基础上，继续把剩余热点按职责拆开。

### 1. `help.Tests.ps1` 改为最小帮助夹具 + wrapper 模块内 mock

`Search-ModuleHelp` 继续保留真实行为测试，但输入不再是整个 `psutils` 目录，而是一个最小帮助夹具目录。  
`Find-PSUtilsFunction` 和 `Get-FunctionHelp` 则改成 wrapper 级测试，在 `InModuleScope help` 里 mock `Search-ModuleHelp`，避免同一份搜索成本被反复支付。

```powershell
BeforeAll {
    Import-Module "$PSScriptRoot\..\modules\help.psm1" -Force

    # 为搜索类测试构造最小帮助夹具，避免每次断言都递归扫描整个 psutils 目录。
    $script:HelpFixtureRoot = Join-Path $TestDrive 'help-fixtures'
    New-Item -ItemType Directory -Path $script:HelpFixtureRoot -Force | Out-Null

    @'
function Get-OperatingSystem { param(); return "TestOS" }
function Install-TestTool { param(); return "ok" }
'@ | Set-Content -Path (Join-Path $script:HelpFixtureRoot 'fixture-help.psm1') -Encoding utf8NoBOM
}

InModuleScope help {
    Mock Search-ModuleHelp {
        [PSCustomObject]@{
            Name = 'Get-OperatingSystem'
            Synopsis = 'fixture synopsis'
        }
    }

    $results = Get-FunctionHelp "Get-OperatingSystem" -ModulePath $script:HelpFixtureRoot
    $results.Name | Should -Be "Get-OperatingSystem"
    Should -Invoke Search-ModuleHelp -Times 1 -Exactly
}
```

### 2. 给 `Invoke-Benchmark.ps1` 增加测试友好的同进程退出 seam

`Invoke-Benchmark.ps1` 原本直接 `exit`，这会让 Pester 很难在当前宿主进程里复用脚本逻辑。  
这次新增 `Complete-BenchmarkScript`，在测试态只设置 `LASTEXITCODE` 并 `return`，正常 CLI 行为仍保持 `exit`。

```powershell
function Complete-BenchmarkScript {
    [CmdletBinding()]
    param(
        [int]$ExitCode = 0
    )

    if ($env:PWSH_TEST_IN_PROCESS_BENCHMARK -eq '1') {
        $global:LASTEXITCODE = $ExitCode
        return
    }

    exit $ExitCode
}
```

同时把 `--list`、取消选择和未知 benchmark 分支统一改成“设置退出码后立即返回”，避免后续控制流继续落到 `$selected` 读取路径。

### 3. `Invoke-Benchmark.Tests.ps1` 主要改成同进程测试，只保留必要 smoke

测试侧通过 `PWSH_TEST_IN_PROCESS_BENCHMARK=1` 直接调用脚本；  
文本选择路径不再依赖 stdin，而是用 `Mock Read-Host` 驱动；  
只有真正需要验证 benchmark 路由和结构化输出的 `help-search` smoke 继续保留真实 benchmark 子进程。

```powershell
BeforeEach {
    $env:PWSH_TEST_IN_PROCESS_BENCHMARK = '1'
    $script:BenchmarksRoot = Join-Path $script:TestRoot 'benchmarks'
}

Import-Module $script:SelectionModulePath -Force
Mock -ModuleName selection Test-InteractiveSelectionFzfAvailable { return $false }
Mock -ModuleName selection Read-Host { return '2' }

$null = & $script:InvokeBenchmarkScriptPath `
    -BenchmarksRoot $script:BenchmarksRoot `
    -MarkerPath $script:MarkerPath

$LASTEXITCODE | Should -Be 0
```

### 4. `Sync-PathFromBash.Tests.ps1` 把三条 `WhatIf` 分支合并到一个子进程

之前 append / prepend / login 三条路径各跑一次子进程；  
现在改成一个批量子进程同时验证三种 `WhatIf` 行为，在保留 `ShouldProcess` 语义覆盖的同时，减少重复 shell 启动和模块导入。

```powershell
$childSegments = @(
    '$ErrorActionPreference = ''Stop'''
    "Import-Module '$escapedModulePath' -Force"
    "`$env:PWSH_TEST_BASH_PATH = '$escapedMockPath'"
    'Sync-PathFromBash -WhatIf -ReturnObject:$false -CacheSeconds 0'
    'Sync-PathFromBash -WhatIf -ReturnObject:$false -CacheSeconds 0 -Prepend'
    'Sync-PathFromBash -WhatIf -ReturnObject:$false -CacheSeconds 0 -Login'
)

$childScript = $childSegments -join '; '
$output = & $pwshPath -NoProfile -Command $childScript 2>&1
```

### Commands run

```bash
pnpm qa
pnpm test:pwsh:all
```

此外还对热点文件做了定向 Pester 复测，以便确认每个文件的变化是否命中根因。

## Why This Works

这次优化真正生效的原因，不是简单“删测试”或“静音输出”，而是把测试成本重新压回到应该发生的边界：

- **真实搜索只保留在最小夹具上**，因此 `help.Tests.ps1` 不再把整个仓库的扫描成本带进默认门禁。
- **wrapper 只测参数转发和返回契约**，因此 `Find-PSUtilsFunction` / `Get-FunctionHelp` 不再隐式重复走重搜索路径。
- **CLI 脚本提供测试专用 seam**，因此测试可以在 Pester 进程内复用业务脚本，而不必为退出语义重复拉起外层 `pwsh`。
- **`WhatIf` 分支合并到单个子进程**，因此仍然验证真实主机提示语义，但不会为每条路径单独支付固定成本。

## Verified result

### Hotspot changes

- `psutils/tests/help.Tests.ps1`
  - host `3.95s` → `0.92s`
  - linux `16.86s` → `0.92s`
- `tests/Invoke-Benchmark.Tests.ps1`
  - host `12.24s` → `4.91s`
  - linux `8.26s` → `4.06s`
- `tests/Sync-PathFromBash.Tests.ps1`
  - linux `2.41s` → `0.91s`
  - host full 约 `4.08s` → `4.05s`
    - 说明结构性成本已经下降，但 host full 侧剩余耗时仍主要由保留的真实子进程语义和 coverage 放大

### Quality gates

- `pnpm qa` 通过
- `pnpm test:pwsh:all` 通过

### New hotspot picture

- 这轮优化后，`help.Tests.ps1` 不再是共享主热点。
- `Invoke-Benchmark.Tests.ps1` 仍然是可继续优化的高价值对象，但已经从“双层 shell 启动”回落到“单层必要 smoke + 同进程逻辑测试”。
- 最新 full 套件里，host 侧更突出的剩余热点已经转移到 `tests/Switch-Mirrors.Tests.ps1`。

## Prevention

- 不改 `full / qa / all` 的门禁语义，只改测试实现成本。
- 先做职责分层，再做提速：功能正确性留在 Pester；性能比较、诊断输出和探索型实验迁到 `benchmark`、`debug` 或 `Slow`。
- 每个热点测试都先判断真实 CLI 或子进程是否真的必需；默认只保留一条最小 smoke，其余 catalog / 参数路由 / 选择逻辑尽量下沉到同进程 helper 测试。
- 外部命令、模块安装、平台探测统一收口到模块内 seam；测试只 mock 自有边界，不直接依赖真实宿主环境。
- 测试夹具必须最小化，避免全仓库扫描、重复目录枚举和大体量 `TestDrive`。
- 时间相关断言优先改状态，不要等时间；优先回拨时间戳、改环境变量或改输入状态。
- `WhatIf`、`Write-Host` 和预期 warning 默认都视为噪音源；如果必须验证，优先在单个子进程里集中捕获。
- 持续维护文件级耗时基线，优先处理 host / linux 共享热点。

## Related Issues

- See also: [pwsh-cross-platform-test-gate-performance-stability-system-20260315.md](./pwsh-cross-platform-test-gate-performance-stability-system-20260315.md) — 记录了 `pnpm test:pwsh:all` 下热点测试、默认输出降噪与测试隔离边界的整体治理，本次改动是该基线上的继续收口。
- See also: [pwsh-cross-platform-test-workflow-stability-system-20260314.md](./pwsh-cross-platform-test-workflow-stability-system-20260314.md) — 记录了跨平台 pwsh 质量门的上一轮稳定性与性能治理。
- See also: [benchmark-interactive-selection-psutils-20260314.md](../developer-experience/benchmark-interactive-selection-psutils-20260314.md) — 记录了 `Invoke-Benchmark.ps1` 的交互选择与取消返回语义，是这次 test-friendly 退出路径调整的前序。
- See also: [linux-macos-powershell-tooling-tests-system-20260314.md](../test-failures/linux-macos-powershell-tooling-tests-system-20260314.md) — 记录了 `tests/Invoke-Benchmark.Tests.ps1` 在 Linux/macOS 下的 fake `fzf`、PATH 与退出码问题，可作为跨平台测试友好设计的背景。
- See also: [pwsh-test-command-alignment-system-20260314.md](./pwsh-test-command-alignment-system-20260314.md) — 固定了 `pnpm qa` 与 `pnpm test:pwsh:all` 的工作流边界，便于说明这次性能优化应如何验证。
