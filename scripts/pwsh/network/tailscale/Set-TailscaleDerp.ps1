#!/usr/bin/env pwsh

<#
.SYNOPSIS
    编辑 tailnet policy 中的自定义 DERP `derpMap` 配置。

.DESCRIPTION
    该脚本负责读取本地 tailnet policy 文件，在其中新增、更新或删除脚本受管的
    单 Region + 单 Node DERP 配置，并把结果写回原文件或新的输出文件。

.PARAMETER ServerIp
    Apply 与 Snippet 模式下使用的自建 DERP 服务器公网 IP 或主机名。

.PARAMETER PolicyPath
    Apply 与 Reset 模式下必填的 tailnet policy 文件路径。

.PARAMETER Reset
    Reset 模式。执行后会从 tailnet policy 中删除脚本受管的目标 Region。

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
    可选输出路径；指定后会把修改结果写到新文件，而不是覆盖原始 policy。

.PARAMETER PrintSnippet
    只输出脚本当前会生成的 `derpMap` 片段，不读写 policy 文件。

.PARAMETER PassThru
    返回结构化结果对象，便于自动化链路继续消费。
#>
[CmdletBinding(SupportsShouldProcess = $true, DefaultParameterSetName = 'Apply')]
param(
    [Parameter(ParameterSetName = 'Apply')]
    [Parameter(ParameterSetName = 'Snippet')]
    [string]$ServerIp,

    [Parameter(ParameterSetName = 'Apply')]
    [Parameter(ParameterSetName = 'Reset')]
    [string]$PolicyPath,

    [Parameter(ParameterSetName = 'Reset')]
    [switch]$Reset,

    [ValidateRange(1, 65535)]
    [int]$RegionId = 900,

    [string]$RegionCode = 'cn-custom',
    [string]$NodeName = 'cn-node',

    [ValidateRange(1, 65535)]
    [int]$DerpPort = 8443,

    [ValidateRange(0, 65535)]
    [int]$StunPort = 3478,

    [string]$OutputPath,

    [Parameter(ParameterSetName = 'Snippet')]
    [switch]$PrintSnippet,

    [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Assert-TailscaleDerpServerIp {
    <#
    .SYNOPSIS
        校验 Apply / Snippet 模式下的服务器地址。

    .DESCRIPTION
        第一版接受 IPv4、IPv6 与常见主机名格式；遇到空值或明显非法字符时直接失败，
        避免把坏输入写入 policy 文件或示例片段。

    .PARAMETER ServerIp
        待校验的服务器地址字符串。
    #>
    [CmdletBinding()]
    param([string]$ServerIp)

    if ([string]::IsNullOrWhiteSpace($ServerIp)) {
        throw 'ServerIp 不能为空。'
    }

    $parsedAddress = $null
    $isIpAddress = [System.Net.IPAddress]::TryParse($ServerIp, [ref]$parsedAddress)
    $isHostNameLike = $ServerIp -match '^[A-Za-z0-9][A-Za-z0-9\.\-:]*[A-Za-z0-9]$'

    if (-not $isIpAddress -and -not $isHostNameLike) {
        throw "无效的服务器地址: $ServerIp"
    }
}

function New-TailscaleDerpRegion {
    <#
    .SYNOPSIS
        构造脚本受管的单 Region、单 Node `derpMap` 结构。

    .DESCRIPTION
        Apply、`-PrintSnippet` 与 policy 合并都复用这一份 Region 对象，
        避免不同输出模式维护多套字段定义而漂移。

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
        System.Collections.Specialized.OrderedDictionary
        返回能直接写入 `derpMap.Regions["<RegionId>"]` 的 Region 对象。
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

    return [ordered]@{
        RegionID   = $RegionId
        RegionCode = $RegionCode
        Nodes      = @(
            [ordered]@{
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

function New-TailscaleDerpSnippetJson {
    <#
    .SYNOPSIS
        生成包含 `derpMap` 顶层节点的 JSON 片段。

    .DESCRIPTION
        该输出模式用于预览脚本会写入 policy 的 Region 结构，
        也方便文档和自动化链路在不落盘的情况下复用相同格式。

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
        返回包含 `derpMap` 包装层的 JSON 文本。
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

    $region = New-TailscaleDerpRegion `
        -ServerIp $ServerIp `
        -RegionId $RegionId `
        -RegionCode $RegionCode `
        -NodeName $NodeName `
        -DerpPort $DerpPort `
        -StunPort $StunPort

    return ([ordered]@{
            derpMap = [ordered]@{
                Regions = [ordered]@{
                    ([string]$RegionId) = $region
                }
            }
        } | ConvertTo-Json -Depth 20)
}

function Convert-TailscaleHuJsonToJson {
    <#
    .SYNOPSIS
        把第一版支持范围内的 HuJSON 文本转成标准 JSON。

    .DESCRIPTION
        这里只支持脚本当前需要的最小特性：`//` 注释、`/* */` 注释与尾随逗号。
        通过逐字符状态机跳过注释，避免把字符串值中的 `https://` 误删成注释。

    .PARAMETER Content
        原始 tailnet policy 文本。

    .OUTPUTS
        System.String
        返回可交给 `ConvertFrom-Json` 解析的 JSON 文本。
    #>
    [CmdletBinding()]
    param([string]$Content)

    $builder = New-Object System.Text.StringBuilder
    $inString = $false
    $escapeNext = $false
    $inLineComment = $false
    $inBlockComment = $false

    for ($index = 0; $index -lt $Content.Length; $index++) {
        $current = [string]$Content[$index]
        $next = if ($index + 1 -lt $Content.Length) { [string]$Content[$index + 1] } else { '' }

        if ($inLineComment) {
            if ($current -eq "`n") {
                $inLineComment = $false
                [void]$builder.Append($current)
            }
            continue
        }

        if ($inBlockComment) {
            if ($current -eq '*' -and $next -eq '/') {
                $inBlockComment = $false
                $index++
            }
            continue
        }

        if ($inString) {
            [void]$builder.Append($current)
            if ($escapeNext) {
                $escapeNext = $false
                continue
            }

            if ($current -eq '\') {
                $escapeNext = $true
                continue
            }

            if ($current -eq '"') {
                $inString = $false
            }

            continue
        }

        if ($current -eq '"') {
            $inString = $true
            [void]$builder.Append($current)
            continue
        }

        if ($current -eq '/' -and $next -eq '/') {
            $inLineComment = $true
            $index++
            continue
        }

        if ($current -eq '/' -and $next -eq '*') {
            $inBlockComment = $true
            $index++
            continue
        }

        [void]$builder.Append($current)
    }

    return ([regex]::Replace($builder.ToString(), ',(?=\s*[}\]])', ''))
}

function Read-TailscalePolicyDocument {
    <#
    .SYNOPSIS
        读取本地 tailnet policy 文件并解析成可修改的字典对象。

    .DESCRIPTION
        该函数先做最小 HuJSON 预处理，再统一交给 `ConvertFrom-Json -AsHashtable` 校验，
        保证后续 Region 合并面对的是稳定的数据结构。

    .PARAMETER Path
        已存在的 tailnet policy 文件路径。

    .OUTPUTS
        System.Collections.IDictionary
        返回顶层 policy 对象；若文件缺失、为空或不可解析则直接抛错。
    #>
    [CmdletBinding()]
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "未找到 tailnet policy 文件: $Path"
    }

    $rawContent = Get-Content -LiteralPath $Path -Raw -Encoding utf8
    if ([string]::IsNullOrWhiteSpace($rawContent)) {
        throw "tailnet policy 文件为空: $Path"
    }

    $jsonText = Convert-TailscaleHuJsonToJson -Content $rawContent

    try {
        $document = $jsonText | ConvertFrom-Json -AsHashtable -Depth 100
    }
    catch {
        throw "tailnet policy 文件无法解析为 JSON/HuJSON: $Path"
    }

    if ($document -isnot [System.Collections.IDictionary]) {
        throw "tailnet policy 顶层必须是对象: $Path"
    }

    return $document
}

function Set-TailscalePolicyDerpRegion {
    <#
    .SYNOPSIS
        在 policy 中新增或覆盖脚本受管 Region，同时保留其它 Region 不动。

    .PARAMETER Policy
        待更新的顶层 policy 对象。

    .PARAMETER Region
        要写入 `derpMap.Regions` 的受管 Region 对象。

    .OUTPUTS
        PSCustomObject
        返回更新后的 policy 与是否发生实质变更的标记。
    #>
    [CmdletBinding()]
    param(
        [System.Collections.IDictionary]$Policy,
        [System.Collections.IDictionary]$Region
    )

    if (-not $Policy.Contains('derpMap') -or $null -eq $Policy['derpMap']) {
        $Policy['derpMap'] = [ordered]@{}
    }

    if ($Policy['derpMap'] -isnot [System.Collections.IDictionary]) {
        throw 'policy.derpMap 必须是对象。'
    }

    if (-not $Policy['derpMap'].Contains('Regions') -or $null -eq $Policy['derpMap']['Regions']) {
        $Policy['derpMap']['Regions'] = [ordered]@{}
    }

    if ($Policy['derpMap']['Regions'] -isnot [System.Collections.IDictionary]) {
        throw 'policy.derpMap.Regions 必须是对象。'
    }

    $regions = $Policy['derpMap']['Regions']
    $regionKey = [string]$Region['RegionID']
    $previousJson = if ($regions.Contains($regionKey)) {
        $regions[$regionKey] | ConvertTo-Json -Depth 20 -Compress
    }
    else {
        ''
    }

    $nextJson = $Region | ConvertTo-Json -Depth 20 -Compress
    $regions[$regionKey] = $Region

    return [pscustomobject]@{
        Policy  = $Policy
        Changed = ($previousJson -ne $nextJson)
    }
}

function Remove-TailscalePolicyDerpRegion {
    <#
    .SYNOPSIS
        从 policy 中删除受管 Region；如删空 `Regions` 则连带移除 `derpMap`。

    .PARAMETER Policy
        待更新的顶层 policy 对象。

    .PARAMETER RegionId
        要删除的受管 RegionID。

    .OUTPUTS
        PSCustomObject
        返回更新后的 policy、是否发生变更以及是否移除了整个 `derpMap`。
    #>
    [CmdletBinding()]
    param(
        [System.Collections.IDictionary]$Policy,
        [int]$RegionId
    )

    $changed = $false
    $removedDerpMap = $false
    $regionKey = [string]$RegionId

    if ($Policy.Contains('derpMap') -and $Policy['derpMap'] -is [System.Collections.IDictionary]) {
        $derpMap = $Policy['derpMap']
        if ($derpMap.Contains('Regions') -and $derpMap['Regions'] -is [System.Collections.IDictionary]) {
            $regions = $derpMap['Regions']
            if ($regions.Contains($regionKey)) {
                [void]$regions.Remove($regionKey)
                $changed = $true
            }

            if ($regions.Count -eq 0) {
                [void]$Policy.Remove('derpMap')
                $removedDerpMap = $true
            }
        }
    }

    return [pscustomobject]@{
        Policy         = $Policy
        Changed        = $changed
        RemovedDerpMap = $removedDerpMap
    }
}

function Write-TailscalePolicyDocument {
    <#
    .SYNOPSIS
        把规范化后的 policy 对象写回目标文件。

    .DESCRIPTION
        第一版统一采用 `ConvertTo-Json` 规范化输出，优先保证结构正确与测试稳定，
        不追求保留原始 HuJSON 注释和排版。

    .PARAMETER Path
        输出文件路径。

    .PARAMETER Document
        已完成合并或删除操作的顶层 policy 对象。
    #>
    [CmdletBinding()]
    param(
        [string]$Path,
        [System.Collections.IDictionary]$Document
    )

    $directory = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($directory) -and -not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    $json = $Document | ConvertTo-Json -Depth 100
    Set-Content -LiteralPath $Path -Value $json -Encoding utf8NoBOM
}

function New-TailscaleDerpResult {
    <#
    .SYNOPSIS
        构造统一的结构化结果对象。

    .PARAMETER Mode
        当前执行模式：`Apply`、`Reset` 或 `Snippet`。

    .PARAMETER Summary
        面向用户的变更摘要。
    #>
    [CmdletBinding()]
    param(
        [string]$Mode,
        [string]$PolicyPath,
        [string]$OutputPath,
        [int]$RegionId,
        [bool]$Changed,
        [bool]$RemovedDerpMap,
        [string]$Summary,
        [string]$Snippet
    )

    return [pscustomobject]@{
        Mode           = $Mode
        PolicyPath     = $PolicyPath
        OutputPath     = $OutputPath
        RegionId       = $RegionId
        Changed        = $Changed
        RemovedDerpMap = $RemovedDerpMap
        Summary        = $Summary
        Snippet        = $Snippet
    }
}

function Invoke-SetTailscaleDerpCommand {
    <#
    .SYNOPSIS
        统一编排 DERP policy 的 snippet 输出、Apply 写入与 Reset 删除。

    .DESCRIPTION
        Apply 分支负责把受管 Region 写入 `derpMap.Regions`；
        Reset 分支只删除目标 `RegionID`；
        Snippet 分支则返回可直接粘贴或审阅的 `derpMap` 片段。

    .PARAMETER ServerIp
        Apply 与 Snippet 模式下的服务器地址。

    .PARAMETER PolicyPath
        Apply 与 Reset 模式下必填的 tailnet policy 文件路径。

    .PARAMETER Reset
        删除受管 Region 的开关。

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
        可选输出路径；指定后会把修改结果写到新文件，而不是覆盖原始 policy。

    .PARAMETER PrintSnippet
        只返回脚本当前会写入 policy 的 `derpMap` 片段，不读写 policy 文件。

    .PARAMETER PassThru
        返回结构化结果对象，便于自动化链路继续消费。
    #>
    [CmdletBinding(SupportsShouldProcess = $true, DefaultParameterSetName = 'Apply')]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Apply')]
        [Parameter(Mandatory = $true, ParameterSetName = 'Snippet')]
        [string]$ServerIp,

        [Parameter(Mandatory = $true, ParameterSetName = 'Apply')]
        [Parameter(Mandatory = $true, ParameterSetName = 'Reset')]
        [string]$PolicyPath,

        [Parameter(Mandatory = $true, ParameterSetName = 'Reset')]
        [switch]$Reset,

        [ValidateRange(1, 65535)]
        [int]$RegionId = 900,

        [string]$RegionCode = 'cn-custom',
        [string]$NodeName = 'cn-node',

        [ValidateRange(1, 65535)]
        [int]$DerpPort = 8443,

        [ValidateRange(0, 65535)]
        [int]$StunPort = 3478,

        [string]$OutputPath,

        [Parameter(Mandatory = $true, ParameterSetName = 'Snippet')]
        [switch]$PrintSnippet,

        [switch]$PassThru
    )

    if ($PrintSnippet.IsPresent -and -not [string]::IsNullOrWhiteSpace($OutputPath)) {
        throw '-PrintSnippet 与 -OutputPath 不能同时使用。'
    }

    if (-not $Reset.IsPresent) {
        Assert-TailscaleDerpServerIp -ServerIp $ServerIp
    }

    if ($PrintSnippet.IsPresent) {
        $snippet = New-TailscaleDerpSnippetJson `
            -ServerIp $ServerIp `
            -RegionId $RegionId `
            -RegionCode $RegionCode `
            -NodeName $NodeName `
            -DerpPort $DerpPort `
            -StunPort $StunPort

        $snippetResult = New-TailscaleDerpResult `
            -Mode 'Snippet' `
            -PolicyPath $null `
            -OutputPath $null `
            -RegionId $RegionId `
            -Changed $true `
            -RemovedDerpMap $false `
            -Summary "已生成 Region $RegionId 的 derpMap 片段。" `
            -Snippet $snippet

        if ($PassThru) {
            return $snippetResult
        }

        return $snippet
    }

    $targetPath = if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
        $OutputPath
    }
    else {
        $PolicyPath
    }

    $policy = Read-TailscalePolicyDocument -Path $PolicyPath
    $change = if ($Reset.IsPresent) {
        Remove-TailscalePolicyDerpRegion -Policy $policy -RegionId $RegionId
    }
    else {
        $region = New-TailscaleDerpRegion `
            -ServerIp $ServerIp `
            -RegionId $RegionId `
            -RegionCode $RegionCode `
            -NodeName $NodeName `
            -DerpPort $DerpPort `
            -StunPort $StunPort

        Set-TailscalePolicyDerpRegion -Policy $policy -Region $region
    }

    $summary = if ($Reset.IsPresent) {
        if ($change.Changed) {
            "已从 Region $RegionId 删除受管 DERP 配置，请把结果提交到 Tailscale Admin Console 或你的 GitOps 流程。"
        }
        else {
            "Region $RegionId 不存在，无需修改。"
        }
    }
    else {
        "已把 Region $RegionId 写入 $targetPath，请把结果提交到 Tailscale Admin Console 或你的 GitOps 流程。"
    }

    if ($change.Changed -and $PSCmdlet.ShouldProcess($targetPath, $summary)) {
        Write-TailscalePolicyDocument -Path $targetPath -Document $change.Policy
    }

    $removedDerpMap = if ($change.PSObject.Properties.Name -contains 'RemovedDerpMap') {
        [bool]$change.RemovedDerpMap
    }
    else {
        $false
    }

    $result = New-TailscaleDerpResult `
        -Mode $(if ($Reset.IsPresent) { 'Reset' } else { 'Apply' }) `
        -PolicyPath $PolicyPath `
        -OutputPath $targetPath `
        -RegionId $RegionId `
        -Changed ([bool]$change.Changed) `
        -RemovedDerpMap $removedDerpMap `
        -Summary $summary `
        -Snippet $null

    if ($PassThru) {
        return $result
    }

    Write-Host $summary
}

if ($env:PWSH_TEST_SKIP_TAILSCALE_DERP_MAIN -ne '1') {
    Invoke-SetTailscaleDerpCommand @PSBoundParameters
}
