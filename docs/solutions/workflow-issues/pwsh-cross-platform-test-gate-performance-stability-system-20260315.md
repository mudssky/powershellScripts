---
module: System
date: 2026-03-15
problem_type: workflow_issue
component: testing_framework
symptoms:
  - "`pnpm test:pwsh:all` 作为 PowerShell 提交门禁时，少数热点测试显著拉高整体执行耗时"
  - "部分 Pester 用例对内部实现细节和默认输出耦合过深，结果不稳定，偶发干扰断言"
  - "默认门禁输出混入 `Write-Host`、`Write-Warning` 与 WhatIf 提示，关键信号被噪音稀释"
root_cause: test_isolation
resolution_type: code_fix
severity: high
tags: [powershell, pester, pre-commit, performance, stability, console-output, qa, developer-experience]
---

# Troubleshooting: 收敛 pwsh 提交门禁的热点测试与默认输出噪音

## Problem

`pnpm test:pwsh:all` 作为 PowerShell 提交门禁时，整体耗时被少数测试文件明显拉高，同时默认日志里混入了大量与断言无关的提示输出，真正的失败点不够显眼。问题的核心不在业务逻辑本身，而在测试发现阶段和执行阶段过于依赖真实外部环境、高成本命令探测路径，以及未收口的默认提示输出。

## Environment

- Module: System
- Affected Component: root `pnpm test:pwsh:all` 提交门禁、Pester 测试隔离边界与默认测试输出
- Key files:
  - `psutils/modules/install.psm1`
  - `psutils/tests/test.Tests.ps1`
  - `psutils/tests/install.Tests.ps1`
  - `psutils/tests/hardware.Tests.ps1`
  - `psutils/tests/cache.Tests.ps1`
  - `psutils/tests/env.Tests.ps1`
  - `psutils/tests/help.Tests.ps1`
  - `psutils/tests/functions.Tests.ps1`
  - `psutils/tests/os.Tests.ps1`
  - `psutils/tests/web.Tests.ps1`
  - `tests/Manage-BinScripts.Tests.ps1`
  - `tests/Sync-PathFromBash.Tests.ps1`
- Platform: Windows host + Linux Docker container
- PowerShell: 7.5.4
- Pester: 5.7.1
- Date: 2026-03-15

## Symptoms

- `pnpm test:pwsh:all` 在提交前回归里明显偏慢，阅读与等待成本都很高。
- `psutils/tests/test.Tests.ps1`、`psutils/tests/install.Tests.ps1`、`psutils/tests/hardware.Tests.ps1` 在 fast 单文件基线下仍然很慢，说明问题不只是 coverage。
- `hardware.Tests.ps1` 在某些写法下会在发现阶段或真实探测链路中先慢、先抖，再进入断言。
- 默认日志中混入 `Write-Host`、`Write-Warning` 和 WhatIf 提示，导致真正的失败和耗时信号不够集中。

## What Didn't Work

**Attempted Solution 1:** 直接在测试里用原生命令探测或真实命令调用判断外部环境。  
- **Why it failed:** 像 `brew`、`nvidia-smi`、`free` 这类命令缺失时，会落回明显更慢、而且依赖宿主机状态的路径，把少数测试直接拖成热点。

**Attempted Solution 2:** 直接 mock `Install-Module` / `Import-Module` 这类外部 cmdlet。  
- **Why it failed:** 这种 mock 边界不够稳定，外部 cmdlet 仍可能穿过模块边界触发真实模块解析，甚至碰到 PowerShell Gallery 相关路径，既慢又不稳定。

**Attempted Solution 3:** 让测试默认输出保留所有用户提示型信息。  
- **Why it failed:** 这些输出对调试有用，但对提交门禁的默认阅读路径是噪音，会把关键断言和耗时摘要稀释掉。

## Solution

核心修复思路是两件事：先把“外部依赖探测”和“外部副作用调用”都收口成仓库内可控边界，再把测试默认输出降到只保留真正需要看的内容。

### 1. 用轻量探测替换测试内的慢路径探测

`psutils/tests/test.Tests.ps1` 不再直接用原生命令探测判断 `brew` 是否存在，而是复用仓库里已经优化过的 `Find-ExecutableCommand`。

```powershell
It "在没有brew的系统上应该返回false" {
    $brewLookup = Find-ExecutableCommand -Name "brew" -CacheMisses
    if (-not $brewLookup.Found) {
        $result = Test-HomebrewFormula -AppName "nonexistent-formula"
        $result | Should -Be $false
    }
}
```

### 2. 把外部安装/导入 cmdlet 收口为模块内包装函数

`psutils/modules/install.psm1` 新增包装函数，让测试只 mock 仓库自己的边界，而不是去碰 PowerShell 内建 cmdlet。

```powershell
function Invoke-InstallModuleCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ModuleName
    )

    Install-Module -Name $ModuleName -Scope CurrentUser -Force -ErrorAction Stop
}

function Import-InstalledModule {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ModuleName,
        [Parameter()]
        [System.Management.Automation.ActionPreference]$ErrorAction = [System.Management.Automation.ActionPreference]::Continue
    )

    Import-Module $ModuleName -ErrorAction $ErrorAction
}
```

### 3. 测试只 mock 模块内包装函数，不触发真实安装链路

`psutils/tests/install.Tests.ps1` 改成只验证控制流，不再触发真实模块安装或导入。

```powershell
Mock -ModuleName install Test-ModuleInstalled { return $false }
Mock -ModuleName install Invoke-InstallModuleCommand { }
Mock -ModuleName install Import-InstalledModule { }

{ Install-RequiredModule -ModuleNames @("NewModule") } | Should -Not -Throw
```

### 4. 提前稳定 `hardware` 测试的模块加载与缺失命令占位

`psutils/tests/hardware.Tests.ps1` 在发现阶段就加载轻量探测模块，并且只在命令确实不存在时创建占位函数，让 Pester 的 mock 挂载更稳定。

```powershell
Import-Module "$PSScriptRoot\..\modules\commandDiscovery.psm1" -Force

if (-not (Find-ExecutableCommand -Name 'nvidia-smi' -CacheMisses).Found) {
    function global:nvidia-smi { }
}

if (-not (Find-ExecutableCommand -Name 'free' -CacheMisses).Found) {
    function global:free { }
}

Import-Module "$PSScriptRoot\..\modules\hardware.psm1" -Force
```

### 5. 在测试层收口默认噪音输出

多个测试文件统一把用户提示型输出压回测试边界，只保留断言相关结果和必要摘要。涉及：

- `psutils/tests/cache.Tests.ps1`
- `psutils/tests/env.Tests.ps1`
- `psutils/tests/help.Tests.ps1`
- `psutils/tests/functions.Tests.ps1`
- `psutils/tests/os.Tests.ps1`
- `psutils/tests/web.Tests.ps1`
- `tests/Manage-BinScripts.Tests.ps1`
- `tests/Sync-PathFromBash.Tests.ps1`

### Commands run

```bash
pnpm qa
pnpm test:pwsh:all
```

### Verified result

- `psutils/tests/test.Tests.ps1`（fast, 单文件）大致从 `29s` 降到 `12s`
- `psutils/tests/install.Tests.ps1`（fast, 单文件）大致从 `20s+` 降到 `3.6s`
- `psutils/tests/hardware.Tests.ps1`（fast, 单文件）从“失败且约 `39-49s`”收敛到稳定通过且约 `4.7s`
- `pnpm qa` 通过
- `pnpm test:pwsh:all` 通过

## Why This Works

这次修复本质上把测试从“依赖宿主环境的真实行为”改成了“依赖仓库内可控边界的行为验证”。

`Find-ExecutableCommand` 避免了缺失命令时的慢探测路径，所以像 `test.Tests.ps1` 这类原本被 `brew` 缺失拖慢的用例，能直接回到轻量探测路径。  
模块内包装函数把外部副作用隔离开以后，`install.Tests.ps1` 不再意外触发真实模块解析或安装流程，测试运行时间和稳定性一起改善。  
`hardware.Tests.ps1` 在发现阶段就完成稳定模块加载，并为缺失命令准备 mock 友好的占位函数后，测试不再依赖 CI 主机或本机是否真的具备这些命令，避免了“先慢、先抖、再断言”的状态。  
最后，把默认提示输出静音到测试层以后，`pnpm test:pwsh:all` 的门禁日志主要保留真正有诊断价值的信息，可读性明显提升。

## Prevention

- 把提交门禁中的高频命令探测视为性能敏感路径，默认只允许走轻量封装，不要在热点逻辑里直接落回 `Get-Command`、外部进程探测或其他高成本系统调用。
- 外部 cmdlet、可执行文件探测、平台差异判断都先收口为模块内包装函数；业务代码只依赖这些自有边界，测试也只 mock 自有边界。
- 为包装函数建立稳定契约测试，至少覆盖“找到”“未找到”“批量查询”“缓存命中/失效”几类场景，防止实现改动后又偷偷回退到慢路径或不稳定边界。
- 把 `qa` / 热点子集与 `full` / 跨平台完整回归继续分层；前者要求快速、可重复、低噪音，后者再承担更重的覆盖和环境差异验证。
- 默认测试输出只保留断言相关信息；诊断信息统一走 `Write-Verbose` 或 `Write-Debug`，仅在显式开启 `PWSH_TEST_VERBOSE` 或 debug 模式时放开。
- 给热点测试建立“时间预算 + 稳定性预算”，一旦出现明显耗时回升、重复运行结果不一致、或默认模式下出现非断言输出，就按回归处理。

## Related Issues

- See also: [pwsh-cross-platform-test-workflow-stability-system-20260314.md](../workflow-issues/pwsh-cross-platform-test-workflow-stability-system-20260314.md) — 记录了 `test:pwsh:all` 作为跨平台质量门的上一轮稳定性、性能与输出治理，本次问题是在该基线上的进一步收口。
- See also: [pwsh-test-command-alignment-system-20260314.md](../workflow-issues/pwsh-test-command-alignment-system-20260314.md) — 固定了 `qa` 与 `test:pwsh:all` 的职责边界；本次治理是在不改变该门禁语义的前提下做提速、稳定性修复与默认输出收口。
- See also: [linux-macos-powershell-tooling-tests-system-20260314.md](../test-failures/linux-macos-powershell-tooling-tests-system-20260314.md) — 记录了跨平台 Pester 失败背后的 Windows 假设问题，是本次 Linux 相关稳定性治理的重要前置。
- See also: [command-discovery-regression-profile-20260314.md](../performance-issues/command-discovery-regression-profile-20260314.md) — 提供了缺失命令探测的性能根因与轻量替代方案，是本次热点测试提速的直接技术依据。
