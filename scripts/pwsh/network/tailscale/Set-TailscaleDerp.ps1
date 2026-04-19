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

function Assert-TailscaleDerpServerIp {
    <#
    .SYNOPSIS
        对用户输入的服务器地址做最小但明确的格式校验。

    .PARAMETER ServerIp
        待校验的 IPv4、IPv6 或主机名字符串。
    #>
    [CmdletBinding()]
    param([string]$ServerIp)

    if ([string]::IsNullOrWhiteSpace($ServerIp)) {
        throw 'ServerIp 不能为空。'
    }

    $parsedAddress = $null
    $isIpAddress = [System.Net.IPAddress]::TryParse($ServerIp, [ref]$parsedAddress)
    $isHostNameLike = $ServerIp -match '^[A-Za-z0-9][A-Za-z0-9\.\-:]*$'
    if (-not $isIpAddress -and -not $isHostNameLike) {
        throw "无效的服务器地址: $ServerIp"
    }
}

function Write-TailscaleDerpMapFile {
    <#
    .SYNOPSIS
        把 DERP JSON 写入受管路径，并确保父目录存在。

    .PARAMETER Path
        目标 DERP JSON 路径。

    .PARAMETER Json
        要写入的 DERP JSON 文本。
    #>
    [CmdletBinding()]
    param(
        [string]$Path,
        [string]$Json
    )

    $directory = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($directory) -and -not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    Set-Content -LiteralPath $Path -Value $Json -Encoding utf8NoBOM
}

function Get-TailscalePrefsSnapshot {
    <#
    .SYNOPSIS
        通过 Tailscale LocalAPI 读取当前 prefs 快照。

    .OUTPUTS
        PSCustomObject
        返回从 `/localapi/v0/prefs` 读取并解析出的 prefs 对象。
    #>
    [CmdletBinding()]
    param()

    $rawOutput = @(tailscale debug localapi GET /localapi/v0/prefs 2>&1)
    $jsonText = (@($rawOutput) | Where-Object { $_ -notmatch '^# doing request ' }) -join [Environment]::NewLine

    return ($jsonText | ConvertFrom-Json -Depth 20)
}

function Get-TailscaleCliVersionLine {
    <#
    .SYNOPSIS
        读取当前 Tailscale CLI 的首行版本信息。

    .OUTPUTS
        System.String
        返回 `tailscale version` 的第一行输出。
    #>
    [CmdletBinding()]
    param()

    return [string](tailscale version | Select-Object -First 1)
}

function Invoke-TailscaleCli {
    <#
    .SYNOPSIS
        执行 Tailscale CLI 并把参数与输出收口成结构化结果。

    .PARAMETER Arguments
        传给 `tailscale` 的参数数组。

    .OUTPUTS
        PSCustomObject
        返回 `ExitCode`、`Arguments` 与 `Output` 等字段，便于测试断言。
    #>
    [CmdletBinding()]
    param([string[]]$Arguments)

    $output = @(& tailscale @Arguments 2>&1)
    return [pscustomobject]@{
        ExitCode  = $LASTEXITCODE
        Arguments = @($Arguments)
        Output    = @($output)
    }
}

function Test-TailscaleDerpApplyPreconditions {
    <#
    .SYNOPSIS
        在真正改动网络配置前检查当前是否允许再次应用。

    .PARAMETER StatePath
        受管状态文件路径。
    #>
    [CmdletBinding()]
    param([string]$StatePath)

    if (Test-Path -LiteralPath $StatePath) {
        throw "检测到已有活动的自定义 DERP 状态文件: $StatePath。请先执行 -Reset 再应用新的服务器 IP。"
    }
}

function Invoke-TailscaleDerpApply {
    <#
    .SYNOPSIS
        在恢复参数基础上叠加 DERP flag 并执行 `tailscale up`。

    .PARAMETER RestoreArgs
        应用前基线对应的可恢复参数集合。

    .PARAMETER DerpMapUri
        指向 DERP JSON 的 `file://` URI。
    #>
    [CmdletBinding()]
    param(
        [string[]]$RestoreArgs,
        [string]$DerpMapUri
    )

    $arguments = @('up') + @($RestoreArgs) + @(
        "--derp-map-url=$DerpMapUri",
        '--tls-skip-verify'
    )

    try {
        return Invoke-TailscaleCli -Arguments $arguments
    }
    catch {
        $message = $_.Exception.Message
        if ($message -match 'unknown flag|flag provided but not defined') {
            throw '当前 Tailscale CLI 不支持自定义 DERP flag（--derp-map-url / --tls-skip-verify）。请升级或切换到支持这些参数的构建后再试。'
        }

        throw
    }
}

function Invoke-TailscaleDerpReset {
    <#
    .SYNOPSIS
        按应用前快照回放恢复参数，撤销自定义 DERP 定制。

    .PARAMETER RestoreArgs
        应用前基线对应的可恢复参数集合。
    #>
    [CmdletBinding()]
    param([string[]]$RestoreArgs)

    return Invoke-TailscaleCli -Arguments (@('up') + @($RestoreArgs))
}

function Invoke-SetTailscaleDerpCommand {
    <#
    .SYNOPSIS
        统一编排自定义 DERP 的应用与取消流程。

    .DESCRIPTION
        Apply 分支负责读取当前 prefs、写入受管 DERP JSON、应用 CLI 参数并保存恢复状态；
        Reset 分支负责按状态文件中的恢复参数回放原始配置，只有恢复成功后才清理受管文件。

    .PARAMETER ServerIp
        Apply 模式下的服务器地址。

    .PARAMETER Reset
        Reset 模式开关。

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

    .PARAMETER OutputPath
        可选 DERP JSON 输出路径。

    .PARAMETER ManagedStatePath
        仅供测试使用的状态文件路径覆盖。

    .PARAMETER ManagedDerpJsonPath
        仅供测试使用的 DERP JSON 路径覆盖。
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
        [string]$OutputPath,
        [string]$ManagedStatePath,
        [string]$ManagedDerpJsonPath
    )

    $managedPaths = Get-TailscaleDerpManagedPaths
    $statePath = if (-not [string]::IsNullOrWhiteSpace($ManagedStatePath)) {
        $ManagedStatePath
    }
    else {
        $managedPaths.StatePath
    }
    $derpJsonPath = if (-not [string]::IsNullOrWhiteSpace($ManagedDerpJsonPath)) {
        $ManagedDerpJsonPath
    }
    elseif (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
        $OutputPath
    }
    else {
        $managedPaths.DerpJsonPath
    }

    if ($Reset.IsPresent) {
        $state = Read-TailscaleDerpState -Path $statePath
        $result = Invoke-TailscaleDerpReset -RestoreArgs @($state.RestoreArgs)
        if ($result.ExitCode -ne 0) {
            throw "恢复普通 Tailscale 配置失败: $($result.Output -join [Environment]::NewLine)"
        }

        Remove-Item -LiteralPath $statePath -Force -ErrorAction Stop
        if (-not [string]::IsNullOrWhiteSpace([string]$state.DerpJsonPath)) {
            Remove-Item -LiteralPath ([string]$state.DerpJsonPath) -Force -ErrorAction SilentlyContinue
        }
        elseif (Test-Path -LiteralPath $derpJsonPath) {
            Remove-Item -LiteralPath $derpJsonPath -Force -ErrorAction SilentlyContinue
        }

        return $result
    }

    Assert-TailscaleDerpServerIp -ServerIp $ServerIp
    Test-TailscaleDerpApplyPreconditions -StatePath $statePath

    $prefs = Get-TailscalePrefsSnapshot
    $restoreArgs = Convert-TailscalePrefsToRestoreArgs -Prefs $prefs
    $derpJson = New-TailscaleDerpMapJson `
        -ServerIp $ServerIp `
        -RegionId $RegionId `
        -RegionCode $RegionCode `
        -NodeName $NodeName `
        -DerpPort $DerpPort `
        -StunPort $StunPort

    Write-TailscaleDerpMapFile -Path $derpJsonPath -Json $derpJson
    $derpMapUri = Convert-TailscalePathToFileUri -Path $derpJsonPath
    $applyResult = Invoke-TailscaleDerpApply -RestoreArgs $restoreArgs -DerpMapUri $derpMapUri
    if ($applyResult.ExitCode -ne 0) {
        throw "应用自定义 DERP 失败: $($applyResult.Output -join [Environment]::NewLine)"
    }

    Save-TailscaleDerpState -Path $statePath -State ([pscustomobject]@{
        AppliedAt     = (Get-Date).ToUniversalTime().ToString('o')
        ServerIp      = $ServerIp
        DerpJsonPath  = $derpJsonPath
        DerpMapUri    = $derpMapUri
        RestoreArgs   = @($restoreArgs)
        BaselinePrefs = $prefs
        CliVersion    = Get-TailscaleCliVersionLine
    })

    return $applyResult
}

if ($env:PWSH_TEST_SKIP_TAILSCALE_DERP_MAIN -ne '1') {
    Invoke-SetTailscaleDerpCommand @PSBoundParameters
}
