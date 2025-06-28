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
System.String
返回操作系统名称的字符串。
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
        检测当前PowerShell会话是否以管理员权限运行
    .DESCRIPTION
        该函数检查当前用户是否具有管理员权限。在Windows系统上检查是否为管理员角色，
        在Linux/macOS系统上检查是否为root用户。
    .EXAMPLE
        Test-Administrator
        返回$true表示具有管理员权限，$false表示普通用户权限
    .EXAMPLE
        if (Test-Administrator) {
            Write-Host "当前以管理员权限运行"
        } else {
            Write-Host "当前以普通用户权限运行"
        }
    .OUTPUTS
        System.Boolean
        返回布尔值，$true表示管理员权限，$false表示普通用户权限
    .NOTES
        在Windows系统上使用WindowsIdentity和WindowsPrincipal检查管理员角色
        在Linux/macOS系统上检查用户ID是否为0（root用户）
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

Export-ModuleMember  -Function  *