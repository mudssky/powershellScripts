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

Export-ModuleMember  -Function  *