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

## Scenario: OpenSSH 到 PSRP HTTPS 远程 Bootstrap

### 1. Scope / Trigger

- Trigger: 修改 `windows/bootstrap/WindowsRemotePsRemoting.psm1`、`Enable-WindowsRemotePsRemoting.ps1`、远程 Ansible Windows inventory 或 PSRP bootstrap 文档。
- Scope: 目标机已安装 Windows、Tailscale 和 OpenSSH Server，并允许管理员通过 SSH 执行固定脚本；本场景不负责操作系统无人值守安装或 OpenSSH 配置。
- Design intent: SSH 只承担首次 bootstrap；稳定管理面使用仅绑定 Tailscale IPv4 的 PSRP HTTPS listener。

### 2. Signatures

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass `
  -File windows/bootstrap/Enable-WindowsRemotePsRemoting.ps1 `
  [-TailscaleIPv4 <100.64.0.0/10 address>] [-Port 5986] `
  [-CertificateValidityYears 1..10] [-Rollback] `
  [-OutputFormat Text|Json] [-WhatIf]
```

Ansible inventory 侧使用 `ansible_connection=psrp`、HTTPS、NTLM、`ansible_psrp_message_encryption=always`；自签名证书首期允许 `ansible_psrp_cert_validation=ignore`。

### 3. Contracts

- 入口与模块必须兼容 Windows PowerShell 5.1；含中文帮助或字符串的 `.ps1`/`.psm1` 必须使用 UTF-8 BOM，避免 5.1 按本地 ANSI 代码页误读；真实执行要求当前进程已是管理员，禁止请求 UAC。
- 自动发现或显式参数必须解析为唯一的 `100.64.0.0/10` IPv4；拒绝 LAN、loopback、IPv6、wildcard 和多地址歧义。
- 托管证书 subject 前缀为 `CN=powershellScripts-PSRP-`，位于 `Cert:\LocalMachine\My`，含私钥且剩余有效期超过 30 天时复用。
- HTTPS listener 默认端口为 `5986`；写入 WSMan provider 时 `Address` selector 必须使用 `IP:<tailscale-ip>`，读取后规范化为裸 IPv4 并精确等于目标 Tailscale 地址；同端口存在非托管 listener 时禁止覆盖。
- WinRM 必须保持 `AllowUnencrypted=false`、`Negotiate=true`；禁止调用会创建 wildcard listener 的 `Enable-PSRemoting`。
- 目标机尚未初始化 WinRM 时，`WSMan:\localhost\Listener` 和 `WSMan:\localhost\Service` 可以不存在；状态发现必须把它规约为无 listener、`AllowUnencrypted=false`、`Negotiate=true` 的 Missing 基线，使 WhatIf 能生成计划，不能误报 `StateDiscovery/1`。
- Windows Firewall 至少一个 profile 启用时，固定 rule 必须同时限制 `LocalAddress=<tailscale-ip>`、`RemoteAddress=100.64.0.0/10`、`LocalPort=5986`、TCP/Inbound/Allow；所有 profile 关闭时不得启用全局防火墙。
- NetSecurity provider 可能把 `RemoteAddress=100.64.0.0/10` 读回为等价的 `100.64.0.0/255.192.0.0`；精确验证允许这两个固定表示，禁止放宽为其他地址或范围。
- rollback 只删除固定前缀证书、使用这些证书的 listener 和固定名称 rule；OpenSSH 服务、端口和授权文件始终不变。
- JSON stdout 必须是单文档，字段至少包含 `SchemaVersion`、`Operation`、`Status`、`ExitCode`、`TailscaleIPv4`、`Port`、`FirewallEnabled`、`ListenerAddress`、`Results`、`RerunCommand`、`OpenSshUnchanged`。

### 4. Validation & Error Matrix

| Condition | Expected Behavior |
|---|---|
| IP 非 CGNAT、未发现或存在多个候选 | `Invalid/2`，零系统写操作 |
| 非 Windows 真实执行 | `Blocked/10`；显式 IP + WhatIf 仍可生成跨平台计划 |
| Windows 非管理员真实执行 | 在读取系统状态前返回 `Blocked/10`，不请求 UAC |
| WinRM 为 Manual/Stopped 且 WSMan Listener/Service 子路径不存在 | WhatIf 返回 Missing 配置计划；不调用 `Enable-PSRemoting`，不创建 wildcard listener |
| 端口存在非托管或其他接口 HTTPS listener | `Blocked/10`，不删除或覆盖 listener |
| Firewall profile 全部关闭 | 保持关闭，rule 动作为 `Skip`，仍验证 listener |
| provider/certificate/firewall cmdlet 或最终验证失败 | `Failed/1`，结果中保留失败资源与消息 |
| WhatIf、幂等状态或成功 apply/rollback | exit `0`；WhatIf 状态为 `Preview` |

### 5. Good / Base / Bad Cases

- Good: 管理员 SSH 会话运行入口，脚本复用有效证书，listener 只绑定 Tailscale IP，防火墙 rule 同时限制本地与远端地址，随后 Ansible 切换到 PSRP。
- Base: 防火墙全局关闭或资源已满足时不改变全局状态；重复执行返回 `AlreadyPresent`/`Skipped`，不重建无关资源。
- Bad: 调用 `Enable-PSRemoting` 创建 `Address=*` listener，打开全局防火墙，或 rollback 按端口删除所有 HTTPS listener。

### 6. Tests Required

- Pester：CGNAT 边界、唯一地址选择、多地址拒绝、证书复用和 WSMan provider 子项读取。
- Pester：单 IPv4 转换为 `IP:<address>` selector，provider 返回的 `IP:` 前缀规范化后仍通过精确绑定检查。
- Pester：WinRM 未初始化且 WSMan Listener/Service 子路径缺失时返回安全 Missing 基线，不调用缺失 provider 子项。
- Pester：Missing/Matched/ManagedDrift/Conflict、Firewall 开关与精确 filter、幂等和 rollback action plan。
- Pester：非管理员在状态读取前返回 `Blocked/10`；非 Windows 显式 IP WhatIf 输出可解析单文档 JSON。
- Parser：模块与入口必须通过 parser、断言 UTF-8 BOM；Windows CI 还要由 Windows PowerShell 5.1 加载。
- Gates：`pnpm qa`、`pnpm test:pwsh:all`、`git diff --check`。

### 7. Wrong vs Correct

#### Wrong

```powershell
$state = Get-WindowsRemotePsRemotingState -IPAddress $resolvedIPAddress
if (-not (Test-WindowsBootstrapAdministrator)) {
    return New-BlockedResult
}
```

#### Correct

```powershell
if (-not $Preview -and -not (Test-WindowsBootstrapAdministrator)) {
    return New-BlockedResult
}
$state = Get-WindowsRemotePsRemotingState -IPAddress $resolvedIPAddress
```

理由：非管理员可能无权读取证书、WSMan 或 NetSecurity provider；权限边界必须先于系统状态发现，才能稳定兑现 `Blocked/10` 而不是误报 `Failed/1`。
