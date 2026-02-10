<#
.SYNOPSIS
    设置 PowerShell 配置文件
.DESCRIPTION
    将当前脚本路径写入到 PowerShell 配置文件中，确保每次启动时自动加载。
    如果已有配置文件，会先备份（带时间戳后缀）。
#>
function Set-PowerShellProfile {
    [CmdletBinding()]
    param()

    try {
        # 备份逻辑：覆盖前备份，防止数据丢失
        if (Test-Path -Path $profile) {
            $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
            $backupPath = "$profile.$timestamp.bak"
            Write-Warning "发现现有的profile文件，备份为 $backupPath"
            Copy-Item -Path $profile -Destination $backupPath -Force
        }

        # 确保 profile 目录存在
        $profileDir = Split-Path -Path $profile -Parent
        if (-not (Test-Path -Path $profileDir)) {
            Write-Verbose "创建 PowerShell 配置文件目录: $profileDir"
            New-Item -Path $profileDir -ItemType Directory -Force | Out-Null
        }

        # 写入配置文件
        $profileContent = ". `"$script:ProfileEntryScriptPath`""
        Set-Content -Path $profile -Value $profileContent -Encoding UTF8
        Write-Host -ForegroundColor Green "已成功将配置写入 PowerShell 配置文件: $profile"
    }
    catch {
        Write-Error "设置 PowerShell 配置文件时出错: $($_.Exception.Message)"
    }
}
