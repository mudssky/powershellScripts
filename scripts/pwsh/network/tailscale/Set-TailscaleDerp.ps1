#!/usr/bin/env pwsh

<#
.SYNOPSIS
    一键应用或取消当前设备的自定义 Tailscale DERP 配置。

.DESCRIPTION
    该脚本负责生成受管 DERP JSON、保存应用前的 Tailscale 基线状态，
    并在需要时恢复到应用前的普通 Tailscale 配置。

.PARAMETER ServerIp
    应用模式下使用的自建 DERP 服务器公网 IP 或主机名。

.PARAMETER Reset
    取消模式。执行后会恢复到脚本应用前的普通 Tailscale 配置。

.PARAMETER RegionId
    DERP map 中使用的 RegionID，默认 `900`。

.PARAMETER RegionCode
    DERP map 中使用的 RegionCode，默认 `cn-custom`。

.PARAMETER NodeName
    DERP map 中使用的节点名称，默认 `cn-node`。

.PARAMETER DerpPort
    DERP 服务端口，默认 `8443`。

.PARAMETER StunPort
    STUN 服务端口，默认 `3478`。

.PARAMETER OutputPath
    可选的 DERP JSON 输出路径。未指定时，脚本会使用受管默认路径。
#>
[CmdletBinding(SupportsShouldProcess = $true, DefaultParameterSetName = 'Apply')]
param(
    [Parameter(ParameterSetName = 'Apply')]
    [string]$ServerIp,

    [Parameter(ParameterSetName = 'Reset')]
    [switch]$Reset,

    [int]$RegionId = 900,
    [string]$RegionCode = 'cn-custom',
    [string]$NodeName = 'cn-node',
    [int]$DerpPort = 8443,
    [int]$StunPort = 3478,
    [string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-TailscaleDerpManagedPaths {
    <#
    .SYNOPSIS
        计算受管 DERP JSON 与状态文件路径。

    .DESCRIPTION
        路径规则按平台统一收口，方便测试时通过显式平台参数覆盖真实环境。

    .PARAMETER Platform
        目标平台标识；默认使用当前 PowerShell 平台值。

    .PARAMETER HomeDirectory
        POSIX 平台使用的用户目录；默认取 `$HOME`。

    .PARAMETER AppDataDirectory
        Windows 平台使用的 `APPDATA` 目录；默认取 `$env:APPDATA`。

    .OUTPUTS
        PSCustomObject
        返回 `BasePath`、`DerpJsonPath` 与 `StatePath` 三个标准化路径。
    #>
    [CmdletBinding()]
    param(
        [string]$Platform = $PSVersionTable.Platform,
        [string]$HomeDirectory = $HOME,
        [string]$AppDataDirectory = $env:APPDATA
    )

    if ($Platform -eq 'Win32NT' -or $Platform -eq 'Windows') {
        # 测试环境可能在非 Windows 平台上构造 Windows 路径，因此这里避免使用会解析盘符的 Join-Path。
        $basePath = ([System.IO.Path]::Combine($AppDataDirectory, 'powershell-scripts', 'tailscale')) -replace '/', '\'
        $derpJsonPath = "$basePath\derp.json"
        $statePath = "$basePath\derp-state.json"
    }
    else {
        $basePath = Join-Path $HomeDirectory '.config/powershell-scripts/tailscale'
        $derpJsonPath = [System.IO.Path]::Combine($basePath, 'derp.json')
        $statePath = [System.IO.Path]::Combine($basePath, 'derp-state.json')
    }

    return [pscustomobject]@{
        BasePath     = $basePath
        DerpJsonPath = $derpJsonPath
        StatePath    = $statePath
    }
}

function Convert-TailscalePathToFileUri {
    <#
    .SYNOPSIS
        把绝对文件路径转换为 Tailscale 可消费的 `file://` URI。

    .PARAMETER Path
        待转换的绝对文件路径。

    .OUTPUTS
        System.String
        返回标准化后的 `file://` URI。
    #>
    [CmdletBinding()]
    param([string]$Path)

    if ($Path -match '^[A-Za-z]:[\\/]') {
        $normalized = ($Path -replace '\\', '/').TrimStart('/')
        return ([System.Uri]("file:///$normalized")).AbsoluteUri
    }

    return ([System.Uri]("file://$Path")).AbsoluteUri
}

function New-TailscaleDerpMapJson {
    <#
    .SYNOPSIS
        生成单 Region、单 Node 的 DERP map JSON 文本。

    .PARAMETER ServerIp
        自定义 DERP 节点的公网 IP 或主机名。

    .PARAMETER RegionId
        DERP map 中使用的 RegionID。

    .PARAMETER RegionCode
        DERP map 中使用的 RegionCode。

    .PARAMETER NodeName
        DERP 节点名称。

    .PARAMETER DerpPort
        DERP 服务端口。

    .PARAMETER StunPort
        STUN 服务端口。

    .OUTPUTS
        System.String
        返回格式化好的 DERP map JSON。
    #>
    [CmdletBinding()]
    param(
        [string]$ServerIp,
        [int]$RegionId,
        [string]$RegionCode,
        [string]$NodeName,
        [int]$DerpPort,
        [int]$StunPort
    )

    $regionKey = [string]$RegionId
    $document = @{
        Regions = @{
            $regionKey = @{
                RegionID   = $RegionId
                RegionCode = $RegionCode
                Nodes      = @(
                    @{
                        Name             = $NodeName
                        RegionID         = $RegionId
                        HostName         = $ServerIp
                        DERPPort         = $DerpPort
                        STUNPort         = $StunPort
                        InsecureForTests = $true
                    }
                )
            }
        }
    }

    return ($document | ConvertTo-Json -Depth 10)
}

function Get-TailscalePrefsBaselineDefaults {
    <#
    .SYNOPSIS
        返回脚本当前支持恢复的 Tailscale prefs 默认基线。

    .DESCRIPTION
        这份默认值集合用于判断当前机器上是否存在脚本还不能安全恢复的非默认配置。

    .OUTPUTS
        System.Collections.Hashtable
        返回脚本已知的 prefs 默认值字典。
    #>
    [CmdletBinding()]
    param()

    return @{
        ControlURL             = 'https://controlplane.tailscale.com'
        CorpDNS                = $true
        RouteAll               = $false
        ExitNodeIP             = ''
        ExitNodeAllowLANAccess = $false
        RunSSH                 = $false
        ShieldsUp              = $false
        Hostname               = ''
        AdvertiseRoutes        = @()
        AdvertiseTags          = @()
        NoSNAT                 = $false
        RunWebClient           = $false
    }
}

function Convert-TailscalePrefsToRestoreArgs {
    <#
    .SYNOPSIS
        把应用前的 Tailscale prefs 转成一组可重放的 `tailscale up` 参数。

    .DESCRIPTION
        该函数只接受脚本明确知道如何恢复的字段。遇到当前还不支持恢复且又处于非默认值的配置时，
        会直接抛错，避免脚本修改了网络设置却无法恢复。

    .PARAMETER Prefs
        来自 Tailscale LocalAPI 的 prefs 对象。

    .OUTPUTS
        System.String[]
        返回可直接重放到 `tailscale up` 的显式参数集合。
    #>
    [CmdletBinding()]
    param([psobject]$Prefs)

    $defaults = Get-TailscalePrefsBaselineDefaults
    $restoreArgs = New-Object 'System.Collections.Generic.List[string]'
    $runWebClient = if ($Prefs.PSObject.Properties.Name -contains 'RunWebClient') {
        [bool]$Prefs.RunWebClient
    }
    else {
        [bool]$defaults.RunWebClient
    }

    if ($runWebClient -ne [bool]$defaults.RunWebClient) {
        throw '当前脚本暂不支持恢复非默认的 RunWebClient 配置，请先手动恢复默认状态后再应用自定义 DERP。'
    }

    $restoreArgs.Add("--login-server=$([string]$Prefs.ControlURL)")
    $restoreArgs.Add("--accept-dns=$(([bool]$Prefs.CorpDNS).ToString().ToLowerInvariant())")
    $restoreArgs.Add("--accept-routes=$(([bool]$Prefs.RouteAll).ToString().ToLowerInvariant())")
    $restoreArgs.Add("--exit-node-allow-lan-access=$(([bool]$Prefs.ExitNodeAllowLANAccess).ToString().ToLowerInvariant())")
    $restoreArgs.Add("--ssh=$(([bool]$Prefs.RunSSH).ToString().ToLowerInvariant())")
    $restoreArgs.Add("--shields-up=$(([bool]$Prefs.ShieldsUp).ToString().ToLowerInvariant())")
    # `NoSNAT=true` 代表关闭源地址转换，因此对应的恢复参数需要显式写成 `--snat-subnet-routes=false`。
    $restoreArgs.Add("--snat-subnet-routes=$(((-not [bool]$Prefs.NoSNAT).ToString().ToLowerInvariant()))")

    if (-not [string]::IsNullOrWhiteSpace([string]$Prefs.ExitNodeIP)) {
        $restoreArgs.Add("--exit-node=$([string]$Prefs.ExitNodeIP)")
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$Prefs.Hostname)) {
        $restoreArgs.Add("--hostname=$([string]$Prefs.Hostname)")
    }
    if ($null -ne $Prefs.AdvertiseRoutes -and @($Prefs.AdvertiseRoutes).Count -gt 0) {
        $restoreArgs.Add("--advertise-routes=$((@($Prefs.AdvertiseRoutes) -join ','))")
    }
    if ($null -ne $Prefs.AdvertiseTags -and @($Prefs.AdvertiseTags).Count -gt 0) {
        $restoreArgs.Add("--advertise-tags=$((@($Prefs.AdvertiseTags) -join ','))")
    }

    return @($restoreArgs.ToArray())
}

function Save-TailscaleDerpState {
    <#
    .SYNOPSIS
        把恢复所需的基线信息写入状态文件。

    .PARAMETER Path
        目标状态文件路径。

    .PARAMETER State
        要持久化的状态对象。
    #>
    [CmdletBinding()]
    param(
        [string]$Path,
        [psobject]$State
    )

    $directory = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($directory) -and -not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    $State | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $Path -Encoding utf8NoBOM
}

function Read-TailscaleDerpState {
    <#
    .SYNOPSIS
        读取上一次成功应用后的受管状态快照。

    .PARAMETER Path
        状态文件路径。

    .OUTPUTS
        PSCustomObject
        返回脚本保存的状态对象。
    #>
    [CmdletBinding()]
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "未找到受管状态文件: $Path"
    }

    return (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -Depth 20)
}

if ($env:PWSH_TEST_SKIP_TAILSCALE_DERP_MAIN -ne '1') {
    throw 'Main entry will be implemented in a later task.'
}
