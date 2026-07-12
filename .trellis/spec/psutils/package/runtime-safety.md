# PsUtils Runtime Safety Contract

> 本规范约束 psutils 中的敏感原生命令参数、动态执行、可降级异常和跨平台运行边界。

## Scenario: Sensitive Native Commands And Cross-Platform Diagnostics

### 1. Scope / Trigger

- Trigger：修改 SSH、历史命令执行、代理探测、网络端口、缓存读写、硬件探测或其他 native command 调用。
- Scope：`psutils/modules/linux.psm1`、`functions.psm1`、`env.psm1`、`hardware.psm1`、`network.psm1`、`proxy.psm1` 及对应 Pester 测试。
- Design intent：敏感值不进入进程参数或日志；预期降级可被 `-Verbose` 诊断；平台限制必须显式，不依赖当前机器偶然安装的命令。

### 2. Signatures

- SSH：`Set-SSHKeyAuth -RemoteUser <string> -RemoteHost <string> [-Passphrase ''] [-PromptForPassphrase] [-WhatIf]`
- 历史排名：`Get-HistoryCommandRank [-Top <int>] [-HistoryPath <string>]`
- 历史执行：`Invoke-FzfHistorySmart`，只有 fzf 返回 `ctrl-e` 动作时执行选中历史。
- 端口占用：`Test-PortOccupation -Port <1..65535>`
- 端口进程：`Get-PortProcess -Port <1..65535>`，当前 PID 映射依赖 Windows `Get-NetTCPConnection`。
- URL 等待：`Wait-ForURL [-DevToolsUrl <uri>] [-Timeout <double>] [-Interval <double>] [-ShowOutput] [-Verbose]`

### 3. Contracts

- `Set-SSHKeyAuth` 仅允许空的兼容 `Passphrase`；非空值必须拒绝且错误不得包含原值。
- 需要密钥口令时使用 `PromptForPassphrase`，调用 `ssh-keygen` 时省略 `-N`，由终端交互读取。
- SSH 密钥目录使用 PowerShell `$HOME/.ssh`；用户名和主机名不得改变 native option 边界。
- SSH 本地和远程状态变更必须经过 `ShouldProcess`，`-WhatIf` 不执行网络探测或 native command。
- `Invoke-Expression` 只允许位于 `Invoke-FzfHistorySmart` 的 `ctrl-e` 分支，输入来自本地 PSReadLine 历史且由用户显式触发；使用局部 `SuppressMessageAttribute` 说明，不全局关闭规则。
- 可忽略的缓存、注册表、TCP 探测和 URL 重试异常必须写 `Verbose` 后降级；禁止完全空的 `catch {}`。
- `Test-PortOccupation` 使用 .NET TCP 快照实现跨平台检测，不依赖 `Get-NetTCPConnection`。
- 无可靠跨平台 PID 映射时，`Get-PortProcess` 明确返回 Windows-only 错误，不临时引入 `lsof` 或 `ss` 依赖。
- 交互命令的 `Write-Host` 属于终端 UI，可保留；不得以清零分析器告警为由改变对象输出契约。

### 4. Validation & Error Matrix

| Condition | Expected Behavior |
|---|---|
| `Passphrase` 为非空字符串 | 返回 false/错误；不调用 `ssh-keygen`；错误不包含口令 |
| `PromptForPassphrase` | `ssh-keygen` 参数不含 `-N` |
| SSH 用户名或主机名改变参数边界 | 在任何网络或 native 调用前拒绝 |
| `Set-SSHKeyAuth -WhatIf` | 不调用 `Test-Connection`、`ssh-keygen` 或 `ssh` |
| fzf 返回 `ctrl-e` + 历史命令 | 恰好执行一次选中命令 |
| fzf 普通 Enter | 仅回填/输出命令，不执行 |
| 缓存或探测可降级失败 | `-Verbose` 可见原因，主流程继续 |
| Port 不在 1..65535 | 参数绑定失败 |
| 非 Windows 调用 `Get-PortProcess` | 返回明确平台错误和空结果 |
| 模块存在 `catch {}` | `runtimeHardening.Tests.ps1` 失败 |

### 5. Good/Base/Bad Cases

- Good：默认无口令密钥传递空 `-N`；需要口令时通过 `PromptForPassphrase` 交互读取。
- Good：本地历史只有用户按 `Ctrl+E` 时执行，普通 Enter 仅回填。
- Good：跨平台端口占用使用 .NET，Windows-only PID 查询明确报错。
- Base：缓存损坏时写 `Verbose` 并重新探测，不把缓存问题升级为主流程失败。
- Bad：把口令放进 `ssh-keygen -N $Passphrase`、日志、错误或返回对象。
- Bad：为了消除告警全局禁用 `Invoke-Expression` 或 `Write-Host` 规则。
- Bad：非 Windows 路径硬编码 `USERPROFILE/AppData`，或假定存在 `Get-NetTCPConnection`、`fzf`、`lsof`。

### 6. Tests Required

- `linux.Tests.ps1`：空口令、非空口令拒绝、交互模式、参数边界、`WhatIf`。
- `functions.Tests.ps1`：显式/默认历史路径，以及只有 `ctrl-e` 调用动态执行。
- `network.Tests.ps1`：真实临时 TCP listener、端口范围、非 Windows PID 查询错误、URL 重试 Verbose。
- `proxy.Tests.ps1`：auto TCP 探测失败产生 Verbose 且不抛出。
- `runtimeHardening.Tests.ps1`：目标模块不得存在完全空的 catch。
- 缺少 fzf 的测试环境必须临时创建可清理的占位函数，再由 Pester mock；不得要求 CI 镜像安装 fzf。
- 完成后运行 `pnpm --filter psutils test:qa`、`pnpm qa`、`pnpm test:pwsh:all`。

### 7. Wrong vs Correct

#### Wrong

```powershell
$keyPath = "$env:USERPROFILE\.ssh\id_rsa"
ssh-keygen -f $keyPath -N $Passphrase

try {
    $client.Connect($hostName, $port)
}
catch {}
```

问题：路径不跨平台，口令进入进程参数，失败路径无法诊断。

#### Correct

```powershell
$keyPath = Join-Path (Join-Path $HOME '.ssh') 'id_rsa'
if ($PromptForPassphrase) {
    ssh-keygen -f $keyPath
}
else {
    ssh-keygen -f $keyPath -N ''
}

try {
    $client.Connect($hostName, $port)
}
catch {
    Write-Verbose "TCP 探测失败，继续降级: $($_.Exception.Message)"
}
```

理由：敏感输入交给终端，默认空口令不泄露 secret，平台路径和降级诊断都有明确契约。

