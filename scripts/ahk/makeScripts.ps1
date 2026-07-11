<#
.SYNOPSIS
    构建 AutoHotkey v2 聚合脚本并部署当前用户 Startup 快捷方式。

.PARAMETER ScriptsPath
    AHK 源脚本目录。

.PARAMETER BasePath
    聚合脚本基础内容文件。

.PARAMETER OutputPath
    聚合脚本输出路径。

.PARAMETER StartupPath
    当前用户 Startup 目录；测试可传临时目录。

.PARAMETER ConcatNotInclude
    将源脚本内容直接拼接，而不是生成 Include 语句。

.PARAMETER Force
    覆盖已有快捷方式。

.PARAMETER SkipShortcut
    不创建 Startup 快捷方式。

.PARAMETER NoAutoStart
    不启动生成后的 AHK 脚本。

.OUTPUTS
    PSCustomObject[]。包含 build、shortcut 和 autostart 结果。
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$ScriptsPath = (Join-Path $PSScriptRoot 'scripts'),

    [string]$BasePath = (Join-Path $PSScriptRoot 'base.ahk'),

    [string]$OutputPath = (Join-Path $PSScriptRoot 'myAllScripts.ahk'),

    [string]$StartupPath = $(if ($env:APPDATA) { Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Startup' } else { '' }),

    [switch]$ConcatNotInclude,

    [switch]$Force,

    [switch]$SkipShortcut,

    [switch]$NoAutoStart
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function New-AutoHotkeyBuildResult {
    <#
    .SYNOPSIS
        创建 AutoHotkey 构建组件结果。

    .PARAMETER Name
        组件名称。

    .PARAMETER Status
        Succeeded、AlreadyPresent、Preview、Skipped 或 Failed。

    .PARAMETER Message
        结果摘要。

    .OUTPUTS
        PSCustomObject。单个构建组件结果。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [ValidateSet('Succeeded', 'AlreadyPresent', 'Preview', 'Skipped', 'Failed')]
        [string]$Status,

        [string]$Message = ''
    )

    return [pscustomobject]@{ Name = $Name; Status = $Status; Message = $Message }
}

function Get-AutoHotkeyBuildContent {
    <#
    .SYNOPSIS
        从基础脚本和排序后的源脚本生成稳定聚合内容。

    .PARAMETER SourceDirectory
        AHK 源脚本目录。

    .PARAMETER BaseFile
        可选基础内容文件。

    .PARAMETER Concatenate
        是否直接拼接源文件内容。

    .OUTPUTS
        System.String。稳定且不包含时间戳的聚合脚本内容。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SourceDirectory,

        [string]$BaseFile = '',

        [switch]$Concatenate
    )

    $resolvedScriptsPath = [System.IO.Path]::GetFullPath($SourceDirectory)
    if (-not (Test-Path -LiteralPath $resolvedScriptsPath -PathType Container)) {
        throw "AHK 源脚本目录不存在: $resolvedScriptsPath"
    }
    $scripts = @(Get-ChildItem -LiteralPath $resolvedScriptsPath -Recurse -Filter '*.ahk' -File | Sort-Object FullName)
    if ($scripts.Count -eq 0) {
        throw "AHK 源脚本目录为空: $resolvedScriptsPath"
    }
    $parts = [System.Collections.Generic.List[string]]::new()
    if ($BaseFile -and (Test-Path -LiteralPath $BaseFile -PathType Leaf)) {
        $parts.Add((Get-Content -LiteralPath $BaseFile -Raw).TrimEnd("`r", "`n"))
    }
    else {
        $parts.Add('; AutoHotkey v2 generated script')
    }
    foreach ($script in $scripts) {
        if ($Concatenate) {
            $parts.Add(("; ===== {0} =====`n{1}" -f $script.Name, (Get-Content -LiteralPath $script.FullName -Raw).TrimEnd("`r", "`n")))
        }
        else {
            $parts.Add(('#Include "{0}"' -f $script.FullName.Replace('"', '""')))
        }
    }
    return ($parts -join "`n`n") + "`n"
}

function New-AutoHotkeyStartupShortcut {
    <#
    .SYNOPSIS
        使用 WScript.Shell 创建当前用户 Startup 快捷方式。

    .PARAMETER ShortcutPath
        .lnk 目标路径。

    .PARAMETER TargetPath
        聚合 AHK 脚本路径。

    .OUTPUTS
        None。失败时抛出异常。
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ShortcutPath,

        [Parameter(Mandatory)]
        [string]$TargetPath
    )

    $shell = New-Object -ComObject WScript.Shell
    try {
        $shortcut = $shell.CreateShortcut($ShortcutPath)
        $shortcut.TargetPath = $TargetPath
        $shortcut.WorkingDirectory = Split-Path -Parent $TargetPath
        $shortcut.Description = 'AutoHotkey v2 user startup script'
        $shortcut.Save()
    }
    finally {
        if ($null -ne $shell) {
            [void][Runtime.InteropServices.Marshal]::ReleaseComObject($shell)
        }
    }
}

$results = [System.Collections.Generic.List[object]]::new()
$resolvedOutputPath = [System.IO.Path]::GetFullPath($OutputPath)
$content = Get-AutoHotkeyBuildContent -SourceDirectory $ScriptsPath -BaseFile $BasePath -Concatenate:$ConcatNotInclude
$currentContent = if (Test-Path -LiteralPath $resolvedOutputPath -PathType Leaf) { Get-Content -LiteralPath $resolvedOutputPath -Raw } else { $null }
if ($null -ne $currentContent -and $currentContent -ceq $content) {
    $results.Add((New-AutoHotkeyBuildResult -Name build -Status AlreadyPresent -Message $resolvedOutputPath))
}
elseif ($WhatIfPreference) {
    $results.Add((New-AutoHotkeyBuildResult -Name build -Status Preview -Message $resolvedOutputPath))
}
else {
    $outputDirectory = Split-Path -Parent $resolvedOutputPath
    if (-not (Test-Path -LiteralPath $outputDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
    }
    [System.IO.File]::WriteAllText($resolvedOutputPath, $content, [System.Text.UTF8Encoding]::new($false))
    $results.Add((New-AutoHotkeyBuildResult -Name build -Status Succeeded -Message $resolvedOutputPath))
}

if ($SkipShortcut) {
    $results.Add((New-AutoHotkeyBuildResult -Name shortcut -Status Skipped -Message '已显式跳过 Startup'))
}
elseif ([string]::IsNullOrWhiteSpace($StartupPath)) {
    if ($WhatIfPreference) {
        $results.Add((New-AutoHotkeyBuildResult -Name shortcut -Status Preview -Message '%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup'))
    }
    else {
        throw '无法解析当前用户 Startup 目录'
    }
}
else {
    $resolvedStartupPath = [System.IO.Path]::GetFullPath($StartupPath)
    $shortcutPath = Join-Path $resolvedStartupPath (([System.IO.Path]::GetFileNameWithoutExtension($resolvedOutputPath)) + '.lnk')
    if ((Test-Path -LiteralPath $shortcutPath -PathType Leaf) -and -not $Force) {
        $results.Add((New-AutoHotkeyBuildResult -Name shortcut -Status AlreadyPresent -Message $shortcutPath))
    }
    elseif ($WhatIfPreference) {
        $results.Add((New-AutoHotkeyBuildResult -Name shortcut -Status Preview -Message $shortcutPath))
    }
    else {
        if (-not (Test-Path -LiteralPath $resolvedStartupPath -PathType Container)) {
            New-Item -ItemType Directory -Path $resolvedStartupPath -Force | Out-Null
        }
        New-AutoHotkeyStartupShortcut -ShortcutPath $shortcutPath -TargetPath $resolvedOutputPath
        $results.Add((New-AutoHotkeyBuildResult -Name shortcut -Status Succeeded -Message $shortcutPath))
    }
}

if ($NoAutoStart) {
    $results.Add((New-AutoHotkeyBuildResult -Name autostart -Status Skipped -Message '已显式禁止启动'))
}
elseif ($WhatIfPreference) {
    $results.Add((New-AutoHotkeyBuildResult -Name autostart -Status Preview -Message $resolvedOutputPath))
}
else {
    Start-Process -FilePath $resolvedOutputPath
    $results.Add((New-AutoHotkeyBuildResult -Name autostart -Status Succeeded -Message $resolvedOutputPath))
}

$results.ToArray()
