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

if ($env:PWSH_TEST_SKIP_TAILSCALE_DERP_MAIN -ne '1') {
    throw 'Main entry will be implemented in a later task.'
}
