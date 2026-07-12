Set-StrictMode -Version Latest

Import-Module (Join-Path $PSScriptRoot 'WindowsBootstrap.psm1') -Force

$script:ManagedCertificateSubjectPrefix = 'CN=powershellScripts-PSRP-'
$script:ManagedFirewallRuleName = 'powershellScripts-PSRP-HTTPS'
$script:TailscaleIPv4Range = '100.64.0.0/10'
$script:TailscaleIPv4NetmaskRange = '100.64.0.0/255.192.0.0'

function New-WindowsRemotePsRemotingAction {
    <#
    .SYNOPSIS
        创建远程 PSRP bootstrap 计划动作。

    .PARAMETER Name
        资源名称。

    .PARAMETER Action
        Create、Ensure、Reuse、AlreadyPresent、Remove、Skip、Verify 或 Blocked。

    .PARAMETER Message
        可操作说明。

    .OUTPUTS
        PSCustomObject。包含 Name、Action 和 Message。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [ValidateSet('Create', 'Ensure', 'Reuse', 'AlreadyPresent', 'Remove', 'Skip', 'Verify', 'Blocked')]
        [string]$Action,

        [string]$Message = ''
    )

    return [pscustomobject][ordered]@{
        Name    = $Name
        Action  = $Action
        Message = $Message
    }
}

function Test-WindowsTailscaleIPv4 {
    <#
    .SYNOPSIS
        判断字符串是否为 Tailscale CGNAT IPv4。

    .PARAMETER IPAddress
        待验证 IPv4 字符串。

    .OUTPUTS
        System.Boolean。地址位于 100.64.0.0/10 时返回 true。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$IPAddress
    )

    $parsed = $null
    if (-not [System.Net.IPAddress]::TryParse($IPAddress, [ref]$parsed)) {
        return $false
    }
    if ($parsed.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork) {
        return $false
    }
    $bytes = $parsed.GetAddressBytes()
    return $bytes[0] -eq 100 -and $bytes[1] -ge 64 -and $bytes[1] -le 127
}

function Select-WindowsTailscaleIPv4 {
    <#
    .SYNOPSIS
        从候选地址中选择唯一的 Tailscale IPv4。

    .PARAMETER Candidate
        显式参数、Tailscale adapter 或 tailscale.exe 返回的候选地址。

    .OUTPUTS
        System.String。唯一且规范化的 Tailscale IPv4。
    #>
    [CmdletBinding()]
    param(
        [string[]]$Candidate
    )

    $valid = @($Candidate | ForEach-Object { ([string]$_).Trim() } |
        Where-Object { $_ -and (Test-WindowsTailscaleIPv4 -IPAddress $_) } |
        Sort-Object -Unique)
    if ($valid.Count -eq 0) {
        throw [System.ArgumentException]::new('未发现 100.64.0.0/10 范围内的 Tailscale IPv4')
    }
    if ($valid.Count -gt 1) {
        throw [System.ArgumentException]::new("发现多个 Tailscale IPv4，必须显式指定一个地址: $($valid -join ', ')")
    }
    return $valid[0]
}

function Get-WindowsTailscaleIPv4 {
    <#
    .SYNOPSIS
        从显式参数、Tailscale adapter 或 tailscale.exe 发现当前 IPv4。

    .PARAMETER IPAddress
        可选显式 Tailscale IPv4；提供时不读取系统 adapter。

    .OUTPUTS
        System.String。唯一的 Tailscale IPv4。
    #>
    [CmdletBinding()]
    param(
        [string]$IPAddress = ''
    )

    if (-not [string]::IsNullOrWhiteSpace($IPAddress)) {
        return Select-WindowsTailscaleIPv4 -Candidate @($IPAddress)
    }

    $candidate = New-Object System.Collections.Generic.List[string]
    if (Get-Command Get-NetAdapter -ErrorAction SilentlyContinue) {
        foreach ($adapter in @(Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object {
                    ([string]$_.Name -match 'Tailscale') -or ([string]$_.InterfaceDescription -match 'Tailscale')
                })) {
            foreach ($address in @(Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue)) {
                $candidate.Add([string]$address.IPAddress)
            }
        }
    }
    $tailscaleCommand = Get-Command tailscale.exe -ErrorAction SilentlyContinue
    if ($null -eq $tailscaleCommand) {
        $tailscaleCommand = Get-Command tailscale -ErrorAction SilentlyContinue
    }
    if ($null -ne $tailscaleCommand) {
        foreach ($line in @(& $tailscaleCommand.Source ip -4 2>$null)) {
            $candidate.Add([string]$line)
        }
    }
    return Select-WindowsTailscaleIPv4 -Candidate $candidate.ToArray()
}

function Select-WindowsRemotePsRemotingCertificate {
    <#
    .SYNOPSIS
        选择仍可复用的托管 PSRP 证书。

    .PARAMETER Certificate
        LocalMachine My store 中的证书对象。

    .PARAMETER Now
        当前时间，测试可注入固定值。

    .OUTPUTS
        X509Certificate2 或 null。返回有效期超过 30 天且含私钥的最新托管证书。
    #>
    [CmdletBinding()]
    param(
        [object[]]$Certificate,

        [datetime]$Now = (Get-Date)
    )

    return @($Certificate | Where-Object {
            ([string]$_.Subject).StartsWith($script:ManagedCertificateSubjectPrefix, [System.StringComparison]::OrdinalIgnoreCase) -and
            [bool]$_.HasPrivateKey -and
            ([datetime]$_.NotBefore) -le $Now -and
            ([datetime]$_.NotAfter) -gt $Now.AddDays(30)
        } | Sort-Object NotAfter -Descending) | Select-Object -First 1
}

function Get-WindowsWsManListenerValue {
    <#
    .SYNOPSIS
        从 WSMan listener 容器或其子项读取配置值。

    .PARAMETER Listener
        Get-ChildItem WSMan:\localhost\Listener 返回的 listener 容器。

    .PARAMETER Name
        Port 或 CertificateThumbprint 等配置项名称。

    .OUTPUTS
        System.Object。返回 listener 直接属性或 WSMan provider 子项的 Value。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Listener,

        [Parameter(Mandatory)]
        [string]$Name
    )

    $property = $Listener.PSObject.Properties[$Name]
    if ($null -ne $property -and $null -ne $property.Value -and [string]$property.Value -ne '') {
        return $property.Value
    }
    $pathProperty = $Listener.PSObject.Properties['PSPath']
    if ($null -eq $pathProperty -or [string]::IsNullOrWhiteSpace([string]$pathProperty.Value)) {
        $pathProperty = $Listener.PSObject.Properties['Path']
    }
    if ($null -eq $pathProperty -or [string]::IsNullOrWhiteSpace([string]$pathProperty.Value)) {
        return $null
    }
    $item = Get-Item -LiteralPath ("{0}\{1}" -f $pathProperty.Value, $Name) -ErrorAction SilentlyContinue
    if ($null -ne $item -and $item.PSObject.Properties.Name -contains 'Value') {
        return $item.Value
    }
    return $null
}

function ConvertTo-WindowsWsManListenerSelector {
    <#
    .SYNOPSIS
        把单个 IPv4 转换为 WSMan listener Address selector。

    .PARAMETER IPAddress
        要绑定的 IPv4 地址。

    .OUTPUTS
        System.String。格式为 IP:<address>。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$IPAddress
    )

    return "IP:$IPAddress"
}

function ConvertFrom-WindowsWsManListener {
    <#
    .SYNOPSIS
        把 WSMan provider listener 转换成稳定结构。

    .PARAMETER Listener
        Get-ChildItem WSMan:\localhost\Listener 返回的对象。

    .OUTPUTS
        PSCustomObject。包含 Address、Transport、Port、CertificateThumbprint 和 Path。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Listener
    )

    $values = @{}
    foreach ($key in @($Listener.Keys)) {
        $parts = ([string]$key) -split '=', 2
        if ($parts.Count -eq 2) {
            $values[$parts[0]] = $parts[1]
        }
    }
    $portValue = Get-WindowsWsManListenerValue -Listener $Listener -Name Port
    $port = 5986
    if ($values.ContainsKey('Port') -and [int]::TryParse([string]$values.Port, [ref]$port)) {
        $port = [int]$values.Port
    }
    elseif ($null -ne $portValue) {
        $port = [int]$portValue
    }
    $address = [string]$values.Address
    if ($address.StartsWith('IP:', [System.StringComparison]::OrdinalIgnoreCase)) {
        $address = $address.Substring(3)
    }
    return [pscustomobject][ordered]@{
        Address               = $address
        Transport             = [string]$values.Transport
        Port                  = $port
        CertificateThumbprint = [string](Get-WindowsWsManListenerValue -Listener $Listener -Name CertificateThumbprint)
        Path                  = [string]$(if ($Listener.PSObject.Properties.Name -contains 'PSPath') { $Listener.PSPath } else { $Listener.Path })
    }
}

function Test-WindowsRemotePsRemotingBinding {
    <#
    .SYNOPSIS
        验证指定端口的 HTTPS listener 只绑定目标 Tailscale IPv4。

    .PARAMETER Listener
        ConvertFrom-WindowsWsManListener 返回的 listener 数组。

    .PARAMETER IPAddress
        期望的 Tailscale IPv4。

    .PARAMETER Port
        HTTPS listener 端口。

    .OUTPUTS
        System.Boolean。至少存在一个精确 listener 且没有 wildcard/其他地址时返回 true。
    #>
    [CmdletBinding()]
    param(
        [object[]]$Listener,

        [Parameter(Mandatory)]
        [string]$IPAddress,

        [ValidateRange(1, 65535)]
        [int]$Port = 5986
    )

    $https = @($Listener | Where-Object {
            [string]$_.Transport -eq 'HTTPS' -and [int]$_.Port -eq $Port
        })
    if ($https.Count -eq 0) {
        return $false
    }
    return @($https | Where-Object { [string]$_.Address -ne $IPAddress }).Count -eq 0
}

function New-WindowsRemotePsRemotingPlan {
    <#
    .SYNOPSIS
        根据已发现状态生成固定 PSRP configure 或 rollback 计划。

    .PARAMETER IPAddress
        目标 Tailscale IPv4。

    .PARAMETER Port
        HTTPS listener 端口。

    .PARAMETER CertificateReusable
        是否存在可复用托管证书。

    .PARAMETER ManagedCertificateExists
        是否存在任意托管证书。

    .PARAMETER ListenerState
        Missing、Matched、ManagedDrift 或 Conflict。

    .PARAMETER FirewallEnabled
        是否至少有一个 Windows Firewall profile 启用。

    .PARAMETER FirewallRuleExists
        固定托管防火墙 rule 是否存在。

    .PARAMETER FirewallRuleMatches
        托管 rule 的 local/remote address、端口和动作是否匹配。

    .PARAMETER Rollback
        生成仅删除托管资源的 rollback 计划。

    .OUTPUTS
        PSCustomObject。包含 Operation、Status、ExitCode 和 Actions。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$IPAddress,

        [ValidateRange(1, 65535)]
        [int]$Port = 5986,

        [switch]$CertificateReusable,

        [switch]$ManagedCertificateExists,

        [ValidateSet('Missing', 'Matched', 'ManagedDrift', 'Conflict')]
        [string]$ListenerState = 'Missing',

        [switch]$FirewallEnabled,

        [switch]$FirewallRuleExists,

        [switch]$FirewallRuleMatches,

        [switch]$Rollback
    )

    if (-not (Test-WindowsTailscaleIPv4 -IPAddress $IPAddress)) {
        throw [System.ArgumentException]::new("不是有效的 Tailscale IPv4: $IPAddress")
    }
    $actions = New-Object System.Collections.Generic.List[object]
    if ($Rollback) {
        $actions.Add((New-WindowsRemotePsRemotingAction -Name HttpsListener `
                    -Action $(if ($ListenerState -in @('Matched', 'ManagedDrift')) { 'Remove' } else { 'Skip' }) `
                    -Message '只删除使用托管证书的 HTTPS listener'))
        $actions.Add((New-WindowsRemotePsRemotingAction -Name FirewallRule `
                    -Action $(if ($FirewallRuleExists) { 'Remove' } else { 'Skip' }) `
                    -Message '不改变 Windows Firewall profile 全局状态'))
        $actions.Add((New-WindowsRemotePsRemotingAction -Name Certificate `
                    -Action $(if ($ManagedCertificateExists) { 'Remove' } else { 'Skip' }) `
                    -Message '只删除 powershellScripts-PSRP subject 前缀证书'))
        $actions.Add((New-WindowsRemotePsRemotingAction -Name Verification -Action Verify -Message '确认托管资源已移除且 OpenSSH 未修改'))
        return [pscustomobject][ordered]@{
            SchemaVersion = 1
            Operation     = 'Rollback'
            Status        = 'Ready'
            ExitCode      = 0
            IPAddress     = $IPAddress
            Port          = $Port
            Actions       = $actions.ToArray()
        }
    }

    if ($ListenerState -eq 'Conflict') {
        $actions.Add((New-WindowsRemotePsRemotingAction -Name HttpsListener -Action Blocked `
                    -Message "端口 $Port 存在非托管或非 Tailscale HTTPS listener，拒绝覆盖"))
        return [pscustomobject][ordered]@{
            SchemaVersion = 1
            Operation     = 'Configure'
            Status        = 'Blocked'
            ExitCode      = 10
            IPAddress     = $IPAddress
            Port          = $Port
            Actions       = $actions.ToArray()
        }
    }

    $actions.Add((New-WindowsRemotePsRemotingAction -Name WinRMService -Action Ensure -Message '保持 WinRM 自动启动并运行'))
    $actions.Add((New-WindowsRemotePsRemotingAction -Name WinRMSecurity -Action Ensure -Message 'AllowUnencrypted=false，Negotiate=true'))
    $actions.Add((New-WindowsRemotePsRemotingAction -Name Certificate `
                -Action $(if ($CertificateReusable) { 'Reuse' } else { 'Create' }) `
                -Message '使用 LocalMachine\My 中的非导出 SSL server 证书'))
    $listenerAction = switch ($ListenerState) {
        'Matched' { 'AlreadyPresent' }
        'ManagedDrift' { 'Ensure' }
        default { 'Create' }
    }
    $actions.Add((New-WindowsRemotePsRemotingAction -Name HttpsListener -Action $listenerAction `
                -Message "Address=$IPAddress, Port=$Port, Transport=HTTPS"))
    if (-not $FirewallEnabled) {
        $actions.Add((New-WindowsRemotePsRemotingAction -Name FirewallRule -Action Skip `
                    -Message 'Windows Firewall profile 当前全部关闭；保持全局状态，只验证 listener'))
    }
    elseif ($FirewallRuleExists -and $FirewallRuleMatches) {
        $actions.Add((New-WindowsRemotePsRemotingAction -Name FirewallRule -Action AlreadyPresent `
                    -Message "LocalAddress=$IPAddress, RemoteAddress=$script:TailscaleIPv4Range, Port=$Port"))
    }
    else {
        $actions.Add((New-WindowsRemotePsRemotingAction -Name FirewallRule -Action Ensure `
                    -Message "LocalAddress=$IPAddress, RemoteAddress=$script:TailscaleIPv4Range, Port=$Port"))
    }
    $actions.Add((New-WindowsRemotePsRemotingAction -Name Verification -Action Verify `
                -Message '拒绝 Address=*、0.0.0.0、:: 或其他接口 listener'))
    return [pscustomobject][ordered]@{
        SchemaVersion = 1
        Operation     = 'Configure'
        Status        = 'Ready'
        ExitCode      = 0
        IPAddress     = $IPAddress
        Port          = $Port
        Actions       = $actions.ToArray()
    }
}

function ConvertTo-WindowsRemoteBoolean {
    <#
    .SYNOPSIS
        把 WSMan/NetSecurity 的 bool 或字符串值转换为布尔值。

    .PARAMETER Value
        True/False、布尔值或数值。

    .OUTPUTS
        System.Boolean。无法识别时返回 false。
    #>
    [CmdletBinding()]
    param(
        [object]$Value
    )

    if ($Value -is [bool]) {
        return [bool]$Value
    }
    $parsed = $false
    if ([bool]::TryParse([string]$Value, [ref]$parsed)) {
        return $parsed
    }
    return [string]$Value -eq '1'
}

function Test-WindowsRemotePsRemotingFirewallRule {
    <#
    .SYNOPSIS
        验证托管防火墙 rule 的方向、动作、地址和端口过滤器。

    .PARAMETER Rule
        Get-NetFirewallRule 返回的单个 rule。

    .PARAMETER PortFilter
        Get-NetFirewallPortFilter 返回的过滤器。

    .PARAMETER AddressFilter
        Get-NetFirewallAddressFilter 返回的过滤器。

    .PARAMETER IPAddress
        期望的本地 Tailscale IPv4。

    .PARAMETER Port
        期望的本地 TCP 端口。

    .OUTPUTS
        System.Boolean。rule 精确匹配安全边界时返回 true。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [object]$Rule,

        [Parameter(Mandatory)]
        [object]$PortFilter,

        [Parameter(Mandatory)]
        [object]$AddressFilter,

        [Parameter(Mandatory)]
        [string]$IPAddress,

        [ValidateRange(1, 65535)]
        [int]$Port = 5986
    )

    $localPorts = @($PortFilter.LocalPort | ForEach-Object { [string]$_ })
    $localAddresses = @($AddressFilter.LocalAddress | ForEach-Object { [string]$_ })
    $remoteAddresses = @($AddressFilter.RemoteAddress | ForEach-Object { [string]$_ })
    return (ConvertTo-WindowsRemoteBoolean -Value $Rule.Enabled) -and
    [string]$Rule.Direction -eq 'Inbound' -and [string]$Rule.Action -eq 'Allow' -and
    ([string]$PortFilter.Protocol) -in @('TCP', '6') -and
    $localPorts.Count -eq 1 -and $localPorts[0] -eq [string]$Port -and
    $localAddresses.Count -eq 1 -and $localAddresses[0] -eq $IPAddress -and
    $remoteAddresses.Count -eq 1 -and $remoteAddresses[0] -in @(
        $script:TailscaleIPv4Range,
        $script:TailscaleIPv4NetmaskRange
    )
}

function Get-WindowsRemotePsRemotingWsManState {
    <#
    .SYNOPSIS
        读取 WSMan listener 与安全项，兼容尚未初始化 WinRM 的主机。

    .OUTPUTS
        PSCustomObject。包含 Listeners、AllowUnencrypted 和 Negotiate。
    #>
    [CmdletBinding()]
    param()

    $listenerPath = 'WSMan:\localhost\Listener'
    $listeners = @()
    if (Test-Path -LiteralPath $listenerPath) {
        $listeners = @(Get-ChildItem -LiteralPath $listenerPath -ErrorAction Stop | ForEach-Object {
                ConvertFrom-WindowsWsManListener -Listener $_
            })
    }

    $allowUnencrypted = $false
    $allowUnencryptedPath = 'WSMan:\localhost\Service\AllowUnencrypted'
    if (Test-Path -LiteralPath $allowUnencryptedPath) {
        $allowUnencrypted = ConvertTo-WindowsRemoteBoolean -Value (
            Get-Item -LiteralPath $allowUnencryptedPath -ErrorAction Stop
        ).Value
    }

    $negotiate = $true
    $negotiatePath = 'WSMan:\localhost\Service\Auth\Negotiate'
    if (Test-Path -LiteralPath $negotiatePath) {
        $negotiate = ConvertTo-WindowsRemoteBoolean -Value (
            Get-Item -LiteralPath $negotiatePath -ErrorAction Stop
        ).Value
    }

    return [pscustomobject][ordered]@{
        Listeners          = @($listeners)
        AllowUnencrypted   = $allowUnencrypted
        Negotiate          = $negotiate
    }
}

function Get-WindowsRemotePsRemotingState {
    <#
    .SYNOPSIS
        读取托管证书、WSMan listener、WinRM 安全项和防火墙 rule 状态。

    .PARAMETER IPAddress
        目标 Tailscale IPv4。

    .PARAMETER Port
        HTTPS listener 端口。

    .OUTPUTS
        PSCustomObject。供 New-WindowsRemotePsRemotingPlan 和最终验证使用。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$IPAddress,

        [ValidateRange(1, 65535)]
        [int]$Port = 5986
    )

    $certificates = @(Get-ChildItem Cert:\LocalMachine\My -ErrorAction Stop | Where-Object {
            ([string]$_.Subject).StartsWith($script:ManagedCertificateSubjectPrefix, [System.StringComparison]::OrdinalIgnoreCase)
        })
    $selectedCertificate = Select-WindowsRemotePsRemotingCertificate -Certificate $certificates
    $managedThumbprints = @($certificates | ForEach-Object { [string]$_.Thumbprint })
    $wsManState = Get-WindowsRemotePsRemotingWsManState
    $listeners = @($wsManState.Listeners)
    $managedListeners = @($listeners | Where-Object { [string]$_.CertificateThumbprint -in $managedThumbprints })
    $portListeners = @($listeners | Where-Object {
            [string]$_.Transport -eq 'HTTPS' -and [int]$_.Port -eq $Port
        })
    $exactListeners = @($portListeners | Where-Object { [string]$_.Address -eq $IPAddress })
    $unmanaged = @($portListeners | Where-Object { [string]$_.CertificateThumbprint -notin $managedThumbprints })
    $listenerState = 'Missing'
    if ($unmanaged.Count -gt 0) {
        $listenerState = 'Conflict'
    }
    elseif ($exactListeners.Count -eq 1 -and $null -ne $selectedCertificate -and
        [string]$exactListeners[0].CertificateThumbprint -eq [string]$selectedCertificate.Thumbprint -and
        (Test-WindowsRemotePsRemotingBinding -Listener $portListeners -IPAddress $IPAddress -Port $Port)) {
        $listenerState = 'Matched'
    }
    elseif ($managedListeners.Count -gt 0 -or $exactListeners.Count -gt 0) {
        $listenerState = 'ManagedDrift'
    }

    $firewallEnabled = @((Get-NetFirewallProfile -ErrorAction Stop) | Where-Object {
            ConvertTo-WindowsRemoteBoolean -Value $_.Enabled
        }).Count -gt 0
    $firewallRules = @(Get-NetFirewallRule -Name $script:ManagedFirewallRuleName -ErrorAction SilentlyContinue)
    $firewallRuleMatches = $false
    if ($firewallRules.Count -eq 1) {
        $rule = $firewallRules[0]
        $portFilter = Get-NetFirewallPortFilter -AssociatedNetFirewallRule $rule -ErrorAction SilentlyContinue
        $addressFilter = Get-NetFirewallAddressFilter -AssociatedNetFirewallRule $rule -ErrorAction SilentlyContinue
        if ($null -ne $portFilter -and $null -ne $addressFilter) {
            $firewallRuleMatches = Test-WindowsRemotePsRemotingFirewallRule -Rule $rule `
                -PortFilter $portFilter -AddressFilter $addressFilter -IPAddress $IPAddress -Port $Port
        }
    }
    return [pscustomobject][ordered]@{
        ManagedCertificates       = @($certificates)
        SelectedCertificate       = $selectedCertificate
        ManagedListeners          = @($managedListeners)
        Listeners                 = @($listeners)
        ListenerState             = $listenerState
        ListenerBindingValid      = Test-WindowsRemotePsRemotingBinding -Listener $portListeners -IPAddress $IPAddress -Port $Port
        FirewallEnabled           = $firewallEnabled
        FirewallRuleExists        = $firewallRules.Count -gt 0
        FirewallRuleMatches       = $firewallRuleMatches
        AllowUnencrypted          = [bool]$wsManState.AllowUnencrypted
        Negotiate                 = [bool]$wsManState.Negotiate
        ManagedFirewallRuleName   = $script:ManagedFirewallRuleName
        ManagedCertificatePrefix = $script:ManagedCertificateSubjectPrefix
    }
}

function New-WindowsRemotePsRemotingDocument {
    <#
    .SYNOPSIS
        创建稳定的远程 PSRP bootstrap 输出文档。

    .PARAMETER Operation
        Configure 或 Rollback。

    .PARAMETER Status
        Succeeded、Preview、Blocked、Failed 或 Invalid。

    .PARAMETER ExitCode
        0、1、2 或 10。

    .PARAMETER IPAddress
        目标 Tailscale IPv4。

    .PARAMETER Port
        HTTPS listener 端口。

    .PARAMETER FirewallEnabled
        Windows Firewall 是否启用。

    .PARAMETER Result
        逐资源结果。

    .PARAMETER ListenerAddress
        最终 WSMan listener 地址列表。

    .PARAMETER RerunCommand
        精确重跑或回滚命令。

    .OUTPUTS
        PSCustomObject。可直接序列化成单个 JSON document。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('Configure', 'Rollback')]
        [string]$Operation,

        [Parameter(Mandatory)]
        [ValidateSet('Succeeded', 'Preview', 'Blocked', 'Failed', 'Invalid')]
        [string]$Status,

        [int]$ExitCode,

        [string]$IPAddress = '',

        [int]$Port = 5986,

        [bool]$FirewallEnabled = $false,

        [object[]]$Result,

        [string[]]$ListenerAddress,

        [string]$RerunCommand = ''
    )

    return [pscustomobject][ordered]@{
        SchemaVersion    = 1
        Operation        = $Operation
        Status           = $Status
        ExitCode         = $ExitCode
        TailscaleIPv4    = $IPAddress
        Port             = $Port
        FirewallEnabled  = $FirewallEnabled
        ListenerAddress  = @($ListenerAddress)
        Results          = @($Result)
        RerunCommand     = $RerunCommand
        OpenSshUnchanged = $true
    }
}

function Test-WindowsRemotePsRemotingWindowsHost {
    <#
    .SYNOPSIS
        判断当前进程是否运行在 Windows。

    .OUTPUTS
        System.Boolean。Windows 返回 true。
    #>
    [CmdletBinding()]
    param()

    return [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT
}

function Invoke-WindowsRemotePsRemoting {
    <#
    .SYNOPSIS
        配置或回滚仅绑定 Tailscale IPv4 的 Windows HTTPS PSRP listener。

    .PARAMETER TailscaleIPv4
        可选显式 Tailscale IPv4；空值时从 adapter 或 tailscale.exe 发现。

    .PARAMETER Port
        HTTPS listener 端口，默认 5986。

    .PARAMETER CertificateValidityYears
        新建自签名证书有效年数。

    .PARAMETER Rollback
        删除本模块管理的 listener、规则和证书。

    .PARAMETER Preview
        只输出计划；非 Windows 控制端可用显式 IP 生成合成计划。

    .OUTPUTS
        PSCustomObject。稳定结果文档，调用方按 ExitCode 退出。
    #>
    [CmdletBinding()]
    param(
        [string]$TailscaleIPv4 = '',

        [ValidateRange(1, 65535)]
        [int]$Port = 5986,

        [ValidateRange(1, 10)]
        [int]$CertificateValidityYears = 3,

        [switch]$Rollback,

        [switch]$Preview
    )

    $operation = if ($Rollback) { 'Rollback' } else { 'Configure' }
    $resolvedIPAddress = ''
    $rerunCommand = ''
    try {
        $resolvedIPAddress = Get-WindowsTailscaleIPv4 -IPAddress $TailscaleIPv4
        $rerunCommand = ".\windows\bootstrap\Enable-WindowsRemotePsRemoting.ps1 -TailscaleIPv4 $resolvedIPAddress -Port $Port"
        if ($Rollback) {
            $rerunCommand += ' -Rollback'
        }
    }
    catch [System.ArgumentException] {
        return New-WindowsRemotePsRemotingDocument -Operation $operation -Status Invalid -ExitCode 2 -Port $Port `
            -Result @((New-WindowsBootstrapResult -Name TailscaleIPv4 -Status Failed -Message $_.Exception.Message -ExitCode 2))
    }

    $windowsHost = Test-WindowsRemotePsRemotingWindowsHost
    if (-not $windowsHost -and -not $Preview) {
        return New-WindowsRemotePsRemotingDocument -Operation $operation -Status Blocked -ExitCode 10 `
            -IPAddress $resolvedIPAddress -Port $Port -RerunCommand $rerunCommand `
            -Result @((New-WindowsBootstrapResult -Name Platform -Status Blocked -Message '真实 PSRP bootstrap 只支持 Windows 管理员进程' -ExitCode 10))
    }

    if ($windowsHost -and -not $Preview -and -not (Test-WindowsBootstrapAdministrator)) {
        return New-WindowsRemotePsRemotingDocument -Operation $operation -Status Blocked -ExitCode 10 `
            -IPAddress $resolvedIPAddress -Port $Port -RerunCommand $rerunCommand `
            -Result @((New-WindowsBootstrapResult -Name Administrator -Status Blocked `
                    -Message '当前进程不是管理员；远程入口不会请求 UAC，请从管理员 OpenSSH 会话重跑' -ExitCode 10))
    }

    if (-not $windowsHost -and $Preview) {
        $state = [pscustomobject]@{
            ManagedCertificates  = @()
            SelectedCertificate  = $null
            ManagedListeners     = @()
            Listeners            = @()
            ListenerState        = 'Missing'
            ListenerBindingValid = $false
            FirewallEnabled      = $false
            FirewallRuleExists   = $false
            FirewallRuleMatches  = $false
            AllowUnencrypted     = $false
            Negotiate            = $true
        }
    }
    else {
        try {
            $state = Get-WindowsRemotePsRemotingState -IPAddress $resolvedIPAddress -Port $Port
        }
        catch {
            return New-WindowsRemotePsRemotingDocument -Operation $operation -Status Failed -ExitCode 1 `
                -IPAddress $resolvedIPAddress -Port $Port -RerunCommand $rerunCommand `
                -Result @((New-WindowsBootstrapResult -Name StateDiscovery -Status Failed -Message $_.Exception.Message -ExitCode 1))
        }
    }

    $planArguments = @{
        IPAddress                = $resolvedIPAddress
        Port                     = $Port
        CertificateReusable      = $null -ne $state.SelectedCertificate
        ManagedCertificateExists = @($state.ManagedCertificates).Count -gt 0
        ListenerState            = [string]$state.ListenerState
        FirewallEnabled          = [bool]$state.FirewallEnabled
        FirewallRuleExists       = [bool]$state.FirewallRuleExists
        FirewallRuleMatches      = [bool]$state.FirewallRuleMatches
        Rollback                 = [bool]$Rollback
    }
    $plan = New-WindowsRemotePsRemotingPlan @planArguments
    if ([int]$plan.ExitCode -ne 0) {
        return New-WindowsRemotePsRemotingDocument -Operation $operation -Status Blocked -ExitCode 10 `
            -IPAddress $resolvedIPAddress -Port $Port -FirewallEnabled ([bool]$state.FirewallEnabled) `
            -ListenerAddress @($state.Listeners | ForEach-Object { [string]$_.Address }) -RerunCommand $rerunCommand `
            -Result @($plan.Actions | ForEach-Object {
                    New-WindowsBootstrapResult -Name $_.Name -Status Blocked -Message $_.Message -ExitCode 10
                })
    }

    if ($Preview) {
        $previewResult = @($plan.Actions | ForEach-Object {
                $status = if ($_.Action -in @('AlreadyPresent', 'Reuse')) { 'AlreadyPresent' } elseif ($_.Action -eq 'Skip') { 'Skipped' } else { 'Preview' }
                New-WindowsBootstrapResult -Name $_.Name -Status $status -Message "$($_.Action): $($_.Message)"
            })
        return New-WindowsRemotePsRemotingDocument -Operation $operation -Status Preview -ExitCode 0 `
            -IPAddress $resolvedIPAddress -Port $Port -FirewallEnabled ([bool]$state.FirewallEnabled) `
            -ListenerAddress @($state.Listeners | ForEach-Object { [string]$_.Address }) -RerunCommand $rerunCommand -Result $previewResult
    }

    $results = New-Object System.Collections.Generic.List[object]
    $finalState = $null
    try {
        if ($Rollback) {
            foreach ($listener in @($state.ManagedListeners)) {
                Remove-Item -LiteralPath $listener.Path -Recurse -Force -ErrorAction Stop
            }
            $results.Add((New-WindowsBootstrapResult -Name HttpsListener -Status Succeeded -Message '已删除托管 HTTPS listener'))
            if ($state.FirewallRuleExists) {
                Remove-NetFirewallRule -Name $script:ManagedFirewallRuleName -ErrorAction Stop
                $results.Add((New-WindowsBootstrapResult -Name FirewallRule -Status Succeeded -Message '已删除托管防火墙 rule'))
            }
            else {
                $results.Add((New-WindowsBootstrapResult -Name FirewallRule -Status AlreadyPresent -Message '托管防火墙 rule 不存在'))
            }
            foreach ($certificate in @($state.ManagedCertificates)) {
                Remove-Item -LiteralPath ("Cert:\LocalMachine\My\{0}" -f $certificate.Thumbprint) -Force -ErrorAction Stop
            }
            $results.Add((New-WindowsBootstrapResult -Name Certificate -Status Succeeded -Message '已删除托管证书'))
            $finalState = Get-WindowsRemotePsRemotingState -IPAddress $resolvedIPAddress -Port $Port
            $removed = @($finalState.ManagedListeners).Count -eq 0 -and @($finalState.ManagedCertificates).Count -eq 0 -and -not $finalState.FirewallRuleExists
            $results.Add((New-WindowsBootstrapResult -Name Verification `
                    -Status $(if ($removed) { 'Succeeded' } else { 'Failed' }) `
                    -Message $(if ($removed) { '托管 PSRP 资源已移除；OpenSSH 未修改' } else { '仍存在托管 PSRP 资源' }) `
                    -ExitCode $(if ($removed) { 0 } else { 1 })))
        }
        else {
            Set-Service -Name WinRM -StartupType Automatic -ErrorAction Stop
            if ((Get-Service -Name WinRM -ErrorAction Stop).Status -ne 'Running') {
                Start-Service -Name WinRM -ErrorAction Stop
            }
            $results.Add((New-WindowsBootstrapResult -Name WinRMService -Status Succeeded -Message 'WinRM 已运行并设为 Automatic'))
            Set-Item WSMan:\localhost\Service\AllowUnencrypted -Value $false -Force -ErrorAction Stop
            Set-Item WSMan:\localhost\Service\Auth\Negotiate -Value $true -Force -ErrorAction Stop
            $results.Add((New-WindowsBootstrapResult -Name WinRMSecurity -Status Succeeded -Message 'AllowUnencrypted=false，Negotiate=true'))

            $certificate = $state.SelectedCertificate
            if ($null -eq $certificate) {
                $subject = "$script:ManagedCertificateSubjectPrefix$env:COMPUTERNAME"
                $certificate = New-SelfSignedCertificate -Subject $subject -CertStoreLocation Cert:\LocalMachine\My `
                    -KeyAlgorithm RSA -KeyLength 2048 -HashAlgorithm SHA256 -KeyExportPolicy NonExportable `
                    -NotAfter (Get-Date).AddYears($CertificateValidityYears) -Type SSLServerAuthentication -ErrorAction Stop
                $results.Add((New-WindowsBootstrapResult -Name Certificate -Status Succeeded -Message "已创建托管证书: $($certificate.Thumbprint)"))
            }
            else {
                $results.Add((New-WindowsBootstrapResult -Name Certificate -Status AlreadyPresent -Message "复用托管证书: $($certificate.Thumbprint)"))
            }

            if ($state.ListenerState -ne 'Matched') {
                foreach ($listener in @($state.ManagedListeners)) {
                    Remove-Item -LiteralPath $listener.Path -Recurse -Force -ErrorAction Stop
                }
                $listenerSelector = ConvertTo-WindowsWsManListenerSelector -IPAddress $resolvedIPAddress
                New-Item -Path WSMan:\localhost\Listener -Transport HTTPS -Address $listenerSelector -Port $Port `
                    -CertificateThumbPrint ([string]$certificate.Thumbprint) -Force -ErrorAction Stop | Out-Null
                $results.Add((New-WindowsBootstrapResult -Name HttpsListener -Status Succeeded `
                        -Message "已创建 Address=$resolvedIPAddress Port=$Port HTTPS listener"))
            }
            else {
                $results.Add((New-WindowsBootstrapResult -Name HttpsListener -Status AlreadyPresent `
                        -Message "HTTPS listener 已精确绑定 $resolvedIPAddress`:$Port"))
            }

            if ($state.FirewallEnabled) {
                if (-not $state.FirewallRuleMatches) {
                    if ($state.FirewallRuleExists) {
                        Remove-NetFirewallRule -Name $script:ManagedFirewallRuleName -ErrorAction Stop
                    }
                    New-NetFirewallRule -Name $script:ManagedFirewallRuleName -DisplayName 'powershellScripts PSRP HTTPS' `
                        -Description 'Allow PSRP HTTPS only between Tailscale IPv4 nodes' -Enabled True `
                        -Direction Inbound -Action Allow -Protocol TCP -LocalPort $Port -LocalAddress $resolvedIPAddress `
                        -RemoteAddress $script:TailscaleIPv4Range -Profile Any -ErrorAction Stop | Out-Null
                    $results.Add((New-WindowsBootstrapResult -Name FirewallRule -Status Succeeded `
                            -Message "已限制 LocalAddress=$resolvedIPAddress RemoteAddress=$script:TailscaleIPv4Range"))
                }
                else {
                    $results.Add((New-WindowsBootstrapResult -Name FirewallRule -Status AlreadyPresent -Message '托管防火墙 rule 已匹配'))
                }
            }
            else {
                $results.Add((New-WindowsBootstrapResult -Name FirewallRule -Status Skipped `
                        -Message 'Windows Firewall profile 全部关闭；保持全局状态'))
            }

            $finalState = Get-WindowsRemotePsRemotingState -IPAddress $resolvedIPAddress -Port $Port
            $verified = $finalState.ListenerState -eq 'Matched' -and $finalState.ListenerBindingValid -and
            -not $finalState.AllowUnencrypted -and $finalState.Negotiate -and
            (-not $finalState.FirewallEnabled -or $finalState.FirewallRuleMatches)
            $results.Add((New-WindowsBootstrapResult -Name Verification `
                    -Status $(if ($verified) { 'Succeeded' } else { 'Failed' }) `
                    -Message $(if ($verified) { 'PSRP HTTPS 仅绑定 Tailscale IPv4，安全项已验证' } else { 'PSRP listener 或安全项验证失败' }) `
                    -ExitCode $(if ($verified) { 0 } else { 1 })))
        }
    }
    catch {
        $results.Add((New-WindowsBootstrapResult -Name Runtime -Status Failed -Message $_.Exception.Message -ExitCode 1))
    }

    $exitCode = Get-WindowsBootstrapExitCode -Result $results.ToArray()
    $status = if ($exitCode -eq 1) { 'Failed' } elseif ($exitCode -eq 10) { 'Blocked' } else { 'Succeeded' }
    $listenerAddress = @()
    if ($null -ne $finalState) {
        $listenerAddress = @($finalState.Listeners | ForEach-Object { [string]$_.Address })
    }
    return New-WindowsRemotePsRemotingDocument -Operation $operation -Status $status -ExitCode $exitCode `
        -IPAddress $resolvedIPAddress -Port $Port -FirewallEnabled ([bool]$state.FirewallEnabled) `
        -Result $results.ToArray() -ListenerAddress $listenerAddress -RerunCommand $rerunCommand
}

Export-ModuleMember -Function @(
    'Test-WindowsTailscaleIPv4',
    'Select-WindowsTailscaleIPv4',
    'Get-WindowsTailscaleIPv4',
    'Select-WindowsRemotePsRemotingCertificate',
    'ConvertFrom-WindowsWsManListener',
    'Test-WindowsRemotePsRemotingBinding',
    'New-WindowsRemotePsRemotingPlan',
    'Get-WindowsRemotePsRemotingState',
    'Invoke-WindowsRemotePsRemoting'
)
