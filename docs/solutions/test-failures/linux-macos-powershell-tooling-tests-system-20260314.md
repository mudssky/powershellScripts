---
module: System
date: 2026-03-14
problem_type: test_failure
component: testing_framework
symptoms:
  - "Linux/macOS 上 `Find-ExecutableCommand` 相关 Pester 用例全部失败，CI 只显示泛化的 `Message` 错误"
  - "`Invoke-Benchmark.ps1` 的 `检测到 fzf 时优先走 fzf 选择路径` 在 Linux 容器中返回非零退出码"
  - "`Initialize-Environment command discovery integration` 在 Unix 下输出 `starship、zoxide、fnm` 且缺少自动安装命令，和 Windows 断言不一致"
root_cause: test_isolation
resolution_type: code_fix
severity: medium
tags: [powershell, pester, linux, macos, cross-platform, path, fzf, command-discovery, profile]
---

# Troubleshooting: 修复 Linux/macOS 下 PowerShell 工具链测试的 Windows 假设

## Problem

一组最近新增的 PowerShell 工具链测试在 Windows 本机可以通过，但到了 Linux/macOS CI 后连续失败，覆盖 `Find-ExecutableCommand`、benchmark 交互选择和 Profile 安装提示三个区域。表面上看是多处独立回归，实际都指向同一个问题：测试和辅助代码默认按 Windows 的 PATH、可执行文件和平台能力来思考，到了 Unix 分支就会失真。

这类问题如果只看 CI 摘要很难定位，因为很多失败只显示笼统的断言未通过，必须回到 Linux 运行环境里逐个复现，才能把“测试假设错误”和“实现确实不兼容 Unix”拆开。

## Environment

- Module: System-wide PowerShell tooling
- Affected Component: `psutils/modules/commandDiscovery.psm1`、`psutils/tests/commandDiscovery.Tests.ps1`、`tests/Invoke-Benchmark.Tests.ps1`、`tests/ProfileInstallHints.Tests.ps1`
- Platform: Linux/macOS CI，外加本地 Linux Docker 复现
- PowerShell: 7.x
- Key files:
  - `psutils/modules/commandDiscovery.psm1`
  - `psutils/tests/commandDiscovery.Tests.ps1`
  - `tests/Invoke-Benchmark.Tests.ps1`
  - `tests/ProfileInstallHints.Tests.ps1`
  - `docker-compose.pester.yml`
- Date: 2026-03-14

## Symptoms

- `psutils/tests/commandDiscovery.Tests.ps1` 在 Linux 容器里出现两类真实错误：
  - `chmod` 在测试里找不到，因为 `PATH` 被测试替换成了临时目录
  - `Find-ExecutableCommand` 传入 Unix 空 `PATHEXT` 时，触发 `ParameterBindingValidationException`
- `tests/Invoke-Benchmark.Tests.ps1` 的 fake `fzf` 只提供了 Windows `.cmd` 版本，Linux 下即使补成 shell 脚本，仍会因为 shebang、`PATH` 和 `/tmp` 执行位置问题导致外部命令拉起失败。
- `tests/ProfileInstallHints.Tests.ps1` 复用了 Windows 的 mock 和断言，Linux/macOS 下却会合法地把 `fnm` 纳入缺失提示，并按 `brew` 或 `apt` 生成不同安装命令。

## What Didn't Work

**Attempted Solution 1:** 只在 Windows 本机运行 Pester，认为本地通过就代表问题不在代码本身。  

- **Why it failed:** 这只能覆盖 Windows 分支，无法暴露 Unix 下的空 `PATHEXT`、`chmod` 依赖和平台特定安装提示差异。

**Attempted Solution 2:** 继续在 benchmark 测试里使用 Windows 风格的 `fzf.cmd`，或者简单换成 `#!/usr/bin/env sh` 的 shell 脚本。  

- **Why it failed:** Unix 不会执行 `.cmd`；而测试又把 `PATH` 缩到临时工具目录，`/usr/bin/env sh` 会再次依赖 `PATH`；另外容器里的 `TestDrive` 落在 `/tmp`，不适合作为稳定的外部可执行文件位置。

**Attempted Solution 3:** 在 Profile 安装提示集成测试中继续硬编码“6 个命令 + `scoop install starship zoxide`”的 Windows 断言。  

- **Why it failed:** macOS/Linux 的真实跟踪集合不同，Unix 会把 `fnm` 一并纳入提示，Linux 还要求在 mock 中显式提供 `apt` 才能生成自动安装命令。

**Attempted Solution 4:** 保持 `commandDiscovery.psm1` 里的 `PathExtValue` / `PathValue` 参数为默认的强制非空字符串。  

- **Why it failed:** Unix 下空 `PATHEXT` 是合法状态，参数绑定层先报错，连真正的命令探测逻辑都到不了。

## Solution

最终修复分成四部分：

1. 让 `Find-ExecutableCommand` 接受 Unix 合法的空环境值
2. 让 `commandDiscovery` 测试在覆写 `PATH` 前先解析 `chmod` 的绝对路径
3. 为 `Invoke-Benchmark` 测试提供真正跨平台的 fake `fzf`
4. 让 Profile 安装提示集成测试按运行平台动态生成 mock 与期望值

### Code changes

```powershell
# Before (broken):
function Resolve-ExecutableCommand {
    param(
        [Parameter(Mandatory)]
        [string]$PathExtValue
    )
}
```

```powershell
# After (fixed):
function Resolve-ExecutableCommand {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$PathExtValue
    )
}
```

```powershell
# Before (broken):
Set-Content -Path $commandPath -Value "#!/usr/bin/env sh`necho ok" -Encoding ascii
& chmod +x $commandPath
```

```powershell
# After (fixed):
$script:ChmodPath = if ($IsWindows) { $null } else { (Get-Command chmod -ErrorAction Stop).Source }
Set-Content -Path $commandPath -Value "#!/usr/bin/env sh`necho ok" -Encoding ascii
& $script:ChmodPath +x $commandPath
```

```powershell
# Before (broken):
Set-Content -Path (Join-Path $script:ToolsPath 'fzf.cmd') -Value @'
@echo off
...
'@
$env:PATH = $script:ToolsPath
```

```powershell
# After (fixed):
$script:ToolsPath = if ($IsWindows) {
    Join-Path $script:TestRoot 'tools'
}
else {
    Join-Path $PSScriptRoot '.tmp-executables' ([Guid]::NewGuid().ToString())
}

$unixFzfScript = @(
    '#!/bin/sh'
    'if [ -n "$FAKE_FZF_MARKER" ]; then'
    '  printf ''used\n'' > "$FAKE_FZF_MARKER"'
    'fi'
    'IFS= read -r first_line || exit 0'
    'if [ -n "$first_line" ]; then'
    '  printf ''%s\n'' "$first_line"'
    'fi'
    'exit 0'
) -join "`n"
```

```powershell
# Before (broken):
Mock Find-ExecutableCommand {
    return @(
        [PSCustomObject]@{ Name = 'starship'; Found = $false; Path = $null }
        ...
        [PSCustomObject]@{ Name = 'scoop'; Found = $true; Path = 'C:\Users\mudssky\scoop\shims\scoop.cmd' }
    )
} -ParameterFilter {
    $CacheMisses -and @($Name).Count -eq 6
}
```

```powershell
# After (fixed):
$script:RuntimePlatform = Get-ProfileInstallHintPlatform
switch ($script:RuntimePlatform) {
    'windows' {
        $script:ExpectedTrackedCommandNames = @('starship', 'zoxide', 'sccache', 'scoop', 'winget', 'choco')
        $script:ExpectedHintCommand = 'scoop install starship zoxide'
    }
    'macos' {
        $script:ExpectedTrackedCommandNames = @('starship', 'zoxide', 'sccache', 'fnm', 'brew')
        $script:ExpectedHintCommand = 'brew install starship zoxide fnm'
    }
    default {
        $script:ExpectedTrackedCommandNames = @('starship', 'zoxide', 'sccache', 'fnm', 'brew', 'apt')
        $script:ExpectedHintCommand = 'sudo apt install starship zoxide fnm'
    }
}
```

### Commands run

```bash
# 复现和验证 commandDiscovery Unix 问题
pwsh -NoProfile -Command "Invoke-Pester -Path './psutils/tests/commandDiscovery.Tests.ps1' -Output Detailed"
docker compose -f docker-compose.pester.yml run --rm pester-fast pwsh -NoProfile -Command "Invoke-Pester -Path '/workspace/psutils/tests/commandDiscovery.Tests.ps1' -Output Detailed"

# 复现和验证 benchmark / profile 集成测试
pwsh -NoProfile -Command "Invoke-Pester -Path './tests/Invoke-Benchmark.Tests.ps1','./tests/ProfileInstallHints.Tests.ps1' -Output Detailed"
docker compose -f docker-compose.pester.yml run --rm pester-fast pwsh -NoProfile -Command "Invoke-Pester -Path '/workspace/tests/Invoke-Benchmark.Tests.ps1','/workspace/tests/ProfileInstallHints.Tests.ps1' -Output Detailed"

# 仓库级 QA
pnpm qa
```

### Verified result

- `psutils/tests/commandDiscovery.Tests.ps1` 在 Windows 本机和 Linux 容器都通过。
- `tests/Invoke-Benchmark.Tests.ps1` 与 `tests/ProfileInstallHints.Tests.ps1` 在 Windows 本机和 Linux 容器都通过。
- 根目录 `pnpm qa` 通过。

## Why This Works

这次问题的核心不是“某一条断言写错了”，而是测试和实现同时带着隐性的 Windows 语义：

1. **Unix 允许空环境值。**  
   `PATHEXT` 在 Unix 本来就可以为空，辅助函数如果把它当成“非法输入”，会在参数绑定阶段提前失败。

2. **测试一旦覆写 `PATH`，就必须放弃对系统命令名解析的幻想。**  
   `chmod`、`env`、`sh` 这些在交互式 shell 看似理所当然存在的命令，在隔离后的测试环境里都可能失效，因此要么预先解析绝对路径，要么直接使用不依赖 `PATH` 的解释器路径。

3. **fake CLI 必须匹配目标平台的真实可执行语义。**  
   Windows 需要 `.cmd`，Unix 需要 shebang + 执行位；而且容器里的临时目录不一定适合作为 PowerShell 外部进程的可执行路径，因此测试还要控制 fake 文件的落点。

4. **平台敏感的断言必须从平台推导，而不是复用 Windows fixture。**  
   `Initialize-Environment` 在 Unix 下本来就会处理 `fnm`，Linux 还会在 `brew` 不可用时回退到 `apt`。测试若不按平台生成 mock，只会把正确行为错判成回归。

因此，真正有效的修复不是单点补丁，而是把这些平台边界显式写进实现和测试里：允许空值、预解析系统工具、为 Unix 创建真实 fake executable，并让集成测试从运行平台推导预期。

## Prevention

- **凡是会临时覆写 `PATH` 的 Pester 测试，都要先把后续仍需调用的系统命令解析成绝对路径。**
- **跨平台 fake CLI 必须分平台生成。** Windows 用 `.cmd`，Unix 用真实 shebang 脚本并设置执行位。
- **在 Linux/macOS 容器里运行新增的 PowerShell 测试，而不是只看 Windows 本机结果。**
- **平台敏感的集成测试不要硬编码命令数量和输出文本。** 应优先基于 `Get-ProfileInstallHintPlatform` 一类能力派生期望值。
- **如果 PowerShell helper 的参数在 Unix 下可能接收空字符串，明确加上 `[AllowEmptyString()]`，不要默认依赖 Windows 环境变量形态。**

## Related Issues

- See also: [benchmark-interactive-selection-psutils-20260314.md](../developer-experience/benchmark-interactive-selection-psutils-20260314.md)
- See also: [command-discovery-regression-profile-20260314.md](../performance-issues/command-discovery-regression-profile-20260314.md)
- See also: [pwsh-test-command-alignment-system-20260314.md](../workflow-issues/pwsh-test-command-alignment-system-20260314.md)
