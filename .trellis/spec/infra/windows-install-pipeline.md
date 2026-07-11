# Windows 安装流水线规范

## Scenario: Windows Stage 0、Core/Full、AutoHotkey、WSL 宿主与只读验证

### 1. Scope / Trigger

- Trigger: 修改 `windows/**`、`config/install/windows-packages.psd1`、Windows 应用标签、`scripts/ahk/**` 或根编排器中的 Windows 路径。
- Scope: Windows 11 22H2+ x64、Windows 10 22H2 x64；ARM64 和 Server 只提供识别、WhatIf 与 Blocked/Partial。
- Design intent: 根编排器拥有 Stage 1 步骤图；Windows 叶子拥有 Scoop、字体、PATH、AutoHotkey、受限提升和 WSL 宿主业务。

### 2. Signatures

```powershell
powershell.exe -NoProfile -File windows/00quickstart.ps1 `
  [-RepoUrl <url>] [-RepoDir <path>] [-Preset Core|Full] `
  [-NetworkMode Direct|China|Auto] `
  [-GitInstallerPath <exe>] [-PowerShellMsiPath <msi>] `
  [-AutoHotkeyInstallerPath <exe>] [-ScoopInstallerPath <ps1>] `
  [-IncludeWsl] [-WslDistribution <name>] `
  [-Unattended|-NonInteractive] [-WhatIf]

pwsh windows/99verifyInstall.ps1 `
  -Preset Core|Full [-Step <id[]>] [-IncludeWsl] [-OutputFormat Text|Json]
```

### 3. Contracts

- 00 必须兼容 Windows PowerShell 5.1。远程模式先下载 manifest，再按 SHA256 校验最小资产；clone 使用 `--depth=1`，已有 clone 不 pull、不改 history。
- 普通用户进程在提升前预检 Git、PowerShell、Full/AutoHotkey 和 IncludeWsl；一次 00 调用最多启动一个 allowlist UAC 子进程。
- 提升 executor 只接受 `WingetInstall`、`MsiInstall`、`ExeInstaller`、`WslInstall`，参数由代码生成；禁止配置或 plan 注入任意脚本文本。
- Scoop、Profile、用户 PATH、AHK Startup 和 `.wslconfig` 不得在提升进程中执行。提升后的 Stage 1 必须返回 Blocked/10。
- Core Scoop 真源为 `Windows + core + cli`，当前精确 10 项。Full 只追加 `Windows + cli + terminal-extras` 和 AutoHotkey，不默认安装 GUI。
- 03 只读报告 winget Stage 0 状态；共享 source 引擎继续将 winget 标为 Unsupported。npm、pnpm、pip、go 使用根 transaction ID。
- `.wslconfig` 仅由显式 IncludeWsl 写入；设置按 minimum build 过滤，变化时先 `.bak` 再同目录替换并返回 10。禁止自动执行 `wsl --shutdown`、terminate 或 unregister。
- 99 只读，JSON stdout 单文档；Failed/1 > Blocked/10 > Succeeded/0，Skipped/Warn 不单独失败。

### 4. Validation & Error Matrix

| Condition | Expected Behavior |
|---|---|
| 管理员进程启动 00/01/07/09/WSL 用户配置 | Blocked/10，提示普通用户重跑 |
| NonInteractive 需要机器安装 | Blocked/10，零 UAC |
| China/Auto 缺结构化 winget source cmdlets | Blocked/10，不回退 Direct |
| ARM64 或 Server 真实安装 | Blocked/10；WhatIf/fixture 可生成计划 |
| Full 经 00 已执行提升但 09 仍缺 AHK | Blocked/10，不请求第二次 UAC |
| `.wslconfig` 相同 | AlreadyPresent，不备份、不 shutdown |
| `.wslconfig` 变化 | 创建时间戳备份、替换、返回 10，提示手工 shutdown |
| 99 默认 Core 且 WSL 缺失 | WSL 不在默认检查，不影响 Core |

### 5. Good / Base / Bad Cases

- Good: 00 在请求 UAC 前把 Git、PowerShell、Full/AutoHotkey 与 IncludeWsl 全部加入一个 plan；提升结果的顶层 ExitCode 和逐项 Results 都传播回普通用户进程。
- Good: executor 从自身资产树推导 source helper/config，winget package ID 必须等于组件 allowlist，并在管理员进程内重新验证本地 MSI/EXE 签名。
- Base: 机器组件已存在时 00 不请求 UAC，只刷新 PATH、复用或 shallow clone 仓库并进入 Stage 1。
- Bad: 09 忽略 UAC 取消产生的顶层 Blocked、继续写 Startup；或让 plan 提供任意 helper 路径、winget ID、安装参数或脚本文本。

### 6. Tests Required

- Pester：Windows 11/10/ARM64/Server 平台矩阵、Core 精确集合、Full/GUI 边界、退出优先级。
- Pester：manifest hash、PS5 parser、03 单文档 JSON、05/06/08/09/WSL WhatIf 零写入、99 JSON。
- Pester：WSL build 过滤、相同内容幂等、变化备份、禁止自动 shutdown。
- Windows CI：fake winget/MSI/EXE/WSL 与一次提升 plan；不得执行真实 UAC、安装、字体、COM、Startup 或重启。
- Gates：`pnpm qa`、`pnpm test:pwsh:all`、`git diff --check`。

### 7. Wrong vs Correct

#### Wrong

```powershell
# 未校验顶层状态，用户取消 UAC 后仍继续写用户配置。
$elevated = Invoke-WindowsBootstrapElevation -Operation $operations
foreach ($result in $elevated.Results) {
    $results.Add($result)
}
Deploy-UserStartup
```

#### Correct

```powershell
$elevated = Invoke-WindowsBootstrapElevation -Operation $operations
foreach ($result in @($elevated.Results)) {
    $results.Add($result)
}
if ($elevated.ExitCode -ne 0 -and @($elevated.Results).Count -eq 0) {
    $results.Add((New-WindowsInstallResult `
                -Name elevation -Status Blocked -ExitCode 10 `
                -Message $elevated.Message))
}
if ((Get-WindowsInstallExitCode -Result $results) -eq 0) {
    Deploy-UserStartup
}
```

理由：UAC 取消和 result file 缺失可能只存在于提升 document 顶层；调用方必须先规约顶层状态，再决定是否执行用户态副作用。
