<#
.SYNOPSIS
    设置 PowerShell 配置文件
.DESCRIPTION
    将当前脚本路径写入到 PowerShell 配置文件中，确保每次启动时自动加载。
    如果已有配置文件，会先备份（带时间戳后缀）。
#>
function Set-PowerShellProfile {
    <#
    .SYNOPSIS
        幂等写入统一 PowerShell Profile 入口。

    .OUTPUTS
        PSCustomObject。包含 Status、ProfilePath、BackupPath 与 Message。
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param()

    $profilePath = [string]$PROFILE
    $profileContent = ". `"$script:ProfileEntryScriptPath`""
    $backupPath = ''
    if (Test-Path -LiteralPath $profilePath -PathType Leaf) {
        $currentContent = Get-Content -LiteralPath $profilePath -Raw
        if ($currentContent.TrimEnd("`r", "`n") -eq $profileContent) {
            return [pscustomobject]@{
                Status      = 'AlreadyPresent'
                ProfilePath = $profilePath
                BackupPath  = ''
                Message     = 'Profile 已指向统一入口'
            }
        }
    }

    if (-not $PSCmdlet.ShouldProcess($profilePath, '写入统一 PowerShell Profile 入口')) {
        return [pscustomobject]@{
            Status      = if ($WhatIfPreference) { 'Preview' } else { 'Skipped' }
            ProfilePath = $profilePath
            BackupPath  = ''
            Message     = '未写入 Profile'
        }
    }

    $profileDir = Split-Path -Path $profilePath -Parent
    if (-not (Test-Path -LiteralPath $profileDir -PathType Container)) {
        New-Item -Path $profileDir -ItemType Directory -Force | Out-Null
    }
    if (Test-Path -LiteralPath $profilePath -PathType Leaf) {
        $timestamp = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
        $backupPath = "$profilePath.$timestamp.bak"
        Copy-Item -LiteralPath $profilePath -Destination $backupPath -Force
    }
    Set-Content -LiteralPath $profilePath -Value $profileContent -Encoding utf8NoBOM

    return [pscustomobject]@{
        Status      = 'Updated'
        ProfilePath = $profilePath
        BackupPath  = $backupPath
        Message     = '已写入统一 Profile 入口'
    }
}
