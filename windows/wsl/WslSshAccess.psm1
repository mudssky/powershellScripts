Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:ProgramDataRoot = if ([string]::IsNullOrWhiteSpace($env:ProgramData)) { [IO.Path]::GetTempPath() } else { $env:ProgramData }
$script:RuntimeRoot = Join-Path $script:ProgramDataRoot 'powershellScripts\wsl-ssh'
$script:PortProxyRegistryPath = 'HKLM:\SYSTEM\CurrentControlSet\Services\PortProxy\v4tov4\tcp'

function ConvertFrom-WslSshText {
    <#
    .SYNOPSIS
        清理 wsl.exe 在 Windows PowerShell 5.1 中返回的 NUL 字符。
    .PARAMETER Value
        原始命令输出。
    .OUTPUTS
        System.String。清理后的文本。
    #>
    [CmdletBinding()]
    param([AllowNull()][object]$Value)

    return (([string]$Value) -replace [char]0, '').Trim()
}

function Get-WslSshAccessSafeId {
    <#
    .SYNOPSIS
        将发行版名称转换为稳定资源 ID。
    .PARAMETER Distribution
        WSL 发行版名称。
    .OUTPUTS
        System.String。仅含小写字母、数字和连字符的 ID。
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Distribution)

    $safe = ($Distribution.Trim().ToLowerInvariant() -replace '[^a-z0-9-]+', '-') -replace '^-+|-+$', ''
    if ([string]::IsNullOrWhiteSpace($safe)) {
        throw 'Distribution cannot be converted to a safe resource ID'
    }
    return $safe
}

function Get-WslSshAccessResourceNames {
    <#
    .SYNOPSIS
        生成本功能拥有的固定 Windows 资源名。
    .PARAMETER Distribution
        WSL 发行版名称。
    .OUTPUTS
        PSCustomObject。包含 TaskName、FirewallRuleName、ConfigPath 和 HelperPath。
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Distribution)

    $safeId = Get-WslSshAccessSafeId -Distribution $Distribution
    return [pscustomobject]@{
        SafeId           = $safeId
        TaskName         = "powershellScripts-WSL-SSH-$safeId"
        FirewallRuleName = "powershellScripts-WSL-SSH-$safeId"
        ConfigPath       = Join-Path $script:RuntimeRoot "$safeId.json"
        StatusPath       = Join-Path $script:RuntimeRoot "$safeId.status.json"
        HelperPath       = Join-Path $script:RuntimeRoot "$safeId.refresh.ps1"
    }
}

function Test-WslSshAccessPublicKey {
    <#
    .SYNOPSIS
        校验单行 OpenSSH 公钥并拒绝私钥内容。
    .PARAMETER PublicKey
        待校验的公钥文本。
    .OUTPUTS
        System.Boolean。格式合法时为 true。
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$PublicKey)

    $trimmed = $PublicKey.Trim()
    return $trimmed -notmatch 'PRIVATE KEY' -and
        $trimmed -match '^(ssh-ed25519|ssh-rsa|ecdsa-sha2-[^\s]+)\s+[A-Za-z0-9+/=]+(?:\s+.*)?$'
}

function Test-WslSshAccessPort {
    <#
    .SYNOPSIS
        校验 TCP 端口范围。
    .PARAMETER Port
        待校验端口。
    .OUTPUTS
        System.Boolean。端口位于 1..65535 时为 true。
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][int]$Port)

    return $Port -ge 1 -and $Port -le 65535
}

function ConvertTo-WslSshAccessRemoteAddress {
    <#
    .SYNOPSIS
        规范化 Windows firewall provider 的等价 remote address 表示。
    .PARAMETER Address
        provider 返回或期望的 remote address。
    .OUTPUTS
        System.String。用于幂等比较的规范值。
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Address)

    if ($Address -eq '100.64.0.0/255.192.0.0') {
        return '100.64.0.0/10'
    }
    return $Address
}

function ConvertTo-WslSshAccessRemoteAddresses {
    <#
    .SYNOPSIS
        规范化 CLI 或模块传入的 firewall remote address 列表。
    .PARAMETER Address
        数组或逗号分隔的 LocalSubnet、IPv4、IPv4 CIDR。
    .OUTPUTS
        System.String[]。去重后的 remote address。
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string[]]$Address)

    $normalized = @($Address | ForEach-Object { ([string]$_) -split ',' } | ForEach-Object { $_.Trim() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
    if ($normalized.Count -eq 0) {
        throw 'remote address allowlist cannot be empty'
    }
    foreach ($entry in $normalized) {
        if ($entry -ne 'LocalSubnet' -and $entry -notmatch '^\d{1,3}(?:\.\d{1,3}){3}(?:/(?:[0-9]|[12][0-9]|3[0-2]))?$') {
            throw "invalid remote address: $entry"
        }
    }
    return $normalized
}

function New-WslSshAccessPlan {
    <#
    .SYNOPSIS
        根据当前状态生成纯逻辑宿主计划。
    .PARAMETER Operation
        Plan、Apply、Verify 或 Rollback。
    .PARAMETER State
        当前资源状态。
    .OUTPUTS
        PSCustomObject。包含 Actions、Changed、Status 和 ExitCode。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('Plan', 'Apply', 'Verify', 'Rollback')][string]$Operation,
        [Parameter(Mandatory)][pscustomobject]$State
    )

    $actions = [System.Collections.Generic.List[object]]::new()
    if ($Operation -eq 'Rollback') {
        foreach ($entry in @(
                @{ Name = 'ScheduledTask'; Exists = $State.TaskExists },
                @{ Name = 'TcpRelay'; Exists = $State.RelayListening -or $State.PortProxyExists },
                @{ Name = 'FirewallRule'; Exists = $State.FirewallRuleExists },
                @{ Name = 'RuntimeFiles'; Exists = $State.RuntimeFilesExist }
            )) {
            $actions.Add([pscustomobject]@{
                    Name    = $entry.Name
                    Action  = if ($entry.Exists) { 'Remove' } else { 'AlreadyAbsent' }
                    Changed = [bool]$entry.Exists
                })
        }
    }
    else {
        foreach ($entry in @(
                @{ Name = 'RuntimeFiles'; Ready = $State.RuntimeFilesMatch },
                @{ Name = 'ScheduledTask'; Ready = $State.TaskMatches },
                @{ Name = 'FirewallRule'; Ready = $State.FirewallRuleMatches },
                @{ Name = 'TcpRelay'; Ready = $State.RelayMatches }
            )) {
            $actions.Add([pscustomobject]@{
                    Name    = $entry.Name
                    Action  = if ($entry.Ready) { 'AlreadyPresent' } else { 'Ensure' }
                    Changed = -not [bool]$entry.Ready
                })
        }
    }
    $changed = @($actions | Where-Object Changed).Count -gt 0
    return [pscustomobject]@{
        Operation = $Operation
        Status    = if ($Operation -eq 'Plan') { 'Preview' } else { 'Succeeded' }
        ExitCode  = 0
        Changed   = $changed
        Actions   = $actions.ToArray()
    }
}

function Invoke-WslSshAccessProcess {
    <#
    .SYNOPSIS
        执行原生命令并隔离 stdout/stderr。
    .PARAMETER FilePath
        可执行文件路径。
    .PARAMETER ArgumentList
        参数数组。
    .OUTPUTS
        PSCustomObject。包含 ExitCode、Stdout 和 Stderr。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$ArgumentList = @()
    )

    $stdoutPath = [IO.Path]::GetTempFileName()
    $stderrPath = [IO.Path]::GetTempFileName()
    try {
        $quotedArguments = @($ArgumentList | ForEach-Object {
                $value = [string]$_
                # wsl.exe 会再次解析命令行；包含反斜杠的 Windows 路径也必须显式引用。
                if ($value -notmatch '[\\\s"]') { return $value }
                return '"' + ($value -replace '(\\*)"', '$1$1\"' -replace '(\\+)$', '$1$1') + '"'
            }) -join ' '
        $process = Start-Process -FilePath $FilePath -ArgumentList $quotedArguments -Wait -PassThru `
            -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
        return [pscustomobject]@{
            ExitCode = $process.ExitCode
            Stdout   = [IO.File]::ReadAllText($stdoutPath, [Text.Encoding]::UTF8)
            Stderr   = [IO.File]::ReadAllText($stderrPath, [Text.Encoding]::UTF8)
        }
    }
    finally {
        Remove-Item -LiteralPath $stdoutPath, $stderrPath -Force -ErrorAction SilentlyContinue
    }
}

function Get-WslSshAccessDistributionNames {
    <#
    .SYNOPSIS
        读取已注册 WSL 发行版名称。
    .OUTPUTS
        System.String[]。已清理 NUL 的发行版名称。
    #>
    [CmdletBinding()]
    param()

    $result = Invoke-WslSshAccessProcess -FilePath 'wsl.exe' -ArgumentList @('--list', '--quiet')
    if ($result.ExitCode -ne 0) {
        return @()
    }
    return @((ConvertFrom-WslSshText -Value $result.Stdout) -split "`r?`n" | Where-Object { $_ })
}

function Get-WslSshAccessPortProxyState {
    <#
    .SYNOPSIS
        读取精确 v4tov4 portproxy 状态。
    .PARAMETER ListenAddress
        Windows 监听地址。
    .PARAMETER ListenPort
        Windows 监听端口。
    .PARAMETER GuestPort
        WSL sshd 端口。
    .PARAMETER ConnectAddress
        Windows 侧转发目标；NAT 模式使用 WSL localhost relay。
    .OUTPUTS
        PSCustomObject。包含 Exists、Matches 和 ConnectAddress。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ListenAddress,
        [Parameter(Mandatory)][int]$ListenPort,
        [Parameter(Mandatory)][int]$GuestPort,
        [string]$ConnectAddress = '127.0.0.1'
    )

    $result = Invoke-WslSshAccessProcess -FilePath 'netsh.exe' -ArgumentList @('interface', 'portproxy', 'show', 'v4tov4')
    $match = [regex]::Match($result.Stdout, "(?m)^\s*$([regex]::Escape($ListenAddress))\s+$ListenPort\s+(\S+)\s+(\d+)\s*$")
    return [pscustomobject]@{
        Exists        = $match.Success
        Matches       = $match.Success -and $match.Groups[1].Value -eq $ConnectAddress -and [int]$match.Groups[2].Value -eq $GuestPort
        ConnectAddress = if ($match.Success) { $match.Groups[1].Value } else { '' }
    }
}

function Get-WslSshAccessHostState {
    <#
    .SYNOPSIS
        读取宿主受管资源状态。
    .PARAMETER Distribution
        WSL 发行版名称。
    .PARAMETER WindowsUser
        Scheduled Task 用户。
    .PARAMETER ListenAddress
        Windows 监听地址。
    .PARAMETER ListenPort
        Windows 监听端口。
    .PARAMETER GuestPort
        WSL sshd 端口。
    .PARAMETER RemoteAddress
        Windows firewall remote allowlist。
    .PARAMETER RuntimeHelperSource
        仓库 runtime helper 源路径。
    .OUTPUTS
        PSCustomObject。宿主状态快照。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Distribution,
        [Parameter(Mandatory)][string]$WindowsUser,
        [Parameter(Mandatory)][string]$ListenAddress,
        [Parameter(Mandatory)][int]$ListenPort,
        [Parameter(Mandatory)][int]$GuestPort,
        [string[]]$RemoteAddress,
        [Parameter(Mandatory)][string]$RuntimeHelperSource
    )

    $names = Get-WslSshAccessResourceNames -Distribution $Distribution
    $runtimeConfig = [ordered]@{
        schemaVersion  = 1
        distribution   = $Distribution
        listenAddress  = $ListenAddress
        listenPort     = $ListenPort
        guestPort      = $GuestPort
    }
    $runtimeConfigJson = $runtimeConfig | ConvertTo-Json -Compress
    $configMatches = Test-Path -LiteralPath $names.ConfigPath -PathType Leaf
    if ($configMatches) {
        $configMatches = (Get-Content -LiteralPath $names.ConfigPath -Raw).Trim() -eq $runtimeConfigJson
    }
    $helperMatches = Test-Path -LiteralPath $names.HelperPath -PathType Leaf
    if ($helperMatches) {
        $helperMatches = (Get-FileHash -Algorithm SHA256 -LiteralPath $names.HelperPath).Hash -eq
            (Get-FileHash -Algorithm SHA256 -LiteralPath $RuntimeHelperSource).Hash
    }
    $task = Get-ScheduledTask -TaskName $names.TaskName -ErrorAction SilentlyContinue
    $expectedArguments = "-NoLogo -NoProfile -ExecutionPolicy Bypass -File `"$($names.HelperPath)`" -ConfigPath `"$($names.ConfigPath)`" -OutputFormat Json"
    $taskMatches = $null -ne $task -and
        [string]$task.Principal.UserId -match [regex]::Escape($WindowsUser) -and
        [string]$task.Principal.LogonType -eq 'S4U' -and
        [string]$task.Principal.RunLevel -eq 'Highest' -and
        [string]$task.Settings.ExecutionTimeLimit -eq 'PT0S' -and
        @($task.Triggers).Count -eq 1 -and
        [string]$task.Triggers[0].CimClass.CimClassName -eq 'MSFT_TaskBootTrigger' -and
        @($task.Actions).Count -eq 1 -and
        [string]$task.Actions[0].Execute -match '(?i)(^|\\)powershell\.exe$' -and
        [string]$task.Actions[0].Arguments -eq $expectedArguments

    $firewallEnabled = @((Get-NetFirewallProfile | Where-Object Enabled)).Count -gt 0
    $firewallRule = Get-NetFirewallRule -Name $names.FirewallRuleName -ErrorAction SilentlyContinue
    $firewallMatches = $false
    if ($firewallRule) {
        $portFilter = $firewallRule | Get-NetFirewallPortFilter
        $addressFilter = $firewallRule | Get-NetFirewallAddressFilter
        $actualRemote = @($addressFilter.RemoteAddress | ForEach-Object { ConvertTo-WslSshAccessRemoteAddress -Address ([string]$_) } | Sort-Object -Unique)
        $expectedRemote = @($RemoteAddress | ForEach-Object { ConvertTo-WslSshAccessRemoteAddress -Address ([string]$_) } | Sort-Object -Unique)
        $firewallMatches = [string]$portFilter.LocalPort -eq [string]$ListenPort -and
            [string]$portFilter.Protocol -in @('TCP', '6') -and
            ($actualRemote -join ',') -eq ($expectedRemote -join ',')
    }
    $portProxy = Get-WslSshAccessPortProxyState -ListenAddress $ListenAddress -ListenPort $ListenPort `
        -GuestPort $GuestPort -ConnectAddress '127.0.0.1'
    $relayListening = $null -ne (Get-NetTCPConnection -LocalPort $ListenPort -State Listen -ErrorAction SilentlyContinue |
            Where-Object { $_.LocalAddress -in @($ListenAddress, '0.0.0.0') } | Select-Object -First 1)
    return [pscustomobject]@{
        Names                = $names
        ListenAddress        = $ListenAddress
        ListenPort           = $ListenPort
        RuntimeConfigJson    = $runtimeConfigJson
        RuntimeFilesExist    = (Test-Path $names.ConfigPath) -or (Test-Path $names.HelperPath)
        RuntimeFilesMatch    = $configMatches -and $helperMatches
        TaskExists           = $null -ne $task
        TaskMatches          = $taskMatches
        FirewallRuleExists   = $null -ne $firewallRule
        FirewallRequired     = $firewallEnabled
        FirewallRuleMatches  = if ($firewallEnabled) { $firewallMatches } else { $true }
        PortProxyExists      = $portProxy.Exists
        RelayListening       = $relayListening
        RelayMatches         = $relayListening -and -not $portProxy.Exists
        PortProxyAddress     = $portProxy.ConnectAddress
        ExpectedTaskArguments = $expectedArguments
    }
}

function Invoke-WslSshAccessGuest {
    <#
    .SYNOPSIS
        通过固定 guest helper 执行 WSL SSH 操作。
    .PARAMETER Distribution
        WSL 发行版名称。
    .PARAMETER Operation
        plan、apply、verify 或 rollback。
    .PARAMETER LinuxUser
        WSL 用户。
    .PARAMETER GuestPort
        WSL sshd 端口。
    .PARAMETER PublicKey
        OpenSSH 公钥。
    .PARAMETER GuestScriptPath
        Windows checkout 中的固定 guest helper 路径。
    .OUTPUTS
        PSCustomObject。guest JSON document。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Distribution,
        [Parameter(Mandatory)][string]$Operation,
        [Parameter(Mandatory)][string]$LinuxUser,
        [Parameter(Mandatory)][int]$GuestPort,
        [string]$PublicKey,
        [Parameter(Mandatory)][string]$GuestScriptPath
    )

    $pathResult = Invoke-WslSshAccessProcess -FilePath 'wsl.exe' -ArgumentList @('-d', $Distribution, '--', 'wslpath', '-a', '-u', $GuestScriptPath)
    if ($pathResult.ExitCode -ne 0) {
        throw "cannot resolve guest helper path: $($pathResult.Stderr.Trim())"
    }
    $wslGuestPath = ConvertFrom-WslSshText -Value $pathResult.Stdout
    $arguments = @('-d', $Distribution, '-u', 'root', '--', 'bash', $wslGuestPath,
        '--operation', $Operation, '--user', $LinuxUser, '--port', [string]$GuestPort, '--output-format', 'json')
    if (-not [string]::IsNullOrWhiteSpace($PublicKey)) {
        $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($PublicKey.Trim()))
        $arguments += @('--authorized-key-base64', $encoded)
    }
    $result = Invoke-WslSshAccessProcess -FilePath 'wsl.exe' -ArgumentList $arguments
    try {
        $document = (ConvertFrom-WslSshText -Value $result.Stdout) | ConvertFrom-Json
    }
    catch {
        throw "guest helper returned invalid JSON; exit=$($result.ExitCode); stderr=$($result.Stderr.Trim())"
    }
    if ([int]$document.exitCode -ne $result.ExitCode) {
        throw "guest helper exit code mismatch: process=$($result.ExitCode) document=$($document.exitCode)"
    }
    return $document
}

function Set-WslSshAccessHostResources {
    <#
    .SYNOPSIS
        幂等写入 runtime、task 和 firewall 资源。
    .PARAMETER State
        当前 host state。
    .PARAMETER Distribution
        WSL 发行版名称。
    .PARAMETER WindowsUser
        Scheduled Task 用户。
    .PARAMETER ListenPort
        Windows 监听端口。
    .PARAMETER RemoteAddress
        Windows firewall remote allowlist。
    .PARAMETER RuntimeHelperSource
        runtime helper 源路径。
    .OUTPUTS
        System.Boolean。存在写入时为 true。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][pscustomobject]$State,
        [Parameter(Mandatory)][string]$Distribution,
        [Parameter(Mandatory)][string]$WindowsUser,
        [Parameter(Mandatory)][int]$ListenPort,
        [string[]]$RemoteAddress,
        [Parameter(Mandatory)][string]$RuntimeHelperSource
    )

    $changed = $false
    if (-not (Test-Path -LiteralPath $script:RuntimeRoot -PathType Container)) {
        New-Item -ItemType Directory -Path $script:RuntimeRoot -Force | Out-Null
        $changed = $true
    }
    if (-not $State.RuntimeFilesMatch) {
        Copy-Item -LiteralPath $RuntimeHelperSource -Destination $State.Names.HelperPath -Force
        [IO.File]::WriteAllText($State.Names.ConfigPath, $State.RuntimeConfigJson, [Text.UTF8Encoding]::new($false))
        $changed = $true
    }
    if (-not $State.TaskMatches) {
        $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $State.ExpectedTaskArguments
        $trigger = New-ScheduledTaskTrigger -AtStartup
        $principal = New-ScheduledTaskPrincipal -UserId $WindowsUser -LogonType S4U -RunLevel Highest
        $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Seconds 0) -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
        Register-ScheduledTask -TaskName $State.Names.TaskName -Action $action -Trigger $trigger `
            -Principal $principal -Settings $settings -Force | Out-Null
        $changed = $true
    }
    if ($State.FirewallRequired -and -not $State.FirewallRuleMatches) {
        Remove-NetFirewallRule -Name $State.Names.FirewallRuleName -ErrorAction SilentlyContinue
        New-NetFirewallRule -Name $State.Names.FirewallRuleName -DisplayName $State.Names.FirewallRuleName `
            -Enabled True -Profile Any -Direction Inbound -Action Allow -Protocol TCP `
            -LocalPort $ListenPort -RemoteAddress $RemoteAddress | Out-Null
        $changed = $true
    }
    if ($State.PortProxyExists) {
        & netsh.exe interface portproxy delete v4tov4 "listenaddress=$($State.ListenAddress)" "listenport=$($State.ListenPort)" 2>$null | Out-Null
        $changed = $true
    }
    return $changed
}

function Remove-WslSshAccessHostResources {
    <#
    .SYNOPSIS
        精确删除本功能拥有的宿主资源。
    .PARAMETER State
        当前 host state。
    .OUTPUTS
        System.Boolean。存在删除时为 true。
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][pscustomobject]$State)

    $changed = $false
    if ($State.TaskExists) {
        Stop-ScheduledTask -TaskName $State.Names.TaskName -ErrorAction SilentlyContinue
        Unregister-ScheduledTask -TaskName $State.Names.TaskName -Confirm:$false
        $changed = $true
    }
    if ($State.PortProxyExists) {
        & netsh.exe interface portproxy delete v4tov4 "listenaddress=$($State.ListenAddress)" "listenport=$($State.ListenPort)" 2>$null | Out-Null
        $changed = $true
    }
    if ($State.FirewallRuleExists) {
        Remove-NetFirewallRule -Name $State.Names.FirewallRuleName
        $changed = $true
    }
    foreach ($path in @($State.Names.ConfigPath, $State.Names.StatusPath, $State.Names.HelperPath)) {
        if (Test-Path -LiteralPath $path) {
            Remove-Item -LiteralPath $path -Force
            $changed = $true
        }
    }
    return $changed
}

function Invoke-WslSshAccess {
    <#
    .SYNOPSIS
        执行 WSL SSH host/guest plan、apply、verify 或 rollback。
    .PARAMETER Operation
        Plan、Apply、Verify 或 Rollback。
    .PARAMETER Distribution
        WSL 发行版名称。
    .PARAMETER WindowsUser
        Scheduled Task 用户。
    .PARAMETER LinuxUser
        WSL SSH 用户。
    .PARAMETER ListenAddress
        Windows portproxy 监听地址。
    .PARAMETER ListenPort
        Windows portproxy 监听端口。
    .PARAMETER GuestPort
        WSL sshd 端口。
    .PARAMETER RemoteAddress
        Windows firewall remote allowlist。
    .PARAMETER PublicKey
        OpenSSH 公钥。
    .PARAMETER GuestScriptPath
        guest helper 路径。
    .PARAMETER RuntimeHelperSource
        runtime helper 源路径。
    .OUTPUTS
        PSCustomObject。schema v1 状态文档。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][ValidateSet('Plan', 'Apply', 'Verify', 'Rollback')][string]$Operation,
        [Parameter(Mandatory)][string]$Distribution,
        [Parameter(Mandatory)][string]$WindowsUser,
        [Parameter(Mandatory)][string]$LinuxUser,
        [string]$ListenAddress = '0.0.0.0',
        [int]$ListenPort = 2222,
        [int]$GuestPort = 2223,
        [string[]]$RemoteAddress = @('LocalSubnet', '100.64.0.0/10'),
        [string]$PublicKey,
        [Parameter(Mandatory)][string]$GuestScriptPath,
        [Parameter(Mandatory)][string]$RuntimeHelperSource
    )

    $base = [ordered]@{
        SchemaVersion = 1
        Platform      = 'Windows/WSL'
        Operation     = $Operation
        Status        = 'Invalid'
        ExitCode      = 2
        Changed       = $false
        Distribution  = $Distribution
        WindowsUser   = $WindowsUser
        LinuxUser     = $LinuxUser
        ListenAddress = $ListenAddress
        ListenPort    = $ListenPort
        GuestPort     = $GuestPort
        WslIPv4       = ''
        Guest         = $null
        Actions       = @()
        Errors        = @()
    }
    if (-not (Test-WslSshAccessPort $ListenPort) -or -not (Test-WslSshAccessPort $GuestPort)) {
        $base.Errors = @('invalid port')
        return [pscustomobject]$base
    }
    if ($Distribution -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]+$' -or $LinuxUser -notmatch '^[a-z_][a-z0-9_-]*$') {
        $base.Errors = @('invalid distribution or Linux user')
        return [pscustomobject]$base
    }
    if ($Operation -ne 'Rollback' -and -not (Test-WslSshAccessPublicKey -PublicKey $PublicKey)) {
        $base.Errors = @('invalid or missing SSH public key')
        return [pscustomobject]$base
    }
    try {
        $RemoteAddress = @(ConvertTo-WslSshAccessRemoteAddresses -Address $RemoteAddress)
    }
    catch {
        $base.Errors = @($_.Exception.Message)
        return [pscustomobject]$base
    }
    if ($env:OS -ne 'Windows_NT') {
        $base.Status = 'Blocked'
        $base.ExitCode = 10
        $base.Errors = @('real WSL SSH host operations require Windows')
        return [pscustomobject]$base
    }
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]::new($identity)
    $isAdministrator = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if ($Operation -in @('Apply', 'Rollback') -and -not $isAdministrator) {
        $base.Status = 'Blocked'
        $base.ExitCode = 10
        $base.Errors = @('apply or rollback requires an administrator PSRP session')
        return [pscustomobject]$base
    }
    if ($Distribution -notin (Get-WslSshAccessDistributionNames)) {
        $base.Status = 'Blocked'
        $base.ExitCode = 10
        $base.Errors = @('WSL distribution is not registered')
        return [pscustomobject]$base
    }
    try {
        $state = Get-WslSshAccessHostState -Distribution $Distribution -WindowsUser $WindowsUser `
            -ListenAddress $ListenAddress -ListenPort $ListenPort -GuestPort $GuestPort `
            -RemoteAddress $RemoteAddress -RuntimeHelperSource $RuntimeHelperSource
        Add-Member -InputObject $state.Names -NotePropertyName ListenPort -NotePropertyValue $ListenPort -Force
        $plan = New-WslSshAccessPlan -Operation $Operation -State $state
        $base.Actions = $plan.Actions
        if ($Operation -eq 'Plan') {
            $base.Guest = Invoke-WslSshAccessGuest -Distribution $Distribution -Operation plan `
                -LinuxUser $LinuxUser -GuestPort $GuestPort -PublicKey $PublicKey -GuestScriptPath $GuestScriptPath
            $base.Status = 'Preview'
            $base.ExitCode = 0
            $base.Changed = $plan.Changed -or [bool]$base.Guest.changed
            return [pscustomobject]$base
        }
        if ($Operation -eq 'Rollback') {
            $hostChanged = Remove-WslSshAccessHostResources -State $state
            $base.Guest = Invoke-WslSshAccessGuest -Distribution $Distribution -Operation rollback `
                -LinuxUser $LinuxUser -GuestPort $GuestPort -GuestScriptPath $GuestScriptPath
            $base.Status = if ([int]$base.Guest.exitCode -eq 0) { 'Succeeded' } else { [string]$base.Guest.status }
            $base.ExitCode = [int]$base.Guest.exitCode
            $base.Changed = $hostChanged -or [bool]$base.Guest.changed
            return [pscustomobject]$base
        }
        if ($Operation -eq 'Apply') {
            $base.Guest = Invoke-WslSshAccessGuest -Distribution $Distribution -Operation apply `
                -LinuxUser $LinuxUser -GuestPort $GuestPort -PublicKey $PublicKey -GuestScriptPath $GuestScriptPath
            if ([int]$base.Guest.exitCode -ne 0) {
                $base.Status = [string]$base.Guest.status
                $base.ExitCode = [int]$base.Guest.exitCode
                $base.Errors = @([string]$base.Guest.message)
                return [pscustomobject]$base
            }
            $hostChanged = Set-WslSshAccessHostResources -State $state -Distribution $Distribution `
                -WindowsUser $WindowsUser -ListenPort $ListenPort -RemoteAddress $RemoteAddress `
                -RuntimeHelperSource $RuntimeHelperSource
            if ($hostChanged -or [bool]$base.Guest.changed -or -not $state.RelayMatches) {
                Stop-ScheduledTask -TaskName $state.Names.TaskName -ErrorAction SilentlyContinue
                Start-ScheduledTask -TaskName $state.Names.TaskName
            }
            $deadline = [DateTime]::UtcNow.AddSeconds(60)
            do {
                Start-Sleep -Seconds 1
                $relayReady = $null -ne (Get-NetTCPConnection -LocalPort $ListenPort -State Listen -ErrorAction SilentlyContinue |
                        Where-Object { $_.LocalAddress -in @($ListenAddress, '0.0.0.0') } | Select-Object -First 1)
                $task = Get-ScheduledTask -TaskName $state.Names.TaskName
            } while (-not $relayReady -and $task.State -eq 'Running' -and [DateTime]::UtcNow -lt $deadline)
            if (-not $relayReady -or $task.State -ne 'Running') {
                $taskInfo = Get-ScheduledTaskInfo -TaskName $state.Names.TaskName
                throw "persistent TCP relay failed; state=$($task.State); result=$($taskInfo.LastTaskResult)"
            }
            if (Test-Path -LiteralPath $state.Names.StatusPath -PathType Leaf) {
                $runtimeDocument = Get-Content -LiteralPath $state.Names.StatusPath -Raw | ConvertFrom-Json
                $base.WslIPv4 = [string]$runtimeDocument.wslIPv4
            }
            $base.Changed = [bool]$base.Guest.changed -or $hostChanged
        }
        $base.Guest = Invoke-WslSshAccessGuest -Distribution $Distribution -Operation verify `
            -LinuxUser $LinuxUser -GuestPort $GuestPort -PublicKey $PublicKey -GuestScriptPath $GuestScriptPath
        $verifiedState = Get-WslSshAccessHostState -Distribution $Distribution -WindowsUser $WindowsUser `
            -ListenAddress $ListenAddress -ListenPort $ListenPort -GuestPort $GuestPort `
            -RemoteAddress $RemoteAddress -RuntimeHelperSource $RuntimeHelperSource
        if ([int]$base.Guest.exitCode -eq 0 -and $verifiedState.RuntimeFilesMatch -and
            $verifiedState.TaskMatches -and $verifiedState.FirewallRuleMatches -and $verifiedState.RelayMatches) {
            $base.Status = 'Succeeded'
            $base.ExitCode = 0
        }
        else {
            $base.Status = 'Failed'
            $base.ExitCode = 1
            $base.Errors = @('post-operation verification failed')
        }
    }
    catch {
        $base.Status = 'Failed'
        $base.ExitCode = 1
        $base.Errors = @($_.Exception.Message)
    }
    return [pscustomobject]$base
}

Export-ModuleMember -Function @(
    'ConvertFrom-WslSshText',
    'Get-WslSshAccessSafeId',
    'Get-WslSshAccessResourceNames',
    'Test-WslSshAccessPublicKey',
    'Test-WslSshAccessPort',
    'ConvertTo-WslSshAccessRemoteAddress',
    'ConvertTo-WslSshAccessRemoteAddresses',
    'New-WslSshAccessPlan',
    'Invoke-WslSshAccess'
)
