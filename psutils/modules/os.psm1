<#
.SYNOPSIS
    检测当前操作系统类型（Windows、macOS 或 Linux）。

.DESCRIPTION
    该函数检查当前运行的操作系统，并返回 "Windows"、"macOS"、"Linux" 或 "Unknown OS"。
    优先使用 PowerShell 7+ 的 $IsWindows/$IsLinux/$IsMacOS 变量，如果不支持则回退到其他兼容方法。

.EXAMPLE
    Get-OperatingSystem
    返回当前操作系统的名称（如 "Windows"）。

.OUTPUTS
    [string] 返回操作系统名称的字符串。

.NOTES
    此函数旨在提供跨平台的操作系统检测能力，优先利用PowerShell内置变量以提高效率和准确性。
#>
function Get-OperatingSystem {

    $unknowSystemReturn = "Unknown OS"
    # 检查是否是 PowerShell 7+（支持 $IsWindows、$IsLinux、$IsMacOS）
    if ($PSVersionTable.PSVersion.Major -ge 7) {
        if ($IsWindows) { return "Windows" }
        elseif ($IsLinux) { return "Linux" }
        elseif ($IsMacOS) { return "macOS" }
        else { return $unknowSystemReturn }
    }
    # 否则回退到兼容性检测（Windows PowerShell 或旧版本）
    else {
        # 检测 Windows
        if ($env:OS -eq "Windows_NT") {
            return "Windows"
        }
        # 检测 macOS 或 Linux
        else {
            try {
                # 调用 uname 命令（适用于 macOS/Linux）
                $uname = (uname -s 2>$null)
                if ($uname -eq "Linux") {
                    return "Linux"
                }
                elseif ($uname -eq "Darwin") {
                    return "macOS"
                }
                else {
                    return "Unknown OS (Unix-like: $uname)"
                }
            }
            catch {
                # 如果 uname 不存在，可能是旧版 Windows 或其他系统
                return $unknowSystemReturn
            }
        }
    }
}

function Test-Administrator {
    <#
.SYNOPSIS
    检测当前 PowerShell 会话是否以管理员权限运行。

.DESCRIPTION
    此函数用于检查当前 PowerShell 会话是否具有管理员权限。
    在 Windows 系统上，它通过检查当前用户是否属于管理员组来判断。
    在 Linux/macOS 系统上，它通过检查当前用户 ID 是否为 0（即 root 用户）来判断。

.OUTPUTS
    布尔值。如果当前会话以管理员权限运行，则返回 $true；否则返回 $false。

.EXAMPLE
    Test-Administrator
    检查当前 PowerShell 会话是否以管理员权限运行。

.EXAMPLE
    if (Test-Administrator) {
        Write-Host "当前以管理员权限运行"
    } else {
        Write-Host "当前以普通用户权限运行"
    }
    根据权限状态输出不同的信息。

.NOTES
    在 Windows 系统上，此函数依赖于 .NET 的 `WindowsIdentity` 和 `WindowsPrincipal` 类来执行权限检查。
    在 Linux/macOS 系统上，它通过检查 `id -u` 命令的输出来判断是否为 root 用户。
    此函数会调用 `Get-OperatingSystem` 来确定当前操作系统类型。

#>
    [CmdletBinding()]
    param()
    
    try {
        $os = Get-OperatingSystem
        
        switch ($os) {
            "Windows" {
                # Windows系统：检查是否为管理员角色
                $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
                $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
                return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
            }
            { $_ -in @("Linux", "macOS") } {
                # Linux/macOS系统：检查是否为root用户（UID = 0）
                $userId = (id -u 2>$null)
                return ($userId -eq "0")
            }
            default {
                Write-Warning "无法在未知操作系统上检测管理员权限: $os"
                return $false
            }
        }
    }
    catch {
        Write-Warning "检测管理员权限时发生错误: $_"
        return $false
    }
}

Export-ModuleMember -Function Get-OperatingSystem, Test-Administrator