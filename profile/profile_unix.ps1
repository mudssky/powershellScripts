<#
.SYNOPSIS
    Linux/macOS 平台 Profile 兼容 shim

.DESCRIPTION
    此文件为向后兼容保留。所有逻辑已合并到 profile.ps1（跨平台统一入口）。
    如果你的 $PROFILE 指向此文件，它会自动转发到 profile.ps1。
    运行时基线为 PowerShell 7+（pwsh）。

    建议将 $PROFILE 直接指向 profile.ps1：
        ./profile.ps1 -LoadProfile

.NOTES
    作者: mudssky
    版本: 3.0
    最后更新: 2026
#>

# 透传所有参数到统一入口
. $PSScriptRoot/profile.ps1 @PSBoundParameters
