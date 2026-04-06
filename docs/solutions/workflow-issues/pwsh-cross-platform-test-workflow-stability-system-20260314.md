---
module: System
date: 2026-03-14
problem_type: workflow_issue
component: testing_framework
symptoms:
  - "`pnpm test:pwsh:all` 曾无法稳定充当本地跨环境质量门"
  - "Linux `full` 会因 `CommandNotFoundException: Could not find Command curl` 与 coverage 收尾异常而假红"
  - "Host `full` 基线耗时约 271 秒，提交前回归成本明显偏高"
  - "聚合命令会在首个失败后中断另一侧，导致 host/linux 结果不完整"
root_cause: missing_workflow_step
resolution_type: workflow_improvement
severity: high
tags: [powershell, pester, cross-platform, linux, docker, coverage, performance, qa]
---

# Troubleshooting: 稳定并提速 pwsh 跨平台测试工作流

## Problem

`pnpm test:pwsh:all` 原本被定义为提交前的 PowerShell 跨环境完整验证入口，但在真实使用中同时暴露了三类问题：

- Linux `full` 会因为 `proxy.Tests` 对 `curl` 的假设和 Pester coverage 收尾崩溃而失败，表现为“测试红了”，但其中一部分并不是业务断言失败。
- 聚合入口使用 `--kill-others-on-fail`，任一路先失败就会杀掉另一侧，导致开发者看不到完整的 host / linux 结果。
- Host `full` 总时长过长，实测约 `271s`，而热点主要集中在少数测试文件，提交前完整回归的使用成本过高。

这让 `test:pwsh:all` 在语义上是“质量门禁”，在体验上却更像“噪音放大器”：既不稳定，也不够快，还会丢失定位信息。

## Environment

- Module: System-wide PowerShell / Pester workflow
- Affected Component:
  - `package.json`
  - `PesterConfiguration.ps1`
  - `docker-compose.pester.yml`
  - `psutils/tests/proxy.Tests.ps1`
  - `psutils/modules/test.psm1`
  - `psutils/modules/install.psm1`
  - `psutils/modules/hardware.psm1`
  - `docs/local-cross-platform-testing.md`
  - `README.md`
  - `CLAUDE.md`
- Platform: Windows host + Linux Docker container
- PowerShell: 7.x
- Pester: 5.7.1
- Date: 2026-03-14

## Symptoms

- `pnpm test:pwsh:linux:full` 在容器中报：
  - `CommandNotFoundException: Could not find Command curl`
  - `Normalize-Path: Cannot bind argument to parameter 'Path' because it is an empty string.`
- `pnpm test:pwsh:all` 在任一路失败时会提前中断另一侧，无法保留完整聚合结果。
- Host `full` 的主要热点是：
  - `psutils/tests/test.Tests.ps1`
  - `psutils/tests/install.Tests.ps1`
  - `psutils/tests/hardware.Tests.ps1`
- Full 日志里混入大量 `Write-Host`、`Write-Warning`、`WhatIf` 输出，失败定位成本偏高。

## What Didn't Work

**Attempted Solution 1:** 继续让 Linux `full` 本地承担 coverage。  

- **Why it failed:** 容器内的 Pester coverage 收尾会因路径归一化异常崩溃，让聚合入口出现“非断言类假红”。

**Attempted Solution 2:** 继续在 `proxy.Tests` 中假设容器里存在 `curl`。  

- **Why it failed:** Linux 容器环境与 Windows / 交互式 shell 不同，测试会直接因为命令存在性假设失败，而不是因为代理逻辑本身失败。

**Attempted Solution 3:** 使用 `--kill-others-on-fail` 做聚合。  

- **Why it failed:** 首个失败会杀掉另一侧执行，削弱了 `test:pwsh:all` 的诊断价值，开发者拿不到完整的 host / linux 结论。

**Attempted Solution 4:** 继续在高频探测路径里使用重型命令发现。  

- **Why it failed:** `Get-Command -CommandType Application` 和 `Get-Module -ListAvailable` 在缺失命令/模块场景下成本过高，把少数热点测试拖成了整套 full 回归的主耗时来源。

## Solution

最终修复分成四个层次：

1. **把 Linux `full` 收敛为“full 断言回归”，本地 coverage 责任交给 Host `full`。**
2. **让 `test:pwsh:all` 保留 host / linux 两路完整结果，再统一给出退出码。**
3. **修掉 Linux `proxy` 测试对 `curl` 的假设，并收口一部分用户提示型输出。**
4. **把热点测试中的高成本探测替换为轻量路径或稳定 mock 入口，显著降低 Host `full` 总耗时。**

### Key code changes

```json
// package.json
{
  "scripts": {
    "test:pwsh:all": "pnpm exec concurrently --group --names host,linux --prefix-colors blue,magenta --success all \"pnpm test:pwsh:full\" \"pnpm test:pwsh:linux:full\""
  }
}
```

```yaml
# docker-compose.pester.yml
environment:
  - PWSH_TEST_MODE=full
  - PWSH_TEST_ENABLE_COVERAGE=false
  - CI=false
```

```powershell
# PesterConfiguration.ps1
$coverageOverride = if ([string]::IsNullOrWhiteSpace($env:PWSH_TEST_ENABLE_COVERAGE)) {
    $null
} else {
    $env:PWSH_TEST_ENABLE_COVERAGE.Trim().ToLowerInvariant()
}

$isCoverageEnabled = if ($coverageOverride -in @('1', 'true', 'yes', 'on')) {
    $true
} elseif ($coverageOverride -in @('0', 'false', 'no', 'off')) {
    $false
} else {
    -not $isFast
}
```

```powershell
# psutils/modules/test.psm1
$commandLookup = Find-ExecutableCommand -Name $Name
$result = [bool]($commandLookup -and $commandLookup.Found)
```

```powershell
# psutils/modules/install.psm1
if (-not $script:ModuleInstalledCache) {
    $script:ModuleInstalledCache = @{}
}

$modulePath = Find-InstalledModulePath -ModuleName $ModuleName
$isInstalled = -not [string]::IsNullOrWhiteSpace($modulePath)
```

```powershell
# psutils/tests/proxy.Tests.ps1
if (-not (Get-Command curl -ErrorAction SilentlyContinue)) {
    function global:curl { }
}

Mock -ModuleName proxy Get-Command {
    [pscustomobject]@{ Name = 'curl'; CommandType = 'Function' }
} -ParameterFilter { $Name -eq 'curl' }
```

```powershell
# psutils/modules/hardware.psm1
function Get-HardwareOperatingSystem {
    return Get-OperatingSystem
}
```

### Validation commands

```bash
pnpm test:pwsh:linux:full
pnpm test:pwsh:all
pnpm qa
```

### Verified result

- `pnpm test:pwsh:linux:full` 通过
- `pnpm test:pwsh:all` 通过，且保留 host / linux 双路完整结果
- `pnpm qa` 通过
- Host `full` 从约 `271s` 降到约 `97s`
- 其中热点文件在最新 full 聚合中的变化：
  - `psutils/tests/test.Tests.ps1`: 约 `174s` → 约 `20.78s`
  - `psutils/tests/install.Tests.ps1`: 约 `48.87s` → 约 `12.05s`

## Why This Works

这次问题不是单个测试坏了，而是 **跨平台测试语义、coverage 责任、聚合行为和高成本探测路径同时耦合**。

修复之所以有效，是因为它同时把四个边界拉直了：

1. **Coverage responsibility is explicit.**  
   Host `full` 继续承担 coverage，本地 Linux `full` 则聚焦 full 断言回归，避免容器内 Pester compatibility 问题污染门禁结果。

2. **Aggregate results are preserved.**  
   `test:pwsh:all` 不再因为首个失败中断另一侧，真正恢复成“提交前看完整跨环境结果”的入口，而不是“只看到第一个爆炸点”的入口。

3. **Platform assumptions moved into controlled seams.**  
   `proxy.Tests`、`hardware.Tests` 这类跨平台测试不再直接依赖容器里恰好有什么命令，而是通过稳定的 mock 入口来表达“我想验证的行为”。

4. **Heavy discovery was replaced where it mattered most.**  
   `Test-EXEProgram` 和模块安装探测走轻量路径后，热点测试不再被缺失命令/模块的高成本发现逻辑拖慢，full 回归时间明显下降。

## Prevention

- **本地 coverage 责任与跨平台断言责任要分开定义。** 不要默认每条 `full` 路径都必须同时承担 coverage 与断言回归。
- **聚合测试入口不要用“首个失败即中断另一侧”的策略替代最终诊断。** 质量门禁需要完整结果，而不只是首个红灯。
- **跨平台测试里的外部命令必须通过可控 seam 访问。** 不要在测试里隐式假设 `curl`、`chmod`、`env`、`brew` 等命令一定存在。
- **性能敏感路径优先避免 `Get-Command -CommandType Application` 和 `Get-Module -ListAvailable`。** 缺失命令/模块场景会把成本放大得很夸张。
- **测试输出要区分“用户展示型信息”和“诊断信号”。** 常规 full 模式应保留失败、汇总、关键 warning；用户提示型 `Write-Host` 和重复状态块应尽量下沉到 verbose/debug。
- **命令、文档与 OpenSpec 必须同批更新。** 否则工作流语义会在代码、文档和规范之间漂移。

## Related Issues

- See also: [pwsh-test-command-alignment-system-20260314.md](../workflow-issues/pwsh-test-command-alignment-system-20260314.md)
- See also: [linux-macos-powershell-tooling-tests-system-20260314.md](../test-failures/linux-macos-powershell-tooling-tests-system-20260314.md)
- See also: [command-discovery-regression-profile-20260314.md](../performance-issues/command-discovery-regression-profile-20260314.md)
