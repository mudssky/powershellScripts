<#
.SYNOPSIS
    配置文件同步脚本

.DESCRIPTION
    该脚本用于在两个目录之间同步配置文件。支持备份、恢复和列出配置文件等操作。
    主要用于管理应用程序配置文件的备份和同步，确保配置文件的安全性和一致性。

.PARAMETER Mode
    操作模式，支持以下选项：
    - backup: 备份配置文件
    - restore: 恢复配置文件
    - list: 列出配置文件
    默认为'backup'

.EXAMPLE
    .\syncConfig.ps1 -Mode backup
    备份配置文件到指定目录

.EXAMPLE
    .\syncConfig.ps1 -Mode restore
    从备份目录恢复配置文件

.EXAMPLE
    .\syncConfig.ps1 -Mode list
    列出当前的配置文件

.NOTES
    支持多种应用程序的配置文件同步
    确保在操作前备份重要配置
    可用于配置文件的版本管理
#>


[CmdletBinding()]
param(
    [ValidateSet('backup', 'restore', 'list')]
    [string]$Mode = 'backup'
    # [string]$configDir = "$env:USERPROFILE/AppData/Local/Programs/PixPin/Config
)


# 这里我们用ps1作为配置文件目录的配置文件
# 这样方便用后缀名来过滤
if ( -not ( Test-Path   __sync.ps1)) {
    Write-Host '__sync.ps1 not found in current path'
    exit 1
}
# 导入变量
. ./__sync.ps1




switch ($Mode) {
    'backup' {
        Copy-Item -Recurse -Force $configDir/*  -Destination ./
    }
    'restore' {
        Copy-Item -Recurse -Force ./*  -Destination $configDir
    }
    'list' {
        Get-ChildItem $configDir
        Get-ChildItem ./
    }
}
